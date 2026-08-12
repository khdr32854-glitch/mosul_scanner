import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:google_mlkit_document_scanner/google_mlkit_document_scanner.dart';

/// ===============================================================
/// MOSUL SCANNER
/// GOOGLE DOCUMENT SCANNER
/// ===============================================================
///
/// مسؤول فقط عن:
/// - تشغيل Google ML Kit Document Scanner
/// - استقبال الصور
/// - فحص Google Play Services / Dynamic Module
/// - عدم إخفاء الخطأ الأصلي
///
/// google_mlkit_document_scanner: ^0.5.0
/// ===============================================================

class GoogleScanResult {
  final bool success;
  final List<String> images;

  final String? errorCode;
  final String? nativeMessage;
  final String? details;

  final bool cancelled;
  final bool googleServicesProblem;

  const GoogleScanResult({
    required this.success,
    this.images = const <String>[],
    this.errorCode,
    this.nativeMessage,
    this.details,
    this.cancelled = false,
    this.googleServicesProblem = false,
  });

  factory GoogleScanResult.success(List<String> images) {
    return GoogleScanResult(
      success: true,
      images: images,
    );
  }

  factory GoogleScanResult.cancelled() {
    return const GoogleScanResult(
      success: false,
      cancelled: true,
    );
  }

  factory GoogleScanResult.error({
    String? code,
    String? message,
    String? details,
    bool googleServicesProblem = false,
  }) {
    return GoogleScanResult(
      success: false,
      errorCode: code,
      nativeMessage: message,
      details: details,
      googleServicesProblem: googleServicesProblem,
    );
  }

  String get displayMessage {
    if (cancelled) {
      return 'تم إلغاء عملية المسح.';
    }

    if (googleServicesProblem) {
      return 'Google Document Scanner غير متاح على الجهاز حالياً.\n\n'
          'كود الخطأ: ${errorCode ?? "غير معروف"}\n'
          'رسالة النظام:\n${nativeMessage ?? "غير متوفرة"}';
    }

    if (errorCode != null || nativeMessage != null) {
      return 'حدث خطأ أثناء تشغيل ماسح Google.\n\n'
          'كود الخطأ: ${errorCode ?? "غير معروف"}\n'
          'رسالة النظام:\n${nativeMessage ?? "غير متوفرة"}';
    }

    return 'تعذر تشغيل Google Document Scanner.';
  }

  @override
  String toString() {
    return 'GoogleScanResult('
        'success: $success, '
        'images: ${images.length}, '
        'errorCode: $errorCode, '
        'nativeMessage: $nativeMessage, '
        'details: $details, '
        'cancelled: $cancelled, '
        'googleServicesProblem: $googleServicesProblem'
        ')';
  }
}

/// ===============================================================
/// GOOGLE SCANNER
/// ===============================================================

class GoogleScanner {
  GoogleScanner._();

