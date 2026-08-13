import 'dart:typed_data';
import 'dart:ui';
import 'package:opencv_dart/opencv_dart.dart' as cv;

class DocumentEdgeDetector {
  static List<Offset>? detect(Uint8List imageBytes) {
    try {
      // 1. فك تشفير الصورة باستخدام OpenCV
      final src = cv.imdecode(imageBytes, cv.IMREAD_COLOR);
      if (src.isEmpty) return null;

      final double width = src.cols.toDouble();
      final double height = src.rows.toDouble();

      // 2. تحويل الصورة إلى الأبيض والأسود لتسهيل المعالجة
      final gray = cv.cvtColor(src, cv.COLOR_BGR2GRAY);

      // 3. تطبيق فلتر ضبابي (Gaussian Blur) لتقليل التشويش
      final blurred = cv.gaussianBlur(gray, (5, 5), 0);

      // 4. اكتشاف الحواف باستخدام خوارزمية Canny
      final edges = cv.canny(blurred, 75, 200);

      // 5. استخراج المضلعات (Contours)
      final contours = cv.findContours(edges, cv.RETR_LIST, cv.CHAIN_APPROX_SIMPLE);

      // 6. البحث عن أكبر مضلع يحتوي على 4 زوايا
      List<cv.Point>? bestContour;
      double maxArea = 0;

      for (var contour in contours.contours) {
        final area = cv.contourArea(contour);
        if (area > 5000) { // تجاهل الأشكال الصغيرة جدًا
          final peri = cv.arcLength(contour, true);
          // تبسيط المضلع لمحاولة الحصول على 4 نقاط فقط
          final approx = cv.approxPolyDP(contour, 0.02 * peri, true);

          if (approx.length == 4 && area > maxArea) {
            maxArea = area;
            bestContour = approx.toList();
          }
        }
      }

      // إذا لم يتم العثور على شكل رباعي، يتم إرجاع null (ليعود للوضع اليدوي)
      if (bestContour == null) return null;

      // 7. ترتيب النقاط (أعلى يسار، أعلى يمين، أسفل يمين، أسفل يسار)
      return _sortCorners(bestContour, width, height);

    } catch (e) {
      print('Edge detection error: $e');
      return null;
    }
  }

  // دالة مساعدة لترتيب الزوايا بشكل صحيح لتتوافق مع CropScreen
  static List<Offset> _sortCorners(List<cv.Point> points, double width, double height) {
    points.sort((a, b) => a.x.compareTo(b.x));
    
    final leftMost = [points[0], points[1]];
    final rightMost = [points[2], points[3]];

    leftMost.sort((a, b) => a.y.compareTo(b.y));
    rightMost.sort((a, b) => a.y.compareTo(b.y));

    final topLeft = leftMost[0];
    final bottomLeft = leftMost[1];
    final topRight = rightMost[0];
    final bottomRight = rightMost[1];

    return [
      Offset(topLeft.x.toDouble(), topLeft.y.toDouble()),
      Offset(topRight.x.toDouble(), topRight.y.toDouble()),
      Offset(bottomRight.x.toDouble(), bottomRight.y.toDouble()),
      Offset(bottomLeft.x.toDouble(), bottomLeft.y.toDouble()),
    ];
  }
}
