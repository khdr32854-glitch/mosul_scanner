import 'dart:typed_data';

import 'package:flutter/foundation.dart';
import 'package:opencv_dart/opencv_dart.dart' as cv;

class ImageUtils {
  static cv.Mat? decodeBytes(Uint8List bytes) {
    try {
      final mat = cv.imdecode(bytes, cv.IMREAD_COLOR);

      if (mat.isEmpty) {
        return null;
      }

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
          // matType يجب أن يكون positional في إصدار opencv_dart المستخدم.
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
    if (source.isEmpty) {
      return null;
    }

    final double w = source.cols.toDouble();
    final double h = source.rows.toDouble();

    final srcPts = [
      cv.Point2f(x1 * w, y1 * h),
      cv.Point2f(x2 * w, y2 * h),
      cv.Point2f(x3 * w, y3 * h),
      cv.Point2f(x4 * w, y4 * h),
    ];

    final dstPts = [
      cv.Point2f(0, 0),
      cv.Point2f(w - 1, 0),
      cv.Point2f(w - 1, h - 1),
      cv.Point2f(0, h - 1),
    ];

    try {
      final matrix = cv.getPerspectiveTransform2f(
        srcPts.cvd,
        dstPts.cvd,
      );

      final result = cv.warpPerspective(
        source,
        matrix,
        (
          source.cols,
          source.rows,
        ),
      );

      return result;
    } catch (e) {
      debugPrint('Perspective Crop error: $e');
      return source.clone();
    }
  }
}

class SmartCrop {
  static List<double>? detectCorners(
    cv.Mat source,
  ) {
    if (source.isEmpty) {
      return null;
    }

    // مؤقتاً: حدود قريبة من كامل الصورة.
    // يمكن لاحقاً استبدالها بكشف حقيقي لحواف المستند.
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
