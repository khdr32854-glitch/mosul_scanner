import 'dart:math' as math;
import 'dart:typed_data';

import 'package:flutter/foundation.dart';
import 'package:opencv_dart/opencv_dart.dart' as cv;

class ImageUtils {
  static cv.Mat? decodeBytes(Uint8List bytes) {
    try {
      if (bytes.isEmpty) return null;

      final mat = cv.imdecode(bytes, cv.IMREAD_COLOR);

      if (mat.isEmpty) return null;
      return mat;
    } catch (e) {
      debugPrint('OpenCV decode error: $e');
      return null;
    }
  }

  static Uint8List encodeJpg(
    cv.Mat image, {
    int quality = 95,
  }) {
    try {
      if (image.isEmpty) {
        return Uint8List(0);
      }

      final result = cv.imencode(
        '.jpg',
        image,
        params: cv.VecI32.fromList([
          cv.IMWRITE_JPEG_QUALITY,
          quality.clamp(1, 100),
        ]),
      );

      return result.$2;
    } catch (e) {
      debugPrint('OpenCV encode error: $e');
      return Uint8List(0);
    }
  }
}

enum EnhanceMode {
  none,
  soft,
  bw,
}

class ImageEnhancer {
  static cv.Mat apply(
    cv.Mat source,
    EnhanceMode mode,
  ) {
    if (source.isEmpty) {
      return source;
    }

    switch (mode) {
      case EnhanceMode.none:
        return source.clone();

      case EnhanceMode.soft:
        try {
          // مهم:
          // opencv_dart يحتاج matType كـ positional argument.
          return source.convertTo(
            source.type,
            alpha: 1.10,
            beta: 10,
          );
        } catch (e) {
          debugPrint('Soft enhancement error: $e');
          return source.clone();
        }

      case EnhanceMode.bw:
        try {
          final gray = cv.cvtColor(
            source,
            cv.COLOR_BGR2GRAY,
          );

          return gray.convertTo(
            gray.type,
            alpha: 1.50,
            beta: 20,
          );
        } catch (e) {
          debugPrint('BW enhancement error: $e');
         
