import 'package:flutter/material.dart';

import 'app_build_intent.dart';

/// Live Flutter preview driven by the locked feature intent.
///
/// Generated Dart is shown in Code view for learning/editing; Preview always
/// renders a real widget tree from [intent] so Build never depends on eval.
class AppLivePreview extends StatelessWidget {
  const AppLivePreview({super.key, required this.intent});

  final AppBuildIntent intent;

  @override
  Widget build(BuildContext context) {
    final theme = appLabThemeById(intent.themeId) ?? kAppLabThemes.first;
    return ColoredBox(
      color: theme.background,
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 420),
          child: Material(
            color: theme.surface,
            elevation: 8,
            borderRadius: BorderRadius.circular(24),
            clipBehavior: Clip.antiAlias,
            child: SizedBox(
              height: 640,
              child: Theme(
                data: ThemeData(
                  colorScheme: ColorScheme.fromSeed(
                    seedColor: theme.primary,
                    brightness: theme.background.computeLuminance() < 0.35
                        ? Brightness.dark
                        : Brightness.light,
                  ),
                  useMaterial3: true,
                ),
                child: switch (intent.appTypeId) {
                  'expense' => _ExpensePreview(intent: intent, theme: theme),
                  'quiz' => _QuizPreview(intent: intent, theme: theme),
                  'calculator' => _CalculatorPreview(intent: intent, theme: theme),
                  _ => _TodoPreview(intent: intent, theme: theme),
                },
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _PhoneChrome extends StatelessWidget {
  const _PhoneChrome({
    required this.intent,
    required this.theme,
    required this.child,
  });

  final AppBuildIntent intent;
  final AppLabTheme theme;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Container(
          padding: const EdgeInsets.fromLTRB(16, 18, 16, 14),
          color: theme.primary,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                intent.appName,
                style: TextStyle(
                  color: theme.onPrimary,
                  fontSize: 20,
                  fontWeight: FontWeight.w700,
                ),
              ),
              if (intent.purpose.isNotEmpty) ...[
                const SizedBox(height: 4),
                Text(
                  intent.purpose,
                  style: TextStyle(
                    color: theme.onPrimary.withValues(alpha: 0.9),
                    fontSize: 12,
                  ),
                ),
              ],
            ],
          ),
        ),
        Expanded(child: child),
      ],
    );
  }
}

class _TodoPreview extends StatefulWidget {
  const _TodoPreview({required this.intent, required this.theme});
  final AppBuildIntent intent;
  final AppLabTheme theme;

  @override
  State<_TodoPreview> createState() => _TodoPreviewState();
}

class _TodoPreviewState extends State<_TodoPreview> {
  final _controller = TextEditingController();
  final _items = <({String text, bool done})>[];

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return _PhoneChrome(
      intent: widget.intent,
      theme: widget.theme,
      child: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          if (widget.intent.features.isNotEmpty) ...[
            Text(
              'Features',
              style: Theme.of(context).textTheme.titleSmall,
            ),
            const SizedBox(height: 8),
            Wrap(
              spacing: 6,
              runSpacing: 6,
              children: widget.intent.features
                  .map((f) => Chip(label: Text(f, style: const TextStyle(fontSize: 11))))
                  .toList(),
            ),
            const SizedBox(height: 16),
          ],
          if (widget.intent.features.contains('Add task') ||
              widget.intent.features.contains('Task list') ||
              widget.intent.features.isEmpty) ...[
            TextField(
              controller: _controller,
              decoration: const InputDecoration(
                labelText: 'New task',
                border: OutlineInputBorder(),
              ),
              onSubmitted: (_) => _add(),
            ),
            const SizedBox(height: 8),
            FilledButton(onPressed: _add, child: const Text('Add task')),
            const SizedBox(height: 12),
          ],
          ..._items.asMap().entries.map((e) {
            final i = e.key;
            final item = e.value;
            return CheckboxListTile(
              value: item.done,
              title: Text(
                item.text,
                style: TextStyle(
                  decoration: item.done ? TextDecoration.lineThrough : null,
                ),
              ),
              onChanged: (v) => setState(() {
                _items[i] = (text: item.text, done: v ?? false);
              }),
            );
          }),
        ],
      ),
    );
  }

  void _add() {
    final t = _controller.text.trim();
    if (t.isEmpty) return;
    setState(() {
      _items.add((text: t, done: false));
      _controller.clear();
    });
  }
}

class _ExpensePreview extends StatefulWidget {
  const _ExpensePreview({required this.intent, required this.theme});
  final AppBuildIntent intent;
  final AppLabTheme theme;

  @override
  State<_ExpensePreview> createState() => _ExpensePreviewState();
}

class _ExpensePreviewState extends State<_ExpensePreview> {
  final _label = TextEditingController();
  final _amount = TextEditingController();
  final _rows = <({String label, double amount})>[];

  @override
  void dispose() {
    _label.dispose();
    _amount.dispose();
    super.dispose();
  }

  double get _total => _rows.fold(0, (a, b) => a + b.amount);

