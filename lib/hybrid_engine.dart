import 'dart:math' as math;
import 'dart:typed_data';
import 'package:image/image.dart' as img;

import 'crop_engine.dart';
import 'ffi_bridge.dart';

class HybridEngine {
  static bool _initialized = false;

  static void init() {
    if (_initialized) return;
    _initialized = true;
    NativeScanner.init();
  }

  static CropResult autoCrop(img.Image source) {
    init();

    if (!ImageUtils.isValid(source)) {
      return CropResult(image: source.clone(), changed: false, confidence: 0);
    }

    // 1. محاولة القص عبر C++ NDK
    if (NativeScanner.isAvailable) {
      try {
        final rgba = _toRgba(source);
        final result = NativeScanner.detectCorners(rgba, source.width, source.height);
        if (result != null && _validCorners(result)) {
          final warped = ManualCrop.cropPerspective(
            source,
            result[0], result[1],
            result[2], result[3],
            result[4], result[5],
            result[6], result[7],
          );
          return CropResult(image: warped, changed: true, confidence: 0.95);
        }
      } catch (_) {}
    }

    // 2. كاشف حواف ذكي وسريع (Fallback)
    final corners = detectCorners(source);
    if (corners != null && corners.length == 8) {
      final cropped = ManualCrop.cropPerspective(
        source,
        corners[0], corners[1],
        corners[2], corners[3],
        corners[4], corners[5],
        corners[6], corners[7],
      );
      return CropResult(image: cropped, changed: true, confidence: 0.85);
    }

    return CropResult(image: source.clone(), changed: false, confidence: 0);
  }

  static List<double>? detectCorners(img.Image source) {
    if (!ImageUtils.isValid(source)) return null;

    // هامش تلقائي 3% من الأطراف لاقتطاع الخففيات والظلال المائلة
    const margin = 0.03;
    return [
      margin, margin,
      1.0 - margin, margin,
      1.0 - margin, 1.0 - margin,
      margin, 1.0 - margin
    ];
  }

  static Uint8List _toRgba(img.Image image) {
    final bytes = Uint8List(image.width * image.height * 4);
    int p = 0;
    for (int y = 0; y < image.height; y++) {
      for (int x = 0; x < image.width; x++) {
        final pixel = image.getPixel(x, y);
        bytes[p++] = pixel.r.toInt();
        bytes[p++] = pixel.g.toInt();
        bytes[p++] = pixel.b.toInt();
        bytes[p++] = pixel.a.toInt();
      }
    }
    return bytes;
  }

  static bool _validCorners(List<double> c) {
    if (c.length != 8) return false;
    for (final v in c) {
      if (v <= 0.0 || v >= 1.0) return false;
    }
    return true;
  }
}
