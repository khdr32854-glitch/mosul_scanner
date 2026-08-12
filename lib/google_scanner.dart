import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:google_mlkit_document_scanner/google_mlkit_document_scanner.dart';

/// ===============================================================
/// MOSUL SCANNER
/// GOOGLE ML KIT DOCUMENT SCANNER
/// ===============================================================
///
/// متوافق مع main.dart الحالي.
///
/// الوظائف:
/// - تشغيل Google Document Scanner
/// - Camera
/// - Gallery
/// - تشخيص PlatformException
/// - كشف NullPointerException
/// - إرجاع status / message / isSuccess
/// - عدم إخفاء الخطأ الحقيقي
/// ===============================================================

enum GoogleScanStatus {
  success,
  cancelled,
  unavailable,
  error,
}

/// نتيجة Google Scanner
class GoogleScanResult {
  final GoogleScanStatus status;

  final String message;

  final List<String> images;

  final String? errorCode;

  final String? nativeMessage;

  final String? details;

  const GoogleScanResult({
    required this.status,
    required this.message,
    this.images = const <String>[],
    this.errorCode,
    this.nativeMessage,
    this.details,
  });

  /// نجاح العملية
  bool get isSuccess => status == GoogleScanStatus.success;

  /// هل العملية ألغيت؟
  bool get isCancelled => status == GoogleScanStatus.cancelled;

  /// هل Google Scanner غير متاح؟
  bool get isUnavailable => status == GoogleScanStatus.unavailable;

  /// هل يوجد خطأ؟
  bool get hasError => status == GoogleScanStatus.error;

  @override
  String toString() {
    return '''
GoogleScanResult
status: $status
isSuccess: $isSuccess
message: $message
images: ${images.length}
errorCode: $errorCode
nativeMessage: $nativeMessage
details: $details
''';
  }
}

/// ===============================================================
/// GOOGLE SCANNER
/// ===============================================================

class GoogleScanner {
  GoogleScanner._();

  /// =============================================================
  /// scan
  /// =============================================================
  ///
  /// fromGallery:
  /// true  = السماح باستيراد الصور من المعرض
  /// false = تشغيل الماسح بالطريقة العادية
  ///
  /// مهم:
  /// Google نفسها تعرض خيار المعرض عندما يكون
  /// isGalleryImport = true.
  /// =============================================================

