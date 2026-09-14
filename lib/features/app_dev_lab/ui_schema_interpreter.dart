import 'dart:convert';

import 'package:flutter/material.dart';

import 'app_build_intent.dart';

/// One declarative node from the Qwen 1.5B App Dev Lab schema stream.
@immutable
class UiSchemaNode {
  const UiSchemaNode({
    required this.type,
    this.text = '',
    this.label = '',
    this.hint = '',
    this.action = '',
    this.style = '',
    this.title = '',
    this.items = const [],
  });

  final String type;
  final String text;
  final String label;
  final String hint;
  final String action;
  final String style;
  final String title;
  final List<String> items;

  String get normalizedType => type.trim().toLowerCase();
}

/// Parsed document: optional title/style + ordered nodes.
@immutable
class UiSchemaDocument {
  const UiSchemaDocument({
    this.title = 'Student App',
    this.style = '',
    this.nodes = const [],
  });

  final String title;
  final String style;
  final List<UiSchemaNode> nodes;

  bool get isEmpty => nodes.isEmpty;
}

final _fenceRe = RegExp(
  r'```(?:ui|schema|otic[_-]?ui)?\s*([\s\S]*?)```',
  caseSensitive: false,
);

final _typeLineRe = RegExp(
  r'^\s*(?:[-*•]\s*)?type\s*:\s*(.+)$',
  caseSensitive: false,
);

/// Strip markdown fences / chatter and keep the schema body.
String stripUiSchemaNoise(String raw) {
  var s = raw.trim();
  if (s.isEmpty) return s;
  final fenced = _fenceRe.firstMatch(s);
  if (fenced != null) {
    s = (fenced.group(1) ?? '').trim();
  }
  s = s.replaceAll(
    RegExp(r'<think>[\s\S]*?</think>', caseSensitive: false),
    '',
  );
  final start = RegExp(
    r'(OTIC_UI_V1|^\s*type\s*:)',
    caseSensitive: false,
    multiLine: true,
  ).firstMatch(s);
  if (start != null && start.start > 0) {
    s = s.substring(start.start);
  }
  return s.trim();
}

Map<String, String> _parseKvCsv(String body) {
  final out = <String, String>{};
  for (final part in body.split(',')) {
    final idx = part.indexOf(':');
    if (idx <= 0) continue;
    final key = part.substring(0, idx).trim().toLowerCase();
    final value = part.substring(idx + 1).trim();
    if (key.isEmpty) continue;
    out[key] = value;
  }
  return out;
}

UiSchemaNode? _nodeFromMap(Map<String, String> m) {
  final type = (m['type'] ?? '').trim();
  if (type.isEmpty) return null;
  final itemsRaw = m['items'] ?? '';
  final items = itemsRaw.isEmpty
      ? const <String>[]
      : itemsRaw
          .split(RegExp(r'[|•;]'))
          .map((e) => e.trim())
          .where((e) => e.isNotEmpty)
          .toList();
  return UiSchemaNode(
    type: type,
    text: m['text'] ?? '',
    label: m['label'] ?? '',
    hint: m['hint'] ?? m['placeholder'] ?? '',
    action: m['action'] ?? '',
    style: m['style'] ?? '',
    title: m['title'] ?? '',
    items: items,
  );
}

/// Parse a coder schema block. Returns null only when nothing usable remains.
UiSchemaDocument? parseUiSchema(String raw) {
  try {
    final cleaned = stripUiSchemaNoise(raw);
    if (cleaned.isEmpty) return null;

    var title = 'Student App';
    var style = '';
    final nodes = <UiSchemaNode>[];

    for (final line in cleaned.split(RegExp(r'\r?\n'))) {
      final trimmed = line.trim();
      if (trimmed.isEmpty || trimmed == '---') continue;
      if (trimmed.toUpperCase().startsWith('OTIC_UI')) continue;

      final titleMatch = RegExp(
        r'^title\s*:\s*(.+)$',
        caseSensitive: false,
      ).firstMatch(trimmed);
      if (titleMatch != null) {
        title = titleMatch.group(1)!.trim();
        continue;
      }
      final styleMatch = RegExp(
        r'^style\s*:\s*(.+)$',
        caseSensitive: false,
      ).firstMatch(trimmed);
      if (styleMatch != null) {
        style = styleMatch.group(1)!.trim();
        continue;
      }

      final typeLine = _typeLineRe.firstMatch(trimmed);
      if (typeLine == null) continue;

      final body = typeLine.group(1)!.trim();
      late final Map<String, String> map;
      if (body.contains(':')) {
        final firstComma = body.indexOf(',');
        if (firstComma > 0 && !body.substring(0, firstComma).contains(':')) {
          map = {
            'type': body.substring(0, firstComma).trim(),
            ..._parseKvCsv(body.substring(firstComma + 1)),
          };
        } else {
          map = _parseKvCsv(
            RegExp(r'^type\s*:', caseSensitive: false).hasMatch(body)
                ? body
                : 'type: $body',
          );
        }
      } else {
        map = {'type': body};
      }
      final node = _nodeFromMap(map);
      if (node != null) nodes.add(node);
    }

    if (nodes.isEmpty) return null;
    return UiSchemaDocument(title: title, style: style, nodes: nodes);
  } catch (e, st) {
    debugPrint('parseUiSchema failed: $e\n$st');
    return null;
  }
}

