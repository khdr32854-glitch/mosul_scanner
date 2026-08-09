import 'dart:math';
import 'dart:typed_data';

import 'package:image/image.dart' as img;
import 'package:google_mlkit_document_scanner/google_mlkit_document_scanner.dart';

/// ===============================================================
/// crop_engine.dart
/// Mosul Scanner
///
/// الوظائف:
/// 1. القص الذكي Smart Crop
/// 2. تصحيح المنظور Perspective Warp
/// 3. القص اليدوي
/// 4. Google ML Kit Document Scanner
/// 5. تحسين الصورة ImageEnhancer
/// 6. أدوات فك وترميز الصور
///
/// متوافق مع:
/// image: ^4.2.0
/// google_mlkit_document_scanner: ^0.5.0
/// ===============================================================

/// ===============================================================
/// CropResult
/// ===============================================================

class CropResult {
  final img.Image image;
  final bool changed;

  const CropResult({
    required this.image,
    required this.changed,
  });
}

/// ===============================================================
/// أوضاع تحسين الصورة
/// ===============================================================

enum EnhanceMode {
  none,
  soft,
  bw,
}

/// ===============================================================
/// Perspective Warp
///
/// يحول أربع نقاط من الصورة الأصلية إلى مستطيل مستقيم.
/// ===============================================================

class PerspectiveWarp {
  static img.Image warp(
    img.Image src,
    double x1,
    double y1,
    double x2,
    double y2,
    double x3,
    double y3,
    double x4,
    double y4,
  ) {
    final pts = _orderPoints(
      x1,
      y1,
      x2,
      y2,
      x3,
      y3,
      x4,
      y4,
    );

    final w1 = _distance(
      pts[0],
      pts[1],
      pts[2],
      pts[3],
    );

    final w2 = _distance(
      pts[6],
      pts[7],
      pts[4],
      pts[5],
    );

    final h1 = _distance(
      pts[0],
      pts[1],
      pts[6],
      pts[7],
    );

    final h2 = _distance(
      pts[2],
      pts[3],
      pts[4],
      pts[5],
    );

    final maxW = max(w1, w2).round();
    final maxH = max(h1, h2).round();

    if (maxW < 10 || maxH < 10) {
      return src;
    }

    final result = img.Image(
      width: maxW,
      height: maxH,
    );

    final srcPts = <double>[
      pts[0],
      pts[1],
      pts[2],
      pts[3],
      pts[4],
      pts[5],
      pts[6],
      pts[7],
    ];

    final dstPts = <double>[
      0.0,
      0.0,
      maxW - 1.0,
      0.0,
      maxW - 1.0,
      maxH - 1.0,
      0.0,
      maxH - 1.0,
    ];

    final matrix = _getPerspectiveTransform(
      srcPts,
      dstPts,
    );

    if (matrix == null) {
      return src;
    }

    final inverse = _invert3x3(matrix);

    if (inverse == null) {
      return src;
    }

    for (int y = 0; y < maxH; y++) {
      for (int x = 0; x < maxW; x++) {
        final w =
            inverse[0][0] * x +
            inverse[0][1] * y +
            inverse[0][2];

        final v =
            inverse[1][0] * x +
            inverse[1][1] * y +
            inverse[1][2];

        final q =
            inverse[2][0] * x +
            inverse[2][1] * y +
            inverse[2][2];

        if (q.abs() < 0.000001) {
          continue;
        }

        final sx = (w / q).round();
        final sy = (v / q).round();

        if (sx < 0 ||
            sx >= src.width ||
            sy < 0 ||
            sy >= src.height) {
          continue;
        }

        final p = src.getPixel(
          sx,
          sy,
        );

        result.setPixelRgba(
          x,
          y,
          p.r,
          p.g,
          p.b,
          p.a,
        );
      }
    }

    return result;
  }

  /// حساب المسافة بين نقطتين.
  static double _distance(
    double x1,
    double y1,
    double x2,
    double y2,
  ) {
    final dx = x2 - x1;
    final dy = y2 - y1;

    return sqrt(
      dx * dx + dy * dy,
    );
  }

