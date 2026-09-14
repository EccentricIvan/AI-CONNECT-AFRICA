import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:html/dom.dart' as dom;
import 'package:html/parser.dart' as html_parser;
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:webview_flutter/webview_flutter.dart';
import 'package:webview_flutter_android/webview_flutter_android.dart';

import '../coding/interactive_html.dart';

/// Creates a WebView tuned for interactive in-app HTML previews.
///
/// JavaScript is unrestricted and Android DOM storage is enabled (default in
/// [AndroidWebViewController], reaffirmed here via platform settings) so
/// tabs, calculators, and localStorage work offline without CDN scripts.
Future<WebViewController> createPreviewWebViewController() async {
  final controller = WebViewController();
  await controller.setJavaScriptMode(JavaScriptMode.unrestricted);
  await controller.setBackgroundColor(Colors.white);

  if (!kIsWeb && Platform.isAndroid) {
    final platform = controller.platform;
    if (platform is AndroidWebViewController) {
      // DomStorage is enabled in AndroidWebViewController's constructor;
      // keep JS window-open + file access open for richer student pages.
      await platform.setMediaPlaybackRequiresUserGesture(false);
      await platform.setAllowFileAccess(true);
      AndroidWebViewController.enableDebugging(kDebugMode);
    }
  }
  return controller;
}

/// Strip ```html fences and leading prose so WebView gets a clean document.
String stripMarkdownHtmlNoise(String raw) {
  var s = raw.trim();
  if (s.isEmpty) return s;

  final fenced = RegExp(
    r'```(?:html|HTML|htm)?\s*([\s\S]*?)```',
    multiLine: true,
  ).firstMatch(s);
  if (fenced != null) {
    s = (fenced.group(1) ?? '').trim();
  }

  s = s.replaceAll(
    RegExp(r'<think>[\s\S]*?</think>', caseSensitive: false),
    '',
  );

  final doctype = RegExp(
    r'<!DOCTYPE\s+html[\s\S]*',
    caseSensitive: false,
  ).firstMatch(s);
  if (doctype != null) return doctype.group(0)!.trim();

  final htmlTag = RegExp(r'<html[\s\S]*', caseSensitive: false).firstMatch(s);
  if (htmlTag != null) {
    return '<!DOCTYPE html>\n${htmlTag.group(0)!.trim()}';
  }
  return s.trim();
}

/// Offline shell when the model emits empty / broken HTML.
String get kFallbackPreviewHtml => ensureInteractiveHtmlDocument('');

/// Clean + guarantee a paintable, interactive HTML document for the WebView.
String prepareHtmlForPreview(String raw) {
  final cleaned = stripMarkdownHtmlNoise(raw);
  if (cleaned.isEmpty) return kFallbackPreviewHtml;
  return ensureInteractiveHtmlDocument(cleaned);
}

/// UTF-8 Base64 `data:` URI helper (used as a fallback load path).
Uri htmlToBase64DataUri(String html) {
  final body = prepareHtmlForPreview(html);
  final encoding = Encoding.getByName('utf-8') ?? utf8;
  return Uri.dataFromString(
    body,
    mimeType: 'text/html',
    encoding: encoding,
    base64: true,
  );
}

/// Loads HTML for an in-app Simple Browser (never opens an external browser).
///
/// Prefer paths that execute vanilla JS + localStorage reliably:
/// * **Android / iOS** — `loadHtmlString` (System WebView / WKWebView)
/// * **Desktop** — temp `file://` (WebView2-friendly)
/// * Then Base64 `data:` URI as a last-resort paint path
Future<void> loadHtmlPreview(
  WebViewController controller,
  String html,
) async {
  final body = prepareHtmlForPreview(html);

  // Reaffirm unrestricted JS on every load (some platforms reset mode).
  try {
    await controller.setJavaScriptMode(JavaScriptMode.unrestricted);
  } catch (_) {}

  if (!kIsWeb && (Platform.isAndroid || Platform.isIOS)) {
    try {
      await controller.loadHtmlString(body);
      return;
    } catch (e) {
      debugPrint('Android/iOS loadHtmlString failed: $e');
    }
  }

  if (!kIsWeb && (Platform.isWindows || Platform.isLinux || Platform.isMacOS)) {
    try {
      final dir = await getTemporaryDirectory();
      final file = File(p.join(dir.path, 'otic_live_preview.html'));
      await file.writeAsString(body, flush: true);
      await controller.loadRequest(Uri.file(file.path));
      return;
    } catch (e) {
      debugPrint('file:// preview load failed: $e');
    }
  }

  try {
    await controller.loadHtmlString(body);
    return;
  } catch (e) {
    debugPrint('loadHtmlString failed: $e');
  }

  try {
    await controller.loadRequest(htmlToBase64DataUri(body));
    return;
  } catch (e) {
    debugPrint('Base64 data URI preview failed: $e');
  }

  final encoded = base64Encode(utf8.encode(body));
  await controller.loadRequest(
    Uri.parse('data:text/html;charset=utf-8;base64,$encoded'),
  );
}

