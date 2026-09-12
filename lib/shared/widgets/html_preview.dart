import 'dart:async';
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

/// Creates a WebView tuned for in-app HTML previews on Android + desktop.
Future<WebViewController> createPreviewWebViewController() async {
  final controller = WebViewController();
  await controller.setJavaScriptMode(JavaScriptMode.unrestricted);
  await controller.setBackgroundColor(Colors.white);

  // Android System WebView — enable DOM storage for richer student pages.
  if (!kIsWeb && Platform.isAndroid) {
    final platform = controller.platform;
    if (platform is AndroidWebViewController) {
      await platform.setMediaPlaybackRequiresUserGesture(false);
      AndroidWebViewController.enableDebugging(kDebugMode);
    }
  }
  return controller;
}

/// Loads HTML for an in-app Simple Browser (never opens an external browser).
///
/// * **Android / iOS** — `loadHtmlString` (System WebView / WKWebView).
/// * **Windows / Linux / macOS** — temp `file://` first (WebView2-friendly),
///   then `loadHtmlString`, then a small `data:` URI fallback.
Future<void> loadHtmlPreview(
  WebViewController controller,
  String html,
) async {
  final body = html.trim().isEmpty
      ? '<!DOCTYPE html><html><body><p>Empty preview</p></body></html>'
      : html;

  // Mobile: loadHtmlString is the reliable path (no file-provider needed).
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
  final cleaned = raw.trim();
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
    final doc = html_parser.parse(raw);
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
    if (plain.isNotEmpty) widgets.add(Text(plain));
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

    setState(() {
      _loading = true;
      _error = null;
      _useFlutterHtml = false;
    });

    try {
      final c = _controller ?? await createPreviewWebViewController();
      _controller = c;
      await loadHtmlPreview(c, html).timeout(const Duration(seconds: 10));
      if (!mounted) return;
      setState(() => _loading = false);
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

/// VS Code–style workspace: Code on the left, live Simple Browser on the right.
class LiveHtmlStudio extends StatefulWidget {
  const LiveHtmlStudio({
    super.key,
    required this.controller,
    this.initialHtml = '',
    this.onApply,
    this.toolbar,
    this.debounce = const Duration(milliseconds: 450),
    this.forceFlutterHtml = false,
  });

  final TextEditingController controller;
  final String initialHtml;
  final VoidCallback? onApply;
  final Widget? toolbar;
  final Duration debounce;

  /// When true, skip WebView (widget tests / broken System WebView).
  final bool forceFlutterHtml;

  @override
  State<LiveHtmlStudio> createState() => _LiveHtmlStudioState();
}

class _LiveHtmlStudioState extends State<LiveHtmlStudio> {
  late String _previewHtml;
  Timer? _debounce;
  var _epoch = 0;
  var _split = true;
  var _mobileTab = 0;

  @override
  void initState() {
    super.initState();
    _previewHtml = widget.controller.text.isNotEmpty
        ? widget.controller.text
        : widget.initialHtml;
    if (widget.controller.text.isEmpty && widget.initialHtml.isNotEmpty) {
      widget.controller.text = widget.initialHtml;
    }
    widget.controller.addListener(_onCodeChanged);
  }

  @override
  void didUpdateWidget(covariant LiveHtmlStudio oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.controller != widget.controller) {
      oldWidget.controller.removeListener(_onCodeChanged);
      widget.controller.addListener(_onCodeChanged);
    }
    if (widget.initialHtml != oldWidget.initialHtml &&
        widget.initialHtml.isNotEmpty &&
        widget.controller.text != widget.initialHtml) {
      widget.controller.text = widget.initialHtml;
      _previewHtml = widget.initialHtml;
      _epoch++;
    }
  }

  @override
  void dispose() {
    _debounce?.cancel();
    widget.controller.removeListener(_onCodeChanged);
    super.dispose();
  }

  void _onCodeChanged() {
    _debounce?.cancel();
    _debounce = Timer(widget.debounce, () {
      if (!mounted) return;
      setState(() {
        _previewHtml = widget.controller.text;
        _epoch++;
      });
    });
  }

  void _applyNow() {
    _debounce?.cancel();
    setState(() {
      _previewHtml = widget.controller.text;
      _epoch++;
    });
    widget.onApply?.call();
  }

  @override
  Widget build(BuildContext context) {
    final size = MediaQuery.sizeOf(context);
    // Phones (incl. Android): tabbed Code | Preview. Tablets/desktop: split.
    final useSplit = _split &&
        size.width >= 900 &&
        size.shortestSide >= 600;

    final codePane = Column(
      children: [
        _paneHeader(
          context,
          icon: Icons.code,
          title: 'Code',
          trailing: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (size.width >= 900 && size.shortestSide >= 600)
                IconButton(
                  tooltip: _split ? 'Preview only' : 'Split view',
                  onPressed: () => setState(() => _split = !_split),
                  icon: Icon(_split ? Icons.vertical_split : Icons.view_sidebar),
                ),
              TextButton.icon(
                onPressed: _applyNow,
                icon: const Icon(Icons.refresh, size: 18),
                label: const Text('Refresh'),
              ),
            ],
          ),
        ),
        Expanded(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(8, 0, 8, 8),
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
                  borderRadius: BorderRadius.circular(10),
                ),
                hintText: 'Edit HTML here — preview updates as you type',
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

    final previewPane = Column(
      children: [
        _paneHeader(
          context,
          icon: Icons.language,
          title: 'Simple Browser',
          trailing: const Text(
            'In-app · not Chrome',
            style: TextStyle(fontSize: 11, color: Color(0xFF64748B)),
          ),
        ),
        Expanded(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(8, 0, 8, 8),
            child: HtmlPreviewPane(
              key: ValueKey('live-$_epoch'),
              html: _previewHtml,
              forceFlutterHtml: widget.forceFlutterHtml,
            ),
          ),
        ),
      ],
    );

    if (useSplit) {
      return Row(
        children: [
          Expanded(flex: 5, child: codePane),
          const VerticalDivider(width: 1),
          Expanded(flex: 5, child: previewPane),
        ],
      );
    }

    // Narrow / phone (Android): keep both panes alive so WebView isn't disposed.
    return Column(
      children: [
        Material(
          color: const Color(0xFFF1F5F9),
          child: Row(
            children: [
              Expanded(
                child: TextButton.icon(
                  onPressed: () => setState(() => _mobileTab = 0),
                  icon: Icon(
                    Icons.code,
                    size: 18,
                    color: _mobileTab == 0
                        ? Theme.of(context).colorScheme.primary
                        : const Color(0xFF64748B),
                  ),
                  label: Text(
                    'Code',
                    style: TextStyle(
                      fontWeight:
                          _mobileTab == 0 ? FontWeight.w700 : FontWeight.w500,
                      color: _mobileTab == 0
                          ? Theme.of(context).colorScheme.primary
                          : const Color(0xFF64748B),
                    ),
                  ),
                ),
              ),
              Expanded(
                child: TextButton.icon(
                  onPressed: () => setState(() => _mobileTab = 1),
                  icon: Icon(
                    Icons.language,
                    size: 18,
                    color: _mobileTab == 1
                        ? Theme.of(context).colorScheme.primary
                        : const Color(0xFF64748B),
                  ),
                  label: Text(
                    'Preview',
                    style: TextStyle(
                      fontWeight:
                          _mobileTab == 1 ? FontWeight.w700 : FontWeight.w500,
                      color: _mobileTab == 1
                          ? Theme.of(context).colorScheme.primary
                          : const Color(0xFF64748B),
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
        Expanded(
          child: IndexedStack(
            index: _mobileTab,
            children: [codePane, previewPane],
          ),
        ),
      ],
    );
  }

  Widget _paneHeader(
    BuildContext context, {
    required IconData icon,
    required String title,
    Widget? trailing,
  }) {
    return Container(
      height: 40,
      padding: const EdgeInsets.symmetric(horizontal: 10),
      decoration: const BoxDecoration(
        color: Color(0xFFF1F5F9),
        border: Border(bottom: BorderSide(color: Color(0xFFE2E8F0))),
      ),
      child: Row(
        children: [
          Icon(icon, size: 16, color: const Color(0xFF475569)),
          const SizedBox(width: 6),
          Text(
            title,
            style: const TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w600,
              color: Color(0xFF334155),
            ),
          ),
          const Spacer(),
          if (trailing != null) trailing,
        ],
      ),
    );
  }
}
