import 'dart:math' as math;
import 'dart:typed_data';
import 'package:image/image.dart' as img;

import 'crop_engine.dart';
import 'ffi_bridge.dart';

/// HybridEngine — OpenCV C++ + Dart RANSAC
/// 
/// 1. C++ Native (OpenCV) — الأفضل
/// 2. Dart RANSAC — الاحتياطي
/// 3. هامش 4% — آخر خط دفاع (لا يرجع null أبداً)

class HybridEngine {
  static bool _initialized = false;
  static bool _cppAvailable = false;

  static void init() {
    if (_initialized) return;
    _initialized = true;
    try { 
      NativeScanner.init();
      _cppAvailable = NativeScanner.isAvailable;
    } catch (_) {
      _cppAvailable = false;
    }
  }

  static CropResult autoCrop(img.Image source) {
    init();
    if (!ImageUtils.isValid(source)) {
      return CropResult(image: source, changed: false, confidence: 0);
    }

    final corners = detectCorners(source);
    if (corners != null && corners.length == 8) {
      final cropped = ManualCrop.cropPerspective(
        source,
        corners[0], corners[1], corners[2], corners[3],
        corners[4], corners[5], corners[6], corners[7],
      );
      final changed = cropped.width != source.width || cropped.height != source.height;
      return CropResult(image: cropped, changed: changed, confidence: changed ? 0.88 : 0);
    }

    return CropResult(image: source.clone(), changed: false, confidence: 0);
  }

  static List<double>? detectCorners(img.Image source) {
    if (!ImageUtils.isValid(source)) return null;

    // ── 1. C++ OpenCV ──
    if (_cppAvailable) {
      try {
        final rgba = _toRgba(source);
        final result = NativeScanner.detectCorners(rgba, source.width, source.height);
        if (result != null && _validCorners(result)) return result;
      } catch (_) {}
    }

    // ── 2. Dart RANSAC ──
    try {
      final dartResult = SmartCrop.detectCorners(source);
      if (dartResult != null && _validCorners(dartResult)) return dartResult;
    } catch (_) {}

    // ── 3. هامش 3% — قص آمن (لا يفشل أبداً) ──
    const m = 0.03;
    return [m, m, 1.0 - m, m, 1.0 - m, 1.0 - m, m, 1.0 - m];
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
      if (!v.isFinite || v < -0.15 || v > 1.15) return false;
    }
    final w = math.sqrt(math.pow(c[2]-c[0],2)+math.pow(c[3]-c[1],2));
    final h = math.sqrt(math.pow(c[6]-c[2],2)+math.pow(c[7]-c[3],2));
    return w > 0.02 && h > 0.02;
  }
}
