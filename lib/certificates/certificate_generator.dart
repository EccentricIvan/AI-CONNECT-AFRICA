import 'dart:io';
import 'package:path_provider/path_provider.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;

class CertificateResult {
  const CertificateResult({required this.filePath, required this.fileName});
  final String filePath;
  final String fileName;
}

class CertificateGenerator {
  /// Generates an offline PDF certificate and saves it to the device.
  /// Returns the saved file path.
  static Future<CertificateResult> generate({
    required String studentName,
    required String pathTitle,
    required String topic,
    String schoolName = 'School',
  }) async {
    final doc = pw.Document();
    final dateStr = _formatDate(DateTime.now());

    doc.addPage(
      pw.Page(
        pageFormat: PdfPageFormat.a4,
        margin: const pw.EdgeInsets.all(48),
        build: (pw.Context context) {
          return pw.Column(
            mainAxisAlignment: pw.MainAxisAlignment.center,
            children: [
              // Top border decoration
              pw.Container(
                height: 8,
                color: const PdfColor.fromInt(0xFF1F6BE5),
              ),
              pw.SizedBox(height: 40),

              // Header
              pw.Text(
                schoolName.toUpperCase(),
                style: const pw.TextStyle(
                  fontSize: 14,
                  fontWeight: pw.FontWeight.bold,
                  color: PdfColor.fromInt(0xFF1F6BE5),
                  letterSpacing: 3,
                ),
              ),
              pw.SizedBox(height: 8),
              pw.Container(
                width: 60,
                height: 2,
                color: const PdfColor.fromInt(0xFF1F6BE5),
              ),
              pw.SizedBox(height: 40),

              // Title
              pw.Text(
                'CERTIFICATE OF COMPLETION',
                style: const pw.TextStyle(
                  fontSize: 26,
                  fontWeight: pw.FontWeight.bold,
                  color: PdfColor.fromInt(0xFF142840),
                ),
                textAlign: pw.TextAlign.center,
              ),
              pw.SizedBox(height: 32),

              pw.Text(
                'This is to certify that',
                style: const pw.TextStyle(
                  fontSize: 14,
                  color: PdfColor.fromInt(0xFF3D5A73),
                ),
              ),
              pw.SizedBox(height: 16),

              // Student name
              pw.Text(
                studentName,
                style: const pw.TextStyle(
                  fontSize: 32,
                  fontWeight: pw.FontWeight.bold,
                  color: PdfColor.fromInt(0xFF142840),
                ),
                textAlign: pw.TextAlign.center,
              ),
              pw.SizedBox(height: 16),

              pw.Text(
                'has successfully completed the learning path',
                style: const pw.TextStyle(
                  fontSize: 14,
                  color: PdfColor.fromInt(0xFF3D5A73),
                ),
              ),
              pw.SizedBox(height: 20),

              // Path title
              pw.Container(
                padding: const pw.EdgeInsets.symmetric(
                  horizontal: 24,
                  vertical: 12,
                ),
                decoration: pw.BoxDecoration(
                  color: const PdfColor.fromInt(0xFFF3F9FD),
                  borderRadius: pw.BorderRadius.circular(8),
                ),
                child: pw.Text(
                  pathTitle,
                  style: const pw.TextStyle(
                    fontSize: 18,
                    fontWeight: pw.FontWeight.bold,
                    color: PdfColor.fromInt(0xFF1F6BE5),
                  ),
                  textAlign: pw.TextAlign.center,
                ),
              ),
              pw.SizedBox(height: 12),

              pw.Text(
                'Topic: $topic',
                style: const pw.TextStyle(
                  fontSize: 13,
                  color: PdfColor.fromInt(0xFF3D5A73),
                ),
              ),
              pw.SizedBox(height: 40),

              // Date
              pw.Text(
                'Awarded on $dateStr',
                style: const pw.TextStyle(
                  fontSize: 12,
                  color: PdfColor.fromInt(0xFF94A3B8),
                ),
              ),
              pw.SizedBox(height: 40),

              // Footer line
              pw.Divider(color: const PdfColor.fromInt(0xFFE2E8F0)),
              pw.SizedBox(height: 12),
              pw.Text(
                'Offline AI Learning OS',
                style: const pw.TextStyle(
                  fontSize: 10,
                  color: PdfColor.fromInt(0xFF94A3B8),
                ),
              ),

              pw.SizedBox(height: 40),
              // Bottom border
              pw.Container(
                height: 8,
                color: const PdfColor.fromInt(0xFF10B981),
              ),
            ],
          );
        },
      ),
    );

    final bytes = await doc.save();
    final dir = await getApplicationDocumentsDirectory();
    final certsDir = Directory(
      '${dir.path}${Platform.pathSeparator}otic_certificates',
    );
    await certsDir.create(recursive: true);

    final safeName = studentName.replaceAll(RegExp(r'[^a-zA-Z0-9]'), '_');
    final safeTopic = topic.replaceAll(RegExp(r'[^a-zA-Z0-9]'), '_');
    final timestamp = DateTime.now().millisecondsSinceEpoch;
    final fileName = '${safeName}_${safeTopic}_$timestamp.pdf';
    final filePath = '${certsDir.path}${Platform.pathSeparator}$fileName';

    await File(filePath).writeAsBytes(bytes);
    return CertificateResult(filePath: filePath, fileName: fileName);
  }

  static String _formatDate(DateTime d) {
    const months = [
      'January',
      'February',
      'March',
      'April',
      'May',
      'June',
      'July',
      'August',
      'September',
      'October',
      'November',
      'December',
    ];
    return '${months[d.month - 1]} ${d.day}, ${d.year}';
  }
}
