import 'dart:io';

/// GGUF files start with the ASCII magic `GGUF`.
bool hasGgufMagic(List<int> header) {
  return header.length >= 4 &&
      header[0] == 0x47 &&
      header[1] == 0x47 &&
      header[2] == 0x55 &&
      header[3] == 0x46;
}

/// True when [file] exists and opens with a GGUF header.
///
/// Used so an HTML error page or leftover `.part` rename cannot be
/// treated as a ready AfriSLM / chat brain.
Future<bool> fileLooksLikeGguf(File file) async {
  RandomAccessFile? raf;
  try {
    if (!await file.exists()) return false;
    raf = await file.open();
    final bytes = await raf.read(4);
    return hasGgufMagic(bytes);
  } catch (_) {
    return false;
  } finally {
    try {
      await raf?.close();
    } catch (_) {}
  }
}