  /// ترتيب النقاط:
  ///
  /// 0 = Top Left
  /// 1 = Top Right
  /// 2 = Bottom Right
  /// 3 = Bottom Left
  static List<double> _orderPoints(
    double x1,
    double y1,
    double x2,
    double y2,
    double x3,
    double y3,
    double x4,
    double y4,
  ) {
    final points = <List<double>>[
      [x1, y1],
      [x2, y2],
      [x3, y3],
      [x4, y4],
    ];

    List<double> topLeft = points.first;
    List<double> topRight = points.first;
    List<double> bottomRight = points.first;
    List<double> bottomLeft = points.first;

    double minSum = double.infinity;
    double maxSum = -double.infinity;
    double minDiff = double.infinity;
    double maxDiff = -double.infinity;

    for (final p in points) {
      final sum = p[0] + p[1];
      final diff = p[0] - p[1];

      if (sum < minSum) {
        minSum = sum;
        topLeft = p;
      }

      if (sum > maxSum) {
        maxSum = sum;
        bottomRight = p;
      }

      if (diff > maxDiff) {
        maxDiff = diff;
        topRight = p;
      }

      if (diff < minDiff) {
        minDiff = diff;
        bottomLeft = p;
      }
    }

    return <double>[
      topLeft[0],
      topLeft[1],
      topRight[0],
      topRight[1],
      bottomRight[0],
      bottomRight[1],
      bottomLeft[0],
      bottomLeft[1],
    ];
  }

  /// حساب مصفوفة Perspective 3x3.
  static List<List<double>>? _getPerspectiveTransform(
    List<double> src,
    List<double> dst,
  ) {
    if (src.length != 8 ||
        dst.length != 8) {
      return null;
    }

    final a = List.generate(
      8,
      (_) => List<double>.filled(
        8,
        0.0,
      ),
    );

    final b = List<double>.filled(
      8,
      0.0,
    );

    for (int i = 0; i < 4; i++) {
      final sx = src[i * 2];
      final sy = src[i * 2 + 1];

      final dx = dst[i * 2];
      final dy = dst[i * 2 + 1];

      final r1 = i * 2;
      final r2 = r1 + 1;

      a[r1][0] = sx;
      a[r1][1] = sy;
      a[r1][2] = 1.0;

      a[r1][6] = -dx * sx;
      a[r1][7] = -dx * sy;

      b[r1] = dx;

      a[r2][3] = sx;
      a[r2][4] = sy;
      a[r2][5] = 1.0;

      a[r2][6] = -dy * sx;
      a[r2][7] = -dy * sy;

      b[r2] = dy;
    }

    final h = _solveLinear(
      a,
      b,
    );

    if (h == null ||
        h.length != 8) {
      return null;
    }

    return <List<double>>[
      [
        h[0],
        h[1],
        h[2],
      ],
      [
        h[3],
        h[4],
        h[5],
      ],
      [
        h[6],
        h[7],
        1.0,
      ],
    ];
  }

  /// حل نظام المعادلات باستخدام Gaussian Elimination.
  static List<double>? _solveLinear(
    List<List<double>> matrix,
    List<double> values,
  ) {
    final n = matrix.length;

    if (n == 0 ||
        values.length != n) {
      return null;
    }

    final augmented = List.generate(
      n,
      (i) => <double>[
        ...matrix[i],
        values[i],
      ],
    );

    for (int col = 0; col < n; col++) {
      int pivotRow = col;

      for (int row = col + 1;
          row < n;
          row++) {
        if (augmented[row][col].abs() >
            augmented[pivotRow][col].abs()) {
          pivotRow = row;
        }
      }

      if (augmented[pivotRow][col].abs() <
          1e-12) {
        return null;
      }

      if (pivotRow != col) {
        final temp = augmented[col];
        augmented[col] = augmented[pivotRow];
        augmented[pivotRow] = temp;
      }

      for (int row = col + 1;
          row < n;
          row++) {
        final divisor =
            augmented[col][col];

        if (divisor.abs() < 1e-12) {
          return null;
        }

        final factor =
            augmented[row][col] / divisor;

        for (int j = col;
            j <= n;
            j++) {
          augmented[row][j] -=
              factor * augmented[col][j];
        }
      }
    }

    final result =
        List<double>.filled(
      n,
      0.0,
    );

    for (int i = n - 1;
        i >= 0;
        i--) {
      double value =
          augmented[i][n];

      for (int j = i + 1;
          j < n;
          j++) {
        value -=
            augmented[i][j] *
            result[j];
      }

      final divisor =
          augmented[i][i];

      if (divisor.abs() < 1e-12) {
        return null;
      }

      result[i] =
          value / divisor;
    }

    return result;
  }

