import 'dart:async';
import 'dart:collection';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:webview_flutter/webview_flutter.dart';
import 'package:webview_flutter_android/webview_flutter_android.dart';
import 'package:webview_flutter_windows/webview_flutter_windows.dart' as win;

import '../coding/interactive_html.dart';

// ── Document preparation ─────────────────────────────────────────────────────

/// Strip ```html fences and leading prose so the browser gets a clean document.
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

/// Clean + structurally repair, so the WebView always gets a parseable
/// document. Content is never added — see [ensureRenderableHtmlDocument].
String prepareHtmlForPreview(String raw) =>
    ensureRenderableHtmlDocument(stripMarkdownHtmlNoise(raw));

/// The document's own `<title>`, for the address bar. Falls back to a
/// filename so the chrome always reads like a browser.
String htmlDocumentTitle(String html, {String fallback = 'index.html'}) {
  final m = RegExp(
    r'<title[^>]*>([\s\S]*?)</title>',
    caseSensitive: false,
  ).firstMatch(html);
  final title = m?.group(1)?.trim().replaceAll(RegExp(r'\s+'), ' ');
  return (title == null || title.isEmpty) ? fallback : title;
}

/// UTF-8 Base64 `data:` URI helper (fallback load path on mobile).
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

// ── Temp files ───────────────────────────────────────────────────────────────

/// Every write gets a fresh filename so a `file://` reload can never serve a
/// cached copy of the previous document. Older files are deleted as new ones
/// land — live preview writes one per keystroke pause, and the storage floor
/// on a target device is 32 GB.
const _tempPreviewKeep = 3;
final Queue<File> _tempPreviewFiles = Queue<File>();
int _tempPreviewCounter = 0;

Future<File> writeTempPreviewFile(String body) async {
  final dir = await getTemporaryDirectory();
  final file = File(
    p.join(dir.path, 'otic_preview_${_tempPreviewCounter++}.html'),
  );
  await file.writeAsString(body, flush: true);

  _tempPreviewFiles.addLast(file);
  while (_tempPreviewFiles.length > _tempPreviewKeep) {
    final stale = _tempPreviewFiles.removeFirst();
    try {
      if (await stale.exists()) await stale.delete();
    } catch (_) {
      // A file the WebView still holds open is not worth failing a repaint.
    }
  }
  return file;
}

// ── System browser ───────────────────────────────────────────────────────────

/// Opens [html] in the OS's own browser. Fully offline — a local file, no
/// network — and the one render path that needs no embedded engine at all.
Future<bool> openHtmlInSystemBrowser(String html) async {
  if (kIsWeb) return false;
  try {
    final file = await writeTempPreviewFile(prepareHtmlForPreview(html));
    final (exe, args) = switch (Platform.operatingSystem) {
      'windows' => ('explorer', [file.path]),
      'linux' => ('xdg-open', [file.path]),
      'macos' => ('open', [file.path]),
      _ => ('', <String>[]),
    };
    if (exe.isEmpty) return false;
    await Process.start(exe, args, mode: ProcessStartMode.detached);
    return true;
  } catch (e) {
    debugPrint('Open in system browser failed: $e');
    return false;
  }
}

// ── Mobile (webview_flutter) plumbing ────────────────────────────────────────

/// Creates a WebView tuned for interactive in-app HTML previews.
///
/// Android/iOS only: `webview_flutter` has no Windows or Linux implementation,
/// which is why [HtmlPreviewPane] routes those platforms elsewhere.
Future<WebViewController> createPreviewWebViewController() async {
  final controller = WebViewController();
  await controller.setJavaScriptMode(JavaScriptMode.unrestricted);
  await controller.setBackgroundColor(Colors.white);

  if (!kIsWeb && Platform.isAndroid) {
    final platform = controller.platform;
    if (platform is AndroidWebViewController) {
      await platform.setMediaPlaybackRequiresUserGesture(false);
      await platform.setAllowFileAccess(true);
      AndroidWebViewController.enableDebugging(kDebugMode);
    }
  }
  return controller;
}

