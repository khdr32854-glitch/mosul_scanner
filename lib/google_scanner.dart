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

/// نتيجة تشغيل الماسح: إما صور ناجحة، أو نص خطأ واضح لعرضه
/// مباشرة بالواجهة (بدل ابتلاعه بصمت داخل debugPrint فقط).
class GoogleScanResult {
  final List<String>? images;
  final String? errorMessage;

  const GoogleScanResult.success(this.images) : errorMessage = null;

  const GoogleScanResult.failure(this.errorMessage) : images = null;
}

class GoogleScanner {
  GoogleScanner._();

  static Future<GoogleScanResult> scan({
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

    DocumentScanner? scanner;

    try {
      debugPrint(
        'Google Scanner: starting '
        '(fromGallery: $fromGallery)',
      );

      scanner = DocumentScanner(options: options);

      final result = await scanner.scanDocument();

      // في إصدار الحزمة لديك images يمكن أن تكون null.
      final images = result.images;

      if (images == null || images.isEmpty) {
        debugPrint('Google Scanner: no images returned');
        return const GoogleScanResult.failure(
          'الماسح لم يُعِد أي صور (قد يكون المستخدم أغلق الشاشة '
          'بدون التقاط صورة)',
        );
      }

      debugPrint(
        'Google Scanner: ${images.length} image(s) returned',
      );

      return GoogleScanResult.success(images);
    } catch (e, stackTrace) {
      // النص الحقيقي للاستثناء - هذا هو المهم لمعرفة السبب
      // الفعلي بدل التخمين، ويُعرض الآن مباشرة بالتطبيق.
      final message = '${e.runtimeType}: $e';

      debugPrint('Google Document Scanner Error: $message');
      debugPrint('$stackTrace');

      return GoogleScanResult.failure(message);
    } finally {
      try {
        await scanner?.close();
      } catch (e) {
        debugPrint('Google Scanner close error: $e');
      }
    }
  }
}