  /// عكس مصفوفة 3x3.
  static List<List<double>>? _invert3x3(
    List<List<double>> m,
  ) {
    if (m.length != 3 ||
        m.any((row) => row.length != 3)) {
      return null;
    }

    final det =
        m[0][0] *
            (m[1][1] * m[2][2] -
                m[1][2] * m[2][1]) -
        m[0][1] *
            (m[1][0] * m[2][2] -
                m[1][2] * m[2][0]) +
        m[0][2] *
            (m[1][0] * m[2][1] -
                m[1][1] * m[2][0]);

    if (det.abs() < 1e-12) {
      return null;
    }

    final invDet = 1.0 / det;

    return <List<double>>[
      [
        (m[1][1] * m[2][2] -
                m[1][2] * m[2][1]) *
            invDet,
        (m[0][2] * m[2][1] -
                m[0][1] * m[2][2]) *
            invDet,
        (m[0][1] * m[1][2] -
                m[0][2] * m[1][1]) *
            invDet,
      ],
      [
        (m[1][2] * m[2][0] -
                m[1][0] * m[2][2]) *
            invDet,
        (m[0][0] * m[2][2] -
                m[0][2] * m[2][0]) *
            invDet,
        (m[0][2] * m[1][0] -
                m[0][0] * m[1][2]) *
            invDet,
      ],
      [
        (m[1][0] * m[2][1] -
                m[1][1] * m[2][0]) *
            invDet,
        (m[0][1] * m[2][0] -
                m[0][0] * m[2][1]) *
            invDet,
        (m[0][0] * m[1][1] -
                m[0][1] * m[1][0]) *
            invDet,
      ],
    ];
  }
}

/// ===============================================================
/// SmartCrop
///
/// كشف المستند اعتمادًا على الحواف والمكونات المتصلة.
/// ===============================================================

class SmartCrop {
  static CropResult detect(
    img.Image src,
  ) {
    if (src.width < 100 ||
        src.height < 100) {
      return CropResult(
        image: src,
        changed: false,
      );
    }

    final corners =
        detectCorners(src);

    if (corners == null ||
        corners.length != 8) {
      return CropResult(
        image: src,
        changed: false,
      );
    }

    final px = <double>[
      corners[0] * src.width,
      corners[1] * src.height,
      corners[2] * src.width,
      corners[3] * src.height,
      corners[4] * src.width,
      corners[5] * src.height,
      corners[6] * src.width,
      corners[7] * src.height,
    ];

    final area = _quadArea(
      px[0],
      px[1],
      px[2],
      px[3],
      px[4],
      px[5],
      px[6],
      px[7],
    );

    final imageArea =
        src.width *
        src.height.toDouble();

    if (imageArea <= 0) {
      return CropResult(
        image: src,
        changed: false,
      );
    }

    final ratio =
        area / imageArea;

    /// إذا كان الكشف صغيرًا جدًا، نرفضه.
    if (ratio < 0.08) {
      return CropResult(
        image: src,
        changed: false,
      );
    }

    /// إذا كان تقريبًا كامل الصورة،
    /// لا نعتبره قصًا حقيقيًا.
    if (ratio > 0.94) {
      return CropResult(
        image: src,
        changed: false,
      );
    }

    final warped =
        PerspectiveWarp.warp(
      src,
      px[0],
      px[1],
      px[2],
      px[3],
      px[4],
      px[5],
      px[6],
      px[7],
    );

    if (warped.width < 30 ||
        warped.height < 30) {
      return CropResult(
        image: src,
        changed: false,
      );
    }

    return CropResult(
      image: warped,
      changed: true,
    );
  }

