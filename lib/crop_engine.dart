import 'dart:math' as math;
import 'dart:typed_data';
import 'package:image/image.dart' as img;

import 'crop_engine.dart';
import 'ffi_bridge.dart';

/// HybridEngine — OpenCV Native + Dart RANSAC
///
/// الإستراتيجية:
/// 1. إذا OpenCV C++ متاح → استخدمه (أفضل نتيجة)
/// 2. إذا فشل → استخدم Dart RANSAC
/// 3. إذا الكل فشل → ارجع الصورة الأصلية
///
/// هذا يعطي أفضل ما في العالمين.

class HybridEngine {
  static bool _initialized = false;

  static void init() {
    if (_initialized) return;
    _initialized = true;
    NativeScanner.init();
  }

  /// قص تلقائي متكامل
  static CropResult autoCrop(img.Image source) {
    init();

    if (!ImageUtils.isValid(source)) {
      return CropResult(image: source.clone(), changed: false, confidence: 0);
    }

    // ── المحاولة 1: OpenCV C++ ──
    if (NativeScanner.isAvailable) {
      final jpg = Uint8List.fromList(ImageUtils.encodeJpg(source, quality: 95));
      final dec = img.decodeImage(jpg);
      if (dec != null) {
        // نحتاج RGBA
        final rgba = _toRgba(dec);
        final result = NativeScanner.detectCorners(rgba, dec.width, dec.height);
        if (result != null && _validCorners(result)) {
          final warped = ManualCrop.cropPerspective(
            source,
            result[0], result[1], result[2], result[3],
            result[4], result[5], result[6], result[7],
          );
          final changed = warped.width != source.width || warped.height != source.height;
          if (changed) {
            return CropResult(image: warped, changed: true, confidence: 0.95);
          }
        }
      }
    }

    // ── المحاولة 2: Dart RANSAC ──
    try {
      final dartResult = SmartCrop.detect(source);
      if (dartResult.changed && dartResult.confidence > 0.5) {
        return dartResult;
      }
    } catch (_) {}

    // ── المحاولة 3: إرجاع الصورة الأصلية ──
    return CropResult(image: source.clone(), changed: false, confidence: 0);
  }

  /// كشف الزوايا (للـ CropScreen)
  static List<double>? detectCorners(img.Image source) {
    init();

    if (!ImageUtils.isValid(source)) return null;

    // OpenCV أولاً
    if (NativeScanner.isAvailable) {
      final jpg = Uint8List.fromList(ImageUtils.encodeJpg(source, quality: 95));
      final dec = img.decodeImage(jpg);
      if (dec != null) {
        final rgba = _toRgba(dec);
        final result = NativeScanner.detectCorners(rgba, dec.width, dec.height);
        if (result != null && _validCorners(result)) return result;
      }
    }

    // Dart RANSAC
    return SmartCrop.detectCorners(source);
  }

  /// قص مع منظور + تحسين
  static img.Image cropAndEnhance(
    img.Image source,
    List<double> corners,
    int enhanceMode, // 0=none, 1=soft, 2=bw
  ) {
    init();

    // OpenCV warp
    if (NativeScanner.isAvailable) {
      final jpg = Uint8List.fromList(ImageUtils.encodeJpg(source, quality: 95));
      final dec = img.decodeImage(jpg);
      if (dec != null) {
        final rgba = _toRgba(dec);
        final w1 = math.sqrt(math.pow(corners[2]-corners[0], 2) + math.pow(corners[3]-corners[1], 2));
        final w2 = math.sqrt(math.pow(corners[6]-corners[4], 2) + math.pow(corners[7]-corners[5], 2));
        final h1 = math.sqrt(math.pow(corners[4]-corners[0], 2) + math.pow(corners[5]-corners[1], 2));
        final h2 = math.sqrt(math.pow(corners[6]-corners[2], 2) + math.pow(corners[7]-corners[3], 2));
        int dw = math.max(1, math.max(w1, w2).round());
        int dh = math.max(1, math.max(h1, h2).round());
        final lng = math.max(dw, dh);
        if (lng > 3200) { final f = 3200 / lng; dw = math.max(1, (dw * f).round()); dh = math.max(1, (dh * f).round()); }

        final warped = NativeScanner.warpAndEnhance(rgba, dec.width, dec.height, corners, dw, dh, enhanceMode);
        if (warped != null) {
          final result = img.Image.fromBytes(width: dw, height: dh, bytes: warped.buffer, numChannels: 4, order: img.ChannelOrder.rgba);
          if (result != null && ImageUtils.isValid(result)) return result;
        }
      }
    }

    // Dart fallback
    final warped = ManualCrop.cropPerspective(
      source,
      corners[0], corners[1], corners[2], corners[3],
      corners[4], corners[5], corners[6], corners[7],
    );

    final mode = switch (enhanceMode) { 1 => EnhanceMode.soft, 2 => EnhanceMode.bw, _ => EnhanceMode.none };
    return ImageEnhancer.apply(warped, mode);
  }

  static bool _validCorners(List<double> c) {
    if (c.length != 8) return false;
    for (final v in c) { if (!v.isFinite || v < -0.2 || v > 1.2) return false; }
    final w = math.sqrt(math.pow(c[2]-c[0],2)+math.pow(c[3]-c[1],2));
    final h = math.sqrt(math.pow(c[6]-c[2],2)+math.pow(c[7]-c[3],2));
    return w > 0.05 && h > 0.05;
  }

  static Uint8List _toRgba(img.Image src) {
    if (src.numChannels == 4 && src.format == img.Format.uint8) {
      return Uint8List.fromList(src.toUint8List());
    }
    final rgba = img.Image(width: src.width, height: src.height, numChannels: 4);
    for (int y = 0; y < src.height; y++) {
      for (int x = 0; x < src.width; x++) {
        final p = src.getPixel(x, y);
        rgba.setPixelRgba(x, y, p.r.toInt(), p.g.toInt(), p.b.toInt(), p.a.toInt());
      }
    }
    return Uint8List.fromList(rgba.toUint8List());
  }
}