/// Offline default schema so the canvas never goes blank.
String fallbackUiSchemaSource(AppBuildIntent intent) {
  final name = intent.appName;
  final purpose = intent.purpose.isEmpty ? intent.appTypeName : intent.purpose;
  final style = intent.themeName;
  final featureChips = intent.features.isEmpty
      ? 'Type: Chip, Text: Home screen'
      : intent.features.map((f) => 'Type: Chip, Text: $f').join('\n');

  return '''
OTIC_UI_V1
title: $name
style: $style
---
Type: Header, Text: $name
Type: Text, Text: $purpose
Type: Card, Title: Features, Text: Offline feature template — edit Source and tap Apply Changes.
$featureChips
Type: TextField, Label: Quick try, Hint: Type something…
Type: Button, Text: Save, Action: Alert, Style: $style
Type: List, Items: Sample item 1|Sample item 2|Sample item 3
''';
}

UiSchemaDocument fallbackUiSchemaDocument(AppBuildIntent intent) {
  return parseUiSchema(fallbackUiSchemaSource(intent)) ??
      const UiSchemaDocument(
        title: 'Student App',
        nodes: [
          UiSchemaNode(type: 'Header', text: 'Student App'),
          UiSchemaNode(type: 'Text', text: 'Offline preview ready.'),
          UiSchemaNode(type: 'Button', text: 'OK', action: 'Alert'),
        ],
      );
}

/// Resolve schema text → document, never null (uses [intent] fallback).
UiSchemaDocument resolveUiSchema(
  String source, {
  AppBuildIntent? intent,
}) {
  final parsed = parseUiSchema(source);
  if (parsed != null && !parsed.isEmpty) return parsed;
  if (intent != null) return fallbackUiSchemaDocument(intent);
  return const UiSchemaDocument(
    title: 'Preview',
    nodes: [
      UiSchemaNode(type: 'Header', text: 'Preview'),
      UiSchemaNode(
        type: 'Text',
        text: 'Schema incomplete — showing safe offline layout.',
      ),
      UiSchemaNode(type: 'Button', text: 'OK', action: 'Alert'),
    ],
  );
}

bool _isCyber(String style) {
  final s = style.toLowerCase();
  return s.contains('cyber') ||
      s.contains('neon') ||
      s.contains('obsidian') ||
      s.contains('dark');
}

Color _primaryFor(String style, AppLabTheme? theme) {
  if (theme != null) return theme.primary;
  if (_isCyber(style)) return const Color(0xFF22D3EE);
  return const Color(0xFF0EA5E9);
}

/// Native Flutter canvas mapped from a declarative UI schema.
class UiSchemaInterpreter extends StatefulWidget {
  const UiSchemaInterpreter({
    super.key,
    required this.source,
    this.intent,
    this.borderRadius = 12,
  });

  final String source;
  final AppBuildIntent? intent;
  final double borderRadius;

  @override
  State<UiSchemaInterpreter> createState() => _UiSchemaInterpreterState();
}

class _UiSchemaInterpreterState extends State<UiSchemaInterpreter> {
  late UiSchemaDocument _doc;
  var _usedFallback = false;
  final _fieldControllers = <String, TextEditingController>{};
  final _listItems = <String>[];

  @override
  void initState() {
    super.initState();
    _hydrate(widget.source);
  }

