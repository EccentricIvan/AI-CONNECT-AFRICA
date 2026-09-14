import '../ai_core/inference/runtime_config.dart';

/// Flushes coder/UI tokens the moment a clause ends or the pending span
/// crosses [flushChars] (default 60) so the preview stays fluid.
class ClauseStreamChopper {
  ClauseStreamChopper({
    this.flushChars = kCoderStreamFlushChars,
    this.onFlush,
  });

  final int flushChars;
  final void Function(String cumulative)? onFlush;

  final StringBuffer _pending = StringBuffer();
  final StringBuffer _all = StringBuffer();

  String get cumulative => _all.toString();

  /// Ingest one model token; may emit zero or more UI flushes.
  void add(String token) {
    if (token.isEmpty) return;
    _pending.write(token);
    _all.write(token);
    _drain(flush: false);
  }

  /// Emit any remainder (end of generation).
  void end() => _drain(flush: true);

  void _drain({required bool flush}) {
    var rest = _pending.toString();
    if (rest.isEmpty) return;
    final ready = <String>[];
    final sentence = RegExp(r'[\s\S]*?[.!?…]["”)]*(?:\s+|$)');
    while (rest.isNotEmpty) {
      if (rest.contains('\n')) {
        final i = rest.indexOf('\n');
        final left = rest.substring(0, i + 1);
        if (left.isNotEmpty) ready.add(left);
        rest = rest.substring(i + 1);
        continue;
      }
      final m = sentence.firstMatch(rest);
      if (m != null && RegExp(r'[.!?…]').hasMatch(m.group(0)!)) {
        ready.add(m.group(0)!);
        rest = rest.substring(m.group(0)!.length);
        continue;
      }
      if (!flush && rest.length >= flushChars) {
        ready.add(rest);
        rest = '';
        break;
      }
      if (flush) {
        if (rest.isNotEmpty) ready.add(rest);
        rest = '';
        break;
      }
      break;
    }
    _pending
      ..clear()
      ..write(rest);
    if (ready.isEmpty) return;
    onFlush?.call(_all.toString());
  }
}
