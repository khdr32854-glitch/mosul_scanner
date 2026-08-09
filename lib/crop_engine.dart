import 'dart:math';
import 'dart:typed_data';

import 'package:google_mlkit_document_scanner/google_mlkit_document_scanner.dart';
import 'package:image/image.dart' as img;

/// ============================================================
/// crop_engine.dart
/// الإصدار: 12.0
///
/// الوظائف:
/// 1. القص الذكي التلقائي.
/// 2. تصحيح منظور المستند.
/// 3. القص المستطيلي اليدوي.
/// 4. القص الرباعي/المائل اليدوي.
/// 5. Google ML Kit Document Scanner.
/// 6. ترميز وفك ترميز الصور.
///
/// ملاحظات:
/// - لا يستخدم OpenCV.
/// - المعالجة الأساسية تتم داخل Dart.
/// - لا يعتمد على dart:io، لذلك الملف أنظف وأسهل للدمج.
/// - مناسب لحزمة image 4.x.
/// ============================================================

/// ============================================================
/// CropResult
/// ============================================================

class CropResult {
  final img.Image image;
  final bool changed;

  const CropResult({
    required this.image,
    required this.changed,
  });
}

/// ============================================================
/// EnhanceMode
/// ============================================================

enum EnhanceMode {
  none,
  soft,
  bw,
}

/// ============================================================
/// Point2D
/// ============================================================

class Point2D {
  final double x;
  final double y;

  const Point2D(
    this.x,
    this.y,
  );

  Point2D operator +(Point2D other) {
    return Point2D(
      x + other.x,
      y + other.y,
    );
  }

  Point2D operator -(Point2D other) {
    return Point2D(
      x - other.x,
      y - other.y,
    );
  }

  Point2D operator *(double value) {
    return Point2D(
      x * value,
      y * value,
    );
  }

  double distanceTo(Point2D other) {
    final dx = x - other.x;
    final dy = y - other.y;

    return sqrt(
      dx * dx + dy * dy,
    );
  }
}

