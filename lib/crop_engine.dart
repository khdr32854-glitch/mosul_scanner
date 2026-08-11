import 'dart:typed_data';
import 'package:flutter/foundation.dart';
import 'package:opencv_dart/opencv_dart.dart' as cv;

/// ===============================================================
/// MOSUL SCANNER - CROP ENGINE (OPENCV EDITION)
/// ===============================================================
/// يعتمد هذا المحرك حصرياً على opencv_dart لمعالجة الصور بسرعة عالية
/// ===============================================================

class ImageUtils {
  /// تحويل الصورة من بايتات (من الاستوديو أو الكاميرا) إلى مصفوفة OpenCV
  static cv.Mat? decodeBytes(Uint8List bytes) {
    try {
      final mat = cv.imdecode(bytes, cv.IMREAD_COLOR);
      if (mat.isEmpty) return null;
      return mat;
    } catch (e) {
      debugPrint('MOSUL SCANNER OpenCV decode error: $e');
      return null;
    }
  }

  /// تحويل الصورة من مصفوفة OpenCV إلى بايتات لعرضها في الواجهة
  static Uint8List encodeJpg(cv.Mat image, {int quality = 95}) {
    try {
      if (image.isEmpty) return Uint8List(0);
      final result = cv.imencode('.jpg', image, params: [cv.IMWRITE_JPEG_QUALITY, quality]);
      // opencv_dart تُرجع قيمة (success, bytes)
      return result.$2; 
    } catch (e) {
      debugPrint('MOSUL SCANNER OpenCV encode error: $e');
      return Uint8List(0);
    }
  }
}

/// ===============================================================
/// IMAGE ENHANCER (فلاتر التحسين)
/// ===============================================================

enum EnhanceMode { none, soft, bw }

class ImageEnhancer {
  static cv.Mat apply(cv.Mat source, EnhanceMode mode) {
    if (source.isEmpty) return source;

    switch (mode) {
      case EnhanceMode.none:
        return source.clone();

      case EnhanceMode.soft:
        try {
          // زيادة التباين والإضاءة بشكل احترافي
          final result = cv.Mat.empty();
          source.convertTo(result, -1, alpha: 1.1, beta: 10);
          return result;
        } catch (e) {
          return source;
        }

      case EnhanceMode.bw:
        try {
          // تحويل الصورة لأبيض وأسود عالي التباين (للمستندات)
          final gray = cv.cvtColor(source, cv.COLOR_BGR2GRAY);
          final result = cv.Mat.empty();
          gray.convertTo(result, -1, alpha: 1.5, beta: 20);
          return result;
        } catch (e) {
          return source;
        }
    }
  }
}

/// ===============================================================
/// MANUAL CROP (قص حقيقي مع تصحيح المنظور)
/// ===============================================================

class ManualCrop {
  static cv.Mat? cropPerspective(
    cv.Mat source,
    double x1, double y1, // أعلى يسار
    double x2, double y2, // أعلى يمين
    double x3, double y3, // أسفل يمين
    double x4, double y4, // أسفل يسار
  ) {
    if (source.isEmpty) return null;

    final w = source.cols.toDouble();
    final h = source.rows.toDouble();

    // تحديد النقاط الأصلية للصورة المحددة
    final srcPts = [
      cv.Point2f(x1 * w, y1 * h),
      cv.Point2f(x2 * w, y2 * h),
      cv.Point2f(x3 * w, y3 * h),
      cv.Point2f(x4 * w, y4 * h),
    ];

    // تحديد أبعاد الصورة الجديدة بعد القص (لتبدو كورقة مستقيمة)
    final dstPts = [
      cv.Point2f(0, 0),
      cv.Point2f(w, 0),
      cv.Point2f(w, h),
      cv.Point2f(0, h),
    ];

    try {
      // حساب مصفوفة التحويل (Perspective Transform)
      final matrix = cv.getPerspectiveTransform2f(srcPts.cvd, dstPts.cvd);
      
      // تطبيق القص والتعديل
      final result = cv.warpPerspective(source, matrix, cv.Size(source.cols, source.rows));
      return result;
    } catch (e) {
      debugPrint('MOSUL SCANNER Perspective Crop error: $e');
      return source.clone();
    }
  }
}

/// ===============================================================
/// SMART CROP (التعرف التلقائي على الحواف)
/// ===============================================================

class SmartCrop {
  /// ترجع الإحداثيات التقريبية لحواف الورقة
  static List<double>? detectCorners(cv.Mat source) {
    if (source.isEmpty) return null;

    // في هذه المرحلة، نضع إحداثيات مبدئية ممتازة لقص المستند
    // (لاحقاً يمكننا إضافة كود Canny Edge Detection للبحث عن الورقة آلياً)
    return [
      0.05, 0.05, // أعلى يسار
      0.95, 0.05, // أعلى يمين
      0.95, 0.95, // أسفل يمين
      0.05, 0.95, // أسفل يسار
    ];
  }
}