  /// إرجاع الزوايا كنسب من 0 إلى 1.
  static List<double>? detectCorners(
    img.Image src,
  ) {
    if (src.width < 100 ||
        src.height < 100) {
      return null;
    }

    final data =
        _detectCandidate(src);

    if (data == null) {
      return null;
    }

    if (data.sw <= 0 ||
        data.sh <= 0) {
      return null;
    }

    final pts = <double>[
      data.tlX / data.sw,
      data.tlY / data.sh,
      data.trX / data.sw,
      data.trY / data.sh,
      data.brX / data.sw,
      data.brY / data.sh,
      data.blX / data.sw,
      data.blY / data.sh,
    ];

    /// هامش صغير جدًا خارج الحواف المكتشفة
    /// حتى لا تبقى حافة سوداء حول الورقة.
    const pad = 0.008;

    for (int i = 0;
        i < pts.length;
        i += 2) {
      pts[i] =
          (pts[i] +
                  (pts[i] < 0.5
                      ? -pad
                      : pad))
              .clamp(
                0.0,
                1.0,
              )
              .toDouble();

      pts[i + 1] =
          (pts[i + 1] +
                  (pts[i + 1] < 0.5
                      ? -pad
                      : pad))
              .clamp(
                0.0,
                1.0,
              )
              .toDouble();
    }

    return pts;
  }

  /// الكشف الأساسي.
  static _Candidate? _detectCandidate(
    img.Image src,
  ) {
    const target = 320;

    final largest =
        max(
      src.width,
      src.height,
    );

    final scale =
        largest / target;

    final safeScale =
        scale <= 0
            ? 1.0
            : scale;

    final sw = max(
      80,
      (src.width / safeScale).round(),
    );

    final sh = max(
      80,
      (src.height / safeScale).round(),
    );

    img.Image gray =
        img.grayscale(
      img.copyResize(
        src,
        width: sw,
        height: sh,
      ),
    );

    gray = img.gaussianBlur(
      gray,
      radius: 2,
    );

    final edges =
        _makeEdges(gray);

    final connected =
        _connectEdgesWithSize(
      edges,
      sw,
      sh,
    );

    final candidates =
        <_Candidate>[];

    final visited =
        List<bool>.filled(
      sw * sh,
      false,
    );

    final queue =
        <int>[];

    final imageArea =
        sw * sh.toDouble();

    for (int y = 1;
        y < sh - 1;
        y++) {
      for (int x = 1;
          x < sw - 1;
          x++) {
        final start =
            y * sw + x;

        if (visited[start] ||
            !connected[start]) {
          continue;
        }

        queue.clear();

        queue.add(start);
        visited[start] = true;

        int head = 0;
        int count = 0;

        int minX = x;
        int maxX = x;
        int minY = y;
        int maxY = y;

        double minSum =
            double.infinity;

        double maxSum =
            -double.infinity;

        double minDiff =
            double.infinity;

        double maxDiff =
            -double.infinity;

        int tlX = x;
        int tlY = y;

        int trX = x;
        int trY = y;

        int brX = x;
        int brY = y;

        int blX = x;
        int blY = y;

        while (head <
            queue.length) {
          final index =
              queue[head++];

          final py =
              index ~/ sw;

          final px =
              index - py * sw;

          count++;

          if (px < minX) {
            minX = px;
          }

          if (px > maxX) {
            maxX = px;
          }

          if (py < minY) {
            minY = py;
          }

          if (py > maxY) {
            maxY = py;
          }

          final sum =
              (px + py).toDouble();

          final diff =
              (px - py).toDouble();

          if (sum < minSum) {
            minSum = sum;
            tlX = px;
            tlY = py;
          }

          if (sum > maxSum) {
            maxSum = sum;
            brX = px;
            brY = py;
          }

          if (diff > maxDiff) {
            maxDiff = diff;
            trX = px;
            trY = py;
          }

          if (diff < minDiff) {
            minDiff = diff;
            blX = px;
            blY = py;
          }

          for (int dy = -1;
              dy <= 1;
              dy++) {
            for (int dx = -1;
                dx <= 1;
                dx++) {
              if (dx == 0 &&
                  dy == 0) {
                continue;
              }

              final nx =
                  px + dx;

              final ny =
                  py + dy;

              if (nx < 1 ||
                  nx >= sw - 1 ||
                  ny < 1 ||
                  ny >= sh - 1) {
                continue;
              }

              final next =
                  ny * sw + nx;

              if (!visited[next] &&
                  connected[next]) {
                visited[next] = true;
                queue.add(next);
              }
            }
          }
        }

        final bw =
            maxX - minX + 1;

        final bh =
            maxY - minY + 1;

        final bboxArea =
            bw * bh.toDouble();

        if (count <
            max(
              30,
              imageArea ~/ 5000,
            )) {
          continue;
        }

        if (bw < sw * 0.12 ||
            bh < sh * 0.08) {
          continue;
        }

        if (bboxArea <
            imageArea * 0.07) {
          continue;
        }

        final quadArea =
            _quadArea(
          tlX.toDouble(),
          tlY.toDouble(),
          trX.toDouble(),
          trY.toDouble(),
          brX.toDouble(),
          brY.toDouble(),
          blX.toDouble(),
          blY.toDouble(),
        );

        if (quadArea <
            imageArea * 0.06) {
          continue;
        }

        final coverage =
            (quadArea / imageArea)
                .clamp(
                  0.0,
                  1.0,
                )
                .toDouble();

        final density =
            (count / bboxArea)
                .clamp(
                  0.0,
                  1.0,
                )
                .toDouble();

        /// نعطي المساحة أكبر وزنًا.
        /// هذا يساعد في عدم اختيار بطاقة صغيرة
        /// داخل ورقة أكبر.
        final score =
            coverage * 0.82 +
            density * 0.18;

        candidates.add(
          _Candidate(
            sw: sw,
            sh: sh,
            tlX: tlX.toDouble(),
            tlY: tlY.toDouble(),
            trX: trX.toDouble(),
            trY: trY.toDouble(),
            brX: brX.toDouble(),
            brY: brY.toDouble(),
            blX: blX.toDouble(),
            blY: blY.toDouble(),
            score: score,
            areaRatio: coverage,
          ),
        );
      }
    }

    /// إذا لم نجد مكونًا مناسبًا،
    /// نحاول إيجاد مستطيل بسيط من الحواف.
    if (candidates.isEmpty) {
      final rect =
          _fallbackRect(
        edges,
        sw,
        sh,
      );

      if (rect == null) {
        return null;
      }

      final rectWidth =
          rect[2] - rect[0];

      final rectHeight =
          rect[3] - rect[1];

      if (rectWidth <= 0 ||
          rectHeight <= 0) {
        return null;
      }

      final areaRatio =
          (rectWidth * rectHeight) /
          imageArea;

      if (areaRatio < 0.08 ||
          areaRatio > 0.94) {
        return null;
      }

      return _Candidate(
        sw: sw,
        sh: sh,
        tlX: rect[0].toDouble(),
        tlY: rect[1].toDouble(),
        trX: rect[2].toDouble(),
        trY: rect[1].toDouble(),
        brX: rect[2].toDouble(),
        brY: rect[3].toDouble(),
        blX: rect[0].toDouble(),
        blY: rect[3].toDouble(),
        score: areaRatio,
        areaRatio: areaRatio,
      );
    }

    candidates.sort(
      (a, b) =>
          b.score.compareTo(
        a.score,
      ),
    );

    final best =
        candidates.first;

    final scaleX =
        src.width / sw;

    final scaleY =
        src.height / sh;

    return _Candidate(
      sw: src.width,
      sh: src.height,
      tlX: best.tlX * scaleX,
      tlY: best.tlY * scaleY,
      trX: best.trX * scaleX,
      trY: best.trY * scaleY,
      brX: best.brX * scaleX,
      brY: best.brY * scaleY,
      blX: best.blX * scaleX,
      blY: best.blY * scaleY,
      score: best.score,
      areaRatio: best.areaRatio,
    );
  }