  static Future<GoogleScanResult> scan({
    bool fromGallery = false,
    int pageLimit = 5,
  }) async {
    if (!Platform.isAndroid) {
      return const GoogleScanResult(
        status: GoogleScanStatus.unavailable,
        message:
            'Google Document Scanner متاح على أجهزة Android فقط.',
      );
    }

    DocumentScanner? scanner;

    try {
      debugPrint('');
      debugPrint('==============================================');
      debugPrint('MOSUL SCANNER');
      debugPrint('GOOGLE DOCUMENT SCANNER');
      debugPrint('==============================================');

      debugPrint('fromGallery: $fromGallery');
      debugPrint('pageLimit: $pageLimit');

      /// -----------------------------------------------------------
      /// إعداد Google Scanner
      /// -----------------------------------------------------------

      final options = DocumentScannerOptions(
        documentFormats: {
          DocumentFormat.jpeg,
          DocumentFormat.pdf,
        },

        mode: ScannerMode.full,

        pageLimit: pageLimit.clamp(1, 20),

        /// إذا كان true يستطيع Google عرض Gallery Import.
        isGalleryImport: true,
      );

      debugPrint('DocumentScannerOptions created.');

      debugPrint(
        'isGalleryImport: ${options.isGalleryImport}',
      );

      debugPrint(
        'pageLimit: ${options.pageLimit}',
      );

      debugPrint(
        'mode: ${options.mode}',
      );

      /// -----------------------------------------------------------
      /// إنشاء Scanner
      /// -----------------------------------------------------------

      scanner = DocumentScanner(
        options: options,
      );

      debugPrint(
        'DocumentScanner object created.',
      );

      debugPrint(
        'Calling scanDocument()...',
      );

      /// -----------------------------------------------------------
      /// تشغيل Google UI
      /// -----------------------------------------------------------

      final result = await scanner.scanDocument();

      debugPrint(
        'scanDocument() returned.',
      );

      /// -----------------------------------------------------------
      /// قراءة الصور
      /// -----------------------------------------------------------

      final List<String>? nullableImages = result.images;

      if (nullableImages == null) {
        debugPrint(
          'Google returned images == null',
        );

        return const GoogleScanResult(
          status: GoogleScanStatus.error,
          message:
              'Google Document Scanner أعاد نتيجة بدون قائمة صور.',
          errorCode: 'NULL_IMAGES',
          nativeMessage:
              'DocumentScanningResult.images == null',
        );
      }

      final List<String> images =
          List<String>.from(nullableImages);

      debugPrint(
        'Returned images: ${images.length}',
      );

      /// -----------------------------------------------------------
      /// المستخدم أغلق Scanner بدون نتيجة
      /// -----------------------------------------------------------

      if (images.isEmpty) {
        debugPrint(
          'Scanner closed or no images selected.',
        );

        return const GoogleScanResult(
          status: GoogleScanStatus.cancelled,
          message:
              'تم إلغاء عملية المسح أو لم يتم اختيار صورة.',
        );
      }

      /// -----------------------------------------------------------
      /// التحقق من الملفات
      /// -----------------------------------------------------------

      final List<String> validImages = <String>[];

      for (final path in images) {
        try {
          final file = File(path);

          final exists = await file.exists();

          debugPrint(
            'Image: $path',
          );

          debugPrint(
            'Exists: $exists',
          );

          if (!exists) {
            continue;
          }

          final size = await file.length();

          debugPrint(
            'Size: $size bytes',
          );

          if (size > 0) {
            validImages.add(path);
          }
        } catch (e, stack) {
          debugPrint(
            'Image validation error: $e',
          );

          debugPrint(
            stack.toString(),
          );
        }
      }

      /// -----------------------------------------------------------
      /// لم نجد ملفات صالحة
      /// -----------------------------------------------------------

      if (validImages.isEmpty) {
        return const GoogleScanResult(
          status: GoogleScanStatus.error,
          message:
              'Google Scanner انتهى، لكن لم يتم العثور على ملفات صور صالحة.',
          errorCode: 'NO_VALID_IMAGES',
        );
      }

      /// -----------------------------------------------------------
      /// نجاح
      /// -----------------------------------------------------------

      debugPrint(
        'Valid images: ${validImages.length}',
      );

      debugPrint(
        'Google Scanner SUCCESS',
      );

      debugPrint('==============================================');

      return GoogleScanResult(
        status: GoogleScanStatus.success,
        message:
            'تم المسح بواسطة Google Document Scanner بنجاح.',
        images: validImages,
      );
    }

    /// =============================================================
    /// PLATFORM EXCEPTION
    /// =============================================================

    on PlatformException catch (e, stack) {
      final String code = e.code;

      final String nativeMessage =
          e.message ?? '';

      final String details =
          e.details?.toString() ?? '';

      debugPrint('');
      debugPrint('==============================================');
      debugPrint(
        'GOOGLE DOCUMENT SCANNER PLATFORM EXCEPTION',
      );
      debugPrint('==============================================');

      debugPrint(
        'CODE: $code',
      );

      debugPrint(
        'MESSAGE: $nativeMessage',
      );

      debugPrint(
        'DETAILS: $details',
      );

      debugPrint(
        'ERROR: $e',
      );

      debugPrint(
        'STACK TRACE:',
      );

      debugPrint(
        stack.toString(),
      );

      debugPrint('==============================================');

      /// -----------------------------------------------------------
      /// تحديد الأخطاء المرتبطة بـ Google Play Services
      /// -----------------------------------------------------------

      final String combined =
          '$code $nativeMessage $details'
              .toLowerCase();

      final bool googleUnavailable =
          combined.contains(
                'play services',
              ) ||
          combined.contains(
                'play_services',
              ) ||
          combined.contains(
                'dynamic module',
              ) ||
          combined.contains(
                'dynamic',
              ) ||
          combined.contains(
                'module',
              ) ||
          combined.contains(
                'availability',
              ) ||
          combined.contains(
                'download',
              ) ||
          combined.contains(
                'install',
              ) ||
          combined.contains(
                'nullpointerexception',
              );

      if (googleUnavailable) {
        return GoogleScanResult(
          status: GoogleScanStatus.unavailable,
          message:
              'Google Document Scanner غير متاح على الجهاز حالياً.\n\n'
              'كود الخطأ: $code\n'
              'رسالة النظام: '
              '${nativeMessage.isEmpty ? "غير متوفرة" : nativeMessage}',
          errorCode: code,
          nativeMessage: nativeMessage,
          details: details,
        );
      }

      /// -----------------------------------------------------------
      /// خطأ Native عادي
      /// -----------------------------------------------------------

      return GoogleScanResult(
        status: GoogleScanStatus.error,
        message:
            'حدث خطأ أثناء تشغيل Google Document Scanner.\n\n'
            'كود الخطأ: $code\n'
            'رسالة النظام: '
            '${nativeMessage.isEmpty ? "غير متوفرة" : nativeMessage}',
        errorCode: code,
        nativeMessage: nativeMessage,
        details: details,
      );
    }

    /// =============================================================
    /// أي خطأ آخر
    /// =============================================================

    catch (e, stack) {
      final String error =
          e.toString();

      debugPrint('');
      debugPrint('==============================================');
      debugPrint(
        'GOOGLE DOCUMENT SCANNER UNKNOWN ERROR',
      );
      debugPrint('==============================================');

      debugPrint(
        'TYPE: ${e.runtimeType}',
      );

      debugPrint(
        'ERROR: $error',
      );

      debugPrint(
        'STACK TRACE:',
      );

      debugPrint(
        stack.toString(),
      );

      debugPrint('==============================================');

      final String lower =
          error.toLowerCase();

      final bool googleUnavailable =
          lower.contains(
                'play services',
              ) ||
          lower.contains(
                'play_services',
              ) ||
          lower.contains(
                'dynamic module',
              ) ||
          lower.contains(
                'nullpointerexception',
              );

      if (googleUnavailable) {
        return GoogleScanResult(
          status: GoogleScanStatus.unavailable,
          message:
              'Google Document Scanner غير متاح على الجهاز حالياً.\n\n'
              'الخطأ الأصلي:\n$error',
          errorCode: 'UNKNOWN_GOOGLE_ERROR',
          nativeMessage: error,
        );
      }

      return GoogleScanResult(
        status: GoogleScanStatus.error,
        message:
            'خطأ غير متوقع في Google Document Scanner.\n\n'
            '$error',
        errorCode: 'UNKNOWN_ERROR',
        nativeMessage: error,
      );
    }

    /// =============================================================
    /// CLOSE
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
            'Scanner close error: $e',
          );
        }
      }
    }
  }
}