/// Visible text extracted from an HTML document (fallback when WebView fails).
String htmlPlainText(String raw) {
  try {
    final doc = html_parser.parse(raw);
    final text = doc.body?.text ?? doc.documentElement?.text ?? '';
    return text.replaceAll(RegExp(r'\s+'), ' ').trim();
  } catch (_) {
    return raw
        .replaceAll(RegExp(r'<[^>]+>'), ' ')
        .replaceAll(RegExp(r'\s+'), ' ')
        .trim();
  }
}

/// Body inner HTML for lightweight fallback rendering.
String htmlBodyForFlutterHtml(String raw) {
  final cleaned = prepareHtmlForPreview(raw);
  final bodyMatch = RegExp(
    r'<body[^>]*>([\s\S]*?)</body>',
    caseSensitive: false,
  ).firstMatch(cleaned);
  if (bodyMatch != null) return bodyMatch.group(1)!.trim();
  return cleaned;
}

/// Builds a simple Flutter layout from common tags (no JS / external browser).
List<Widget> _widgetsFromHtml(String raw) {
  final widgets = <Widget>[];
  try {
    final doc = html_parser.parse(prepareHtmlForPreview(raw));
    final root = doc.body ?? doc.documentElement;
    if (root == null) {
      return [Text(htmlPlainText(raw))];
    }

    void walk(dom.Node node) {
      if (node is dom.Element) {
        final name = node.localName?.toLowerCase() ?? '';
        final text = node.text.replaceAll(RegExp(r'\s+'), ' ').trim();
        if (name == 'script' || name == 'style') return;

        if (name == 'h1' && text.isNotEmpty) {
          widgets.add(Padding(
            padding: const EdgeInsets.only(bottom: 10),
            child: Text(
              text,
              style: const TextStyle(fontSize: 26, fontWeight: FontWeight.w700),
            ),
          ));
          return;
        }
        if (name == 'h2' && text.isNotEmpty) {
          widgets.add(Padding(
            padding: const EdgeInsets.only(top: 12, bottom: 8),
            child: Text(
              text,
              style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w600),
            ),
          ));
          return;
        }
        if (name == 'h3' && text.isNotEmpty) {
          widgets.add(Padding(
            padding: const EdgeInsets.only(top: 8, bottom: 4),
            child: Text(
              text,
              style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
            ),
          ));
          return;
        }
        if ((name == 'p' || name == 'li') && text.isNotEmpty) {
          widgets.add(Padding(
            padding: const EdgeInsets.only(bottom: 6),
            child: Text(text, style: const TextStyle(fontSize: 14, height: 1.45)),
          ));
          return;
        }
        if (name == 'a' && text.isNotEmpty) {
          widgets.add(Padding(
            padding: const EdgeInsets.only(bottom: 6),
            child: Text(
              text,
              style: const TextStyle(
                fontSize: 14,
                color: Color(0xFF2563EB),
                decoration: TextDecoration.underline,
              ),
            ),
          ));
          return;
        }
        if (name == 'button' && text.isNotEmpty) {
          widgets.add(Padding(
            padding: const EdgeInsets.symmetric(vertical: 6),
            child: FilledButton(onPressed: () {}, child: Text(text)),
          ));
          return;
        }
        for (final child in node.nodes) {
          walk(child);
        }
      }
    }

    for (final child in root.nodes) {
      walk(child);
    }
  } catch (_) {
    widgets.add(Text(htmlPlainText(raw)));
  }

  if (widgets.isEmpty) {
    final plain = htmlPlainText(raw);
    if (plain.isNotEmpty) {
      widgets.add(Text(plain));
    } else {
      widgets.add(const Text('Offline preview ready.'));
    }
  }
  return widgets;
}

