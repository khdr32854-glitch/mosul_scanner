import 'dart:math' as math;
import 'dart:typed_data';
import 'package:flutter/foundation.dart';
import 'package:image/image.dart' as img;
import 'package:google_mlkit_document_scanner/google_mlkit_document_scanner.dart';

/// ===============================================================
/// 1. Google ML Kit Scanner (ماسح جوجل الذكي المتوافق)
/// ===============================================================
class GoogleScanner {
  static Future<List<String>?> scan() async {
    final options = DocumentScannerOptions(
      pageLimit: 10,
      isGalleryImport: true,
    );

    final scanner = DocumentScanner(options: options);

    try {
      final result = await scanner.scanDocument();
      return result.images;
    } catch (e) {
      debugPrint('Google Scanner Error: $e');
      return null;
    } finally {
      await scanner.close();
    }
  }
}

/// ===============================================================
/// 2. Image Utilities
/// ===============================================================
class ImageUtils {
  static img.Image? decodeBytes(Uint8List bytes) {
    try {
      return img.decodeImage(bytes);
    } catch (_) {
      return null;
    }
  }

  static List<int> encodeJpg(img.Image image, {int quality = 92}) {
    try {
      return img.encodeJpg(image, quality: quality);
    } catch (_) {
      return [];
    }
  }

  static bool isValid(img.Image? image) {
    return image != null && image.width >= 10 && image.height >= 10;
  }
}

/// ===============================================================
/// 3. Crop Result Model
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
/// 4. Image Enhancer & EnhanceMode
/// ===============================================================
enum EnhanceMode { none, soft, bw }

class ImageEnhancer {
  static img.Image apply(img.Image source, EnhanceMode mode) {
    final image = img.Image.from(source);
    switch (mode) {
      case EnhanceMode.none:
        return image;
      case EnhanceMode.soft:
        try {
          return img.adjustColor(image, contrast: 1.12, brightness: 1.04, saturation: 1.03);
        } catch (_) {
          return image;
        }
      case EnhanceMode.bw:
        try {
          final gray = img.grayscale(image);
          return img.adjustColor(gray, contrast: 1.22, brightness: 1.03);
        } catch (_) {
          return image;
        }
    }
  }
}

/// ===============================================================
/// 5. Manual Perspective Crop
/// ===============================================================
class ManualCrop {
  static img.Image cropPerspective(
    img.Image source,
    double x1, double y1,
    double x2, double y2,
    double x3, double y3,
    double x4, double y4,
  ) {
    if (!ImageUtils.isValid(source)) return img.Image.from(source);

    final w = source.width.toDouble();
    final h = source.height.toDouble();

    final minX = (math.min(math.min(x1, x2), math.min(x3, x4)) * w).toInt().clamp(0, source.width - 1);
    final maxX = (math.max(math.max(x1, x2), math.max(x3, x4)) * w).toInt().clamp(1, source.width);
    final minY = (math.min(math.min(y1, y2), math.min(y3, y4)) * h).toInt().clamp(0, source.height - 1);
    final maxY = (math.max(math.max(y1, y2), math.max(y3, y4)) * h).toInt().clamp(1, source.height);

    final cropW = math.max(10, maxX - minX);
    final cropH = math.max(10, maxY - minY);

    return img.copyCrop(source, x: minX, y: minY, width: cropW, height: cropH);
  }
}

/// ===============================================================
/// 6. Smart Crop Fallback
/// ===============================================================
class SmartCrop {
  static CropResult detect(img.Image source) {
    if (!ImageUtils.isValid(source)) {
      return CropResult(image: img.Image.from(source), changed: false, confidence: 0);
    }

    const margin = 0.01;
    final cropped = ManualCrop.cropPerspective(
      source,
      margin, margin,
      1.0 - margin, margin,
      1.0 - margin, 1.0 - margin,
      margin, 1.0 - margin,
    );

    return CropResult(image: cropped, changed: true, confidence: 0.85);
  }

  static List<double>? detectCorners(img.Image source) {
    if (!ImageUtils.isValid(source)) return null;
    return [0.05, 0.05, 0.95, 0.05, 0.95, 0.95, 0.05, 0.95];
  }
}
