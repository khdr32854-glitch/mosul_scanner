import 'dart:typed_data';
import 'dart:ui';
import 'package:opencv_dart/opencv_dart.dart' as cv;

class DocumentEdgeDetector {
  static List<Offset>? detect(Uint8List imageBytes) {
    try {
      final src = cv.imdecode(imageBytes, cv.IMREAD_COLOR);
      if (src.isEmpty) return null;

      final gray = cv.cvtColor(src, cv.COLOR_BGR2GRAY);
      final blurred = cv.gaussianBlur(gray, (5, 5), 0);
      final edges = cv.canny(blurred, 75, 200);

      final contoursResult = cv.findContours(edges, cv.RETR_LIST, cv.CHAIN_APPROX_SIMPLE);
      final contours = contoursResult.$1;

      List<cv.Point>? bestContour;
      double maxArea = 0;

      for (int i = 0; i < contours.length; i++) {
        final contour = contours[i];
        final area = cv.contourArea(contour);

        if (area > 5000) {
          final peri = cv.arcLength(contour, true);
          final approx = cv.approxPolyDP(contour, 0.02 * peri, true);

          if (approx.length == 4 && area > maxArea) {
            maxArea = area;
            bestContour = approx.toList();
          }
        }
      }

      if (bestContour == null) return null;

      return _sortCorners(bestContour);
    } catch (e) {
      return null;
    }
  }

  static List<Offset> _sortCorners(List<cv.Point> points) {
    points.sort((a, b) => a.y.compareTo(b.y));

    final topPoints = [points[0], points[1]];
    final bottomPoints = [points[2], points[3]];

    topPoints.sort((a, b) => a.x.compareTo(b.x));
    final topLeft = topPoints[0];
    final topRight = topPoints[1];

    bottomPoints.sort((a, b) => a.x.compareTo(b.x));
    final bottomLeft = bottomPoints[0];
    final bottomRight = bottomPoints[1];

    return [
      Offset(topLeft.x.toDouble(), topLeft.y.toDouble()), 
      Offset(topRight.x.toDouble(), topRight.y.toDouble()), 
      Offset(bottomRight.x.toDouble(), bottomRight.y.toDouble()), 
      Offset(bottomLeft.x.toDouble(), bottomLeft.y.toDouble()), 
    ];
  }
}