/// Loads [html] into a mobile WebView. `loadHtmlString` first (System WebView
/// and WKWebView both run vanilla JS + localStorage from it), Base64 `data:`
/// as the fallback paint path.
Future<void> loadHtmlPreview(WebViewController controller, String html) async {
  final body = prepareHtmlForPreview(html);
  try {
    await controller.setJavaScriptMode(JavaScriptMode.unrestricted);
  } catch (_) {}

  try {
    await controller.loadHtmlString(body);
    return;
  } catch (e) {
    debugPrint('loadHtmlString failed: $e');
  }
  await controller.loadRequest(htmlToBase64DataUri(body));
}

// ── Embedded preview surface ─────────────────────────────────────────────────

/// In-app preview of one HTML document.
///
/// The engine is chosen per platform, because there is no single package that
/// covers the targets:
/// * **Android / iOS** — `webview_flutter`
/// * **Windows** — `webview_flutter_windows` (WebView2), which is a standalone
///   package rather than a `webview_flutter` implementation, so it cannot be
///   driven through [WebViewController]
/// * **Linux** — neither package ships an implementation; the pane says so and
///   offers the system browser instead of faking a render
class HtmlPreviewPane extends StatefulWidget {
  const HtmlPreviewPane({
    super.key,
    required this.html,
    this.borderRadius = 12,
  });

  final String html;
  final double borderRadius;

  @override
  State<HtmlPreviewPane> createState() => HtmlPreviewPaneState();
}

class HtmlPreviewPaneState extends State<HtmlPreviewPane> {
  WebViewController? _mobile;
  win.WebviewController? _windows;

