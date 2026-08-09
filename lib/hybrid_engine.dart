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

    // 1. تجربة C++ Native
    if (NativeScanner.isAvailable) {
      final jpg = Uint8List.fromList(ImageUtils.encodeJpg(source, quality: 95));
      final dec = img.decodeImage(jpg);
      if (dec != null) {
        final rgba = _toRgba(dec);
        final result = NativeScanner.detectCorners(rgba, dec.width, dec.height);
        if (result != null && _validCorners(result)) {
          final warped = ManualCrop.cropPerspective(
            source,
            result[0], result[1],
            result[2], result[3],
            result[4], result[5],
            result[6], result[7],
          );
          final changed = warped.width != source.width || warped.height != source.height;
          if (changed) {
            return CropResult(image: warped, changed: true, confidence: 0.95);
          }
        }
      }
    }

    // 2. تجربة Dart RANSAC
    try {
      final dartResult = SmartCrop.detect(source);
      if (dartResult.changed && dartResult.confidence > 0.5) {
        return dartResult;
      }
    } catch (_) {}

    return CropResult(image: source.clone(), changed: false, confidence: 0);
  }

  static List<double>? detectCorners(img.Image source) {
    init();
    if (!ImageUtils.isValid(source)) return null;

    if (NativeScanner.isAvailable) {
      final jpg = Uint8List.fromList(ImageUtils.encodeJpg(source, quality: 95));
      final dec = img.decodeImage(jpg);
      if (dec != null) {
        final rgba = _toRgba(dec);
        final result = NativeScanner.detectCorners(rgba, dec.width, dec.height);
        if (result != null && _validCorners(result)) return result;
      }
    }
    return SmartCrop.detectCorners(source);
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
      if (v < 0.0 || v > 1.0) return false;
    }
    return true;
  }
}