/// In-app Simple Browser pane — WebView when available, Flutter fallback.
class HtmlPreviewPane extends StatefulWidget {
  const HtmlPreviewPane({
    super.key,
    required this.html,
    this.borderRadius = 12,
    this.forceFlutterHtml = false,
  });

  final String html;
  final double borderRadius;
  final bool forceFlutterHtml;

  @override
  State<HtmlPreviewPane> createState() => _HtmlPreviewPaneState();
}

class _HtmlPreviewPaneState extends State<HtmlPreviewPane> {
  WebViewController? _controller;
  var _loading = true;
  var _useFlutterHtml = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _boot(widget.html);
  }

  @override
  void didUpdateWidget(covariant HtmlPreviewPane oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.html != widget.html ||
        oldWidget.forceFlutterHtml != widget.forceFlutterHtml) {
      _boot(widget.html);
    }
  }

  Future<void> _boot(String html) async {
    if (widget.forceFlutterHtml) {
      if (!mounted) return;
      setState(() {
        _useFlutterHtml = true;
        _loading = false;
        _error = null;
      });
      return;
    }

    // Keep prior frame visible while Base64 reloads (zero-latency feel).
    final hadController = _controller != null;
    if (!hadController) {
      setState(() {
        _loading = true;
        _error = null;
        _useFlutterHtml = false;
      });
    }

    try {
      final c = _controller ?? await createPreviewWebViewController();
      _controller = c;
      await loadHtmlPreview(c, html).timeout(const Duration(seconds: 10));
      if (!mounted) return;
      setState(() {
        _loading = false;
        _useFlutterHtml = false;
        _error = null;
      });
    } catch (e) {
      debugPrint('WebView preview failed, using Flutter HTML: $e');
      if (!mounted) return;
      setState(() {
        _useFlutterHtml = true;
        _loading = false;
        _error = null;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_error != null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Text(
            'Preview failed.\n$_error',
            textAlign: TextAlign.center,
            style: TextStyle(color: Theme.of(context).colorScheme.error),
          ),
        ),
      );
    }

    final child = _useFlutterHtml
        ? ColoredBox(
            color: Colors.white,
            child: ListView(
              padding: const EdgeInsets.all(16),
              children: _widgetsFromHtml(widget.html),
            ),
          )
        : (_controller == null || _loading)
            ? const Center(child: CircularProgressIndicator())
            : WebViewWidget(controller: _controller!);

    return ClipRRect(
      borderRadius: BorderRadius.circular(widget.borderRadius),
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: Colors.white,
          border: Border.all(color: const Color(0xFFE2E8F0)),
        ),
        child: child,
      ),
    );
  }
}

/// Dual-tab website workspace: Preview Layout ↔ View Source Code.
///
/// One primary action — **Apply Changes & Preview** — plus Full Screen Preview.
/// No duplicate FABs / secondary Apply bars.
class LiveHtmlStudio extends StatefulWidget {
  const LiveHtmlStudio({
    super.key,
    required this.controller,
    this.initialHtml = '',
    this.onApply,
    this.toolbar,
    this.debounce = const Duration(milliseconds: 450),
    this.forceFlutterHtml = false,
    this.previewLabel = 'Preview Layout',
    this.sourceLabel = 'View Source Code',
    @Deprecated('Duplicates removed — Apply lives in the control bar only')
    this.showApplyFab = false,
  });

  final TextEditingController controller;
  final String initialHtml;
  final VoidCallback? onApply;
  final Widget? toolbar;
  final Duration debounce;
  final bool forceFlutterHtml;
  final String previewLabel;
  final String sourceLabel;

  /// Ignored — kept for call-site compatibility.
  final bool showApplyFab;

