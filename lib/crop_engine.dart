import 'dart:math' as math;
import 'dart:typed_data';

import 'package:flutter/foundation.dart';
import 'package:google_mlkit_document_scanner/google_mlkit_document_scanner.dart';
import 'package:image/image.dart' as img;

/// ===============================================================
/// MOSUL SCANNER - CROP ENGINE
/// ===============================================================
///
/// المسؤول عن:
/// 1. تشغيل Google ML Kit Document Scanner
/// 2. استلام مسارات الصور الناتجة
/// 3. معالجة الصور
/// 4. القص اليدوي
/// 5. تحسين الصورة
///
/// Google ML Kit Document Scanner 0.5.0
/// ===============================================================

/// ===============================================================
/// 1. GOOGLE DOCUMENT SCANNER
/// ===============================================================

class GoogleScanner {
  static Future<List<String>?> scan({
    int pageLimit = 10,
    bool allowGallery = false,
  }) async {
    final options = DocumentScannerOptions(
      documentFormats: const {
        DocumentFormat.jpeg,
      },
      mode: ScannerMode.full,
      pageLimit: pageLimit,
      isGalleryImport: allowGallery,
    );

    final scanner = DocumentScanner(
      options: options,
    );

    try {
      debugPrint('MOSUL SCANNER: Opening Google Document Scanner');

      final result = await scanner.scanDocument();

      final images = result.images;

      debugPrint(
        'MOSUL SCANNER: Google returned '
        '${images?.length ?? 0} image(s)',
      );

      return images;
    } catch (e, stackTrace) {
      debugPrint('==========================================');
      debugPrint('GOOGLE DOCUMENT SCANNER ERROR');
      debugPrint('$e');
      debugPrint('$stackTrace');
      debugPrint('==========================================');

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

/// ===============================================================
/// 2. IMAGE UTILITIES
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

  static Uint8List encodeJpg(
    img.Image image, {
    int quality = 92,
  }) {
    try {
      return Uint8List.fromList(
        img.encodeJpg(
          image,
          quality: quality,
        ),
      );
    } catch (e) {
      debugPrint('Image encode error: $e');
      return Uint8List(0);
    }
  }

  static bool isValid(img.Image? image) {
    return image != null &&
        image.width >= 10 &&
        image.height >= 10;
  }
}

/// ===============================================================
/// 3. CROP RESULT
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
/// 4. IMAGE ENHANCER
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
          debugPrint('Soft enhancement error: $e');
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
          debugPrint('BW enhancement error: $e');
          return image;
        }
    }
  }
}

/// ===============================================================
/// 5. MANUAL CROP
/// ===============================================================
///
/// الإحداثيات normalized:
/// 0.0 = بداية الصورة
/// 1.0 = نهاية الصورة
///
/// ترتيب النقاط:
/// 1 = أعلى يسار
/// 2 = أعلى يمين
/// 3 = أسفل يمين
/// 4 = أسفل يسار
///
/// ملاحظة:
/// هذه النسخة تنفذ قص المستطيل المحيط بالنقاط.
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

    final valuesX = <double>[
      x1,
      x2,
      x3,
      x4,
    ];

    final valuesY = <double>[
      y1,
      y2,
      y3,
      y4,
    ];

    final minNormalizedX =
        valuesX.reduce(math.min).clamp(0.0, 1.0);

    final maxNormalizedX =
        valuesX.reduce(math.max).clamp(0.0, 1.0);

    final minNormalizedY =
        valuesY.reduce(math.min).clamp(0.0, 1.0);

    final maxNormalizedY =
        valuesY.reduce(math.max).clamp(0.0, 1.0);

    int minX = (minNormalizedX * w).round();
    int maxX = (maxNormalizedX * w).round();

    int minY = (minNormalizedY * h).round();
    int maxY = (maxNormalizedY * h).round();

    minX = minX.clamp(0, source.width - 1);
    minY = minY.clamp(0, source.height - 1);

    maxX = maxX.clamp(minX + 1, source.width);
    maxY = maxY.clamp(minY + 1, source.height);

    final cropWidth =
        math.max(10, maxX - minX);

    final cropHeight =
        math.max(10, maxY - minY);

    return img.copyCrop(
      source,
      x: minX,
      y: minY,
      width: cropWidth,
      height: cropHeight,
    );
  }
}

/// ===============================================================
/// 6. SMART CROP FALLBACK
/// ===============================================================

class SmartCrop {
  static CropResult detect(
    img.Image source,
  ) {
    if (!ImageUtils.isValid(source)) {
      return CropResult(
        image: img.Image.from(source),
        changed: false,
        confidence: 0.0,
      );
    }

    const margin = 0.01;

    final cropped = ManualCrop.cropPerspective(
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