  static Future<GoogleScanResult> scan({
    int pageLimit = 5,
  }) async {
    if (!Platform.isAndroid) {
      return GoogleScanResult.error(
        code: 'UNSUPPORTED_PLATFORM',
        message: 'Google Document Scanner يعمل على Android فقط.',
      );
    }

    DocumentScanner? scanner;

    try {
      debugPrint('');
      debugPrint('==============================================');
      debugPrint('MOSUL SCANNER - GOOGLE DOCUMENT SCANNER');
      debugPrint('==============================================');
      debugPrint('Creating Google Document Scanner...');

      final int safePageLimit = pageLimit.clamp(1, 20).toInt();

      final options = DocumentScannerOptions(
        documentFormats: {
          DocumentFormat.jpeg,
          DocumentFormat.pdf,
        },
        mode: ScannerMode.full,
        pageLimit: safePageLimit,

        // مهم:
        // تفعيل استيراد الصور من المعرض.
        isGalleryImport: true,
      );

      debugPrint('Options created.');
      debugPrint('Page limit: $safePageLimit');
      debugPrint('Gallery import: true');
      debugPrint('Mode: full');

      scanner = DocumentScanner(
        options: options,
      );

      debugPrint('DocumentScanner created.');
      debugPrint('Starting scanDocument()...');

      final result = await scanner.scanDocument();

      debugPrint('scanDocument() returned.');

      /// -----------------------------------------------------------
      /// images nullable في نسخة 0.5.0
      /// -----------------------------------------------------------

      final List<String>? resultImages = result.images;

      if (resultImages == null) {
        debugPrint('ERROR: result.images == null');

        return GoogleScanResult.error(
          code: 'NULL_IMAGES',
          message:
              'Google returned a null images list.',
          details:
              'JPEG was requested but Google returned null images.',
        );
      }

      if (resultImages.isEmpty) {
        debugPrint('No images returned.');

        return GoogleScanResult.cancelled();
      }

      debugPrint(
        'Google returned ${resultImages.length} image(s).',
      );

      /// -----------------------------------------------------------
      /// فحص الملفات
      /// -----------------------------------------------------------

      final List<String> validImages = <String>[];

      for (final path in resultImages) {
        try {
          final file = File(path);

          final exists = await file.exists();

          debugPrint('Image: $path');
          debugPrint('Exists: $exists');

          if (!exists) {
            continue;
          }

          final size = await file.length();

          debugPrint('Size: $size bytes');

          if (size > 0) {
            validImages.add(path);
          }
        } catch (e) {
          debugPrint(
            'Error checking image: $e',
          );
        }
      }

      if (validImages.isEmpty) {
        return GoogleScanResult.error(
          code: 'NO_VALID_IMAGES',
          message:
              'Google scanner returned image paths but no valid files were found.',
        );
      }

      debugPrint(
        'Valid images: ${validImages.length}',
      );

      debugPrint(
        'Google Document Scanner completed successfully.',
      );

      debugPrint('==============================================');

      return GoogleScanResult.success(
        validImages,
      );
    }

    /// =============================================================
    /// PLATFORM EXCEPTION
    /// =============================================================

    on PlatformException catch (e, stackTrace) {
      final String code = e.code;
      final String message = e.message ?? '';
      final String details = e.details?.toString() ?? '';

      debugPrint('');
      debugPrint('==============================================');
      debugPrint('GOOGLE DOCUMENT SCANNER ERROR');
      debugPrint('==============================================');

      debugPrint('ERROR CODE: $code');
      debugPrint('NATIVE MESSAGE: $message');
      debugPrint('DETAILS: $details');
      debugPrint('TYPE: ${e.runtimeType}');

      debugPrint('STACK TRACE:');
      debugPrint(stackTrace.toString());

      debugPrint('==============================================');

      final String combined =
          '$code $message $details'.toLowerCase();

      final bool googleProblem =
          combined.contains('play services') ||
          combined.contains('play_services') ||
          combined.contains('dynamic') ||
          combined.contains('module') ||
          combined.contains('availability') ||
          combined.contains('download') ||
          combined.contains('install') ||
          combined.contains('nullpointerexception');

      return GoogleScanResult.error(
        code: code,
        message: message.isEmpty ? e.toString() : message,
        details: details,
        googleServicesProblem: googleProblem,
      );
    }

    /// =============================================================
    /// أي خطأ آخر
    /// =============================================================

    catch (e, stackTrace) {
      final String error = e.toString();

      debugPrint('');
      debugPrint('==============================================');
      debugPrint('GOOGLE DOCUMENT SCANNER UNKNOWN ERROR');
      debugPrint('==============================================');

      debugPrint('ERROR: $error');
      debugPrint('TYPE: ${e.runtimeType}');

      debugPrint('STACK TRACE:');
      debugPrint(stackTrace.toString());

      debugPrint('==============================================');

      final String lower = error.toLowerCase();

      final bool googleProblem =
          lower.contains('play services') ||
          lower.contains('play_services') ||
          lower.contains('dynamic') ||
          lower.contains('module') ||
          lower.contains('nullpointerexception');

      return GoogleScanResult.error(
        code: 'UNKNOWN_ERROR',
        message: error,
        googleServicesProblem: googleProblem,
      );
    }

    /// =============================================================
    /// إغلاق Google Scanner
    /// =============================================================

    finally {
      if (scanner != null) {
        try {
          await scanner.close();
          debugPrint(
            'Google Document Scanner closed.',
          );
        } catch (e) {
          debugPrint(
            'Error closing Google Scanner: $e',
          );
        }
      }
    }
  }
}
