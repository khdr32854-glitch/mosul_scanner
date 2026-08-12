import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:google_mlkit_document_scanner/google_mlkit_document_scanner.dart';

class GoogleScannerException implements Exception {
  final String title;
  final String message;
  final String? code;
  final Object? details;
  final String? stackTrace;
  final Object? originalError;

  const GoogleScannerException({
    required this.title,
    required this.message,
    this.code,
    this.details,
    this.stackTrace,
    this.originalError,
  });

  @override
  String toString() {
    final buffer = StringBuffer();

    buffer.writeln(title);

    if (code != null && code!.trim().isNotEmpty) {
      buffer.writeln('CODE: $code');
    }

    buffer.writeln('MESSAGE: $message');

    if (details != null) {
      buffer.writeln('DETAILS: $details');
    }

    if (originalError != null) {
      buffer.writeln('ERROR: $originalError');
    }

    if (stackTrace != null && stackTrace!.trim().isNotEmpty) {
      buffer.writeln('STACK TRACE:');
      buffer.writeln(stackTrace);
    }

    return buffer.toString();
  }
}

class GoogleScanner {
  GoogleScanner._();

  static Future<List<String>> scan({
    bool fromGallery = false,
  }) async {
    DocumentScanner? scanner;

    try {
      debugPrint('==========================================');
      debugPrint('MOSUL SCANNER - GOOGLE DOCUMENT SCANNER');
      debugPrint('Starting...');
      debugPrint('fromGallery: $fromGallery');
      debugPrint('==========================================');

      final options = DocumentScannerOptions(
        documentFormats: {
          DocumentFormat.jpeg,
        },
        mode: ScannerMode.base,
        pageLimit: 5,
        isGalleryImport: fromGallery,
      );

      debugPrint('Options created.');
      debugPrint('Mode: ${options.mode}');
      debugPrint('Page limit: ${options.pageLimit}');
      debugPrint('Gallery import: ${options.isGalleryImport}');
      debugPrint('Formats: ${options.documentFormats}');

      scanner = DocumentScanner(options: options);

      debugPrint('DocumentScanner created.');
      debugPrint('Calling scanDocument()...');

      final result = await scanner.scanDocument();

      debugPrint('scanDocument() completed.');

      final images = result.images ?? <String>[];

      debugPrint('Images count: ${images.length}');

      for (var i = 0; i < images.length; i++) {
        debugPrint('Image[$i]: ${images[i]}');
      }

      return List<String>.from(images);
    }

    on PlatformException catch (e, stack) {
      debugPrint('');
      debugPrint('==========================================');
      debugPrint('GOOGLE DOCUMENT SCANNER ERROR');
      debugPrint('==========================================');
      debugPrint('TYPE: PlatformException');
      debugPrint('CODE: ${e.code}');
      debugPrint('MESSAGE: ${e.message}');
      debugPrint('DETAILS: ${e.details}');
      debugPrint('ERROR: $e');
      debugPrint('');
      debugPrint('STACK TRACE:');
      debugPrint(stack.toString());
      debugPrint('==========================================');
      debugPrint('');

      throw GoogleScannerException(
        title: 'Google Document Scanner PlatformException',
        code: e.code,
        message: e.message ?? 'Native Google Scanner returned no message.',
        details: e.details,
        stackTrace: stack.toString(),
        originalError: e,
      );
    }

    on TimeoutException catch (e, stack) {
      debugPrint('');
      debugPrint('==========================================');
      debugPrint('GOOGLE DOCUMENT SCANNER TIMEOUT');
      debugPrint('==========================================');
      debugPrint('ERROR: $e');
      debugPrint('STACK TRACE:');
      debugPrint(stack.toString());
      debugPrint('==========================================');

      throw GoogleScannerException(
        title: 'Google Document Scanner Timeout',
        message: e.toString(),
        stackTrace: stack.toString(),
        originalError: e,
      );
    }

    catch (e, stack) {
      debugPrint('');
      debugPrint('==========================================');
      debugPrint('GOOGLE DOCUMENT SCANNER UNKNOWN ERROR');
      debugPrint('==========================================');
      debugPrint('TYPE: ${e.runtimeType}');
      debugPrint('ERROR: $e');
      debugPrint('STACK TRACE:');
      debugPrint(stack.toString());
      debugPrint('==========================================');

      throw GoogleScannerException(
        title: 'Google Document Scanner Error',
        message: e.toString(),
        stackTrace: stack.toString(),
        originalError: e,
      );
    }

    finally {
      if (scanner != null) {
        try {
          await scanner.close();
          debugPrint('Google Document Scanner closed.');
        } catch (e, stack) {
          debugPrint('Scanner close error: $e');
          debugPrint(stack.toString());
        }
      }
    }
  }
}