  @override
  Widget build(BuildContext context) {
    return _PhoneChrome(
      intent: widget.intent,
      theme: widget.theme,
      child: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Text(
            'Total: ${_total.toStringAsFixed(2)}',
            style: Theme.of(context).textTheme.titleMedium,
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _label,
            decoration: const InputDecoration(
              labelText: 'Expense',
              border: OutlineInputBorder(),
            ),
          ),
          const SizedBox(height: 8),
          TextField(
            controller: _amount,
            keyboardType: TextInputType.number,
            decoration: const InputDecoration(
              labelText: 'Amount',
              border: OutlineInputBorder(),
            ),
          ),
          const SizedBox(height: 8),
          FilledButton(
            onPressed: () {
              final amt = double.tryParse(_amount.text.trim()) ?? 0;
              final label = _label.text.trim();
              if (label.isEmpty || amt <= 0) return;
              setState(() {
                _rows.add((label: label, amount: amt));
                _label.clear();
                _amount.clear();
              });
            },
            child: const Text('Add expense'),
          ),
          const SizedBox(height: 12),
          ..._rows.map(
            (r) => ListTile(
              title: Text(r.label),
              trailing: Text(r.amount.toStringAsFixed(2)),
            ),
          ),
        ],
      ),
    );
  }
}

class _QuizPreview extends StatefulWidget {
  const _QuizPreview({required this.intent, required this.theme});
  final AppBuildIntent intent;
  final AppLabTheme theme;

  @override
  State<_QuizPreview> createState() => _QuizPreviewState();
}

class _QuizPreviewState extends State<_QuizPreview> {
  static const _qs = [
    ('2 + 2 = ?', ['3', '4', '5'], 1),
    ('Capital of Kenya?', ['Nairobi', 'Kampala', 'Kigali'], 0),
  ];
  var _i = 0;
  var _score = 0;
  var _done = false;

  @override
  Widget build(BuildContext context) {
    return _PhoneChrome(
      intent: widget.intent,
      theme: widget.theme,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: _done
            ? Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Text('Score: $_score / ${_qs.length}',
                      style: Theme.of(context).textTheme.headlineSmall),
                  const SizedBox(height: 16),
                  FilledButton(
                    onPressed: () => setState(() {
                      _i = 0;
                      _score = 0;
                      _done = false;
                    }),
                    child: const Text('Restart quiz'),
                  ),
                ],
              )
            : Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text('Score: $_score', style: Theme.of(context).textTheme.titleSmall),
                  const SizedBox(height: 12),
                  Text(_qs[_i].$1, style: Theme.of(context).textTheme.titleLarge),
                  const SizedBox(height: 16),
                  ..._qs[_i].$2.asMap().entries.map((e) {
                    return Padding(
                      padding: const EdgeInsets.only(bottom: 8),
                      child: OutlinedButton(
                        onPressed: () {
                          if (e.key == _qs[_i].$3) _score++;
                          setState(() {
                            if (_i + 1 >= _qs.length) {
                              _done = true;
                            } else {
                              _i++;
                            }
                          });
                        },
                        child: Text(e.value),
                      ),
                    );
                  }),
                ],
              ),
      ),
    );
  }
}

class _CalculatorPreview extends StatefulWidget {
  const _CalculatorPreview({required this.intent, required this.theme});
  final AppBuildIntent intent;
  final AppLabTheme theme;

  @override
  State<_CalculatorPreview> createState() => _CalculatorPreviewState();
}

class _CalculatorPreviewState extends State<_CalculatorPreview> {
  String _display = '0';
  double? _acc;
  String? _op;

  void _digit(String d) {
    setState(() {
      if (_display == '0') {
        _display = d;
      } else {
        _display += d;
      }
    });
  }

  void _setOp(String op) {
    _acc = double.tryParse(_display) ?? 0;
    _op = op;
    _display = '0';
    setState(() {});
  }

  void _eq() {
    final b = double.tryParse(_display) ?? 0;
    final a = _acc ?? 0;
    double r = b;
    switch (_op) {
      case '+':
        r = a + b;
      case '-':
        r = a - b;
      case '×':
        r = a * b;
      case '÷':
        r = b == 0 ? 0 : a / b;
    }
    setState(() {
      _display = (r == r.roundToDouble()) ? '${r.toInt()}' : r.toStringAsFixed(2);
      _acc = null;
      _op = null;
    });
  }

  void _clear() => setState(() {
        _display = '0';
        _acc = null;
        _op = null;
      });

  @override
  Widget build(BuildContext context) {
    final keys = [
      ['7', '8', '9', '÷'],
      ['4', '5', '6', '×'],
      ['1', '2', '3', '-'],
      ['C', '0', '=', '+'],
    ];
    return _PhoneChrome(
      intent: widget.intent,
      theme: widget.theme,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          children: [
            Align(
              alignment: Alignment.centerRight,
              child: Text(_display, style: Theme.of(context).textTheme.headlineMedium),
            ),
            const SizedBox(height: 16),
            Expanded(
              child: Column(
                children: [
                  for (final row in keys)
                    Expanded(
                      child: Row(
                        children: [
                          for (final k in row)
                            Expanded(
                              child: Padding(
                                padding: const EdgeInsets.all(4),
                                child: FilledButton.tonal(
                                  onPressed: () {
                                    if (k == 'C') {
                                      _clear();
                                    } else if (k == '=') {
                                      _eq();
                                    } else if ('+-×÷'.contains(k)) {
                                      _setOp(k);
                                    } else {
                                      _digit(k);
                                    }
                                  },
                                  child: Text(k, style: const TextStyle(fontSize: 18)),
                                ),
                              ),
                            ),
                        ],
                      ),
                    ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
