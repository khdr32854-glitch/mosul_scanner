import 'dart:typed_data';
import 'dart:ui';
import 'package:opencv_dart/opencv_dart.dart' as cv;

class DocumentEdgeDetector {
  static List<Offset>? detect(Uint8List imageBytes) {
    try {
      // 1. قراءة الصورة
      final src = cv.imdecode(imageBytes, cv.IMREAD_COLOR);
      if (src.isEmpty) return null;

      final width = src.cols;
      final height = src.rows;
      final imageArea = width * height;

      // 2. تحويل الصورة إلى تدرج الرمادي
      final gray = cv.cvtColor(src, cv.COLOR_BGR2GRAY);

      // 3. الفلتر المزدوج (Bilateral Filter) الاحترافي
      // ممتاز جداً في طمس تفاصيل الخلفية (كالسجاد) مع الحفاظ على حواف المستند حادة
      final blurred = cv.bilateralFilter(gray, 9, 75, 75);

      // 4. استخراج الحواف
      final edges = cv.canny(blurred, 30, 150);

      // 5. تمديد الحواف (Dilation) لربط أي خطوط متقطعة بسبب ظلال الإضاءة
      final kernel = cv.getStructuringElement(cv.MORPH_RECT, (3, 3));
      final dilated = cv.dilate(edges, kernel);

      // 6. البحث عن المضلعات الخارجية فقط (RETR_EXTERNAL) لتجاهل النصوص داخل البطاقة
      final contoursResult = cv.findContours(dilated, cv.RETR_EXTERNAL, cv.CHAIN_APPROX_SIMPLE);
      final contours = contoursResult.$1.toList();

      // ترتيب المضلعات من الأكبر إلى الأصغر مساحة
      contours.sort((a, b) => cv.contourArea(b).compareTo(cv.contourArea(a)));

      List<cv.Point>? bestContour;

      // 7. فحص أكبر المضلعات بحثاً عن المستند
      for (int i = 0; i < contours.length && i < 5; i++) {
        final contour = contours[i];
        final area = cv.contourArea(contour);

        // يجب أن يغطي المستند على الأقل 10% من مساحة الصورة لاستبعاد الأشكال الصغيرة
        if (area < imageArea * 0.1) continue;

        final peri = cv.arcLength(contour, true);
        
        // استخدام نسبة 0.03 لتنعيم الزوايا الدائرية للبطاقات (مثل البطاقة الوطنية) 
        // وتقريبها إلى 4 زوايا حادة
        final approx = cv.approxPolyDP(contour, 0.03 * peri, true);

        // هل الشكل يحتوي على 4 زوايا؟
        if (approx.length == 4) {
          // هل الشكل محدب (Convex)؟ الأوراق والبطاقات يجب أن تكون محدبة دائماً
          if (cv.isContourConvex(approx)) {
            bestContour = approx.toList();
            break; // وجدنا البطاقة بدقة، نوقف البحث
          }
        }
      }

      if (bestContour == null) return null;

      // 8. ترتيب الزوايا هندسياً للتعامل مع كل زوايا التصوير
      return _sortCorners(bestContour);
    } catch (e) {
      return null;
    }
  }

  /// خوارزمية ترتيب الزوايا الرياضية الاحترافية (Sum and Difference)
  /// لا تتأثر إطلاقاً بدوران الصورة وتحدد الزوايا بدقة تامة
  static List<Offset> _sortCorners(List<cv.Point> points) {
    // Top-Left: أصغر مجموع لـ (x + y)
    // Bottom-Right: أكبر مجموع لـ (x + y)
    points.sort((a, b) => (a.x + a.y).compareTo(b.x + b.y));
    final topLeft = points.first;
    final bottomRight = points.last;

    // Top-Right: أصغر فرق لـ (y - x)
    // Bottom-Left: أكبر فرق لـ (y - x)
    points.sort((a, b) => (a.y - a.x).compareTo(b.y - b.x));
    final topRight = points.first;
    final bottomLeft = points.last;

    return [
      Offset(topLeft.x.toDouble(), topLeft.y.toDouble()), // الزاوية 1
      Offset(topRight.x.toDouble(), topRight.y.toDouble()), // الزاوية 2
      Offset(bottomRight.x.toDouble(), bottomRight.y.toDouble()), // الزاوية 3
      Offset(bottomLeft.x.toDouble(), bottomLeft.y.toDouble()), // الزاوية 4
    ];
  }
}
