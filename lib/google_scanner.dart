import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:google_mlkit_document_scanner/google_mlkit_document_scanner.dart';

/// ===============================================================
/// MOSUL SCANNER
/// GOOGLE ML KIT DOCUMENT SCANNER
/// ===============================================================
///
/// المسؤوليات:
/// 1. فحص إمكانية تشغيل Google Document Scanner.
/// 2. تشغيل الكاميرا أو المعرض.
/// 3. عدم إخفاء PlatformException.
/// 4. استخراج error code و native message.
/// 5. التعامل الصحيح مع images == null.
/// 6. إعطاء رسالة تشخيصية واضحة للـ main.dart.
/// ===============================================================

class GoogleScanResult {
  final bool success;
  final List<String> images;

  /// كود الخطأ القادم من Flutter / Android.
  final String? errorCode;

  /// الرسالة الأصلية القادمة من native Android.
  final String? nativeMessage;

  /// تفاصيل إضافية مفيدة للتشخيص.
  final String? details;

  /// هل المشكلة غالبًا من Google Play Services؟
  final bool requiresGooglePlayServices;

  /// هل المستخدم ألغى عملية المسح؟
  final bool cancelled;

  const GoogleScanResult({
    required this.success,
    this.images = const <String>[],
    this.errorCode,
    this.nativeMessage,
    this.details,
    this.requiresGooglePlayServices = false,
    this.cancelled = false,
  });

  factory GoogleScanResult.success(List<String> images) {
    return GoogleScanResult(
      success: true,
      images: List<String>.from(images),
    );
  }

  factory GoogleScanResult.empty() {
    return const GoogleScanResult(
      success: false,
      images: <String>[],
      cancelled: true,
    );
  }

  factory GoogleScanResult.error({
    String? code,
    String? nativeMessage,
    String? details,
    bool requiresGooglePlayServices = false,
  }) {
    return GoogleScanResult(
      success: false,
      errorCode: code,
      nativeMessage: nativeMessage,
      details: details,
      requiresGooglePlayServices: requiresGooglePlayServices,
    );
  }

  /// رسالة جاهزة للعرض للمستخدم.
  String get userMessage {
    if (cancelled) {
      return 'تم إلغاء عملية المسح.';
    }

    if (requiresGooglePlayServices) {
      return 'Google Document Scanner غير متاح على الجهاز حالياً.\n'
          'تأكد من تحديث Google Play services والاتصال بالإنترنت، '
          'ثم أعد تشغيل التطبيق.';
    }

    if (errorCode != null || nativeMessage != null) {
      final buffer = StringBuffer();

      buffer.writeln('حدث خطأ أثناء تشغيل ماسح Google.');

      if (errorCode != null && errorCode!.isNotEmpty) {
        buffer.writeln('كود الخطأ: $errorCode');
      }

      if (nativeMessage != null && nativeMessage!.isNotEmpty) {
        buffer.writeln('رسالة النظام: $nativeMessage');
      }

      return buffer.toString().trim();
    }

    return details ?? 'تعذر تشغيل Google Document Scanner.';
  }

  @override
  String toString() {
    return '''
GoogleScanResult(
  success: $success,
  images: ${images.length},
  errorCode: $errorCode,
  nativeMessage: $nativeMessage,
  details: $details,
  requiresGooglePlayServices: $requiresGooglePlayServices,
  cancelled: $cancelled,
)
''';
  }
}

/// ===============================================================
/// GOOGLE SCANNER
/// ===============================================================

class GoogleScanner {
  GoogleScanner._();

