import 'package:flutter/foundation.dart' show compute;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../ai_core/providers/ai_provider.dart';
import '../../../shared/coding/code_autocorrect.dart' show CodeAutocorrectKind;
import '../../../shared/coding/code_instruction_edit.dart';
import '../../../shared/coding/html_images.dart';
import '../../../shared/coding/image_instruction.dart';
import '../../../shared/coding/image_palette.dart';
import '../../../shared/coding/quick_style_edit.dart';
import '../../../shared/coding/ui_look.dart';
import '../../settings/coder_package_prompt.dart';

/// Runs "do this with the picture I attached" from the Tell-AI bar on a
/// built app or website. "Make the UI like this" matches the screenshot's
/// look; otherwise the picture is placed and styled. None of that needs the
/// model — only leftover styling goes to the coder, as a CSS patch aimed at
/// the placed picture. Null when nothing changed; an unchanged [html] with a
/// message when the picture couldn't be used.
Future<({String html, String message})?> runImageInstruction({
  required BuildContext context,
  required WidgetRef ref,
  required String html,
  required String instruction,
  required List<PickedImage> images,
}) async {
  if (isLookRequest(instruction)) {
    final look = await compute(analyzeUiScreenshot, images.first.bytes);
    if (look == null) {
      return (
        html: html,
        message: "I couldn't read that picture — try a PNG or JPG screenshot.",
      );
    }
    return (
      html: applyUiLook(html, look),
      message:
          'Matched the look: ${look.describe().join(', ')}. '
          'The layout and fonts stay your own.',
    );
  }

  final result = applyImageInstruction(html, instruction, images);
  var out = result.html;
  final notes = <String>[result.summary];

  if (result.wantsColours) {
    final style = await compute(paletteStyleFromImageBytes, images.first.bytes);
    if (style != null) {
      out = applyQuickStyle(out, readQuickStyle(out).merge(style));
    } else {
      notes.add("I couldn't read that picture's colours.");
    }
  }

  final modelInstruction = result.modelInstruction;
  if (modelInstruction != null && context.mounted) {
    final coderOk = await promptAndFetchCoderPackage(context, ref);
    if (coderOk && context.mounted) {
      try {
        final engine = await ref.read(programmingEngineProvider.future);
        final masked = maskEmbeddedImages(out);
        final edited = await applyCodeInstruction(
          source: masked.text,
          instruction: modelInstruction,
          kind: CodeAutocorrectKind.html,
          engine: engine,
        );
        if (edited != null) {
          out = masked.restore(edited);
        } else {
          notes.add("Part of the style change couldn't be applied.");
        }
      } catch (_) {
        notes.add("Part of the style change couldn't be applied.");
      }
    }
  }

  if (out == html) return null;
  return (html: out, message: notes.where((n) => n.isNotEmpty).join(' '));
}
