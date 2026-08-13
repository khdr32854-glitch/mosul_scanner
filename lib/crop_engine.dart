import 'dart:math' as math;
import 'package:flutter/foundation.dart';
import 'package:image/image.dart' as img;
import 'package:opencv_dart/opencv_dart.dart' as cv;

class CropEngine {
  /// محرك القص الاحترافي (Perspective Warp)
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

      // استخدام نقاط صحيحة (Point) بدلاً من العشرية (Point2f) لحل مشكلة التوافق
      final pt1 = cv.Point((x1 * w).toInt(), (y1 * h).toInt());
      final pt2 = cv.Point((x2 * w).toInt(), (y2 * h).toInt());
      final pt3 = cv.Point((x3 * w).toInt(), (y3 * h).toInt());
      final pt4 = cv.Point((x4 * w).toInt(), (y4 * h).toInt());

      final widthA = math.sqrt(math.pow(pt3.x - pt4.x, 2) + math.pow(pt3.y - pt4.y, 2));
      final widthB = math.sqrt(math.pow(pt2.x - pt1.x, 2) + math.pow(pt2.y - pt1.y, 2));
      final maxWidth = math.max(widthA, widthB).toInt();

      final heightA = math.sqrt(math.pow(pt2.x - pt3.x, 2) + math.pow(pt2.y - pt3.y, 2));
      final heightB = math.sqrt(math.pow(pt1.x - pt4.x, 2) + math.pow(pt1.y - pt4.y, 2));
      final maxHeight = math.max(heightA, heightB).toInt();

      if (maxWidth <= 0 || maxHeight <= 0) return source;

      final srcBytes = Uint8List.fromList(img.encodeJpg(source, quality: 100));
      final srcMat = cv.imdecode(srcBytes, cv.IMREAD_COLOR);

      if (srcMat.isEmpty) return source;

      // تحويل النقاط إلى VecPoint لتتوافق مع مكتبة opencv_dart
      final srcPts = cv.VecPoint.fromList([pt1, pt2, pt3, pt4]);
      
      final dstPts = cv.VecPoint.fromList([
        cv.Point(0, 0),                               
        cv.Point(maxWidth - 1, 0),                         
        cv.Point(maxWidth - 1, maxHeight - 1),  
        cv.Point(0, maxHeight - 1),                        
      ]);

      final matrix = cv.getPerspectiveTransform(srcPts, dstPts);

      final warpedMat = cv.warpPerspective(srcMat, matrix, (maxWidth, maxHeight));

      final encodeResult = cv.imencode('.jpg', warpedMat);
      final outBytes = encodeResult.$2; 
      
      final decoded = img.decodeJpg(outBytes);

      return decoded ?? source;
    } catch (e) {
      debugPrint('CropEngine Error: $e');
      return source;
    }
  }
}
