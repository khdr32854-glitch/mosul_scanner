import 'dart:typed_data';
import 'dart:ui' show Offset;

import 'package:opencv_dart/opencv_dart.dart' as cv;

/// ===============================================================
/// DOCUMENT EDGE DETECTOR - كشف حواف المستند تلقائياً (نسخة احترافية)
/// ===============================================================
class DocumentEdgeDetector {
  static List<Offset>? detect(Uint8List imageBytes) {
    cv.Mat? original;
    cv.Mat? gray;
    cv.Mat? blurred;
    cv.Mat? thresh;
    cv.Mat? edges;

    try {
      original = cv.imdecode(imageBytes, cv.IMREAD_COLOR);

      if (original.rows == 0 || original.cols == 0) {
        return null;
      }

      // 1. تحويل الصورة إلى تدرج رمادي
      gray = cv.cvtColor(original, cv.COLOR_BGR2GRAY);

      // 2. استخدام Bilateral Filter لحفظ الحواف الحقيقية وإزالة تفاصيل الخلفية المشتتة
      blurred = cv.bilateralFilter(gray, 9, 75, 75);

      // 3. تقوية التباين باستخدام Adaptive Thresholding لتجاوز مشاكل الإضاءة والظلال
      thresh = cv.adaptiveThreshold(
        blurred,
        255,
        cv.ADAPTIVE_THRESH_GAUSSIAN_C,
        cv.THRESH_BINARY,
        11,
        2,
      );

      // 4. استخراج الحواف بمرونة أعلى
      edges = cv.canny(thresh, 30, 100);

      // 5. استخدام RETR_EXTERNAL لجلب الحدود الخارجية الكبرى فقط
      final (contours, _) = cv.findContours(
        edges,
        cv.RETR_EXTERNAL,
        cv.CHAIN_APPROX_SIMPLE,
      );

      final imageArea = (original.rows * original.cols).toDouble();

      List<cv.Point>? bestQuad;
      double maxArea = 0;

      for (final contour in contours) {
        final area = cv.contourArea(contour);

        // نتجاهل المساحات الصغيرة جداً أو التي تملأ كامل الصورة
        if (area < imageArea * 0.10 || area > imageArea * 0.99) {
          continue;
        }

        final perimeter = cv.arcLength(contour, true);
        
        // تجربة عدة نسب تبسيط للوصول لشكل رباعي دقيق
        for (double factor in [0.01, 0.02, 0.03, 0.04, 0.05]) {
          final approx = cv.approxPolyDP(contour, factor * perimeter, true);

          if (approx.length == 4) {
            if (area > maxArea && cv.isContourConvex(approx)) {
              maxArea = area;
              bestQuad = approx.toList();
            }
            break;
          }
        }
      }

      if (bestQuad == null) {
        // خطة بديلة: إذا فشل العثور على رباعي عبر Canny، نبحث عن أكبر مضلع خشن
        for (final contour in contours) {
          final area = cv.contourArea(contour);
          if (area > maxArea && area > imageArea * 0.15) {
            final perimeter = cv.arcLength(contour, true);
            final approx = cv.approxPolyDP(contour, 0.02 * perimeter, true);
            
            if (approx.length >= 4 && approx.length <= 6) {
              maxArea = area;
              // تم الإصلاح: تحويل VecPoint إلى List أولاً ثم استخدام sublist
              bestQuad = approx.toList().sublist(0, 4);
            }
          }
        }
      }

      if (bestQuad == null) {
        return null;
      }

      return _orderCorners(bestQuad);
    } catch (_) {
      return null;
    } finally {
      original?.dispose();
      gray?.dispose();
      blurred?.dispose();
      thresh?.dispose();
      edges?.dispose();
    }
  }

  static List<Offset> _orderCorners(List<cv.Point> points) {
    // تم الإصلاح: إزالة (?? 0) لأن المتغيرات x و y غير قابلة لتكون null في opencv_dart
    final offsets = points
        .map(
          (p) => Offset(
            p.x.toDouble(),
            p.y.toDouble(),
          ),
        )
        .toList();

    if (offsets.length < 4) {
      return [
        const Offset(0, 0),
        const Offset(100, 0),
        const Offset(100, 100),
        const Offset(0, 100),
      ];
    }

    final bySum = List<Offset>.from(offsets)
      ..sort((a, b) => (a.dx + a.dy).compareTo(b.dx + b.dy));

    final topLeft = bySum.first;
    final bottomRight = bySum.last;

    final remaining = offsets
        .where((o) => o != topLeft && o != bottomRight)
        .toList();

    remaining.sort((a, b) => (a.dy - a.dx).compareTo(b.dy - b.dx));

    final topRight = remaining.isNotEmpty ? remaining.first : const Offset(100, 0);
    final bottomLeft = remaining.length > 1 ? remaining.last : const Offset(0, 100);

    return [topLeft, topRight, bottomRight, bottomLeft];
  }
}