  /// تشغيل Google Document Scanner.
  ///
  /// ملاحظة:
  /// Google Document Scanner يعتمد على Google Play services،
  /// والـ UI والنماذج يتم توفيرها من خدمات Google وليس من APK نفسه.
  static Future<GoogleScanResult> scan({
    bool fromGallery = false,
    int pageLimit = 5,
  }) async {
    if (!Platform.isAndroid) {
      return GoogleScanResult.error(
        code: 'UNSUPPORTED_PLATFORM',
        nativeMessage: 'Google ML Kit Document Scanner متاح على Android فقط.',
        details: 'Current platform: ${Platform.operatingSystem}',
      );
    }

    DocumentScanner? scanner;

    try {
      debugPrint('=================================================');
      debugPrint('MOSUL SCANNER - GOOGLE DOCUMENT SCANNER');
      debugPrint('=================================================');
      debugPrint('Platform: ${Platform.operatingSystem}');
      debugPrint('Gallery import: $fromGallery');
      debugPrint('Page limit: $pageLimit');
      debugPrint('Creating DocumentScanner...');

      /// -----------------------------------------------------------
      /// إعداد Google ML Kit
      /// -----------------------------------------------------------
      final options = DocumentScannerOptions(
        documentFormats: const {
          DocumentFormat.jpeg,
          DocumentFormat.pdf,
        },
        mode: ScannerMode.full,
        pageLimit: pageLimit.clamp(1, 20),
        isGalleryImport: true,
      );

      debugPrint('Options:');
      debugPrint('  formats: JPEG + PDF');
      debugPrint('  mode: full');
      debugPrint('  pageLimit: ${pageLimit.clamp(1, 20)}');
      debugPrint('  galleryImport: true');

      scanner = DocumentScanner(options: options);

      debugPrint('DocumentScanner created successfully.');
      debugPrint('Calling scanDocument()...');

      /// -----------------------------------------------------------
      /// تشغيل Google UI
      /// -----------------------------------------------------------
      final result = await scanner.scanDocument();

      debugPrint('scanDocument() returned successfully.');

      /// -----------------------------------------------------------
      /// images في الإصدار 0.5.0 nullable.
      /// -----------------------------------------------------------
      final List<String>? nullableImages = result.images;

      if (nullableImages == null) {
        debugPrint('WARNING: result.images == null');

        return GoogleScanResult.error(
          code: 'NULL_IMAGES',
          nativeMessage:
              'Google Document Scanner returned a null images list.',
          details:
              'DocumentFormat.jpeg is enabled, but the native result contained null images.',
        );
      }

      final images = List<String>.from(nullableImages);

      debugPrint('Images returned: ${images.length}');

      if (images.isEmpty) {
        debugPrint('No images returned.');

        return GoogleScanResult.empty();
      }

      /// -----------------------------------------------------------
      /// التأكد من وجود الملفات فعليًا.
      /// -----------------------------------------------------------
      final validImages = <String>[];

      for (final path in images) {
        debugPrint('Checking image: $path');

        try {
          final file = File(path);
          final exists = await file.exists();

          debugPrint('  exists: $exists');

          if (exists) {
            final size = await file.length();
            debugPrint('  size: $size bytes');

            if (size > 0) {
              validImages.add(path);
            }
          }
        } catch (e, stack) {
          debugPrint('Error checking image file: $e');
          debugPrint('$stack');
        }
      }

      if (validImages.isEmpty) {
        return GoogleScanResult.error(
          code: 'NO_VALID_IMAGES',
          nativeMessage:
              'Scanner completed but no valid image files were returned.',
          details:
              'Google returned ${images.length} image path(s), but none could be verified.',
        );
      }

      debugPrint('Valid images: ${validImages.length}');
      debugPrint('Google Scanner completed successfully.');
      debugPrint('=================================================');

      return GoogleScanResult.success(validImages);
    }

    /// =============================================================
    /// PLATFORM EXCEPTION
    /// =============================================================
    on PlatformException catch (e, stack) {
      final code = e.code;
      final message = e.message;
      final details = e.details;

      debugPrint('=================================================');
      debugPrint('GOOGLE DOCUMENT SCANNER PLATFORM EXCEPTION');
      debugPrint('=================================================');

      debugPrint('ERROR CODE: $code');
      debugPrint('NATIVE MESSAGE: $message');
      debugPrint('DETAILS: $details');
      debugPrint('RUNTIME TYPE: ${e.runtimeType}');

      debugPrint('STACK TRACE:');
      debugPrint('$stack');

      /// -----------------------------------------------------------
      /// نحاول معرفة إذا كان الخطأ متعلقًا بـ Google Play services.
      /// -----------------------------------------------------------
      final combined = [
        code,
        message,
        details?.toString(),
      ].whereType<String>().join(' ').toLowerCase();

      final playServicesProblem =
          combined.contains('play services') ||
          combined.contains('play_services') ||
          combined.contains('module') ||
          combined.contains('dynamic') ||
          combined.contains('availability') ||
          combined.contains('download') ||
          combined.contains('install') ||
          combined.contains('nullpointerexception');

      debugPrint(
        'LIKELY GOOGLE PLAY SERVICES PROBLEM: $playServicesProblem',
      );

      debugPrint('=================================================');

      return GoogleScanResult.error(
        code: code,
        nativeMessage: message ?? e.toString(),
        details: details?.toString(),
        requiresGooglePlayServices: playServicesProblem,
      );
    }

    /// =============================================================
    /// NULL POINTER EXCEPTION
    /// =============================================================
    on NullThrownError catch (e, stack) {
      debugPrint('=================================================');
      debugPrint('GOOGLE SCANNER NULL THROWN ERROR');
      debugPrint('=================================================');
      debugPrint('ERROR: $e');
      debugPrint('STACK:');
      debugPrint('$stack');
      debugPrint('=================================================');

      return GoogleScanResult.error(
        code: 'DART_NULL_ERROR',
        nativeMessage: e.toString(),
        details: 'A Dart null error occurred while starting the scanner.',
      );
    }

    /// =============================================================
    /// كل الأخطاء الأخرى
    /// =============================================================
    catch (e, stack) {
      final errorString = e.toString();

      debugPrint('=================================================');
      debugPrint('GOOGLE DOCUMENT SCANNER UNKNOWN ERROR');
      debugPrint('=================================================');
      debugPrint('ERROR: $errorString');
      debugPrint('TYPE: ${e.runtimeType}');
      debugPrint('STACK TRACE:');
      debugPrint('$stack');
      debugPrint('=================================================');

      final lower = errorString.toLowerCase();

      final playServicesProblem =
          lower.contains('play services') ||
          lower.contains('play_services') ||
          lower.contains('nullpointerexception') ||
          lower.contains('dynamic module') ||
          lower.contains('module');

      return GoogleScanResult.error(
        code: 'UNKNOWN_ERROR',
        nativeMessage: errorString,
        details:
            'Unhandled exception type: ${e.runtimeType}',
        requiresGooglePlayServices: playServicesProblem,
      );
    }

    /// =============================================================
    /// إغلاق scanner
    /// =============================================================
    finally {
      if (scanner != null) {
        try {
          debugPrint('Closing DocumentScanner...');
          await scanner.close();
          debugPrint('DocumentScanner closed.');
        } catch (e, stack) {
          debugPrint('Error while closing DocumentScanner: $e');
          debugPrint('$stack');
        }
      }
    }
  }
}
