import 'package:flutter/material.dart';

import 'html_preview.dart';

/// Pulls runnable HTML documents out of a tutor reply so the chat can render
/// them like a mini offline browser instead of leaving them as dead text.
///
/// Prefers fenced ` ```html ` blocks (what the coder is prompted to emit);
/// falls back to a bare `<!DOCTYPE html>…</html>` document if the model
/// forgot the fence.
List<String> extractHtmlBlocksFromChat(String text) {
  final blocks = <String>[];
  final fenceRe = RegExp(
    r'```(?:html|HTML|htm)\s*\n?([\s\S]*?)```',
    multiLine: true,
  );
  for (final m in fenceRe.allMatches(text)) {
    final code = (m.group(1) ?? '').trim();
    if (code.isNotEmpty) blocks.add(code);
  }
  if (blocks.isEmpty) {
    final docRe = RegExp(
      r'<!DOCTYPE\s+html[\s\S]*?</html\s*>',
      caseSensitive: false,
    );
    final m = docRe.firstMatch(text);
    if (m != null) blocks.add(m.group(0)!.trim());
  }
  return blocks;
}

/// One HTML block from a chat reply, shown in the shared browser chrome.
class ChatHtmlPreviewCard extends StatelessWidget {
  const ChatHtmlPreviewCard({super.key, required this.html});

  final String html;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(top: 10),
      child: BrowserFrame(html: html, height: 300),
    );
  }
}
