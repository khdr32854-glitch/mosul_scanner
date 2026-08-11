import 'dart:typed_data';
import 'dart:ui' show Offset;

import 'package:opencv_dart/opencv_dart.dart' as cv;

/// ===============================================================
/// DOCUMENT EDGE DETECTOR - كشف حواف المستند تلقائياً
/// ===============================================================
///
/// يحلل صورة جاهزة (بايتات JPEG) ويحاول العثور على الشكل الرباعي
/// (الحواف الأربع) للمستند/البطاقة داخلها، عبر خط أنابيب كلاسيكي:
///
/// تدرج رمادي -> تنعيم (Gaussian Blur) -> كشف حواف (Canny) ->
/// إيجاد الكنتورات (findContours) -> تبسيط كل كنتور لأقرب شكل
/// رباعي (approxPolyDP) -> اختيار الأكبر مساحة من بينها.
///
/// يتطلب حزمة opencv_dart (native / NDK على أندرويد) - راجع
/// ملاحظات pubspec.yaml وworkflow المرفقة معه.
///
/// هذه الوحدة "تجريبية" من الناحية التقنية: opencv_dart نفسها
/// موسومة رسمياً بأنها WIP وقد تتغير توقيعات دوالها بين الإصدارات،
/// لذا ينصح باختبارها ببناء حقيقي وتعديل الاستدعاءات إذا لزم.
/// ===============================================================

class DocumentEdgeDetector {
  /// يحاول اكتشاف زوايا المستند داخل الصورة.
  ///
  /// يُعيد 4 نقاط بإحداثيات بكسل حقيقية (وليست نسبية) بالترتيب:
  /// أعلى-يسار، أعلى-يمين، أسفل-يمين، أسفل-يسار.
  ///
  /// يُعيد null إذا تعذر العثور على شكل رباعي واضح، وعندها يجب
  /// الرجوع لتحديد افتراضي (هامش صغير حول كامل الصورة) من واجهة
  /// المستخدم.
  static List<Offset>? detect(Uint8List imageBytes) {
    cv.Mat? original;
    cv.Mat? gray;
    cv.Mat? blurred;
    cv.Mat? edges;

    try {
      original = cv.imdecode(imageBytes, cv.IMREAD_COLOR);

      if (original.rows == 0 || original.cols == 0) {
        return null;
      }

      gray = cv.cvtColor(original, cv.COLOR_BGR2GRAY);
      blurred = cv.gaussianBlur(gray, (5, 5), 0);
      edges = cv.canny(blurred, 50, 150);

      final (contours, _) = cv.findContours(
        edges,
        cv.RETR_LIST,
        cv.CHAIN_APPROX_SIMPLE,
      );

      final imageArea = (original.rows * original.cols).toDouble();

      List<cv.Point>? bestQuad;
      double bestArea = 0;

      for (final contour in contours) {
        final area = cv.contourArea(contour);

        // نتجاهل أي كنتور صغير جداً (أقل من 15% من مساحة الصورة)
        // أو أكبر تقريباً من كامل الصورة (إطار خارجي وهمي).
        if (area < imageArea * 0.15 || area > imageArea * 0.98) {
          continue;
        }

        final perimeter = cv.arcLength(contour, true);
        final approx = cv.approxPolyDP(contour, 0.02 * perimeter, true);

        if (approx.length == 4 && area > bestArea) {
          bestArea = area;
          bestQuad = approx.toList();
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
      edges?.dispose();
    }
  }

  /// يرتب 4 نقاط (بترتيب عشوائي كما خرجت من approxPolyDP) إلى:
  /// أعلى-يسار، أعلى-يمين، أسفل-يمين، أسفل-يسار - بالاعتماد على
  /// مجموع وفرق الإحداثيات (طريقة معيارية شائعة في كشف المستندات).
  static List<Offset> _orderCorners(List<cv.Point> points) {
    final offsets = points
        .map(
          (p) => Offset(
            (p.x ?? 0).toDouble(),
            (p.y ?? 0).toDouble(),
          ),
        )
        .toList();

    // أعلى-يسار = أصغر (x+y)، أسفل-يمين = أكبر (x+y)
    final bySum = List<Offset>.from(offsets)
      ..sort((a, b) => (a.dx + a.dy).compareTo(b.dx + b.dy));

    final topLeft = bySum.first;
    final bottomRight = bySum.last;

    final remaining = offsets
        .where((o) => o != topLeft && o != bottomRight)
        .toList();

    // أعلى-يمين = أصغر (y-x)، أسفل-يسار = أكبر (y-x)
    remaining.sort((a, b) => (a.dy - a.dx).compareTo(b.dy - b.dx));

    final topRight = remaining.first;
    final bottomLeft = remaining.last;

    return [topLeft, topRight, bottomRight, bottomLeft];
  }
}