  var _loading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    unawaited(_boot());
  }

  @override
  void didUpdateWidget(covariant HtmlPreviewPane oldWidget) {
    super.didUpdateWidget(oldWidget);
    // Load into the engine that is already running — never rebuild it, or a
    // debounced repaint would spin up a WebView per keystroke pause.
    if (oldWidget.html != widget.html) unawaited(_load());
  }

  @override
  void dispose() {
    unawaited(_windows?.dispose());
    super.dispose();
  }

  bool get _isWindows => !kIsWeb && Platform.isWindows;
  bool get _isMobile => !kIsWeb && (Platform.isAndroid || Platform.isIOS);

  Future<void> _boot() async {
    if (!_isWindows && !_isMobile) {
      _fail('No embedded browser engine is available on this platform.');
      return;
    }
    try {
      if (_isWindows) {
        final version = await win.WebviewController.getWebViewVersion();
        if (version == null) {
          _fail(
            'Microsoft Edge WebView2 Runtime is not installed on this device.',
          );
          return;
        }
        final controller = win.WebviewController();
        await controller.initialize();
        await controller.setBackgroundColor(Colors.white);
        _windows = controller;
      } else {
        _mobile = await createPreviewWebViewController();
      }
      await _load();
    } catch (e) {
      debugPrint('Preview engine failed to start: $e');
      _fail('$e');
    }
  }

  Future<void> _load() async {
    final body = prepareHtmlForPreview(widget.html);
    try {
      final windows = _windows;
      if (windows != null) {
        // A real file:// origin, not NavigateToString — pages that use
        // localStorage are blocked on the about:blank origin a string load
        // gets, and student projects lean on localStorage.
        final file = await writeTempPreviewFile(body);
        await windows.loadUrl(Uri.file(file.path).toString());
      } else if (_mobile != null) {
        await loadHtmlPreview(_mobile!, body);
      } else {
        return;
      }
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = null;
      });
    } catch (e) {
      debugPrint('Preview load failed: $e');
      _fail('$e');
    }
  }

  void _fail(String message) {
    if (!mounted) return;
    setState(() {
      _loading = false;
      _error = message;
    });
  }

  /// Repaints the current document — the browser chrome's reload button.
  Future<void> reload() async {
    final windows = _windows;
    if (windows != null) {
      await windows.reload();
      return;
    }
    await _load();
  }

  @override
  Widget build(BuildContext context) {
    final Widget child;
    if (_error != null) {
      child = _PreviewUnavailable(reason: _error!, html: widget.html);
    } else if (_loading) {
      child = const ColoredBox(
        color: Colors.white,
        child: Center(child: CircularProgressIndicator()),
      );
    } else if (_windows != null) {
      child = win.Webview(_windows!);
    } else if (_mobile != null) {
      child = WebViewWidget(controller: _mobile!);
    } else {
      child = const ColoredBox(color: Colors.white);
    }

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

/// Shown instead of a render when no engine can paint the page.
///
/// Deliberately not an approximation of the page: a half-rendered stand-in
/// reads as "your code is broken" when the truth is "this device has no
/// browser engine", and the student cannot tell the two apart.
class _PreviewUnavailable extends StatelessWidget {
  const _PreviewUnavailable({required this.reason, required this.html});

  final String reason;
  final String html;

  @override
  Widget build(BuildContext context) {
    return ColoredBox(
      color: const Color(0xFFF8FAFC),
      child: Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.public_off, size: 32, color: Color(0xFF94A3B8)),
              const SizedBox(height: 12),
              const Text(
                'In-app preview unavailable',
                style: TextStyle(fontWeight: FontWeight.w700, fontSize: 15),
              ),
              const SizedBox(height: 6),
              Text(
                reason,
                textAlign: TextAlign.center,
                style: const TextStyle(fontSize: 12, color: Color(0xFF64748B)),
              ),
              const SizedBox(height: 16),
              FilledButton.icon(
                onPressed: () async {
                  final ok = await openHtmlInSystemBrowser(html);
                  if (!ok && context.mounted) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(
                        content: Text('Could not open the system browser.'),
                      ),
                    );
                  }
                },
                icon: const Icon(Icons.open_in_browser, size: 18),
                label: const Text('Open in system browser'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ── Browser chrome ───────────────────────────────────────────────────────────

/// Browser-style frame around a rendered page: window dots, an address bar
/// carrying the document's own `<title>`, reload, optional source toggle,
/// full screen, and open-in-system-browser.
///
/// One widget for every surface that shows built HTML, so the chat card, the
/// builders, and the labs all behave the same.
class BrowserFrame extends StatefulWidget {
  const BrowserFrame({
    super.key,
    required this.html,
    this.height,
    this.borderRadius = 14,
    this.showSourceToggle = true,
  });

  final String html;

  /// Fixed body height; null expands to fill the parent.
  final double? height;
  final double borderRadius;
  final bool showSourceToggle;

  @override
  State<BrowserFrame> createState() => _BrowserFrameState();
}

class _BrowserFrameState extends State<BrowserFrame> {
  final _paneKey = GlobalKey<HtmlPreviewPaneState>();
  var _showSource = false;

  Future<void> _openInBrowser() async {
    final ok = await openHtmlInSystemBrowser(widget.html);
    if (!ok && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Could not open the system browser.')),
      );
    }
  }

  void _openFullScreen() => showHtmlFullScreen(context, widget.html);

  Widget _dot(Color c) => Container(
        width: 9,
        height: 9,
        decoration: BoxDecoration(color: c, shape: BoxShape.circle),
      );

  @override
  Widget build(BuildContext context) {
    final body = _showSource
        ? Container(
            color: const Color(0xFF0F172A),
            padding: const EdgeInsets.all(12),
            child: SingleChildScrollView(
              child: SelectableText(
                widget.html.trim(),
                style: const TextStyle(
                  fontFamily: 'Consolas',
                  fontSize: 12,
                  height: 1.45,
                  color: Color(0xFFE2E8F0),
                ),
              ),
            ),
          )
        : HtmlPreviewPane(
            key: _paneKey,
            html: widget.html,
            borderRadius: 0,
          );

    return Container(
      clipBehavior: Clip.antiAlias,
      decoration: BoxDecoration(
        color: const Color(0xFF0B1220),
        borderRadius: BorderRadius.circular(widget.borderRadius),
        border: Border.all(color: const Color(0xFF1E293B)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 8, 4, 8),
            child: Row(
              children: [
                _dot(const Color(0xFFEF4444)),
                const SizedBox(width: 5),
                _dot(const Color(0xFFF59E0B)),
                const SizedBox(width: 5),
                _dot(const Color(0xFF22C55E)),
                const SizedBox(width: 10),
                Expanded(
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 10,
                      vertical: 5,
                    ),
                    decoration: BoxDecoration(
                      color: const Color(0xFF1E293B),
                      borderRadius: BorderRadius.circular(999),
                    ),
                    child: Row(
                      children: [
                        const Icon(Icons.folder_outlined,
                            size: 11, color: Color(0xFF64748B)),
                        const SizedBox(width: 6),
                        Expanded(
                          child: Text(
                            htmlDocumentTitle(widget.html),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              fontSize: 11,
                              color: Color(0xFF94A3B8),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
                _ChromeButton(
                  icon: Icons.refresh,
                  tooltip: 'Reload',
                  onTap: () => _paneKey.currentState?.reload(),
                ),
                if (widget.showSourceToggle)
                  _ChromeButton(
                    icon: _showSource ? Icons.public : Icons.code,
                    tooltip: _showSource ? 'Show page' : 'View source',
                    onTap: () => setState(() => _showSource = !_showSource),
                  ),
                _ChromeButton(
                  icon: Icons.fullscreen,
                  tooltip: 'Full screen',
                  onTap: _openFullScreen,
                ),
                _ChromeButton(
                  icon: Icons.open_in_browser,
                  tooltip: 'Open in system browser',
                  onTap: _openInBrowser,
                ),
              ],
            ),
          ),
          const Divider(height: 1, color: Color(0xFF1E293B)),
          if (widget.height != null)
            SizedBox(height: widget.height, child: body)
          else
            Expanded(child: body),
        ],
      ),
    );
  }
}

class _ChromeButton extends StatelessWidget {
  const _ChromeButton({
    required this.icon,
    required this.tooltip,
    required this.onTap,
  });

  final IconData icon;
  final String tooltip;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return IconButton(
      tooltip: tooltip,
      visualDensity: VisualDensity.compact,
      padding: const EdgeInsets.all(6),
      constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
      onPressed: onTap,
      icon: Icon(icon, size: 17, color: Colors.white70),
    );
  }
}

/// Unconstrained full-screen view of [html], offline like every other path.
void showHtmlFullScreen(BuildContext context, String html) {
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
              child: HtmlPreviewPane(html: html, borderRadius: 0),
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
                    padding:
                        EdgeInsets.symmetric(horizontal: 16, vertical: 12),
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

// ── Code ⇄ live preview workspace ────────────────────────────────────────────

/// Source on the left, the page it produces on the right.
///
/// The preview follows the editor on a [debounce] tick — no Apply step — so
/// what is on the left is what is painted on the right, including while the
/// coder model streams a build in.
class LiveHtmlStudio extends StatefulWidget {
  const LiveHtmlStudio({
    super.key,
    required this.controller,
    this.initialHtml = '',
    this.onApply,
    this.toolbar,
    this.debounce = const Duration(milliseconds: 450),
    this.previewLabel = 'Preview',
    this.sourceLabel = 'Code',
  });

  final TextEditingController controller;
  final String initialHtml;
  final VoidCallback? onApply;
  final Widget? toolbar;
  final Duration debounce;
  final String previewLabel;
  final String sourceLabel;

  @override
  State<LiveHtmlStudio> createState() => LiveHtmlStudioState();
}

/// Public so callers holding a `GlobalKey<LiveHtmlStudioState>` can flush an
/// out-of-band edit (an AI rewrite) into the preview without waiting for the
/// debounce tick.
class LiveHtmlStudioState extends State<LiveHtmlStudio> {
  late String _previewHtml;
  Timer? _debounce;
  var _split = true;
  var _mobileTab = 0; // 0 = preview, 1 = source

  @override
  void initState() {
    super.initState();
    if (widget.controller.text.isEmpty && widget.initialHtml.isNotEmpty) {
      widget.controller.text = widget.initialHtml;
    }
    _previewHtml = prepareHtmlForPreview(widget.controller.text);
    widget.controller.addListener(_onCodeChanged);
  }

  @override
  void didUpdateWidget(covariant LiveHtmlStudio oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.controller != widget.controller) {
      oldWidget.controller.removeListener(_onCodeChanged);
      widget.controller.addListener(_onCodeChanged);
      applyNow();
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
    _debounce = Timer(widget.debounce, applyNow);
  }

  /// Repaints the preview from the editor's current text, immediately.
  void applyNow() {
    _debounce?.cancel();
    if (!mounted) return;
    final next = prepareHtmlForPreview(widget.controller.text);
    if (next == _previewHtml) return;
    setState(() => _previewHtml = next);
    widget.onApply?.call();
  }

  @override
  Widget build(BuildContext context) {
    final size = MediaQuery.sizeOf(context);
    final useSplit = _split && size.width >= 900 && size.shortestSide >= 600;

    final controlBar = Material(
      color: const Color(0xFF0F172A),
      child: Padding(
        padding: const EdgeInsets.all(10),
        child: Row(
          children: [
            if (!useSplit) ...[
              _TabChip(
                selected: _mobileTab == 0,
                icon: Icons.public,
                label: widget.previewLabel,
                onTap: () => setState(() => _mobileTab = 0),
              ),
              const SizedBox(width: 6),
              _TabChip(
                selected: _mobileTab == 1,
                icon: Icons.code,
                label: widget.sourceLabel,
                onTap: () => setState(() => _mobileTab = 1),
              ),
            ] else
              const Text(
                'Live preview — the page updates as you type',
                style: TextStyle(fontSize: 12, color: Color(0xFF94A3B8)),
              ),
            const Spacer(),
            if (size.width >= 900 && size.shortestSide >= 600)
              IconButton(
                tooltip: _split ? 'Tabbed view' : 'Split view',
                color: Colors.white70,
                onPressed: () => setState(() => _split = !_split),
                icon: Icon(_split ? Icons.view_agenda : Icons.vertical_split),
              ),
          ],
        ),
      ),
    );

    final codePane = Column(
      children: [
        Expanded(
          child: Padding(
            padding: const EdgeInsets.all(8),
            child: TextField(
              controller: widget.controller,
              maxLines: null,
              expands: true,
              textAlignVertical: TextAlignVertical.top,
              style: const TextStyle(
                fontFamily: 'Consolas',
                fontSize: 12,
                height: 1.4,
              ),
              decoration: InputDecoration(
                filled: true,
                fillColor: const Color(0xFFF8FAFC),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
                hintText: 'Edit the HTML — the preview follows as you type',
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
      padding: const EdgeInsets.all(8),
      child: BrowserFrame(html: _previewHtml, showSourceToggle: false),
    );

    return Column(
      children: [
        controlBar,
        Expanded(
          child: useSplit
              ? Row(
                  children: [
                    Expanded(child: codePane),
                    const VerticalDivider(width: 1),
                    Expanded(child: previewPane),
                  ],
                )
              : IndexedStack(
                  index: _mobileTab,
                  children: [previewPane, codePane],
                ),
        ),
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
      color:
          selected ? Colors.white.withValues(alpha: 0.14) : Colors.transparent,
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
