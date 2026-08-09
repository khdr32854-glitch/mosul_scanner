import 'dart:ffi';
import 'dart:typed_data';
import 'package:ffi/ffi.dart';

/// FFI Bridge — يربط Dart بكود C++ (document_scanner.cpp)
class NativeScanner {
  static DynamicLibrary? _lib;
  static bool _loaded = false;
  static bool _available = false;

  /// محاولة تحميل المكتبة الأصلية
  static bool get isAvailable => _available;

  static void init() {
    if (_loaded) return;
    _loaded = true;
    try {
      _lib = DynamicLibrary.open('libopencv_java4.so');
      _available = true;
    } catch (_) {
      _available = false;
    }
  }

  // ──────────────────────────────────────────
  // detect_document_corners
  // ──────────────────────────────────────────
  static final _detectCornersNative = _lib?.lookupFunction<
      Int32 Function(Pointer<Uint8>, Int32, Int32, Pointer<Float>),
      int Function(Pointer<Uint8>, int, int, Pointer<Float>)
  >('detect_document_corners');

  /// كشف الزوايا الأربع — تُرجع null إذا فشل
  static List<double>? detectCorners(Uint8List rgba, int width, int height) {
    if (!_available || _lib == null || _detectCornersNative == null) return null;

    final pixels = calloc<Uint8>(rgba.length);
    final corners = calloc<Float>(8);
    try {
      // نسخ البيانات
      for (int i = 0; i < rgba.length; i++) {
        pixels[i] = rgba[i];
      }

      final result = _detectCornersNative!(pixels, width, height, corners);
      if (result == 0) return null;

      return [
        corners[0], corners[1], corners[2], corners[3],
        corners[4], corners[5], corners[6], corners[7],
      ];
    } finally {
      calloc.free(pixels);
      calloc.free(corners);
    }
  }

  // ──────────────────────────────────────────
  // warp_and_enhance
  // ──────────────────────────────────────────
  static final _warpEnhanceNative = _lib?.lookupFunction<
      Int32 Function(Pointer<Uint8>, Int32, Int32, Pointer<Float>, Pointer<Uint8>, Int32, Int32, Int32),
      int Function(Pointer<Uint8>, int, int, Pointer<Float>, Pointer<Uint8>, int, int, int)
  >('warp_and_enhance');

  /// تصحيح منظور + تحسين — تُرجع null إذا فشل
  static Uint8List? warpAndEnhance(
    Uint8List srcRgba, int sw, int sh,
    List<double> corners, int dw, int dh, int enhanceMode,
  ) {
    if (!_available || _lib == null || _warpEnhanceNative == null) return null;

    final src = calloc<Uint8>(srcRgba.length);
    final dst = calloc<Uint8>(dw * dh * 4);
    final c = calloc<Float>(8);
    try {
      for (int i = 0; i < srcRgba.length; i++) src[i] = srcRgba[i];
      for (int i = 0; i < 8; i++) c[i] = corners[i];

      final result = _warpEnhanceNative!(src, sw, sh, c, dst, dw, dh, enhanceMode);
      if (result == 0) return null;

      return dst.asTypedList(dw * dh * 4);
    } finally {
      calloc.free(src);
      calloc.free(dst);
      calloc.free(c);
    }
  }

  // ──────────────────────────────────────────
  // auto_scan_document
  // ──────────────────────────────────────────
  static final _autoScanNative = _lib?.lookupFunction<
      Pointer<Uint8> Function(Pointer<Uint8>, Int32, Int32, Pointer<Int32>, Pointer<Int32>, Int32),
      Pointer<Uint8> Function(Pointer<Uint8>, int, int, Pointer<Int32>, Pointer<Int32>, int)
  >('auto_scan_document');

  /// قص تلقائي كامل — تُرجع (pixels, width, height) أو null
  static ({Uint8List pixels, int width, int height})? autoScan(
    Uint8List rgba, int width, int height, int enhanceMode,
  ) {
    if (!_available || _lib == null || _autoScanNative == null) return null;

    final pixels = calloc<Uint8>(rgba.length);
    final ow = calloc<Int32>();
    final oh = calloc<Int32>();
    try {
      for (int i = 0; i < rgba.length; i++) pixels[i] = rgba[i];

      final dstPtr = _autoScanNative!(pixels, width, height, ow, oh, enhanceMode);
      if (dstPtr == nullptr) return null;

      final w = ow.value;
      final h = oh.value;
      final size = w * h * 4;
      final result = dstPtr.asTypedList(size);
      final copy = Uint8List.fromList(result);

      // تحرير الذاكرة المخصصة في C++
      calloc.free(dstPtr);

      return (pixels: copy, width: w, height: h);
    } finally {
      calloc.free(pixels);
      calloc.free(ow);
      calloc.free(oh);
    }
  }
}