  /// Sobel edge detector.
  static List<bool> _makeEdges(
    img.Image gray,
  ) {
    final w =
        gray.width;

    final h =
        gray.height;

    final output =
        List<bool>.filled(
      w * h,
      false,
    );

    for (int y = 1;
        y < h - 1;
        y++) {
      for (int x = 1;
          x < w - 1;
          x++) {
        final tl =
            gray
                .getPixel(
                  x - 1,
                  y - 1,
                )
                .r
                .toInt();

        final tc =
            gray
                .getPixel(
                  x,
                  y - 1,
                )
                .r
                .toInt();

        final tr =
            gray
                .getPixel(
                  x + 1,
                  y - 1,
                )
                .r
                .toInt();

        final ml =
            gray
                .getPixel(
                  x - 1,
                  y,
                )
                .r
                .toInt();

        final mr =
            gray
                .getPixel(
                  x + 1,
                  y,
                )
                .r
                .toInt();

        final bl =
            gray
                .getPixel(
                  x - 1,
                  y + 1,
                )
                .r
                .toInt();

        final bc =
            gray
                .getPixel(
                  x,
                  y + 1,
                )
                .r
                .toInt();

        final br =
            gray
                .getPixel(
                  x + 1,
                  y + 1,
                )
                .r
                .toInt();

        final gx =
            (tr +
                2 * mr +
                br) -
            (tl +
                2 * ml +
                bl);

        final gy =
            (bl +
                2 * bc +
                br) -
            (tl +
                2 * tc +
                tr);

        final magnitude =
            sqrt(
          (gx * gx +
                  gy * gy)
              .toDouble(),
        );

        /// Threshold متوسط لتقليل الضوضاء.
        if (magnitude > 52) {
          output[
              y * w + x] = true;
        }
      }
    }

    return output;
  }