/// ============================================================
/// Perspective Warp
///
/// تحويل رباعي إلى مستطيل مع تصحيح المنظور.
/// ============================================================

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
    final points = _orderPoints(
      Point2D(x1, y1),
      Point2D(x2, y2),
      Point2D(x3, y3),
      Point2D(x4, y4),
    );

    final tl = points[0];
    final tr = points[1];
    final br = points[2];
    final bl = points[3];

    final topWidth = tl.distanceTo(tr);
    final bottomWidth = bl.distanceTo(br);

    final leftHeight = tl.distanceTo(bl);
    final rightHeight = tr.distanceTo(br);

    final maxWidth = max(
      1,
      max(
        topWidth,
        bottomWidth,
      ).round(),
    );

    final maxHeight = max(
      1,
      max(
        leftHeight,
        rightHeight,
      ).round(),
    );

    if (maxWidth < 10 ||
        maxHeight < 10) {
      return src;
    }

    final sourcePoints = <double>[
      tl.x,
      tl.y,
      tr.x,
      tr.y,
      br.x,
      br.y,
      bl.x,
      bl.y,
    ];

    final destinationPoints = <double>[
      0.0,
      0.0,
      maxWidth - 1.0,
      0.0,
      maxWidth - 1.0,
      maxHeight - 1.0,
      0.0,
      maxHeight - 1.0,
    ];

    final matrix = _getPerspectiveTransform(
      sourcePoints,
      destinationPoints,
    );

    if (matrix == null) {
      return src;
    }

    final inverse = _invert3x3(matrix);

    if (inverse == null) {
      return src;
    }

    final result = img.Image(
      width: maxWidth,
      height: maxHeight,
      numChannels: 4,
    );

    // نملأ الخلفية باللون الأبيض.
    for (final pixel in result) {
      pixel
        ..r = 255
        ..g = 255
        ..b = 255
        ..a = 255;
    }

    for (int y = 0; y < maxHeight; y++) {
      for (int x = 0; x < maxWidth; x++) {
        final source = _mapDestinationToSource(
          inverse,
          x.toDouble(),
          y.toDouble(),
        );

        if (source == null) {
          continue;
        }

        final sx = source.x;
        final sy = source.y;

        if (sx < 0 ||
            sy < 0 ||
            sx >= src.width - 1 ||
            sy >= src.height - 1) {
          continue;
        }

        final pixel = _bilinearSample(
          src,
          sx,
          sy,
        );

        result.setPixelRgba(
          x,
          y,
          pixel.r.toInt(),
          pixel.g.toInt(),
          pixel.b.toInt(),
          pixel.a.toInt(),
        );
      }
    }

    return result;
  }

  /// ترتيب النقاط:
  ///
  /// 0 = أعلى يسار
  /// 1 = أعلى يمين
  /// 2 = أسفل يمين
  /// 3 = أسفل يسار
  static List<Point2D> _orderPoints(
    Point2D p1,
    Point2D p2,
    Point2D p3,
    Point2D p4,
  ) {
    final points = <Point2D>[
      p1,
      p2,
      p3,
      p4,
    ];

    final centerX =
        points.map((p) => p.x).reduce((a, b) => a + b) /
            points.length;

    final centerY =
        points.map((p) => p.y).reduce((a, b) => a + b) /
            points.length;

    points.sort(
      (a, b) {
        final angleA =
            atan2(a.y - centerY, a.x - centerX);

        final angleB =
            atan2(b.y - centerY, b.x - centerX);

        return angleA.compareTo(angleB);
      },
    );

    // بعد الترتيب حول المركز، نبحث عن النقطة الأقرب
    // إلى أعلى اليسار لتكون البداية.
    int topLeftIndex = 0;
    double bestScore = double.infinity;

    for (int i = 0; i < points.length; i++) {
      final score =
          points[i].x + points[i].y;

      if (score < bestScore) {
        bestScore = score;
        topLeftIndex = i;
      }
    }

    final ordered = <Point2D>[];

    for (int i = 0; i < 4; i++) {
      ordered.add(
        points[
          (topLeftIndex + i) % 4
        ],
      );
    }

    // التأكد من أن الاتجاه هو:
    // TL -> TR -> BR -> BL
    final cross = _cross(
      ordered[1] - ordered[0],
      ordered[2] - ordered[1],
    );

    if (cross < 0) {
      final first = ordered[0];

      ordered
        ..clear()
        ..add(first)
        ..add(points[(topLeftIndex + 3) % 4])
        ..add(points[(topLeftIndex + 2) % 4])
        ..add(points[(topLeftIndex + 1) % 4]);
    }

    return ordered;
  }

  static double _cross(
    Point2D a,
    Point2D b,
  ) {
    return a.x * b.y -
        a.y * b.x;
  }

  /// ==========================================================
  /// Bilinear interpolation
  /// ==========================================================

  static img.Pixel _bilinearSample(
    img.Image image,
    double x,
    double y,
  ) {
    final x0 = x.floor();
    final y0 = y.floor();

    final x1 = min(
      x0 + 1,
      image.width - 1,
    );

    final y1 = min(
      y0 + 1,
      image.height - 1,
    );

    final fx = x - x0;
    final fy = y - y0;

    final p00 = image.getPixel(
      x0,
      y0,
    );

    final p10 = image.getPixel(
      x1,
      y0,
    );

    final p01 = image.getPixel(
      x0,
      y1,
    );

    final p11 = image.getPixel(
      x1,
      y1,
    );

    final r =
        _interpolate4(
          p00.r.toDouble(),
          p10.r.toDouble(),
          p01.r.toDouble(),
          p11.r.toDouble(),
          fx,
          fy,
        );

    final g =
        _interpolate4(
          p00.g.toDouble(),
          p10.g.toDouble(),
          p01.g.toDouble(),
          p11.g.toDouble(),
          fx,
          fy,
        );

    final b =
        _interpolate4(
          p00.b.toDouble(),
          p10.b.toDouble(),
          p01.b.toDouble(),
          p11.b.toDouble(),
          fx,
          fy,
        );

    final a =
        _interpolate4(
          p00.a.toDouble(),
          p10.a.toDouble(),
          p01.a.toDouble(),
          p11.a.toDouble(),
          fx,
          fy,
        );

    final output = img.Image(
      width: 1,
      height: 1,
      numChannels: 4,
    );

    output.setPixelRgba(
      0,
      0,
      r.round().clamp(0, 255),
      g.round().clamp(0, 255),
      b.round().clamp(0, 255),
      a.round().clamp(0, 255),
    );

    return output.getPixel(
      0,
      0,
    );
  }

  static double _interpolate4(
    double p00,
    double p10,
    double p01,
    double p11,
    double fx,
    double fy,
  ) {
    final top =
        p00 + (p10 - p00) * fx;

    final bottom =
        p01 + (p11 - p01) * fx;

    return top +
        (bottom - top) * fy;
  }

  /// ==========================================================
  /// Destination -> Source
  /// ==========================================================

  static Point2D? _mapDestinationToSource(
    List<List<double>> matrix,
    double x,
    double y,
  ) {
    final px =
        matrix[0][0] * x +
        matrix[0][1] * y +
        matrix[0][2];

    final py =
        matrix[1][0] * x +
        matrix[1][1] * y +
        matrix[1][2];

    final pz =
        matrix[2][0] * x +
        matrix[2][1] * y +
        matrix[2][2];

    if (pz.abs() < 1e-10) {
      return null;
    }

    return Point2D(
      px / pz,
      py / pz,
    );
  }

  /// ==========================================================
  /// Perspective Transform
  /// ==========================================================

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

      final rowX = i * 2;
      final rowY = rowX + 1;

      a[rowX][0] = sx;
      a[rowX][1] = sy;
      a[rowX][2] = 1.0;

      a[rowX][6] =
          -dx * sx;

      a[rowX][7] =
          -dx * sy;

      b[rowX] = dx;

      a[rowY][3] = sx;
      a[rowY][4] = sy;
      a[rowY][5] = 1.0;

      a[rowY][6] =
          -dy * sx;

      a[rowY][7] =
          -dy * sy;

      b[rowY] = dy;
    }

    final h = _solveLinearSystem(
      a,
      b,
    );

    if (h == null) {
      return null;
    }

    return <List<double>>[
      <double>[
        h[0],
        h[1],
        h[2],
      ],
      <double>[
        h[3],
        h[4],
        h[5],
      ],
      <double>[
        h[6],
        h[7],
        1.0,
      ],
    ];
  }

  /// ==========================================================
  /// Gaussian elimination
  /// ==========================================================

  static List<double>? _solveLinearSystem(
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

    for (int column = 0;
         column < n;
         column++) {
      int pivotRow = column;

      for (int row = column + 1;
           row < n;
           row++) {
        if (augmented[row][column].abs() >
            augmented[pivotRow][column].abs()) {
          pivotRow = row;
        }
      }

      final pivot =
          augmented[pivotRow][column];

      if (pivot.abs() < 1e-12) {
        return null;
      }

      if (pivotRow != column) {
        final temp =
            augmented[column];

        augmented[column] =
            augmented[pivotRow];

        augmented[pivotRow] =
            temp;
      }

      for (int row = column + 1;
           row < n;
           row++) {
        final factor =
            augmented[row][column] /
                augmented[column][column];

        if (factor.abs() < 1e-15) {
          continue;
        }

        for (int j = column;
             j <= n;
             j++) {
          augmented[row][j] -=
              factor *
                  augmented[column][j];
        }
      }
    }

    final result =
        List<double>.filled(
      n,
      0.0,
    );

    for (int row = n - 1;
         row >= 0;
         row--) {
      var value =
          augmented[row][n];

      for (int column = row + 1;
           column < n;
           column++) {
        value -=
            augmented[row][column] *
                result[column];
      }

      final divisor =
          augmented[row][row];

      if (divisor.abs() < 1e-12) {
        return null;
      }

      result[row] =
          value / divisor;
    }

    return result;
  }

  /// ==========================================================
  /// Inverse 3x3
  /// ==========================================================

  static List<List<double>>? _invert3x3(
    List<List<double>> m,
  ) {
    if (m.length != 3 ||
        m.any((row) => row.length != 3)) {
      return null;
    }

    final a = m[0][0];
    final b = m[0][1];
    final c = m[0][2];

    final d = m[1][0];
    final e = m[1][1];
    final f = m[1][2];

    final g = m[2][0];
    final h = m[2][1];
    final i = m[2][2];

    final determinant =
        a * (e * i - f * h) -
        b * (d * i - f * g) +
        c * (d * h - e * g);

    if (determinant.abs() < 1e-12) {
      return null;
    }

    final invDet =
        1.0 / determinant;

    return <List<double>>[
      <double>[
        (e * i - f * h) * invDet,
        (c * h - b * i) * invDet,
        (b * f - c * e) * invDet,
      ],
      <double>[
        (f * g - d * i) * invDet,
        (a * i - c * g) * invDet,
        (c * d - a * f) * invDet,
      ],
      <double>[
        (d * h - e * g) * invDet,
        (b * g - a * h) * invDet,
        (a * e - b * d) * invDet,
      ],
    ];
  }
}

