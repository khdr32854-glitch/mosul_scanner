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

  static const Duration startupTimeout = Duration(seconds: 30);

  static Future<GoogleScanResult> scan({
    bool fromGallery = false,
    Duration timeout = startupTimeout,
  }) async {
    DocumentScanner? scanner;

    try {
      final options = DocumentScannerOptions(
        documentFormats: {
          DocumentFormat.jpeg,
          DocumentFormat.pdf,
        },
        mode: ScannerMode.full,
        pageLimit: 5,
        isGalleryImport: fromGallery,
      );

      scanner = DocumentScanner(options: options);

      debugPrint(
        '[GoogleScanner] Starting scanner. gallery=$fromGallery',
      );

      final result = await scanner.scanDocument().timeout(
        timeout,
        onTimeout: () => throw TimeoutException(
          'Google Document Scanner did not start within '
          '${timeout.inSeconds} seconds.',
        ),
      );

      // images قد تكون nullable في إصدار الـ plugin.
      final List<String> images =
          List<String>.from(result.images ?? const <String>[]);

      if (images.isEmpty) {
        return const GoogleScanResult(
          status: GoogleScanStatus.cancelled,
          message: 'لم يتم اختيار أو مسح أي مستند.',
        );
      }

      debugPrint(
        '[GoogleScanner] Success: ${images.length} image(s)',
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
            'تعذر تشغيل ماسح Google خلال ${timeout.inSeconds} ثانية. '
            'تأكد من تحديث Google Play services واتصال الإنترنت عند أول تشغيل.',
        error: e,
      );
    } catch (e, stackTrace) {
      debugPrint('[GoogleScanner] ERROR: $e');
      debugPrintStack(stackTrace: stackTrace);

      final lower = e.toString().toLowerCase();

      if (lower.contains('cancel') ||
          lower.contains('canceled') ||
          lower.contains('cancelled')) {
        return GoogleScanResult(
          status: GoogleScanStatus.cancelled,
          message: 'تم إلغاء عملية المسح.',
          error: e,
        );
      }

      if (lower.contains('unsupported') ||
          lower.contains('module') ||
          lower.contains('play services') ||
          lower.contains('google play') ||
          lower.contains('service unavailable') ||
          lower.contains('not available')) {
        return GoogleScanResult(
          status: GoogleScanStatus.unavailable,
          message:
              'ماسح Google غير متاح حالياً. '
              'تأكد من وجود Google Play services وتحديثه، ثم أعد المحاولة.',
          error: e,
        );
      }

      return GoogleScanResult(
        status: GoogleScanStatus.error,
        message: 'حدث خطأ أثناء تشغيل ماسح Google: $e',
        error: e,
      );
    } finally {
      if (scanner != null) {
        try {
          await scanner.close();
          debugPrint('[GoogleScanner] Scanner closed.');
        } catch (e) {
          debugPrint('[GoogleScanner] Close error: $e');
        }
      }
    }
  }
}