  /// Dilate للحواف.
  static List<bool> _dilate(
    List<bool> source,
    int w,
    int h,
    int radius,
  ) {
    final output =
        List<bool>.filled(
      source.length,
      false,
    );

    for (int y = 0;
        y < h;
        y++) {
      for (int x = 0;
          x < w;
          x++) {
        bool hit = false;

        for (int dy = -radius;
            dy <= radius &&
                !hit;
            dy++) {
          final ny =
              y + dy;

          if (ny < 0 ||
              ny >= h) {
            continue;
          }

          for (int dx = -radius;
              dx <= radius;
              dx++) {
            final nx =
                x + dx;

            if (nx < 0 ||
                nx >= w) {
              continue;
            }

            if (source[
                ny * w + nx]) {
              hit = true;
              break;
            }
          }
        }

        output[
            y * w + x] = hit;
      }
    }

    return output;
  }

  /// توصيل الحواف القريبة من بعضها.
  static List<bool>
      _connectEdgesWithSize(
    List<bool> source,
    int w,
    int h,
  ) {
    var result =
        _dilate(
      source,
      w,
      h,
      2,
    );

    result =
        _dilate(
      result,
      w,
      h,
      1,
    );

    return result;
  }

  /// كاشف مستطيل احتياطي.
  static List<int>? _fallbackRect(
    List<bool> edges,
    int w,
    int h,
  ) {
    int? top;
    int? bottom;
    int? left;
    int? right;

    /// أعلى
    for (int y = 0;
        y < h;
        y++) {
      int count = 0;

      for (int x = 0;
          x < w;
          x++) {
        if (edges[
            y * w + x]) {
          count++;
        }
      }

      if (count > w * 0.10) {
        top = y;
        break;
      }
    }

    /// أسفل
    for (int y = h - 1;
        y >= 0;
        y--) {
      int count = 0;

      for (int x = 0;
          x < w;
          x++) {
        if (edges[
            y * w + x]) {
          count++;
        }
      }

      if (count > w * 0.10) {
        bottom = y;
        break;
      }
    }

    /// يسار
    for (int x = 0;
        x < w;
        x++) {
      int count = 0;

      for (int y = 0;
          y < h;
          y++) {
        if (edges[
            y * w + x]) {
          count++;
        }
      }

      if (count > h * 0.10) {
        left = x;
        break;
      }
    }

    /// يمين
    for (int x = w - 1;
        x >= 0;
        x--) {
      int count = 0;

      for (int y = 0;
          y < h;
          y++) {
        if (edges[
            y * w + x]) {
          count++;
        }
      }

      if (count > h * 0.10) {
        right = x;
        break;
      }
    }

    if (top == null ||
        bottom == null ||
        left == null ||
        right == null) {
      return null;
    }

    if (right - left <
            w * 0.12 ||
        bottom - top <
            h * 0.08) {
      return null;
    }

    return <int>[
      left,
      top,
      right,
      bottom,
    ];
  }

  /// مساحة الشكل الرباعي.
  static double _quadArea(
    double x1,
    double y1,
    double x2,
    double y2,
    double x3,
    double y3,
    double x4,
    double y4,
  ) {
    final value =
        (x1 * y2 +
                x2 * y3 +
                x3 * y4 +
                x4 * y1) -
            (y1 * x2 +
                y2 * x3 +
                y3 * x4 +
                y4 * x1);

    return value.abs() / 2.0;
  }
}

/// ===============================================================
/// بيانات مرشح
/// ===============================================================

class _Candidate {
  final int sw;
  final int sh;