  @override
  State<LiveHtmlStudio> createState() => _LiveHtmlStudioState();
}

class _LiveHtmlStudioState extends State<LiveHtmlStudio> {
  late String _previewHtml;
  var _epoch = 0;
  var _split = true;
  var _mobileTab = 0; // 0 = Preview Layout, 1 = View Source Code
  var _applying = false;

  @override
  void initState() {
    super.initState();
    _previewHtml = widget.controller.text.isNotEmpty
        ? widget.controller.text
        : widget.initialHtml;
    if (widget.controller.text.isEmpty && widget.initialHtml.isNotEmpty) {
      widget.controller.text = widget.initialHtml;
    }
    if (_previewHtml.trim().isEmpty) {
      _previewHtml = kFallbackPreviewHtml;
    }
    _previewHtml = prepareHtmlForPreview(_previewHtml);
  }

  @override
  void didUpdateWidget(covariant LiveHtmlStudio oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.initialHtml != oldWidget.initialHtml &&
        widget.initialHtml.isNotEmpty &&
        widget.controller.text != widget.initialHtml) {
      widget.controller.text = widget.initialHtml;
      _previewHtml = prepareHtmlForPreview(widget.initialHtml);
      _epoch++;
    }
  }

  /// Flush editor → Base64 data URI → force WebView remount (zero-latency).
  Future<void> _applyNow() async {
    if (_applying) return;
    setState(() => _applying = true);
    try {
      final raw = widget.controller.text.trim().isEmpty
          ? kFallbackPreviewHtml
          : widget.controller.text;
      final next = prepareHtmlForPreview(raw);
      // Warm the Base64 encoder on this frame before the WebView paints.
      htmlToBase64DataUri(next);
      if (!mounted) return;
      setState(() {
        _previewHtml = next;
        _epoch++;
        _mobileTab = 0;
      });
      widget.onApply?.call();
    } finally {
      if (mounted) setState(() => _applying = false);
    }
  }

  void _openFullScreenPreview() {
    final html = prepareHtmlForPreview(_previewHtml);
    htmlToBase64DataUri(html);
    showDialog<void>(
      context: context,
      useSafeArea: false,
      barrierDismissible: true,
      builder: (ctx) {
        final top = MediaQuery.paddingOf(ctx).top;
        return Dialog.fullscreen(
          backgroundColor: const Color(0xFF0B1220),
          child: Stack(
            fit: StackFit.expand,
            children: [
              Positioned.fill(
                child: HtmlPreviewPane(
                  key: ValueKey('fs-$_epoch'),
                  html: html,
                  borderRadius: 0,
                  forceFlutterHtml: widget.forceFlutterHtml,
                ),
              ),
              Positioned(
                top: top + 12,
                right: 16,
                child: Material(
                  elevation: 8,
                  borderRadius: BorderRadius.circular(28),
                  color: Colors.white.withValues(alpha: 0.94),
                  child: InkWell(
                    borderRadius: BorderRadius.circular(28),
                    onTap: () => Navigator.of(ctx).pop(),
                    child: const Padding(
                      padding: EdgeInsets.symmetric(
                        horizontal: 16,
                        vertical: 12,
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(Icons.close, size: 20),
                          SizedBox(width: 8),
                          Text(
                            'Close Full Screen',
                            style: TextStyle(fontWeight: FontWeight.w700),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final size = MediaQuery.sizeOf(context);
    final useSplit =
        _split && size.width >= 900 && size.shortestSide >= 600;
    final primary = Theme.of(context).colorScheme.primary;

    final controlBar = Material(
      color: const Color(0xFF0F172A),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(10, 10, 10, 10),
        child: LayoutBuilder(
          builder: (context, constraints) {
            final compact = constraints.maxWidth < 720;
            final tabs = Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                _TabChip(
                  selected: useSplit || _mobileTab == 0,
                  icon: Icons.preview_outlined,
                  label: compact ? 'Preview' : widget.previewLabel,
                  onTap: () => setState(() => _mobileTab = 0),
                ),
                const SizedBox(width: 6),
                _TabChip(
                  selected: useSplit || _mobileTab == 1,
                  icon: Icons.code,
                  label: compact ? 'Source' : widget.sourceLabel,
                  onTap: () => setState(() => _mobileTab = 1),
                ),
                if (size.width >= 900 && size.shortestSide >= 600) ...[
                  const SizedBox(width: 4),
                  IconButton(
                    tooltip: _split ? 'Tabbed view' : 'Split view',
                    color: Colors.white70,
                    onPressed: () => setState(() => _split = !_split),
                    icon: Icon(
                      _split ? Icons.view_agenda : Icons.vertical_split,
                    ),
                  ),
                ],
              ],
            );

            final actions = Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                OutlinedButton.icon(
                  style: OutlinedButton.styleFrom(
                    foregroundColor: Colors.white,
                    side: const BorderSide(color: Color(0xFF334155)),
                    backgroundColor: const Color(0xFF1E293B),
                  ),
                  onPressed: _openFullScreenPreview,
                  icon: const Icon(Icons.fullscreen, size: 18),
                  label: Text(compact ? 'Full Screen' : 'Full Screen Preview'),
                ),
                const SizedBox(width: 8),
                FilledButton.icon(
                  style: FilledButton.styleFrom(
                    backgroundColor: primary,
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(
                      horizontal: 14,
                      vertical: 12,
                    ),
                  ),
                  onPressed: _applying ? null : _applyNow,
                  icon: _applying
                      ? const SizedBox(
                          width: 16,
                          height: 16,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            color: Colors.white,
                          ),
                        )
                      : const Icon(Icons.bolt, size: 18),
                  label: Text(
                    _applying
                        ? 'Painting…'
                        : (compact
                            ? 'Apply & Preview'
                            : 'Apply Changes & Preview'),
                  ),
                ),
              ],
            );

            if (compact) {
              return Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  tabs,
                  const SizedBox(height: 8),
                  actions,
                ],
              );
            }
            return Row(
              children: [
                tabs,
                const Spacer(),
                actions,
              ],
            );
          },
        ),
      ),
    );

    // Wide split: equal panes without nested duplicate headers/actions.
    final codePane = Column(
      children: [
        Expanded(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(8, 8, 8, 8),
            child: TextField(
              controller: widget.controller,
              maxLines: null,
              expands: true,
              textAlignVertical: TextAlignVertical.top,
              style: const TextStyle(
                fontFamily: 'monospace',
                fontSize: 12,
                height: 1.4,
              ),
              decoration: InputDecoration(
                filled: true,
                fillColor: const Color(0xFFF8FAFC),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
                hintText:
                    'Edit HTML — tap Apply Changes & Preview to run interactive JS in the WebView',
              ),
            ),
          ),
        ),
        if (widget.toolbar != null)
          Padding(
            padding: const EdgeInsets.fromLTRB(8, 0, 8, 8),
            child: widget.toolbar!,
          ),
      ],
    );

    final previewPane = Padding(
      padding: const EdgeInsets.fromLTRB(8, 8, 8, 8),
      child: HtmlPreviewPane(
        html: _previewHtml,
        forceFlutterHtml: widget.forceFlutterHtml,
      ),
    );

    final Widget workspace;
    if (useSplit) {
      workspace = Row(
        children: [
          Expanded(flex: 5, child: codePane),
          const VerticalDivider(width: 1),
          Expanded(flex: 5, child: previewPane),
        ],
      );
    } else {
      workspace = IndexedStack(
        index: _mobileTab,
        children: [previewPane, codePane],
      );
    }

    return Column(
      children: [
        controlBar,
        Expanded(child: workspace),
      ],
    );
  }
}

class _TabChip extends StatelessWidget {
  const _TabChip({
    required this.selected,
    required this.icon,
    required this.label,
    required this.onTap,
  });

  final bool selected;
  final IconData icon;
  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: selected
          ? Colors.white.withValues(alpha: 0.14)
          : Colors.transparent,
      borderRadius: BorderRadius.circular(10),
      child: InkWell(
        borderRadius: BorderRadius.circular(10),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                icon,
                size: 16,
                color: selected ? Colors.white : const Color(0xFF94A3B8),
              ),
              const SizedBox(width: 6),
              Text(
                label,
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
                  color: selected ? Colors.white : const Color(0xFF94A3B8),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
