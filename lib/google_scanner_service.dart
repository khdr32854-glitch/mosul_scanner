import 'package:flutter/foundation.dart';
import 'package:google_mlkit_document_scanner/google_mlkit_document_scanner.dart';

/// ===============================================================
/// GOOGLE SCANNER SERVICE - خدمة ماسح المستندات الذكي
/// ===============================================================
class GoogleScannerService {
  /// يقوم بتشغيل ماسح جوجل الذكي محلياً (Offline AI)
  static Future<List<String>?> scanDocument({bool fromGallery = false}) async {
    final options = DocumentScannerOptions(
      documentFormats: {
        DocumentFormat.jpeg,
        DocumentFormat.pdf,
      },
      mode: ScannerMode.full,
      pageLimit: 5, 
      isGalleryImport: true, 
    );

    final scanner = DocumentScanner(options: options);

    try {
      final result = await scanner.scanDocument();
      return result.images;
    } catch (e) {
      debugPrint('Google Document Scanner Error: $e');
      return null;
    } finally {
      try {
        await scanner.close();
      } catch (_) {}
    }
  }
}