  final double tlX;
  final double tlY;

  final double trX;
  final double trY;

  final double brX;
  final double brY;

  final double blX;
  final double blY;

  final double score;
  final double areaRatio;

  const _Candidate({
    required this.sw,
    required this.sh,
    required this.tlX,
    required this.tlY,
    required this.trX,
    required this.trY,
    required this.brX,
    required this.brY,
    required this.blX,
    required this.blY,
    required this.score,
    required this.areaRatio,
  });
}

/// ===============================================================
/// القص اليدوي
/// ===============================================================

class ManualCrop {
  /// قص منظور بأربع نقاط.
  static img.Image cropPerspective(
    img.Image src,
    double x1,
    double y1,
    double x2,
    double y2,
    double x3,
    double y3,
    double x4,
    double y4,
  ) {
    return PerspectiveWarp.warp(
      src,
      x1,
      y1,
      x2,
      y2,
      x3,
      y3,
      x4,
      y4,
    );
  }

  /// قص مستطيل عادي.
  ///
  /// الإحداثيات نسب من 0 إلى 1.
  static img.Image cropRect(
    img.Image src,
    double x1,
    double y1,
    double x2,
    double y2,
    double x3,
    double y3,
    double x4,
    double y4,
  ) {
    final xs = <double>[
      x1 * src.width,
      x2 * src.width,
      x3 * src.width,
      x4 * src.width,
    ];

    final ys = <double>[
      y1 * src.height,
      y2 * src.height,
      y3 * src.height,
      y4 * src.height,
    ];

    final left =
        xs.reduce(min)
            .round()
            .clamp(
              0,
              max(0, src.width - 1),
            )
            .toInt();

    final right =
        xs.reduce(max)
            .round()
            .clamp(
              1,
              src.width,
            )
            .toInt();

    final top =
        ys.reduce(min)
            .round()
            .clamp(
              0,
              max(0, src.height - 1),
            )
            .toInt();

    final bottom =
        ys.reduce(max)
            .round()
            .clamp(
              1,
              src.height,
            )
            .toInt();

    final width =
        max(
      10,
      right - left,
    );

    final height =
        max(
      10,
      bottom - top,
    );

    return img.copyCrop(
      src,
      x: left,
      y: top,
      width: width,
      height: height,
    );
  }
}

/// ===============================================================
/// Google ML Kit Document Scanner
///
/// الإصدار:
/// google_mlkit_document_scanner: ^0.5.0
///
/// هذا المكوّن يعمل عبر واجهة Google ML Kit
/// على Android.
/// ===============================================================

class GoogleScanner {
  static Future<List<String>?> scan() async {
    DocumentScanner? scanner;

    try {
      scanner = DocumentScanner(
        options: DocumentScannerOptions(
          documentFormats: {
            DocumentFormat.jpeg,
          },
          mode: ScannerMode.filter,
          pageLimit: 10,
          isGalleryImport: true,
        ),
      );

      final result =
          await scanner.scanDocument();

      final images =
          result.images;

      if (images == null ||
          images.isEmpty) {
        return null;
      }

      return List<String>.from(
        images,
      );
    } catch (_) {
      return null;
    } finally {
      if (scanner != null) {
        try {
          await scanner.close();
        } catch (_) {
          // تجاهل خطأ إغلاق الماسح.
        }
      }
    }
  }
}

/// ===============================================================
/// ImageEnhancer
///
/// هذا الكلاس كان مفقودًا في النسخة السابقة،
/// بينما main.dart يستدعي:
///
/// ImageEnhancer.apply(res, _filter)
///
/// لذلك تمت إضافته هنا.
/// ===============================================================

class ImageEnhancer {
  /// تطبيق الفلتر المطلوب.
  static img.Image apply(
    img.Image source,
    EnhanceMode mode,
  ) {
    switch (mode) {
      case EnhanceMode.none:
        return source;

      case EnhanceMode.soft:
        return soft(source);

      case EnhanceMode.bw:
        return blackAndWhite(source);
    }
  }

