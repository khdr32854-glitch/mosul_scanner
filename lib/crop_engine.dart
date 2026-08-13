import 'dart:math' as math;
import 'dart:typed_data';
import 'package:flutter/foundation.dart';
import 'package:image/image.dart' as img;
import 'package:opencv_dart/opencv_dart.dart' as cv;

class CropEngine {
  /// محرك القص الاحترافي (Perspective Warp)
  /// يعتمد على OpenCV لضبط منظور الصورة (جعل البطاقة المائلة مستطيلة ومسطحة تماماً)
  static img.Image cropPerspective(
    img.Image source,
    double x1, double y1, // أعلى اليسار
    double x2, double y2, // أعلى اليمين
    double x3, double y3, // أسفل اليمين
    double x4, double y4, // أسفل اليسار
  ) {
    try {
      final w = source.width.toDouble();
      final h = source.height.toDouble();

      // 1. تحويل النسب (0.0 إلى 1.0) إلى بكسلات حقيقية بناءً على أبعاد الصورة
      final pt1 = cv.Point2f(x1 * w, y1 * h);
      final pt2 = cv.Point2f(x2 * w, y2 * h);
      final pt3 = cv.Point2f(x3 * w, y3 * h);
      final pt4 = cv.Point2f(x4 * w, y4 * h);

      // 2. حساب الأبعاد الدقيقة للمستند بعد القص باستخدام نظرية فيثاغورس
      // حساب العرض (أطول مسافة أفقية بين النقاط)
      final widthA = math.sqrt(math.pow(pt3.x - pt4.x, 2) + math.pow(pt3.y - pt4.y, 2));
      final widthB = math.sqrt(math.pow(pt2.x - pt1.x, 2) + math.pow(pt2.y - pt1.y, 2));
      final maxWidth = math.max(widthA, widthB).toInt();

      // حساب الارتفاع (أطول مسافة عمودية بين النقاط)
      final heightA = math.sqrt(math.pow(pt2.x - pt3.x, 2) + math.pow(pt2.y - pt3.y, 2));
      final heightB = math.sqrt(math.pow(pt1.x - pt4.x, 2) + math.pow(pt1.y - pt4.y, 2));
      final maxHeight = math.max(heightA, heightB).toInt();

      // تجنب أخطاء الأبعاد الصفرية في حال كان التحديد خاطئاً
      if (maxWidth <= 0 || maxHeight <= 0) return source;

      // 3. تحويل صورة Dart (img.Image) إلى مصفوفة OpenCV (Mat)
      // يتم ذلك عبر ضغط الصورة في الذاكرة لتسهيل نقلها بسرعة فائقة للمحرك
      final srcBytes = Uint8List.fromList(img.encodeJpg(source, quality: 100));
      final srcMat = cv.imdecode(srcBytes, cv.IMREAD_COLOR);

      if (srcMat.isEmpty) return source;

      // 4. تجهيز مصفوفات النقاط (المصدر والهدف)
      final srcPts = cv.VecPoint2f.fromList([pt1, pt2, pt3, pt4]);
      
      final dstPts = cv.VecPoint2f.fromList([
        cv.Point2f(0, 0),                                               // أعلى اليسار
        cv.Point2f(maxWidth.toDouble() - 1, 0),                         // أعلى اليمين
        cv.Point2f(maxWidth.toDouble() - 1, maxHeight.toDouble() - 1),  // أسفل اليمين
        cv.Point2f(0, maxHeight.toDouble() - 1),                        // أسفل اليسار
      ]);

      // 5. حساب مصفوفة التحويل الهندسي (Perspective Transform)
      final matrix = cv.getPerspectiveTransform(srcPts, dstPts);

      // 6. تنفيذ عملية التسطيح والقص (Warp Perspective)
      final warpedMat = cv.warpPerspective(srcMat, matrix, (maxWidth, maxHeight));

      // 7. إرجاع النتيجة إلى صيغة Dart الأساسية لاستخدامها في باقي التطبيق
      final encodeResult = cv.imencode('.jpg', warpedMat);
      final outBytes = encodeResult.$2; 
      
      final decoded = img.decodeJpg(outBytes);

      return decoded ?? source;
    } catch (e) {
      debugPrint('CropEngine Error: $e');
      // إرجاع الصورة الأصلية لحماية التطبيق من الانهيار في حال حدوث خطأ برمجي
      return source;
    }
  }
}
