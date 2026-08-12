import 'package:flutter/foundation.dart';
import 'package:google_mlkit_document_scanner/google_mlkit_document_scanner.dart';

/// ===============================================================
/// MOSUL SCANNER
/// GOOGLE ML KIT DOCUMENT SCANNER
/// ===============================================================
///
/// مسؤول فقط عن Google ML Kit Document Scanner.
/// لا يحتوي على معالجة الصور أو القص أو واجهة التطبيق.
/// ===============================================================

class GoogleScanner {
  GoogleScanner._();

  static Future<List<String>?> scan({
    bool fromGallery = false,
  }) async {
    final options = DocumentScannerOptions(
      documentFormats: {
        DocumentFormat.jpeg,
        DocumentFormat.pdf,
      },
      mode: ScannerMode.full,
      pageLimit: 5,

      // Google ML Kit يحتاج هذا مفعلاً حتى يستطيع
      // المستخدم استيراد صورة من المعرض.
      isGalleryImport: true,
    );

    final scanner = DocumentScanner(options: options);

    try {
      debugPrint(
        'Google Scanner: starting '
        '(fromGallery: $fromGallery)',
      );

      final result = await scanner.scanDocument();

      // في إصدار الحزمة لديك images يمكن أن تكون null.
      final images = result.images;

      if (images == null || images.isEmpty) {
        debugPrint('Google Scanner: no images returned');
        return null;
      }

      debugPrint(
        'Google Scanner: ${images.length} image(s) returned',
      );

      return images;
    } catch (e, stackTrace) {
      debugPrint('Google Document Scanner Error: $e');
      debugPrint('$stackTrace');
      return null;
    } finally {
      try {
        await scanner.close();
      } catch (e) {
        debugPrint('Google Scanner close error: $e');
      }
    }
  }
}