  @override
  void didUpdateWidget(covariant UiSchemaInterpreter oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.source != widget.source) {
      _hydrate(widget.source);
    }
  }

  @override
  void dispose() {
    for (final c in _fieldControllers.values) {
      c.dispose();
    }
    super.dispose();
  }

  void _hydrate(String source) {
    for (final c in _fieldControllers.values) {
      c.dispose();
    }
    _fieldControllers.clear();
    _listItems.clear();

    late UiSchemaDocument doc;
    var fallback = false;
    try {
      final parsed = parseUiSchema(source);
      if (parsed == null || parsed.isEmpty) {
        doc = widget.intent != null
            ? fallbackUiSchemaDocument(widget.intent!)
            : resolveUiSchema(source);
        fallback = true;
      } else {
        doc = parsed;
      }
    } catch (_) {
      doc = widget.intent != null
          ? fallbackUiSchemaDocument(widget.intent!)
          : resolveUiSchema('');
      fallback = true;
    }

    for (final n in doc.nodes) {
      if (n.normalizedType == 'list' && n.items.isNotEmpty) {
        _listItems.addAll(n.items);
      }
    }

    setState(() {
      _doc = doc;
      _usedFallback = fallback;
    });
  }

  TextEditingController _ctrl(String key) =>
      _fieldControllers.putIfAbsent(key, TextEditingController.new);

  void _runAction(UiSchemaNode node) {
    final action = node.action.toLowerCase();
    final label = node.text.isNotEmpty ? node.text : 'Action';
    if (action.contains('alert') || action.isEmpty) {
      final msg = _fieldControllers.values
          .map((c) => c.text.trim())
          .where((t) => t.isNotEmpty)
          .join('\n');
      showDialog<void>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: Text(label),
          content: Text(
            msg.isEmpty ? 'Saved in this offline preview.' : msg,
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('OK'),
            ),
          ],
        ),
      );
      return;
    }
    if (action.contains('add') || action.contains('save')) {
      final text = _fieldControllers.values
          .map((c) => c.text.trim())
          .firstWhere((t) => t.isNotEmpty, orElse: () => '');
      if (text.isEmpty) return;
      setState(() {
        _listItems.add(text);
        for (final c in _fieldControllers.values) {
          c.clear();
        }
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = widget.intent != null
        ? appLabThemeById(widget.intent!.themeId)
        : null;
    final cyber = _isCyber(
      _doc.style.isNotEmpty
          ? _doc.style
          : (theme?.name ?? widget.intent?.themeName ?? ''),
    );
    final primary = _primaryFor(_doc.style, theme);
    final bg = theme?.background ??
        (cyber ? const Color(0xFF12061F) : const Color(0xFFF1F5F9));
    final surface = theme?.surface ??
        (cyber ? const Color(0xFF1E1033) : Colors.white);
    final onPrimary = theme?.onPrimary ?? Colors.white;
    final fg = cyber ? const Color(0xFFE2E8F0) : const Color(0xFF0F172A);
    final muted = cyber ? const Color(0xFF94A3B8) : const Color(0xFF475569);

    return ClipRRect(
      borderRadius: BorderRadius.circular(widget.borderRadius),
      child: ColoredBox(
        color: bg,
        child: SingleChildScrollView(
          scrollDirection: Axis.vertical,
          child: SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: ConstrainedBox(
              constraints: BoxConstraints(
                minWidth: MediaQuery.sizeOf(context).width,
                minHeight: 420,
              ),
              child: Center(
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 420),
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Material(
                      color: surface,
                      elevation: 8,
                      borderRadius: BorderRadius.circular(24),
                      clipBehavior: Clip.antiAlias,
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Container(
                            padding: const EdgeInsets.fromLTRB(16, 18, 16, 14),
                            decoration: BoxDecoration(
                              color: primary,
                              boxShadow: cyber
                                  ? [
                                      BoxShadow(
                                        color: primary.withValues(alpha: 0.45),
                                        blurRadius: 18,
                                      ),
                                    ]
                                  : null,
                            ),
                            child: Text(
                              _doc.title,
                              style: TextStyle(
                                color: onPrimary,
                                fontSize: 20,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                          ),
                          if (_usedFallback)
                            const MaterialBanner(
                              content: Text(
                                'Incomplete schema — offline template loaded.',
                                style: TextStyle(fontSize: 12),
                              ),
                              actions: [SizedBox.shrink()],
                              padding: EdgeInsets.symmetric(
                                horizontal: 12,
                                vertical: 4,
                              ),
                            ),
                          Padding(
                            padding: const EdgeInsets.all(16),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.stretch,
                              children: [
                                for (var i = 0; i < _doc.nodes.length; i++)
                                  _buildNode(
                                    _doc.nodes[i],
                                    index: i,
                                    primary: primary,
                                    fg: fg,
                                    muted: muted,
                                    cyber: cyber,
                                  ),
                                if (_listItems.isNotEmpty) ...[
                                  const SizedBox(height: 8),
                                  Text(
                                    'Items',
                                    style: TextStyle(
                                      color: fg,
                                      fontWeight: FontWeight.w700,
                                    ),
                                  ),
                                  const SizedBox(height: 6),
                                  for (final item in _listItems)
                                    ListTile(
                                      dense: true,
                                      contentPadding: EdgeInsets.zero,
                                      leading: Icon(
                                        Icons.check_circle_outline,
                                        color: primary,
                                      ),
                                      title: Text(
                                        item,
                                        style: TextStyle(color: fg),
                                      ),
                                    ),
                                ],
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildNode(
    UiSchemaNode node, {
    required int index,
    required Color primary,
    required Color fg,
    required Color muted,
    required bool cyber,
  }) {
    switch (node.normalizedType) {
      case 'header':
      case 'title':
        return Padding(
          padding: const EdgeInsets.only(bottom: 10),
          child: Text(
            node.text,
            style: TextStyle(
              fontSize: 22,
              fontWeight: FontWeight.w800,
              color: fg,
            ),
          ),
        );
      case 'text':
      case 'label':
      case 'paragraph':
        return Padding(
          padding: const EdgeInsets.only(bottom: 10),
          child: Text(
            node.text,
            style: TextStyle(fontSize: 14, height: 1.4, color: muted),
          ),
        );
      case 'chip':
      case 'tag':
        return Padding(
          padding: const EdgeInsets.only(bottom: 8, right: 6),
          child: Align(
            alignment: Alignment.centerLeft,
            child: Chip(
              label: Text(node.text),
              backgroundColor: primary.withValues(alpha: 0.15),
              side: BorderSide(color: primary.withValues(alpha: 0.35)),
            ),
          ),
        );
      case 'textfield':
      case 'input':
      case 'field':
        final key = 'field_$index';
        return Padding(
          padding: const EdgeInsets.only(bottom: 10),
          child: TextField(
            controller: _ctrl(key),
            style: TextStyle(color: fg),
            decoration: InputDecoration(
              labelText: node.label.isNotEmpty ? node.label : 'Input',
              hintText: node.hint.isNotEmpty ? node.hint : null,
              labelStyle: TextStyle(color: muted),
              hintStyle: TextStyle(color: muted.withValues(alpha: 0.8)),
              enabledBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
                borderSide: BorderSide(color: muted.withValues(alpha: 0.4)),
              ),
              focusedBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
                borderSide: BorderSide(color: primary, width: 2),
              ),
            ),
          ),
        );
      case 'button':
        final cyberBtn = cyber || _isCyber(node.style);
        return Padding(
          padding: const EdgeInsets.only(bottom: 12),
          child: DecoratedBox(
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(14),
              boxShadow: cyberBtn
                  ? [
                      BoxShadow(
                        color: primary.withValues(alpha: 0.35),
                        blurRadius: 14,
                        offset: const Offset(0, 4),
                      ),
                    ]
                  : null,
            ),
            child: ElevatedButton(
              style: ElevatedButton.styleFrom(
                backgroundColor: primary,
                foregroundColor:
                    cyberBtn ? const Color(0xFF0B0F19) : Colors.white,
                padding: const EdgeInsets.symmetric(
                  horizontal: 18,
                  vertical: 14,
                ),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(14),
                ),
              ),
              onPressed: () => _runAction(node),
              child: Text(
                node.text.isNotEmpty ? node.text : 'Button',
                style: const TextStyle(fontWeight: FontWeight.w700),
              ),
            ),
          ),
        );
      case 'card':
        return Padding(
          padding: const EdgeInsets.only(bottom: 12),
          child: Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: cyber
                  ? Colors.white.withValues(alpha: 0.06)
                  : const Color(0xFFF8FAFC),
              borderRadius: BorderRadius.circular(14),
              border: Border.all(
                color: cyber
                    ? primary.withValues(alpha: 0.35)
                    : const Color(0xFFE2E8F0),
              ),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (node.title.isNotEmpty)
                  Text(
                    node.title,
                    style: TextStyle(
                      fontWeight: FontWeight.w700,
                      color: fg,
                    ),
                  ),
                if (node.text.isNotEmpty) ...[
                  if (node.title.isNotEmpty) const SizedBox(height: 6),
                  Text(node.text, style: TextStyle(color: muted, height: 1.4)),
                ],
              ],
            ),
          ),
        );
      case 'list':
        return const SizedBox.shrink();
      default:
        if (node.text.isEmpty) return const SizedBox.shrink();
        return Padding(
          padding: const EdgeInsets.only(bottom: 8),
          child: Text(node.text, style: TextStyle(color: muted)),
        );
    }
  }
}

/// Encode helper kept for tests / debugging schema payloads.
String encodeSchemaPayload(String source) =>
    base64Encode(utf8.encode(stripUiSchemaNoise(source)));