  /// تحسين خفيف:
  /// - زيادة بسيطة للتباين
  /// - زيادة بسيطة للسطوع
  /// - الحفاظ على الألوان
  static img.Image soft(
    img.Image source,
  ) {
    final result =
        img.Image(
      width: source.width,
      height: source.height,
      numChannels: 4,
    );

    for (int y = 0;
        y < source.height;
        y++) {
      for (int x = 0;
          x < source.width;
          x++) {
        final p =
            source.getPixel(
          x,
          y,
        );

        final r =
            _adjustChannel(
          p.r.toDouble(),
          brightness: 5.0,
          contrast: 1.08,
        );

        final g =
            _adjustChannel(
          p.g.toDouble(),
          brightness: 5.0,
          contrast: 1.08,
        );

        final b =
            _adjustChannel(
          p.b.toDouble(),
          brightness: 5.0,
          contrast: 1.08,
        );

        result.setPixelRgba(
          x,
          y,
          r,
          g,
          b,
          p.a,
        );
      }
    }

    return result;
  }

  /// تحويل إلى أبيض وأسود عالي الوضوح.
  ///
  /// نستخدم luminance بدل متوسط RGB
  /// للحصول على نتيجة أفضل للنصوص.
  static img.Image blackAndWhite(
    img.Image source,
  ) {
    final result =
        img.Image(
      width: source.width,
      height: source.height,
      numChannels: 4,
    );

    for (int y = 0;
        y < source.height;
        y++) {
      for (int x = 0;
          x < source.width;
          x++) {
        final p =
            source.getPixel(
          x,
          y,
        );

        final luminance =
            0.299 * p.r +
            0.587 * p.g +
            0.114 * p.b;

        /// Contrast أعلى للنصوص.
        final enhanced =
            _adjustChannel(
          luminance.toDouble(),
          brightness: 0.0,
          contrast: 1.18,
        );

        result.setPixelRgba(
          x,
          y,
          enhanced,
          enhanced,
          enhanced,
          p.a,
        );
      }
    }

    return result;
  }

  static int _adjustChannel(
    double value, {
    required double brightness,
    required double contrast,
  }) {
    final adjusted =
        ((value - 128.0) *
                contrast) +
            128.0 +
            brightness;

    return adjusted
        .clamp(
          0.0,
          255.0,
        )
        .round();
  }
}

/// ===============================================================
/// ImageUtils
/// ===============================================================

class ImageUtils {
  /// تحويل الصورة إلى JPEG.
  static List<int> encodeJpg(
    img.Image source, {
    int quality = 92,
  }) {
    final safeQuality =
        quality
            .clamp(
              1,
              100,
            )
            .toInt();

    return img.encodeJpg(
      source,
      quality: safeQuality,
    );
  }

  /// تحويل الصورة إلى JPEG وإرجاع Uint8List.
  static Uint8List? encodeJpgBytes(
    img.Image source, {
    int quality = 92,
  }) {
    try {
      return Uint8List.fromList(
        encodeJpg(
          source,
          quality: quality,
        ),
      );
    } catch (_) {
      return null;
    }
  }

  /// فك Bytes إلى Image.
  static img.Image? decodeBytes(
    dynamic bytes,
  ) {
    try {
      if (bytes is Uint8List) {
        return img.decodeImage(
          bytes,
        );
      }

      if (bytes is List<int>) {
        return img.decodeImage(
          Uint8List.fromList(
            bytes,
          ),
        );
      }
    } catch (_) {
      return null;
    }

    return null;
  }

  /// التأكد من أن الصورة صالحة.
  static bool isValid(
    img.Image? image,
  ) {
    if (image == null) {
      return false;
    }

    return image.width >= 10 &&
        image.height >= 10;
  }

  /// نسخ الصورة.
  static img.Image copy(
    img.Image source,
  ) {
    return img.Image.from(
      source,
    );
  }

  /// تغيير حجم الصورة مع الحفاظ على النسبة.
  static img.Image resizeToFit(
    img.Image source, {
    required int maxWidth,
    required int maxHeight,
  }) {
    if (source.width <= maxWidth &&
        source.height <= maxHeight) {
      return source;
    }

    final widthRatio =
        maxWidth /
        source.width;

    final heightRatio =
        maxHeight /
        source.height;

    final ratio =
        min(
      widthRatio,
      heightRatio,
    );

    final newWidth =
        max(
      1,
      (source.width * ratio)
          .round(),
    );

    final newHeight =
        max(
      1,
      (source.height * ratio)
          .round(),
    );

    return img.copyResize(
      source,
      width: newWidth,
      height: newHeight,
    );
  }
}
