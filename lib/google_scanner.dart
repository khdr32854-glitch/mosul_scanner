import 'package:flutter/foundation.dart';
import 'package:google_mlkit_document_scanner/google_mlkit_document_scanner.dart';

/// ===============================================================
/// MOSUL SCANNER
/// GOOGLE ML KIT DOCUMENT SCANNER
/// ===============================================================
///
/// هذا الملف مسؤول فقط عن:
/// - تشغيل Google ML Kit Document Scanner
/// - فتح الكاميرا
/// - استيراد الصور من المعرض
/// - إرجاع مسارات الصور الناتجة
///
/// لا يحتوي على أي كود للقص أو معالجة الصور أو واجهة التطبيق.
/// ===============================================================

class GoogleScanner {
  GoogleScanner._();

  /// تشغيل Google ML Kit Document Scanner
  ///
  /// fromGallery:
  /// true  -> يسمح باستيراد الصور من المعرض
  /// false -> الاستخدام الأساسي للكاميرا
  ///
  /// النتيجة:
  /// List<String> تحتوي على مسارات الصور الناتجة.
  /// إذا فشل المسح أو ألغاه المستخدم ترجع null.
  static Future<List<String>?> scan({
    bool fromGallery = false,
  }) async {
    final options = DocumentScannerOptions(
      documentFormats: {
        DocumentFormat.jpeg,
        DocumentFormat.pdf,
      },

      // الوضع الكامل يعطي واجهة Google الكاملة
      // لاكتشاف المستند وتصحيحه تلقائياً.
      mode: ScannerMode.full,

      // الحد الأقصى لعدد الصفحات في عملية واحدة.
      pageLimit: 5,

      // السماح بالاستيراد من المعرض.
      //
      // Google ML Kit لا يملك خياراً منفصلاً لتحديد
      // "كاميرا فقط" عبر fromGallery هنا؛
      // لذلك نستخدم نفس الماسح مع تفعيل الاستيراد.
      isGalleryImport: true,
    );

    final scanner = DocumentScanner(options: options);

    try {
      debugPrint(
        'Google Scanner: starting '
        '(fromGallery: $fromGallery)',
      );

      final result = await scanner.scanDocument();

      final images = result.images;

      if (images.isEmpty) {
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
