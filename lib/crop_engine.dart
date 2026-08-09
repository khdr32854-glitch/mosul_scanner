import 'dart:math' as math;
import 'dart:typed_data';
import 'package:flutter/foundation.dart';
import 'package:image/image.dart' as img;

/// أدوات الصورة والمعالجة
class ImageUtils {
  static img.Image? decodeBytes(Uint8List bytes) {
    try { return img.decodeImage(bytes); } catch (_) { return null; }
  }

  static List<int> encodeJpg(img.Image image, {int quality = 95}) {
    try { return img.encodeJpg(image, quality: quality); } catch (_) { return []; }
  }

  static bool isValid(img.Image? image) {
    return image != null && image.width > 20 && image.height > 20;
  }
}

/// نتيجة القص
class CropResult {
  final img.Image image;
  final bool changed;
  final double confidence;

  const CropResult({required this.image, required this.changed, required this.confidence});
}

/// فلاتر CamScanner السحرية (Magic Color / B&W / Original)
enum EnhanceMode { none, soft, bw }

class ImageEnhancer {
  static img.Image apply(img.Image source, EnhanceMode mode) {
    final image = img.Image.from(source);
    switch (mode) {
      case EnhanceMode.none:
        return image;

      case EnhanceMode.soft:
        // فلتر اللون السحري (Magic Color): زيادة السطوع مع تباين عالي لتصفية الخففيات
        for (var frame in image.frames) {
          for (var p in frame) {
            num r = p.r * 1.2;
            num g = p.g * 1.2;
            num b = p.b * 1.2;
            // تنظيف الخلفيات البيضاء والرمادية
            if (r > 180 && g > 180 && b > 180) {
              r = 255; g = 255; b = 255;
            }
            p.r = r.clamp(0, 255);
            p.g = g.clamp(0, 255);
            p.b = b.clamp(0, 255);
          }
        }
        return image;

      case EnhanceMode.bw:
        // أبيض وأسود عالي التباين للمستندات والختومات
        final gray = img.grayscale(image);
        return img.adjustColor(gray, contrast: 1.4, brightness: 1.1);
    }
  }
}

/// القص اليدوي وتعديل المنظور
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

    final cropW = math.max(20, maxX - minX);
    final cropH = math.max(20, maxY - minY);

    return img.copyCrop(source, x: minX, y: minY, width: cropW, height: cropH);
  }
}
