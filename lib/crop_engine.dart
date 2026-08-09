import 'dart:math';
import 'dart:typed_data';

import 'package:google_mlkit_document_scanner/google_mlkit_document_scanner.dart';
import 'package:image/image.dart' as img;

/// crop_engine.dart
/// v12.0
///
/// محرك القص الاحترافي:
/// 1. كشف حواف المستند.
/// 2. تحديد الزوايا.
/// 3. تصحيح المنظور Perspective Warp.
/// 4. قص مستطيل يدوي.
/// 5. دعم Google ML Kit Document Scanner.
/// 6. أدوات ترميز وفك ترميز الصور.
///
/// ملاحظة:
/// هذا الملف لا يحتوي على واجهة المستخدم.
/// هو محرك معالجة الصور فقط.


// ═══════════════════════════════════════════════════════════════════════════
// Crop Result
// ═══════════════════════════════════════════════════════════════════════════

class CropResult {
  final img.Image image;
  final bool changed;

  const CropResult({
    required this.image,
    required this.changed,
  });
}


// ═══════════════════════════════════════════════════════════════════════════
// Enhance Mode
// ═══════════════════════════════════════════════════════════════════════════

enum EnhanceMode {
  none,
  soft,
  bw,
}


// ═══════════════════════════════════════════════════════════════════════════
// Perspective Warp
// تصحيح المنظور
// ═══════════════════════════════════════════════════════════════════════════

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

    // عرض الضلع العلوي
    final w1 = _distance(
      pts[0],
      pts[1],
      pts[2],
      pts[3],
    );

    // عرض الضلع السفلي
    final w2 = _distance(
      pts[6],
      pts[7],
      pts[4],
      pts[5],
    );

    // ارتفاع الجهة اليسرى
    final h1 = _distance(
      pts[0],
      pts[1],
      pts[6],
      pts[7],
    );

    // ارتفاع الجهة اليمنى
    final h2 = _distance(
      pts[2],
      pts[3],
      pts[4],
      pts[5],
    );

    final maxW = max(
      10,
      max(w1, w2).round(),
    );

    final maxH = max(
      10,
      max(h1, h2).round(),
    );

    if (maxW < 10 || maxH < 10) {
      return src;
    }

    final result = img.Image(
      width: maxW,
      height: maxH,
      numChannels: 4,
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

    final invM = _invert3x3(matrix);

    if (invM == null) {
      return src;
    }

    for (int y = 0; y < maxH; y++) {
      for (int x = 0; x < maxW; x++) {
        final w =
            invM[0][0] * x +
            invM[0][1] * y +
            invM[0][2];

        final v =
            invM[1][0] * x +
            invM[1][1] * y +
            invM[1][2];

        final q =
            invM[2][0] * x +
            invM[2][1] * y +
            invM[2][2];

        if (q.abs() < 0.000001) {
          continue;
        }

        final fx = w / q;
        final fy = v / q;

        final sx = fx.round();
        final sy = fy.round();

        if (sx >= 0 &&
            sx < src.width &&
            sy >= 0 &&
            sy < src.height) {
          final p = src.getPixel(
            sx,
            sy,
          );

          result.setPixelRgba(
            x,
            y,
            p.r.toInt(),
            p.g.toInt(),
            p.b.toInt(),
            p.a.toInt(),
          );
        }
      }
    }

    return result;
  }

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
  /// TL = أعلى يسار
  /// TR = أعلى يمين
  /// BR = أسفل يمين
  /// BL = أسفل يسار
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

    // مجموع x+y:
    // الأصغر = TL
    // الأكبر = BR
    List<double> topLeft = points.first;
    List<double> bottomRight = points.first;

    // الفرق x-y:
    // الأكبر = TR
    // الأصغر = BL
    List<double> topRight = points.first;
    List<double> bottomLeft = points.first;

    double minSum = double.infinity;
    double maxSum = -double.infinity;

    double minDiff = double.infinity;
    double maxDiff = -double.infinity;

    for (final p in points) {
      final x = p[0];
      final y = p[1];

      final sum = x + y;
      final diff = x - y;

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

  // ═════════════════════════════════════════════════════════════════════════
  // Perspective Matrix
  // ═════════════════════════════════════════════════════════════════════════

  static List<List<double>>? _getPerspectiveTransform(
    List<double> src,
    List<double> dst,
  ) {
    if (src.length != 8 ||
        dst.length != 8) {
      return null;
    }

    final A = List.generate(
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

      A[r1][0] = sx;
      A[r1][1] = sy;
      A[r1][2] = 1.0;

      A[r1][6] = -dx * sx;
      A[r1][7] = -dx * sy;

      b[r1] = dx;

      A[r2][3] = sx;
      A[r2][4] = sy;
      A[r2][5] = 1.0;

      A[r2][6] = -dy * sx;
      A[r2][7] = -dy * sy;

      b[r2] = dy;
    }

    final h = _solveLinear(
      A,
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

  // ═════════════════════════════════════════════════════════════════════════
  // Gaussian Elimination
  // ═════════════════════════════════════════════════════════════════════════

  static List<double>? _solveLinear(
    List<List<double>> A,
    List<double> b,
  ) {
    final n = A.length;

    if (n == 0 ||
        b.length != n) {
      return null;
    }

    final aug = List.generate(
      n,
      (i) => <double>[
        ...A[i],
        b[i],
      ],
    );

    // Forward elimination
    for (int col = 0; col < n; col++) {
      int pivotRow = col;

      for (int row = col + 1;
          row < n;
          row++) {
        if (aug[row][col].abs() >
            aug[pivotRow][col].abs()) {
          pivotRow = row;
        }
      }

      if (aug[pivotRow][col].abs() <
          1e-12) {
        return null;
      }

      if (pivotRow != col) {
        final temp = aug[col];
        aug[col] = aug[pivotRow];
        aug[pivotRow] = temp;
      }

      for (int row = col + 1;
          row < n;
          row++) {
        final factor =
            aug[row][col] /
            aug[col][col];

        if (factor.abs() < 1e-15) {
          continue;
        }

        for (int j = col;
            j <= n;
            j++) {
          aug[row][j] -=
              factor * aug[col][j];
        }
      }
    }

    // Back substitution
    final result =
        List<double>.filled(
      n,
      0.0,
    );

    for (int i = n - 1;
        i >= 0;
        i--) {
      double value = aug[i][n];

      for (int j = i + 1;
          j < n;
          j++) {
        value -=
            aug[i][j] * result[j];
      }

      if (aug[i][i].abs() <
          1e-12) {
        return null;
      }

      result[i] =
          value / aug[i][i];
    }

    return result;
  }

  // ═════════════════════════════════════════════════════════════════════════
  // Inverse 3x3
  // ═════════════════════════════════════════════════════════════════════════

  static List<List<double>>? _invert3x3(
    List<List<double>> M,
  ) {
    if (M.length != 3 ||
        M.any((row) => row.length != 3)) {
      return null;
    }

    final det =
        M[0][0] *
            (M[1][1] * M[2][2] -
                M[1][2] * M[2][1]) -
        M[0][1] *
            (M[1][0] * M[2][2] -
                M[1][2] * M[2][0]) +
        M[0][2] *
            (M[1][0] * M[2][1] -
                M[1][1] * M[2][0]);

    if (det.abs() <
        1e-12) {
      return null;
    }

    final invDet = 1.0 / det;

    return <List<double>>[
      [
        (M[1][1] * M[2][2] -
                M[1][2] * M[2][1]) *
            invDet,

        (M[0][2] * M[2][1] -
                M[0][1] * M[2][2]) *
            invDet,

        (M[0][1] * M[1][2] -
                M[0][2] * M[1][1]) *
            invDet,
      ],
      [
        (M[1][2] * M[2][0] -
                M[1][0] * M[2][2]) *
            invDet,

        (M[0][0] * M[2][2] -
                M[0][2] * M[2][0]) *
            invDet,

        (M[0][2] * M[1][0] -
                M[0][0] * M[1][2]) *
            invDet,
      ],
      [
        (M[1][0] * M[2][1] -
                M[1][1] * M[2][0]) *
            invDet,

        (M[0][1] * M[2][0] -
                M[0][0] * M[2][1]) *
            invDet,

        (M[0][0] * M[1][1] -
                M[0][1] * M[1][0]) *
            invDet,
      ],
    ];
  }
}


// ═══════════════════════════════════════════════════════════════════════════
// Smart Crop
// القص الذكي
// ═══════════════════════════════════════════════════════════════════════════

class SmartCrop {
  /// تنفيذ القص الذكي.
  ///
  /// إذا تم اكتشاف المستند:
  /// يرجع الصورة بعد تصحيح المنظور.
  ///
  /// إذا لم يتم اكتشافه:
  /// يرجع الصورة الأصلية بدون تغيير.
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
        src.width.toDouble() *
        src.height.toDouble();

    if (imageArea <= 0) {
      return CropResult(
        image: src,
        changed: false,
      );
    }

    final ratio =
        area / imageArea;

    // المستند صغير جدًا.
    if (ratio < 0.08) {
      return CropResult(
        image: src,
        changed: false,
      );
    }

    // إذا كان المستند يملأ تقريبًا كامل الصورة
    // فلا حاجة إلى القص.
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

  // ═════════════════════════════════════════════════════════════════════════
  // Detect Corners
  // ═════════════════════════════════════════════════════════════════════════

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

    // هامش بسيط جدًا لمنع ترك حافة غير مرغوبة.
    const pad = 0.006;

    for (int i = 0;
        i < pts.length;
        i += 2) {
      pts[i] = (
        pts[i] +
        (pts[i] < 0.5
            ? -pad
            : pad)
      ).clamp(
        0.0,
        1.0,
      ).toDouble();

      pts[i + 1] = (
        pts[i + 1] +
        (pts[i + 1] < 0.5
            ? -pad
            : pad)
      ).clamp(
        0.0,
        1.0,
      ).toDouble();
    }

    return pts;
  }

  // ═════════════════════════════════════════════════════════════════════════
  // Candidate Detection
  // ═════════════════════════════════════════════════════════════════════════

  static _Candidate? _detectCandidate(
    img.Image src,
  ) {
    // نعمل على نسخة صغيرة لتسريع الكشف.
    const target = 360;

    final longest =
        max(
          src.width,
          src.height,
        );

    final scale =
        longest / target;

    final safeScale =
        scale < 1.0
            ? 1.0
            : scale;

    final sw = max(
      80,
      (src.width / safeScale)
          .round(),
    );

    final sh = max(
      80,
      (src.height / safeScale)
          .round(),
    );

    var gray = img.grayscale(
      img.copyResize(
        src,
        width: sw,
        height: sh,
      ),
    );

    gray = img.gaussianBlur(
      gray,
      radius: 1,
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

    // ═══════════════════════════════════════════════════════════════════════
    // Connected Components
    // ═══════════════════════════════════════════════════════════════════════

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
          final idx =
              queue[head++];

          final py =
              idx ~/ sw;

          final px =
              idx - py * sw;

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
              (px + py)
                  .toDouble();

          final diff =
              (px - py)
                  .toDouble();

          // TL
          if (sum < minSum) {
            minSum = sum;
            tlX = px;
            tlY = py;
          }

          // BR
          if (sum > maxSum) {
            maxSum = sum;
            brX = px;
            brY = py;
          }

          // BL
          if (diff < minDiff) {
            minDiff = diff;
            blX = px;
            blY = py;
          }

          // TR
          if (diff > maxDiff) {
            maxDiff = diff;
            trX = px;
            trY = py;
          }

          // 8-neighbour flood fill
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

              final ni =
                  ny * sw + nx;

              if (!visited[ni] &&
                  connected[ni]) {
                visited[ni] = true;
                queue.add(ni);
              }
            }
          }
        }

        final bw =
            maxX - minX + 1;

        final bh =
            maxY - minY + 1;

        final bboxArea =
            bw.toDouble() *
            bh.toDouble();

        final imageArea =
            sw.toDouble() *
            sh.toDouble();

        if (imageArea <= 0) {
          continue;
        }

        // مكونات صغيرة جدًا = ضوضاء.
        final minimumPixels =
            max(
              30,
              imageArea ~/ 5000,
            );

        if (count <
            minimumPixels) {
          continue;
        }

        // المستند يجب أن يكون له حجم معقول.
        if (bw < sw * 0.12 ||
            bh < sh * 0.08) {
          continue;
        }

        if (bboxArea <
            imageArea * 0.07) {
          continue;
        }

        final qArea =
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

        if (qArea <
            imageArea * 0.06) {
          continue;
        }

        final coverage =
            (qArea / imageArea)
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

        // نعطي مساحة المستند وزنًا أعلى.
        final score =
            coverage * 0.84 +
            density * 0.16;

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

    // ═══════════════════════════════════════════════════════════════════════
    // Fallback
    // ═══════════════════════════════════════════════════════════════════════

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

      final rw =
          rect[2] - rect[0];

      final rh =
          rect[3] - rect[1];

      if (rw <= 0 ||
          rh <= 0) {
        return null;
      }

      final areaRatio =
          (rw.toDouble() *
                  rh.toDouble()) /
              (sw.toDouble() *
                  sh.toDouble());

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

    // الأفضل أولًا.
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

  // ═════════════════════════════════════════════════════════════════════════
  // Edge Detection
  // ═════════════════════════════════════════════════════════════════════════

  static List<bool> _makeEdges(
    img.Image gray,
  ) {
    final w =
        gray.width;

    final h =
        gray.height;

    final out =
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
            (tr + 2 * mr + br) -
            (tl + 2 * ml + bl);

        final gy =
            (bl + 2 * bc + br) -
            (tl + 2 * tc + tr);

        final magnitude =
            sqrt(
          (gx * gx +
                  gy * gy)
              .toDouble(),
        );

        // Threshold مناسب للصور المصغرة.
        if (magnitude > 52) {
          out[y * w + x] =
              true;
        }
      }
    }

    return out;
  }

  // ═════════════════════════════════════════════════════════════════════════
  // Dilation
  // ═════════════════════════════════════════════════════════════════════════

  static List<bool> _dilate(
    List<bool> src,
    int w,
    int h,
    int radius,
  ) {
    if (radius <= 0) {
      return List<bool>.from(
        src,
      );
    }

    final out =
        List<bool>.filled(
      src.length,
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

            if (src[
                ny * w + nx]) {
              hit = true;
              break;
            }
          }
        }

        out[y * w + x] =
            hit;
      }
    }

    return out;
  }

  // ═════════════════════════════════════════════════════════════════════════
  // Connect Edges
  // ═════════════════════════════════════════════════════════════════════════

  static List<bool>
      _connectEdgesWithSize(
    List<bool> src,
    int w,
    int h,
  ) {
    var result =
        _dilate(
      src,
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

  // ═════════════════════════════════════════════════════════════════════════
  // Fallback Rectangle
  // ═════════════════════════════════════════════════════════════════════════

  static List<int>? _fallbackRect(
    List<bool> edges,
    int w,
    int h,
  ) {
    int? top;
    int? bottom;
    int? left;
    int? right;

    // TOP
    for (int y = 0;
        y < h;
        y++) {
      int count = 0;

      for (int x = 0;
          x < w;
          x++) {
        if (edges[y * w + x]) {
          count++;
        }
      }

      if (count >
          w * 0.10) {
        top = y;
        break;
      }
    }

    // BOTTOM
    for (int y = h - 1;
        y >= 0;
        y--) {
      int count = 0;

      for (int x = 0;
          x < w;
          x++) {
        if (edges[y * w + x]) {
          count++;
        }
      }

      if (count >
          w * 0.10) {
        bottom = y;
        break;
      }
    }

    // LEFT
    for (int x = 0;
        x < w;
        x++) {
      int count = 0;

      for (int y = 0;
          y < h;
          y++) {
        if (edges[y * w + x]) {
          count++;
        }
      }

      if (count >
          h * 0.10) {
        left = x;
        break;
      }
    }

    // RIGHT
    for (int x = w - 1;
        x >= 0;
        x--) {
      int count = 0;

      for (int y = 0;
          y < h;
          y++) {
        if (edges[y * w + x]) {
          count++;
        }
      }

      if (count >
          h * 0.10) {
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

    if (right <= left ||
        bottom <= top) {
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

  // ═════════════════════════════════════════════════════════════════════════
  // Quadrilateral Area
  // ═════════════════════════════════════════════════════════════════════════

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


// ═══════════════════════════════════════════════════════════════════════════
// Candidate
// ═══════════════════════════════════════════════════════════════════════════

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


// ═══════════════════════════════════════════════════════════════════════════
// Manual Crop
// القص اليدوي
// ═══════════════════════════════════════════════════════════════════════════

class ManualCrop {
  /// قص منظور رباعي.
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

  /// قص مستطيل من النقاط.
  ///
  /// القيم x/y هنا Normalized:
  /// 0.0 = بداية الصورة
  /// 1.0 = نهاية الصورة
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
    final ax = <double>[
      x1 * src.width,
      x2 * src.width,
      x3 * src.width,
      x4 * src.width,
    ];

    final ay = <double>[
      y1 * src.height,
      y2 * src.height,
      y3 * src.height,
      y4 * src.height,
    ];

    // مهم:
    // clamp() يرجع num في Dart.
    // لذلك نحول النتيجة صراحة إلى int.
    final l = ax
        .reduce(min)
        .round()
        .clamp(
          0,
          max(0, src.width - 1),
        )
        .toInt();

    final r = ax
        .reduce(max)
        .round()
        .clamp(
          1,
          src.width,
        )
        .toInt();

    final t = ay
        .reduce(min)
        .round()
        .clamp(
          0,
          max(0, src.height - 1),
        )
        .toInt();

    final b = ay
        .reduce(max)
        .round()
        .clamp(
          1,
          src.height,
        )
        .toInt();

    final cropWidth =
        max(
          10,
          r - l,
        );

    final cropHeight =
        max(
          10,
          b - t,
        );

    return img.copyCrop(
      src,
      x: l,
      y: t,
      width: cropWidth,
      height: cropHeight,
    );
  }
}


// ═══════════════════════════════════════════════════════════════════════════
// Google ML Kit Document Scanner
// ═══════════════════════════════════════════════════════════════════════════

class GoogleScanner {
  /// تشغيل Google ML Kit Document Scanner.
  ///
  /// النتيجة:
  /// List<String> تحتوي مسارات صور JPEG.
  ///
  /// يدعم:
  /// - القص التلقائي.
  /// - تصحيح المنظور.
  /// - تدوير المستند.
  /// - الفلاتر بحسب وضع ScannerMode.
  /// - الاستيراد من المعرض.
  static Future<List<String>?> scan() async {
    DocumentScanner? scanner;

    try {
      scanner = DocumentScanner(
        options:
            const DocumentScannerOptions(
          documentFormats: {
            DocumentFormat.jpeg,
          },

          // filter يسمح بميزات الفلاتر
          // مع وظائف المسح الأساسية.
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
          // تجاهل خطأ الإغلاق.
        }
      }
    }
  }
}


// ═══════════════════════════════════════════════════════════════════════════
// Image Utilities
// ═══════════════════════════════════════════════════════════════════════════

class ImageUtils {
  /// تحويل الصورة إلى JPEG.
  static List<int> encodeJpg(
    img.Image src, {
    int quality = 92,
  }) {
    final safeQuality =
        quality.clamp(
          1,
          100,
        ).toInt();

    return img.encodeJpg(
      src,
      quality: safeQuality,
    );
  }

  /// فك الصورة من bytes.
  static img.Image? decodeBytes(
    dynamic bytes,
  ) {
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

    return null;
  }

  /// تحويل الصورة إلى JPEG bytes.
  static Uint8List? encodeJpgBytes(
    img.Image src, {
    int quality = 92,
  }) {
    try {
      return Uint8List.fromList(
        encodeJpg(
          src,
          quality: quality,
        ),
      );
    } catch (_) {
      return null;
    }
  }

  /// التحقق من أن الصورة صالحة للمعالجة.
  static bool isValid(
    img.Image? image,
  ) {
    if (image == null) {
      return false;
    }

    return image.width >= 10 &&
        image.height >= 10;
  }
}
