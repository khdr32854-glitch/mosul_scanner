import 'dart:math' as math;
import 'dart:typed_data';

import 'package:flutter/foundation.dart';
import 'package:image/image.dart' as img;
import 'package:google_mlkit_document_scanner/google_mlkit_document_scanner.dart';

/// ===============================================================
/// MOSUL SCANNER - CROP ENGINE
/// ===============================================================
///
/// المسؤول عن:
/// 1. Google ML Kit Document Scanner
/// 2. معالجة الصور
/// 3. التحسين
/// 4. القص اليدوي
///
/// Google Document Scanner يعمل عبر Google Play services.
/// ===============================================================

class GoogleScanner {
  static Future<List<String>?> scan({
    int pageLimit = 10,
    bool allowGallery = false,
  }) async {
    DocumentScanner? scanner;

    try {
      debugPrint('==========================================');
      debugPrint('MOSUL SCANNER - GOOGLE');
      debugPrint('Creating DocumentScanner...');
      debugPrint('==========================================');

      const options = DocumentScannerOptions(
        documentFormats: {
          DocumentFormat.jpeg,
        },
        mode: ScannerMode.full,
        pageLimit: 10,
        isGalleryImport: false,
      );

      scanner = DocumentScanner(
        options: options,
      );

      debugPrint('Opening Google Document Scanner...');

      final result = await scanner.scanDocument();

      debugPrint('Google scanner returned.');
      debugPrint('Images count: ${result.images.length}');

      for (final path in result.images) {
        debugPrint('Google image path: $path');
      }

      if (result.images.isEmpty) {
        debugPrint(
          'Google Document Scanner returned ZERO images.',
        );
        return <String>[];
      }

      return List<String>.from(result.images);
    } catch (e, stackTrace) {
      debugPrint('==========================================');
      debugPrint('GOOGLE DOCUMENT SCANNER ERROR');
      debugPrint('$e');
      debugPrint('$stackTrace');
      debugPrint('==========================================');

      return null;
    } finally {
      try {
        await scanner?.close();
      } catch (e) {
        debugPrint('Scanner close error: $e');
      }
    }
  }
}

/// ===============================================================
/// IMAGE UTILITIES
/// ===============================================================

class ImageUtils {
  static img.Image? decodeBytes(Uint8List bytes) {
    try {
      return img.decodeImage(bytes);
    } catch (e) {
      debugPrint('Image decode error: $e');
      return null;
    }
  }

  static List<int> encodeJpg(
    img.Image image, {
    int quality = 92,
  }) {
    try {
      return img.encodeJpg(
        image,
        quality: quality,
      );
    } catch (e) {
      debugPrint('Image encode error: $e');
      return <int>[];
    }
  }

  static bool isValid(img.Image? image) {
    return image != null &&
        image.width >= 10 &&
        image.height >= 10;
  }
}

/// ===============================================================
/// CROP RESULT
/// ===============================================================

class CropResult {
  final img.Image image;
  final bool changed;
  final double confidence;

  const CropResult({
    required this.image,
    required this.changed,
    required this.confidence,
  });
}

/// ===============================================================
/// IMAGE ENHANCER
/// ===============================================================

enum EnhanceMode {
  none,
  soft,
  bw,
}

class ImageEnhancer {
  static img.Image apply(
    img.Image source,
    EnhanceMode mode,
  ) {
    final image = img.Image.from(source);

    switch (mode) {
      case EnhanceMode.none:
        return image;

      case EnhanceMode.soft:
        try {
          return img.adjustColor(
            image,
            contrast: 1.12,
            brightness: 1.04,
            saturation: 1.03,
          );
        } catch (e) {
          debugPrint(
            'Soft enhancement error: $e',
          );
          return image;
        }

      case EnhanceMode.bw:
        try {
          final gray = img.grayscale(image);

          return img.adjustColor(
            gray,
            contrast: 1.22,
            brightness: 1.03,
          );
        } catch (e) {
          debugPrint(
            'BW enhancement error: $e',
          );
          return image;
        }
    }
  }
}

/// ===============================================================
/// MANUAL CROP
/// ===============================================================

class ManualCrop {
  static img.Image cropPerspective(
    img.Image source,
    double x1,
    double y1,
    double x2,
    double y2,
    double x3,
    double y3,
    double x4,
    double y4,
  ) {
    if (!ImageUtils.isValid(source)) {
      return img.Image.from(source);
    }

    final w = source.width.toDouble();
    final h = source.height.toDouble();

    final minX = (
      math.min(
            math.min(x1, x2),
            math.min(x3, x4),
          ) *
          w
    ).toInt().clamp(
          0,
          source.width - 1,
        );

    final maxX = (
      math.max(
            math.max(x1, x2),
            math.max(x3, x4),
          ) *
          w
    ).toInt().clamp(
          1,
          source.width,
        );

    final minY = (
      math.min(
            math.min(y1, y2),
            math.min(y3, y4),
          ) *
          h
    ).toInt().clamp(
          0,
          source.height - 1,
        );

    final maxY = (
      math.max(
            math.max(y1, y2),
            math.max(y3, y4),
          ) *
          h
    ).toInt().clamp(
          1,
          source.height,
        );

    final cropW = math.max(
      10,
      maxX - minX,
    );

    final cropH = math.max(
      10,
      maxY - minY,
    );

    return img.copyCrop(
      source,
      x: minX,
      y: minY,
      width: cropW,
      height: cropH,
    );
  }
}

/// ===============================================================
/// SMART CROP FALLBACK
/// ===============================================================

class SmartCrop {
  static CropResult detect(
    img.Image source,
  ) {
    if (!ImageUtils.isValid(source)) {
      return CropResult(
        image: img.Image.from(source),
        changed: false,
        confidence: 0,
      );
    }

    const margin = 0.01;

    final cropped =
        ManualCrop.cropPerspective(
      source,
      margin,
      margin,
      1.0 - margin,
      margin,
      1.0 - margin,
      1.0 - margin,
      margin,
      1.0 - margin,
    );

    return CropResult(
      image: cropped,
      changed: true,
      confidence: 0.85,
    );
  }

  static List<double>? detectCorners(
    img.Image source,
  ) {
    if (!ImageUtils.isValid(source)) {
      return null;
    }

    return const [
      0.05,
      0.05,
      0.95,
      0.05,
      0.95,
      0.95,
      0.05,
      0.95,
    ];
  }
}
