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
      if (image.isEmpty) return Uint8List(0);

      final result = cv.imencode(
        '.jpg',
        image,
        params: cv.VecI32.fromList([
          cv.IMWRITE_JPEG_QUALITY,
          quality,
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
  static cv.Mat apply(cv.Mat source, EnhanceMode mode) {
    if (source.isEmpty) return source;

    switch (mode) {
      case EnhanceMode.none:
        return source.clone();

      case EnhanceMode.soft:
        try {
          return source.convertTo(
            source.type,
            alpha: 1.1,
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
            alpha: 1.5,
            beta: 20,
          );
        } catch (e) {
          debugPrint('B&W enhancement error: $e');
          return source.clone();
        }
    }
  }
}

class ManualCrop {
  static cv.Mat? cropPerspective(
    cv.Mat source,
    double x1,
    double y1,
    double x2,
    double y2,
    double x3,
    double y3,
    double x4,
    double y4,
  ) {
    if (source.isEmpty) return null;

    final w = source.cols.toDouble();
    final h = source.rows.toDouble();

    final srcPts = [
      cv.Point2f(x1 * (w - 1), y1 * (h - 1)),
      cv.Point2f(x2 * (w - 1), y2 * (h - 1)),
      cv.Point2f(x3 * (w - 1), y3 * (h - 1)),
      cv.Point2f(x4 * (w - 1), y4 * (h - 1)),
    ];

    final topWidth = _distance(srcPts[0], srcPts[1]);
    final bottomWidth = _distance(srcPts[3], srcPts[2]);
    final leftHeight = _distance(srcPts[0], srcPts[3]);
    final rightHeight = _distance(srcPts[1], srcPts[2]);

    final outputWidth = mathMax(1, mathMaxInt(topWidth.round(), bottomWidth.round()));
    final outputHeight = mathMax(1, mathMaxInt(leftHeight.round(), rightHeight.round()));

    final dstPts = [
      cv.Point2f(0, 0),
      cv.Point2f((outputWidth - 1).toDouble(), 0),
      cv.Point2f(
        (outputWidth - 1).toDouble(),
        (outputHeight - 1).toDouble(),
      ),
      cv.Point2f(0, (outputHeight - 1).toDouble()),
    ];

    try {
      final matrix = cv.getPerspectiveTransform2f(
        srcPts.cvd,
        dstPts.cvd,
      );

      return cv.warpPerspective(
        source,
        matrix,
        (outputWidth, outputHeight),
      );
    } catch (e) {
      debugPrint('Perspective Crop error: $e');
      return source.clone();
    }
  }

  static double _distance(cv.Point2f a, cv.Point2f b) {
    final dx = a.x - b.x;
    final dy = a.y - b.y;
    return math.sqrt(dx * dx + dy * dy);
  }

  static int mathMax(int a, int b) => a > b ? a : b;

  static int mathMaxInt(int a, int b) => a > b ? a : b;
}


class SmartCrop {
  static List<double>? detectCorners(cv.Mat source) {
    if (source.isEmpty) return null;

    // Fallback آمن: يحدد معظم الصورة.
    // يمكن لاحقاً استبداله بكشف مستند حقيقي.
    return [
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