/// ============================================================
/// SmartCrop
///
/// كشف مستند تلقائي سريع.
/// ============================================================

class SmartCrop {
  static CropResult detect(
    img.Image src,
  ) {
    if (!_validImage(src)) {
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

    final points =
        _normalizedToPixels(
      src,
      corners,
    );

    if (!_validQuad(
      points,
      src.width,
      src.height,
    )) {
      return CropResult(
        image: src,
        changed: false,
      );
    }

    final area =
        _quadAreaPoints(points);

    final imageArea =
        src.width.toDouble() *
            src.height.toDouble();

    final ratio =
        area / imageArea;

    // مستند صغير جدًا = غالبًا كشف خاطئ.
    if (ratio < 0.08) {
      return CropResult(
        image: src,
        changed: false,
      );
    }

    // إذا كان المستند يغطي الصورة تقريبًا كلها،
    // لا داعي لإعادة القص.
    if (ratio > 0.965) {
      return CropResult(
        image: src,
        changed: false,
      );
    }

    final warped =
        PerspectiveWarp.warp(
      src,
      points[0].x,
      points[0].y,
      points[1].x,
      points[1].y,
      points[2].x,
      points[2].y,
      points[3].x,
      points[3].y,
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

  /// ==========================================================
  /// Detect corners
  /// ==========================================================

  static List<double>? detectCorners(
    img.Image src,
  ) {
    if (!_validImage(src)) {
      return null;
    }

    final candidate =
        _detectCandidate(src);

    if (candidate == null) {
      return null;
    }

    final points = <double>[
      candidate.tlX / candidate.sw,
      candidate.tlY / candidate.sh,

      candidate.trX / candidate.sw,
      candidate.trY / candidate.sh,

      candidate.brX / candidate.sw,
      candidate.brY / candidate.sh,

      candidate.blX / candidate.sw,
      candidate.blY / candidate.sh,
    ];

    // توسيع بسيط للخارج حتى لا يبقى إطار أسود/خلفية
    // حول الورقة بعد القص.
    const padding = 0.006;

    for (int i = 0;
         i < points.length;
         i += 2) {
      points[i] =
          (points[i] +
                  (points[i] < 0.5
                      ? -padding
                      : padding))
              .clamp(
                0.0,
                1.0,
              )
              .toDouble();

      points[i + 1] =
          (points[i + 1] +
                  (points[i + 1] < 0.5
                      ? -padding
                      : padding))
              .clamp(
                0.0,
                1.0,
              )
              .toDouble();
    }

    return points;
  }

  /// ==========================================================
  /// Candidate detection
  /// ==========================================================

  static _Candidate? _detectCandidate(
    img.Image src,
  ) {
    // حجم صغير جدًا للمعالجة السريعة.
    const targetSize = 360;

    final largest =
        max(
      src.width,
      src.height,
    );

    final scale =
        largest / targetSize;

    final sw = max(
      100,
      (src.width / scale).round(),
    );

    final sh = max(
      100,
      (src.height / scale).round(),
    );

    var gray =
        img.grayscale(
      img.copyResize(
        src,
        width: sw,
        height: sh,
        interpolation:
            img.Interpolation.linear,
      ),
    );

    // blur خفيف لتقليل ضوضاء الصورة.
    gray =
        img.gaussianBlur(
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

    final visited =
        List<bool>.filled(
      sw * sh,
      false,
    );

    final queue =
        <int>[];

    final candidates =
        <_Candidate>[];

    final imageArea =
        sw.toDouble() *
            sh.toDouble();

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

        while (head < queue.length) {
          final index =
              queue[head++];

          final py =
              index ~/ sw;

          final px =
              index - py * sw;

          count++;

          minX =
              min(minX, px);

          maxX =
              max(maxX, px);

          minY =
              min(minY, py);

          maxY =
              max(maxY, py);

          final sum =
              (px + py).toDouble();

          final diff =
              (px - py).toDouble();

          // أعلى يسار.
          if (sum < minSum) {
            minSum = sum;

            tlX = px;
            tlY = py;
          }

          // أسفل يمين.
          if (sum > maxSum) {
            maxSum = sum;

            brX = px;
            brY = py;
          }

          // أسفل يسار.
          if (diff < minDiff) {
            minDiff = diff;

            blX = px;
            blY = py;
          }

          // أعلى يمين.
          if (diff > maxDiff) {
            maxDiff = diff;

            trX = px;
            trY = py;
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

        if (count < 30) {
          continue;
        }

        final bboxWidth =
            maxX - minX + 1;

        final bboxHeight =
            maxY - minY + 1;

        if (bboxWidth <
                sw * 0.12 ||
            bboxHeight <
                sh * 0.08) {
          continue;
        }

        final bboxArea =
            bboxWidth.toDouble() *
                bboxHeight.toDouble();

        if (bboxArea <
            imageArea * 0.07) {
          continue;
        }

        final points =
            <Point2D>[
          Point2D(
            tlX.toDouble(),
            tlY.toDouble(),
          ),
          Point2D(
            trX.toDouble(),
            trY.toDouble(),
          ),
          Point2D(
            brX.toDouble(),
            brY.toDouble(),
          ),
          Point2D(
            blX.toDouble(),
            blY.toDouble(),
          ),
        ];

        final qArea =
            _quadAreaPoints(
          points,
        );

        if (qArea <
            imageArea * 0.055) {
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

        // مستند حقيقي عادة يكون رباعي كبير.
        final rectangularity =
            (qArea / bboxArea)
                .clamp(
                  0.0,
                  1.0,
                )
                .toDouble();

        // نعطي المساحة أولوية، لكن نكافئ الشكل
        // الذي يشبه مستطيلًا/ورقة.
        final score =
            coverage * 0.62 +
            rectangularity * 0.23 +
            density * 0.15;

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

    // إذا لم نجد مكوّنًا واضحًا، نستخدم
    // البحث المستطيلي كحل احتياطي.
    if (candidates.isEmpty) {
      final fallback =
          _fallbackRect(
        edges,
        sw,
        sh,
      );

      if (fallback == null) {
        return null;
      }

      final left =
          fallback[0].toDouble();

      final top =
          fallback[1].toDouble();

      final right =
          fallback[2].toDouble();

      final bottom =
          fallback[3].toDouble();

      final areaRatio =
          ((right - left) *
                  (bottom - top)) /
              imageArea;

      if (areaRatio < 0.08 ||
          areaRatio > 0.965) {
        return null;
      }

      return _Candidate(
        sw: sw,
        sh: sh,
        tlX: left,
        tlY: top,
        trX: right,
        trY: top,
        brX: right,
        brY: bottom,
        blX: left,
        blY: bottom,
        score: areaRatio,
        areaRatio: areaRatio,
      );
    }

    // الأعلى تقييمًا أولًا.
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

  /// ==========================================================
  /// Edge detection
  /// ==========================================================

  static List<bool> _makeEdges(
    img.Image gray,
  ) {
    final width =
        gray.width;

    final height =
        gray.height;

    final result =
        List<bool>.filled(
      width * height,
      false,
    );

    for (int y = 1;
         y < height - 1;
         y++) {
      for (int x = 1;
           x < width - 1;
           x++) {
        final tl =
            gray
                .getPixel(
                  x - 1,
                  y - 1,
                )
                .r
                .toDouble();

        final tc =
            gray
                .getPixel(
                  x,
                  y - 1,
                )
                .r
                .toDouble();

        final tr =
            gray
                .getPixel(
                  x + 1,
                  y - 1,
                )
                .r
                .toDouble();

        final ml =
            gray
                .getPixel(
                  x - 1,
                  y,
                )
                .r
                .toDouble();

        final mr =
            gray
                .getPixel(
                  x + 1,
                  y,
                )
                .r
                .toDouble();

        final bl =
            gray
                .getPixel(
                  x - 1,
                  y + 1,
                )
                .r
                .toDouble();

        final bc =
            gray
                .getPixel(
                  x,
                  y + 1,
                )
                .r
                .toDouble();

        final br =
            gray
                .getPixel(
                  x + 1,
                  y + 1,
                )
                .r
                .toDouble();

        final gx =
            (tr + 2 * mr + br) -
            (tl + 2 * ml + bl);

        final gy =
            (bl + 2 * bc + br) -
            (tl + 2 * tc + tr);

        final magnitude =
            sqrt(
          gx * gx +
              gy * gy,
        );

        // Threshold متوازن للصور العادية.
        if (magnitude > 48) {
          result[
            y * width + x
          ] = true;
        }
      }
    }

    return result;
  }

  /// ==========================================================
  /// Dilation
  /// ==========================================================

  static List<bool> _dilate(
    List<bool> source,
    int width,
    int height,
    int radius,
  ) {
    final result =
        List<bool>.filled(
      source.length,
      false,
    );

    for (int y = 0;
         y < height;
         y++) {
      for (int x = 0;
           x < width;
           x++) {
        bool hit = false;

        for (int dy = -radius;
             dy <= radius && !hit;
             dy++) {
          final ny =
              y + dy;

          if (ny < 0 ||
              ny >= height) {
            continue;
          }

          for (int dx = -radius;
               dx <= radius;
               dx++) {
            final nx =
                x + dx;

            if (nx < 0 ||
                nx >= width) {
              continue;
            }

            if (source[
                ny * width + nx]) {
              hit = true;
              break;
            }
          }
        }

        result[
          y * width + x
        ] = hit;
      }
    }

    return result;
  }

  /// ==========================================================
  /// Connect edges
  /// ==========================================================

  static List<bool> _connectEdgesWithSize(
    List<bool> source,
    int width,
    int height,
  ) {
    var result =
        _dilate(
      source,
      width,
      height,
      1,
    );

    result =
        _dilate(
      result,
      width,
      height,
      1,
    );

    return result;
  }

  /// ==========================================================
  /// Fallback rectangle
  /// ==========================================================

  static List<int>? _fallbackRect(
    List<bool> edges,
    int width,
    int height,
  ) {
    int? top;
    int? bottom;
    int? left;
    int? right;

    // أعلى.
    for (int y = 0;
         y < height;
         y++) {
      int count = 0;

      for (int x = 0;
           x < width;
           x++) {
        if (edges[
            y * width + x]) {
          count++;
        }
      }

      if (count >
          width * 0.10) {
        top = y;
        break;
      }
    }

    // أسفل.
    for (int y = height - 1;
         y >= 0;
         y--) {
      int count = 0;

      for (int x = 0;
           x < width;
           x++) {
        if (edges[
            y * width + x]) {
          count++;
        }
      }

      if (count >
          width * 0.10) {
        bottom = y;
        break;
      }
    }

    // يسار.
    for (int x = 0;
         x < width;
         x++) {
      int count = 0;

      for (int y = 0;
           y < height;
           y++) {
        if (edges[
            y * width + x]) {
          count++;
        }
      }

      if (count >
          height * 0.10) {
        left = x;
        break;
      }
    }

    // يمين.
    for (int x = width - 1;
         x >= 0;
         x--) {
      int count = 0;

      for (int y = 0;
           y < height;
           y++) {
        if (edges[
            y * width + x]) {
          count++;
        }
      }

      if (count >
          height * 0.10) {
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
            width * 0.12 ||
        bottom - top <
            height * 0.08) {
      return null;
    }

    return <int>[
      left,
      top,
      right,
      bottom,
    ];
  }

  /// ==========================================================
  /// Convert normalized points -> pixels
  /// ==========================================================

  static List<Point2D> _normalizedToPixels(
    img.Image image,
    List<double> values,
  ) {
    return <Point2D>[
      Point2D(
        values[0] * image.width,
        values[1] * image.height,
      ),
      Point2D(
        values[2] * image.width,
        values[3] * image.height,
      ),
      Point2D(
        values[4] * image.width,
        values[5] * image.height,
      ),
      Point2D(
        values[6] * image.width,
        values[7] * image.height,
      ),
    ];
  }

  /// ==========================================================
  /// Validate image
  /// ==========================================================

  static bool _validImage(
    img.Image image,
  ) {
    return image.width >= 100 &&
        image.height >= 100;
  }

  /// ==========================================================
  /// Validate quadrilateral
  /// ==========================================================

  static bool _validQuad(
    List<Point2D> points,
    int width,
    int height,
  ) {
    if (points.length != 4) {
      return false;
    }

    final area =
        _quadAreaPoints(
      points,
    );

    if (area <= 1) {
      return false;
    }

    // منع نقاط شاذة جدًا خارج الصورة.
    for (final point in points) {
      if (point.x < -width * 0.05 ||
          point.x > width * 1.05 ||
          point.y < -height * 0.05 ||
          point.y > height * 1.05) {
        return false;
      }
    }

    // أطوال الأضلاع.
    final top =
        points[0].distanceTo(
      points[1],
    );

    final right =
        points[1].distanceTo(
      points[2],
    );

    final bottom =
        points[2].distanceTo(
      points[3],
    );

    final left =
        points[3].distanceTo(
      points[0],
    );

    final shortest =
        min(
      min(top, bottom),
      min(right, left),
    );

    final longest =
        max(
      max(top, bottom),
      max(right, left),
    );

    if (shortest < 10) {
      return false;
    }

    // منع الأشكال المنهارة جدًا.
    if (longest / shortest > 15) {
      return false;
    }

    return true;
  }

  /// ==========================================================
  /// Quad area
  /// ==========================================================

  static double _quadAreaPoints(
    List<Point2D> points,
  ) {
    if (points.length != 4) {
      return 0;
    }

    return (
          points[0].x * points[1].y +
          points[1].x * points[2].y +
          points[2].x * points[3].y +
          points[3].x * points[0].y -
          points[0].y * points[1].x -
          points[1].y * points[2].x -
          points[2].y * points[3].x -
          points[3].y * points[0].x
        ).abs() /
        2.0;
  }

  /// Public helper لمن يحتاج حساب مساحة الرباعي.
  static double quadArea(
    double x1,
    double y1,
    double x2,
    double y2,
    double x3,
    double y3,
    double x4,
    double y4,
  ) {
    return _quadAreaPoints(
      <Point2D>[
        Point2D(x1, y1),
        Point2D(x2, y2),
        Point2D(x3, y3),
        Point2D(x4, y4),
      ],
    );
  }
}

/// ============================================================
/// Candidate
/// ============================================================

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

/// ============================================================
/// ManualCrop
///
/// القص اليدوي.
/// ============================================================

class ManualCrop {
  /// قص رباعي مع تصحيح المنظور.
  ///
  /// الإحداثيات normalized:
  /// 0.0 -> بداية الصورة
  /// 1.0 -> نهاية الصورة
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
      x1 * src.width,
      y1 * src.height,
      x2 * src.width,
      y2 * src.height,
      x3 * src.width,
      y3 * src.height,
      x4 * src.width,
      y4 * src.height,
    );
  }

  /// قص مستطيل عادي من أربع نقاط.
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

    final minX =
        xs.reduce(min);

    final maxX =
        xs.reduce(max);

    final minY =
        ys.reduce(min);

    final maxY =
        ys.reduce(max);

    int left =
        minX.round();

    int top =
        minY.round();

    int right =
        maxX.round();

    int bottom =
        maxY.round();

    left =
        left.clamp(
      0,
      src.width - 1,
    );

    top =
        top.clamp(
      0,
      src.height - 1,
    );

    right =
        right.clamp(
      left + 1,
      src.width,
    );

    bottom =
        bottom.clamp(
      top + 1,
      src.height,
    );

    final cropWidth =
        max(
      10,
      right - left,
    );

    final cropHeight =
        max(
      10,
      bottom - top,
    );

    return img.copyCrop(
      src,
      x: left,
      y: top,
      width: cropWidth,
      height: cropHeight,
    );
  }

  /// قص مستطيل باستخدام pixels مباشرة.
  static img.Image cropRectPixels(
    img.Image src,
    int left,
    int top,
    int right,
    int bottom,
  ) {
    left =
        left.clamp(
      0,
      src.width - 1,
    );

    top =
        top.clamp(
      0,
      src.height - 1,
    );

    right =
        right.clamp(
      left + 1,
      src.width,
    );

    bottom =
        bottom.clamp(
      top + 1,
      src.height,
    );

    return img.copyCrop(
      src,
      x: left,
      y: top,
      width: max(
        10,
        right - left,
      ),
      height: max(
        10,
        bottom - top,
      ),
    );
  }
}

/// ============================================================
/// GoogleScanner
///
/// Google ML Kit Document Scanner.
///
/// ملاحظة:
/// الحزمة الحالية تعمل على Android فقط.
/// ============================================================

class GoogleScanner {
  static Future<List<String>?> scan({
    int pageLimit = 10,
    bool galleryImport = true,
    ScannerMode mode = ScannerMode.filter,
  }) async {
    DocumentScanner? scanner;

    try {
      scanner = DocumentScanner(
        options: DocumentScannerOptions(
          documentFormats: const {
            DocumentFormat.jpeg,
          },
          mode: mode,
          pageLimit: pageLimit,
          isGalleryImport: galleryImport,
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

/// ============================================================
/// ImageUtils
/// ============================================================

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
    );

    return img.encodeJpg(
      src,
      quality: safeQuality,
    );
  }

  /// تحويل الصورة إلى Uint8List بصيغة JPEG.
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

  /// فك صورة من bytes.
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

  /// التحقق من صلاحية الصورة.
  static bool isValid(
    img.Image? image,
  ) {
    if (image == null) {
      return false;
    }

    return image.width >= 10 &&
        image.height >= 10;
  }

  /// إنشاء نسخة من الصورة.
  static img.Image clone(
    img.Image source,
  ) {
    return img
