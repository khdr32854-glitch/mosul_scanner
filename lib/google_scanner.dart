import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:google_mlkit_document_scanner/google_mlkit_document_scanner.dart';

enum GoogleScanStatus {
  success,
  cancelled,
  timeout,
  unavailable,
  error,
}

class GoogleScanResult {
  final GoogleScanStatus status;
  final List<String> images;
  final String? message;
  final Object? error;

  const GoogleScanResult({
    required this.status,
    this.images = const <String>[],
    this.message,
    this.error,
  });

  bool get isSuccess =>
      status == GoogleScanStatus.success && images.isNotEmpty;
}

class GoogleScanner {
  GoogleScanner._();

  static const Duration startupTimeout = Duration(seconds: 35);

  static Future<GoogleScanResult> scan({
    bool fromGallery = false,
    Duration timeout = startupTimeout,
  }) async {
    DocumentScanner? scanner;

    try {
      /*
       * مهم:
       * تطبيقنا لا يحتاج PDF من Google Scanner لأن main.dart
       * ينشئ PDF بنفسه عند الطباعة.
       *
       * لذلك نطلب JPEG فقط + BASE.
       * هذا يقلل المتطلبات على Google Play services
       * ويبتعد عن ميزات FULL التي لا نحتاجها.
       */
      final options = DocumentScannerOptions(
        documentFormats: const {
          DocumentFormat.jpeg,
        },
        mode: ScannerMode.base,
        pageLimit: 5,
        isGalleryImport: fromGallery,
      );

      debugPrint(
        '[GoogleScanner] Creating scanner '
        '(gallery=$fromGallery, mode=base, jpeg-only)',
      );

      scanner = DocumentScanner(options: options);

      final result = await scanner.scanDocument().timeout(
        timeout,
        onTimeout: () {
          throw TimeoutException(
            'Google Document Scanner startup timeout',
          );
        },
      );

      final List<String> images =
          List<String>.from(result.images ?? const <String>[]);

      if (images.isEmpty) {
        return const GoogleScanResult(
          status: GoogleScanStatus.cancelled,
          message: 'لم يتم اختيار أو مسح أي مستند.',
        );
      }

      debugPrint(
        '[GoogleScanner] Scan success: ${images.length} image(s)',
      );

      return GoogleScanResult(
        status: GoogleScanStatus.success,
        images: images,
        message: 'تم المسح بنجاح.',
      );
    } on TimeoutException catch (e) {
      debugPrint('[GoogleScanner] TIMEOUT: $e');

      return GoogleScanResult(
        status: GoogleScanStatus.timeout,
        message:
            'Google Scanner لم يبدأ خلال ${timeout.inSeconds} ثانية. '
            'تأكد من تحديث Google Play services واتصال الإنترنت عند أول تشغيل.',
        error: e,
      );
    } catch (e, stackTrace) {
      debugPrint('[GoogleScanner] NATIVE ERROR: $e');
      debugPrintStack(stackTrace: stackTrace);

      final text = e.toString().toLowerCase();

      if (text.contains('cancel') ||
          text.contains('canceled') ||
          text.contains('cancelled')) {
        return GoogleScanResult(
          status: GoogleScanStatus.cancelled,
          message: 'تم إلغاء عملية المسح.',
          error: e,
        );
      }

      /*
       * بعض إصدارات Google Play services ترجع PlatformException
       * بدلاً من MlKitException عند فشل الـ dynamic module.
       */
      final looksLikeGoogleAvailabilityProblem =
          text.contains('nullpointerexception') ||
          text.contains('module') ||
          text.contains('play services') ||
          text.contains('google play') ||
          text.contains('service unavailable') ||
          text.contains('not available') ||
          text.contains('unsupported') ||
          text.contains('dynamic');

      if (looksLikeGoogleAvailabilityProblem) {
        return GoogleScanResult(
          status: GoogleScanStatus.unavailable,
          message:
              'Google Document Scanner غير متاح على الجهاز حالياً.\n\n'
              'حدّث Google Play services من متجر Google Play، '
              'وتأكد من وجود اتصال بالإنترنت، ثم أعد تشغيل التطبيق.',
          error: e,
        );
      }

      return GoogleScanResult(
        status: GoogleScanStatus.error,
        message: 'خطأ Google Scanner: $e',
        error: e,
      );
    } finally {
      if (scanner != null) {
        try {
          await scanner.close();
        } catch (e) {
          debugPrint('[GoogleScanner] close() error: $e');
        }
      }
    }
  }
}
