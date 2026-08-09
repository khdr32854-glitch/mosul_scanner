import 'dart:math';
import 'dart:typed_data';

import 'package:image/image.dart' as img;
import 'package:google_mlkit_document_scanner/google_mlkit_document_scanner.dart';

/// ===============================================================
/// Mosul Scanner
/// crop_engine.dart
///
/// محرك قص المستندات:
/// - Auto document detection
/// - Perspective correction
/// - Manual crop
/// - Rotation
/// - Image filters
/// - JPEG encode/decode
///
/// لا يعتمد على OpenCV.
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
  final DocumentCorners? corners;

  const CropResult({
    required this.image,
    required this.changed,
    this.corners,
  });
}

/// ===============================================================
/// EnhanceMode
/// ===============================================================

enum EnhanceMode {
  none,
  soft,
  bw,
  gray,
  document,
}

/// ===============================================================
/// DocumentCorners
///
/// النسب دائماً من 0 إلى 1.
/// الترتيب:
///
/// TL = أعلى يسار
/// TR = أعلى يمين
/// BR = أسفل يمين
/// BL = أسفل يسار
/// ===============================================================

class DocumentCorners {
  final double tlX;
  final double tlY;

  final double trX;
  final double trY;

  final double brX;
  final double brY;

  final double blX;
  final double blY;

  const DocumentCorners({
    required this.tlX,
    required this.tlY,
    required this.trX,
    required this.trY,
    required this.brX,
    required this.brY,
    required this.blX,
    required this.blY,
  });

  DocumentCorners copyWith({
    double? tlX,
    double? tlY,
    double? trX,
    double? trY,
    double? brX,
    double? brY,
    double? blX,
    double? blY,
  }) {
    return DocumentCorners(
      tlX: tlX ?? this.tlX,
      tlY: tlY ?? this.tlY,
      trX: trX ?? this.trX,
      trY: trY ?? this.trY,
      brX: brX ?? this.brX,
      brY: brY ?? this.brY,
      blX: blX ?? this.blX,
      blY: blY ?? this.blY,
    );
  }

  List<double> toList() {
    return [
      tlX,
      tlY,
      trX,
      trY,
      brX,
      brY,
      blX,
      blY,
    ];
  }

  static DocumentCorners fromPixels(
    double tlX,
    double tlY,
    double trX,
    double trY,
    double brX,
    double brY,
    double blX,
    double blY,
    int width,
    int height,
  ) {
    return DocumentCorners(
      tlX: tlX / width,
      tlY: tlY / height,
      trX: trX / width,
      trY: trY / height,
      brX: brX / width,
      brY: brY / height,
      blX: blX / width,
      blY: blY / height,
    );
  }

  DocumentCorners clamp() {
    return DocumentCorners(
      tlX: _clamp01(tlX),
      tlY: _clamp01(tlY),
      trX: _clamp01(trX),
      trY: _clamp01(trY),
      brX: _clamp01(brX),
      brY: _clamp01(brY),
      blX: _clamp01(blX),
      blY: _clamp01(blY),
    );
  }

  static double _clamp01(double v) {
    return v.clamp(0.0, 1.0).toDouble();
  }
}

/// ===============================================================
/// PerspectiveWarp
///
/// تحويل أربعة أركان إلى مستطيل مستقيم.
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
    final points = _orderPoints(
      x1,
      y1,
      x2,
      y2,
      x3,
      y3,
      x4,
      y4,
    );

    final tlX = points[0];
    final tlY = points[1];

    final trX = points[2];
    final trY = points[3];

    final brX = points[4];
    final brY = points[5];

    final blX = points[6];
    final blY = points[7];

    final topWidth = _distance(
      tlX,
      tlY,
      trX,
      trY,
    );

    final bottomWidth = _distance(
      blX,
      blY,
      brX,
      brY,
    );

    final leftHeight = _distance(
      tlX,
      tlY,
      blX,
      blY,
    );

    final rightHeight = _distance(
      trX,
      trY,
      brX,
      brY,
    );

    int outputWidth = max(
      20,
      max(
        topWidth.round(),
        bottomWidth.round(),
      ),
    );

    int outputHeight = max(
      20,
      max(
        leftHeight.round(),
        rightHeight.round(),
      ),
    );

    /// منع إنتاج صور ضخمة جداً.
    const maxDimension = 5000;

    if (outputWidth > maxDimension ||
        outputHeight > maxDimension) {
      final scale = min(
        maxDimension / outputWidth,
        maxDimension / outputHeight,
      );

      outputWidth = max(
        20,
        (outputWidth * scale).round(),
      );

      outputHeight = max(
        20,
        (outputHeight * scale).round(),
      );
    }

    final srcPoints = <double>[
      tlX,
      tlY,
      trX,
      trY,
      brX,
      brY,
      blX,
      blY,
    ];

    final dstPoints = <double>[
      0,
      0,
      outputWidth - 1.0,
      0,
      outputWidth - 1.0,
      outputHeight - 1.0,
      0,
      outputHeight - 1.0,
    ];

    final matrix = _getPerspectiveTransform(
      srcPoints,
      dstPoints,
    );

    if (matrix == null) {
      return src;
    }

    final inverse = _invert3x3(matrix);

    if (inverse == null) {
      return src;
    }

    final result = img.Image(
      width: outputWidth,
      height: outputHeight,
    );

    for (int y = 0; y < outputHeight; y++) {
      for (int x = 0; x < outputWidth; x++) {
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

        if (q.abs() < 0.0000001) {
          continue;
        }

        final sx = w / q;
        final sy = v / q;

        if (sx < 0 ||
            sy < 0 ||
            sx >= src.width - 1 ||
            sy >= src.height - 1) {
          continue;
        }

        final color = _bilinear(
          src,
          sx,
          sy,
        );

        result.setPixelRgba(
          x,
          y,
          color[0],
          color[1],
          color[2],
          color[3],
        );
      }
    }

    return result;
  }

  static List<int> _bilinear(
    img.Image source,
    double x,
    double y,
  ) {
    final x0 = x.floor();
    final y0 = y.floor();

    final x1 = min(
      x0 + 1,
      source.width - 1,
    );

    final y1 = min(
      y0 + 1,
      source.height - 1,
    );

    final fx = x - x0;
    final fy = y - y0;

    final p00 = source.getPixel(x0, y0);
    final p10 = source.getPixel(x1, y0);
    final p01 = source.getPixel(x0, y1);
    final p11 = source.getPixel(x1, y1);

    int mix(
      int a,
      int b,
      int c,
      int d,
    ) {
      final top =
          a * (1 - fx) +
          b * fx;

      final bottom =
          c * (1 - fx) +
          d * fx;

      return (
        top * (1 - fy) +
        bottom * fy
      ).round().clamp(0, 255);
    }

    return [
      mix(
        p00.r.toInt(),
        p10.r.toInt(),
        p01.r.toInt(),
        p11.r.toInt(),
      ),
      mix(
        p00.g.toInt(),
        p10.g.toInt(),
        p01.g.toInt(),
        p11.g.toInt(),
      ),
      mix(
        p00.b.toInt(),
        p10.b.toInt(),
        p01.b.toInt(),
        p11.b.toInt(),
      ),
      mix(
        p00.a.toInt(),
        p10.a.toInt(),
        p01.a.toInt(),
        p11.a.toInt(),
      ),
    ];
  }

  static double _distance(
    double x1,
    double y1,
    double x2,
    double y2,
  ) {
    return sqrt(
      pow(x2 - x1, 2) +
      pow(y2 - y1, 2),
    );
  }

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

    /// استعمال مجموع وإحداثي الفرق
    /// يجعل الترتيب أكثر ثباتاً مع الدوران.
    points.sort(
      (a, b) => (a[0] + a[1])
          .compareTo(b[0] + b[1]),
    );

    final tl = points[0];
    final br = points[3];

    final remaining = [
      points[1],
      points[2],
    ];

    remaining.sort(
      (a, b) => (a[0] - a[1])
          .compareTo(b[0] - b[1]),
    );

    final tr = remaining[1];
    final bl = remaining[0];

    return [
      tl[0],
      tl[1],
      tr[0],
      tr[1],
      br[0],
      br[1],
      bl[0],
      bl[1],
    ];
  }

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
        0,
      ),
    );

    final b = List<double>.filled(
      8,
      0,
    );

    for (int i = 0; i < 4; i++) {
      final sx = src[i * 2];
      final sy = src[i * 2 + 1];

      final dx = dst[i * 2];
      final dy = dst[i * 2 + 1];

      final row1 = i * 2;
      final row2 = row1 + 1;

      a[row1][0] = sx;
      a[row1][1] = sy;
      a[row1][2] = 1;

      a[row1][6] = -dx * sx;
      a[row1][7] = -dx * sy;

      b[row1] = dx;

      a[row2][3] = sx;
      a[row2][4] = sy;
      a[row2][5] = 1;

      a[row2][6] = -dy * sx;
      a[row2][7] = -dy * sy;

      b[row2] = dy;
    }

    final h = _solveLinear(
      a,
      b,
    );

    if (h == null) {
      return null;
    }

    return [
      [h[0], h[1], h[2]],
      [h[3], h[4], h[5]],
      [h[6], h[7], 1],
    ];
  }

  static List<double>? _solveLinear(
    List<List<double>> a,
    List<double> b,
  ) {
    final n = a.length;

    final matrix = List.generate(
      n,
      (i) => [
        ...a[i],
        b[i],
      ],
    );

    for (int col = 0; col < n; col++) {
      int pivot = col;

      for (int row = col + 1;
          row < n;
          row++) {
        if (matrix[row][col].abs() >
            matrix[pivot][col].abs()) {
          pivot = row;
        }
      }

      if (matrix[pivot][col].abs() <
          1e-12) {
        return null;
      }

      if (pivot != col) {
        final temp = matrix[col];
        matrix[col] = matrix[pivot];
        matrix[pivot] = temp;
      }

      for (int row = col + 1;
          row < n;
          row++) {
        final factor =
            matrix[row][col] /
            matrix[col][col];

        if (factor == 0) {
          continue;
        }

        for (int j = col;
            j <= n;
            j++) {
          matrix[row][j] -=
              factor * matrix[col][j];
        }
      }
    }

    final result =
        List<double>.filled(
      n,
      0,
    );

    for (int i = n - 1;
        i >= 0;
        i--) {
      double value =
          matrix[i][n];

      for (int j = i + 1;
          j < n;
          j++) {
        value -=
            matrix[i][j] *
            result[j];
      }

      if (matrix[i][i].abs() <
          1e-12) {
        return null;
      }

      result[i] =
          value /
          matrix[i][i];
    }

    return result;
  }

  static List<List<double>>? _invert3x3(
    List<List<double>> m,
  ) {
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

    final inv = 1.0 / det;

    return [
      [
        (m[1][1] * m[2][2] -
                m[1][2] * m[2][1]) *
            inv,
        (m[0][2] * m[2][1] -
                m[0][1] * m[2][2]) *
            inv,
        (m[0][1] * m[1][2] -
                m[0][2] * m[1][1]) *
            inv,
      ],
      [
        (m[1][2] * m[2][0] -
                m[1][0] * m[2][2]) *
            inv,
        (m[0][0] * m[2][2] -
                m[0][2] * m[2][0]) *
            inv,
        (m[0][2] * m[1][0] -
                m[0][0] * m[1][2]) *
            inv,
      ],
      [
        (m[1][0] * m[2][1] -
                m[1][1] * m[2][0]) *
            inv,
        (m[0][1] * m[2][0] -
                m[0][0] * m[2][1]) *
            inv,
        (m[0][0] * m[1][1] -
                m[0][1] * m[1][0]) *
            inv,
      ],
    ];
  }
}

/// ===============================================================
/// SmartCrop
///
/// الاستراتيجية الجديدة:
///
/// 1. تصغير الصورة للتحليل فقط.
/// 2. Grayscale.
/// 3. إزالة الضوضاء.
/// 4. حساب gradient.
/// 5. عدة مستويات threshold.
/// 6. استخراج مكونات الحواف.
/// 7. تقييم المستند حسب:
///    - المساحة
///    - شكل رباعي
///    - نسبة العرض/الارتفاع
///    - قرب الحواف من حدود المرشح
///    - كثافة الحواف
///
/// الهدف منع اختيار نصف البطاقة أو نص داخل البطاقة.
/// ===============================================================

class SmartCrop {
  static CropResult detect(
    img.Image src,
  ) {
    if (src.width < 120 ||
        src.height < 120) {
      return CropResult(
        image: src,
        changed: false,
      );
    }

    final corners = detectCorners(src);

    if (corners == null) {
      return CropResult(
        image: src,
        changed: false,
      );
    }

    final result = applyCorners(
      src,
      corners,
    );

    if (result == null) {
      return CropResult(
        image: src,
        changed: false,
        corners: corners,
      );
    }

    return CropResult(
      image: result,
      changed: true,
      corners: corners,
    );
  }

  /// اكتشاف الزوايا فقط.
  ///
  /// هذه الدالة مهمة جداً للواجهة:
  /// الواجهة تعرض النقاط أولاً، ثم المستخدم يستطيع تعديلها.
  static DocumentCorners? detectCorners(
    img.Image source,
  ) {
    if (source.width < 120 ||
        source.height < 120) {
      return null;
    }

    final scale = min(
      1.0,
      420.0 /
          max(
            source.width,
            source.height,
          ),
    );

    final width = max(
      120,
      (source.width * scale).round(),
    );

    final height = max(
      120,
      (source.height * scale).round(),
    );

    final small = img.copyResize(
      source,
      width: width,
      height: height,
      interpolation: img.Interpolation.average,
    );

    final gray = img.grayscale(
      small,
    );

    final blurred = img.gaussianBlur(
      gray,
      radius: 1,
    );

    final gradient = _gradient(
      blurred,
    );

    final candidates = <_QuadCandidate>[];

    /// أكثر من threshold.
    ///
    /// هذا مهم جداً للإضاءة.
    const thresholds = [
      28.0,
      40.0,
      52.0,
      66.0,
      82.0,
    ];

    for (final threshold in thresholds) {
      final edges = _threshold(
        gradient,
        threshold,
      );

      final cleaned = _closeEdges(
        edges,
        width,
        height,
      );

      final found = _findCandidates(
        cleaned,
        gradient,
        width,
        height,
      );

      candidates.addAll(found);
    }

    if (candidates.isEmpty) {
      return _borderScan(
        gradient,
        width,
        height,
        source,
      );
    }

    candidates.sort(
      (a, b) => b.score.compareTo(
        a.score,
      ),
    );

    final best = candidates.first;

    /// منع اختيار جزء صغير من الصورة.
    if (best.areaRatio < 0.06) {
      return null;
    }

    /// إذا المستند تقريباً يملأ الصورة كلها
    /// نعتبر الصورة أصلاً مقصوصة.
    if (best.areaRatio > 0.985) {
      return null;
    }

    final sx =
        source.width / width;

    final sy =
        source.height / height;

    return DocumentCorners(
      tlX: best.tlX * sx /
          source.width,
      tlY: best.tlY * sy /
          source.height,
      trX: best.trX * sx /
          source.width,
      trY: best.trY * sy /
          source.height,
      brX: best.brX * sx /
          source.width,
      brY: best.brY * sy /
          source.height,
      blX: best.blX * sx /
          source.width,
      blY: best.blY * sy /
          source.height,
    ).clamp();
  }

  /// تطبيق الزوايا.
  static img.Image? applyCorners(
    img.Image source,
    DocumentCorners corners,
  ) {
    final c = corners.clamp();

    final points = [
      c.tlX * source.width,
      c.tlY * source.height,
      c.trX * source.width,
      c.trY * source.height,
      c.brX * source.width,
      c.brY * source.height,
      c.blX * source.width,
      c.blY * source.height,
    ];

    final area = _area(
      points[0],
      points[1],
      points[2],
      points[3],
      points[4],
      points[5],
      points[6],
      points[7],
    );

    final imageArea =
        source.width *
        source.height;

    if (area <
        imageArea * 0.025) {
      return null;
    }

    return PerspectiveWarp.warp(
      source,
      points[0],
      points[1],
      points[2],
      points[3],
      points[4],
      points[5],
      points[6],
      points[7],
    );
  }

  /// =============================================================
  /// Gradient
  /// =============================================================

  static List<double> _gradient(
    img.Image image,
  ) {
    final w = image.width;
    final h = image.height;

    final output =
        List<double>.filled(
      w * h,
      0,
    );

    for (int y = 1;
        y < h - 1;
        y++) {
      for (int x = 1;
          x < w - 1;
          x++) {
        final p00 =
            image
                .getPixel(
                  x - 1,
                  y - 1,
                )
                .r
                .toInt();

        final p01 =
            image
                .getPixel(
                  x,
                  y - 1,
                )
                .r
                .toInt();

        final p02 =
            image
                .getPixel(
                  x + 1,
                  y - 1,
                )
                .r
                .toInt();

        final p10 =
            image
                .getPixel(
                  x - 1,
                  y,
                )
                .r
                .toInt();

        final p12 =
            image
                .getPixel(
                  x + 1,
                  y,
                )
                .r
                .toInt();

        final p20 =
            image
                .getPixel(
                  x - 1,
                  y + 1,
                )
                .r
                .toInt();

        final p21 =
            image
                .getPixel(
                  x,
                  y + 1,
                )
                .r
                .toInt();

        final p22 =
            image
                .getPixel(
                  x + 1,
                  y + 1,
                )
                .r
                .toInt();

        final gx =
            -p00 +
            p02 -
            2 * p10 +
            2 * p12 -
            p20 +
            p22;

        final gy =
            -p00 -
            2 * p01 -
            p02 +
            p20 +
            2 * p21 +
            p22;

        output[y * w + x] =
            sqrt(
              gx * gx +
              gy * gy,
            );
      }
    }

    return output;
  }

  /// =============================================================
  /// Threshold
  /// =============================================================

  static List<bool> _threshold(
    List<double> gradient,
    double threshold,
  ) {
    return List.generate(
      gradient.length,
      (i) => gradient[i] >= threshold,
    );
  }

  /// =============================================================
  /// Morphological close
  /// =============================================================

  static List<bool> _closeEdges(
    List<bool> source,
    int width,
    int height,
  ) {
    var result = _dilate(
      source,
      width,
      height,
      1,
    );

    result = _erode(
      result,
      width,
      height,
      1,
    );

    return result;
  }

  static List<bool> _dilate(
    List<bool> source,
    int width,
    int height,
    int radius,
  ) {
    final output =
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
        bool found = false;

        for (int dy = -radius;
            dy <= radius && !found;
            dy++) {
          final ny = y + dy;

          if (ny < 0 ||
              ny >= height) {
            continue;
          }

          for (int dx = -radius;
              dx <= radius;
              dx++) {
            final nx = x + dx;

            if (nx < 0 ||
                nx >= width) {
              continue;
            }

            if (source[
                ny * width + nx]) {
              found = true;
              break;
            }
          }
        }

        output[
          y * width + x
        ] = found;
      }
    }

    return output;
  }

  static List<bool> _erode(
    List<bool> source,
    int width,
    int height,
    int radius,
  ) {
    final output =
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
        bool all = true;

        for (int dy = -radius;
            dy <= radius && all;
            dy++) {
          final ny = y + dy;

          if (ny < 0 ||
              ny >= height) {
            all = false;
            break;
          }

          for (int dx = -radius;
              dx <= radius;
              dx++) {
            final nx = x + dx;

            if (nx < 0 ||
                nx >= width) {
              all = false;
              break;
            }

            if (!source[
                ny * width + nx]) {
              all = false;
              break;
            }
          }
        }

        output[
          y * width + x
        ] = all;
      }
    }

    return output;
  }

  /// =============================================================
  /// Candidate components
  /// =============================================================

  static List<_QuadCandidate> _findCandidates(
    List<bool> edges,
    List<double> gradient,
    int width,
    int height,
  ) {
    final visited =
        List<bool>.filled(
      width * height,
      false,
    );

    final result =
        <_QuadCandidate>[];

    final queue =
        <int>[];

    final imageArea =
        width * height;

    for (int y = 2;
        y < height - 2;
        y++) {
      for (int x = 2;
          x < width - 2;
          x++) {
        final start =
            y * width + x;

        if (visited[start] ||
            !edges[start]) {
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

        int tlIndex = start;
        int trIndex = start;
        int brIndex = start;
        int blIndex = start;

        double minSum =
            double.infinity;

        double maxSum =
            double.negativeInfinity;

        double minDiff =
            double.infinity;

        double maxDiff =
            double.negativeInfinity;

        while (head < queue.length) {
          final index =
              queue[head++];

          final py =
              index ~/ width;

          final px =
              index -
              py * width;

          count++;

          minX = min(
            minX,
            px,
          );

          maxX = max(
            maxX,
            px,
          );

          minY = min(
            minY,
            py,
          );

          maxY = max(
            maxY,
            py,
          );

          final sum =
              px + py;

          final diff =
              px - py;

          if (sum < minSum) {
            minSum = sum.toDouble();
            tlIndex = index;
          }

          if (sum > maxSum) {
            maxSum = sum.toDouble();
            brIndex = index;
          }

          if (diff > maxDiff) {
            maxDiff = diff.toDouble();
            trIndex = index;
          }

          if (diff < minDiff) {
            minDiff = diff.toDouble();
            blIndex = index;
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
                  nx >= width - 1 ||
                  ny < 1 ||
                  ny >= height - 1) {
                continue;
              }

              final next =
                  ny * width + nx;

              if (!visited[next] &&
                  edges[next]) {
                visited[next] = true;
                queue.add(next);
              }
            }
          }
        }

        final boxWidth =
            maxX - minX + 1;

        final boxHeight =
            maxY - minY + 1;

        final boxArea =
            boxWidth * boxHeight;

        if (count < 20) {
          continue;
        }

        if (boxWidth <
            width * 0.10) {
          continue;
        }

        if (boxHeight <
            height * 0.08) {
          continue;
        }

        if (boxArea <
            imageArea * 0.045) {
          continue;
        }

        final tl =
            _point(
          tlIndex,
          width,
        );

        final tr =
            _point(
          trIndex,
          width,
        );

        final br =
            _point(
          brIndex,
          width,
        );

        final bl =
            _point(
          blIndex,
          width,
        );

        final area =
            _area(
          tl[0],
          tl[1],
          tr[0],
          tr[1],
          br[0],
          br[1],
          bl[0],
          bl[1],
        );

        final areaRatio =
            area /
            imageArea;

        if (areaRatio <
                0.05 ||
            areaRatio >
                0.99) {
          continue;
        }

        final top =
            _distance(
          tl[0],
          tl[1],
          tr[0],
          tr[1],
        );

        final bottom =
            _distance(
          bl[0],
          bl[1],
          br[0],
          br[1],
        );

        final left =
            _distance(
          tl[0],
          tl[1],
          bl[0],
          bl[1],
        );

        final right =
            _distance(
          tr[0],
          tr[1],
          br[0],
          br[1],
        );

        if (top < width * 0.08 ||
            bottom < width * 0.08 ||
            left < height * 0.06 ||
            right < height * 0.06) {
          continue;
        }

        final widthRatio =
            max(top, bottom) /
            max(1, min(top, bottom));

        final heightRatio =
            max(left, right) /
            max(1, min(left, right));

        if (widthRatio > 2.8 ||
            heightRatio > 2.8) {
          continue;
        }

        final rectangularity =
            _rectangularity(
          top,
          bottom,
          left,
          right,
          area,
        );

        final centerX =
            (tl[0] +
                    tr[0] +
                    br[0] +
                    bl[0]) /
                4;

        final centerY =
            (tl[1] +
                    tr[1] +
                    br[1] +
                    bl[1]) /
                4;

        final centerDistance =
            sqrt(
              pow(
                    centerX -
                        width / 2,
                    2,
                  ) +
                  pow(
                    centerY -
                        height / 2,
                    2,
                  ),
            );

        final centerScore =
            1 -
            min(
              1,
              centerDistance /
                  (max(
                    width,
                    height,
                  ) /
                      1.5),
            );

        final sizeScore =
            min(
              1,
              areaRatio /
                  0.65,
            );

        final score =
            areaRatio * 0.48 +
            rectangularity * 0.28 +
            centerScore * 0.10 +
            sizeScore * 0.14;

        result.add(
          _QuadCandidate(
            tlX: tl[0],
            tlY: tl[1],
            trX: tr[0],
            trY: tr[1],
            brX: br[0],
            brY: br[1],
            blX: bl[0],
            blY: bl[1],
            areaRatio: areaRatio,
            score: score,
          ),
        );
      }
    }

    /// لا نرجع مرشحات كثيرة جداً.
    result.sort(
      (a, b) =>
          b.score.compareTo(
        a.score,
      ),
    );

    if (result.length > 12) {
      return result.sublist(
        0,
        12,
      );
    }

    return result;
  }

  /// =============================================================
  /// fallback
  ///
  /// عند فشل connected components نحاول اكتشاف حدود عامة.
  /// =============================================================

  static DocumentCorners? _borderScan(
    List<double> gradient,
    int width,
    int height,
    img.Image source,
  ) {
    final thresholds = [
      25.0,
      35.0,
      50.0,
      70.0,
    ];

    for (final threshold in thresholds) {
      int? left;
      int? right;
      int? top;
      int? bottom;

      final horizontal =
          List<int>.filled(
        height,
        0,
      );

      final vertical =
          List<int>.filled(
        width,
        0,
      );

      for (int y = 0;
          y < height;
          y++) {
        for (int x = 0;
            x < width;
            x++) {
          if (gradient[
                  y * width + x] >=
              threshold) {
            horizontal[y]++;
            vertical[x]++;
          }
        }
      }

      for (int x = 0;
          x < width;
          x++) {
        if (vertical[x] >
            height * 0.08) {
          left = x;
          break;
        }
      }

      for (int x = width - 1;
          x >= 0;
          x--) {
        if (vertical[x] >
            height * 0.08) {
          right = x;
          break;
        }
      }

      for (int y = 0;
          y < height;
          y++) {
        if (horizontal[y] >
            width * 0.08) {
          top = y;
          break;
        }
      }

      for (int y = height - 1;
          y >= 0;
          y--) {
        if (horizontal[y] >
            width * 0.08) {
          bottom = y;
          break;
        }
      }

      if (left == null ||
          right == null ||
          top == null ||
          bottom == null) {
        continue;
      }

      final area =
          (right - left) *
          (bottom - top);

      final imageArea =
          width * height;

      if (area <
              imageArea * 0.08 ||
          area >
              imageArea * 0.98) {
        continue;
      }

      final sx =
          source.width /
          width;

      final sy =
          source.height /
          height;

      return DocumentCorners(
        tlX:
            left * sx /
            source.width,
        tlY:
            top * sy /
            source.height,
        trX:
            right * sx /
            source.width,
        trY:
            top * sy /
            source.height,
        brX:
            right * sx /
            source.width,
        brY:
            bottom * sy /
            source.height,
        blX:
            left * sx /
            source.width,
        blY:
            bottom * sy /
            source.height,
      ).clamp();
    }

    return null;
  }

  static List<double> _point(
    int index,
    int width,
  ) {
    final y =
        index ~/ width;

    final x =
        index -
        y * width;

    return [
      x.toDouble(),
      y.toDouble(),
    ];
  }

  static double _rectangularity(
    double top,
    double bottom,
    double left,
    double right,
    double area,
  ) {
    final averageWidth =
        (top + bottom) / 2;

    final averageHeight =
        (left + right) / 2;

    final expected =
        averageWidth *
        averageHeight;

    if (expected <= 0) {
      return 0;
    }

    return (
      area /
      expected
    ).clamp(
      0.0,
      1.0,
    );
  }

  static double _area(
    double x1,
    double y1,
    double x2,
    double y2,
    double x3,
    double y3,
    double x4,
    double y4,
  ) {
    return (
          x1 * y2 +
          x2 * y3 +
          x3 * y4 +
          x4 * y1 -
          y1 * x2 -
          y2 * x3 -
          y3 * x4 -
          y4 * x1
        ).abs() /
        2;
  }
}

/// ===============================================================
/// Candidate
/// ===============================================================

class _QuadCandidate {
  final double tlX;
  final double tlY;

  final double trX;
  final double trY;

  final double brX;
  final double brY;

  final double blX;
  final double blY;

  final double areaRatio;
  final double score;

  const _QuadCandidate({
    required this.tlX,
    required this.tlY,
    required this.trX,
    required this.trY,
    required this.brX,
    required this.brY,
    required this.blX,
    required this.blY,
    required this.areaRatio,
    required this.score,
  });
}

/// ===============================================================
/// ManualCrop
///
/// القص اليدوي.
///
/// مهم:
/// هذه الدوال ترجع Image جديدة.
/// main.dart يجب أن يستلم هذه الصورة ويضعها
/// في متغير الصورة الحالية.
/// ===============================================================

class ManualCrop {
  /// قص منظور حقيقي.
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

  /// القص المستطيلي التقليدي.
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
    final xs = [
      x1 * src.width,
      x2 * src.width,
      x3 * src.width,
      x4 * src.width,
    ];

    final ys = [
      y1 * src.height,
      y2 * src.height,
      y3 * src.height,
      y4 * src.height,
    ];

    int left =
        xs.reduce(min).round();

    int right =
        xs.reduce(max).round();

    int top =
        ys.reduce(min).round();

    int bottom =
        ys.reduce(max).round();

    left = left.clamp(
      0,
      src.width - 1,
    );

    top = top.clamp(
      0,
      src.height - 1,
    );

    right = right.clamp(
      left + 1,
      src.width,
    );

    bottom = bottom.clamp(
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

  /// استخدام DocumentCorners مباشرة.
  static img.Image crop(
    img.Image src,
    DocumentCorners corners, {
    bool perspective = true,
  }) {
    if (perspective) {
      return cropPerspective(
        src,
        corners.tlX,
        corners.tlY,
        corners.trX,
        corners.trY,
        corners.brX,
        corners.brY,
        corners.blX,
        corners.blY,
      );
    }

    return cropRect(
      src,
      corners.tlX,
      corners.tlY,
      corners.trX,
      corners.trY,
      corners.brX,
      corners.brY,
      corners.blX,
      corners.blY,
    );
  }
}

/// ===============================================================
/// ImageEnhancer
///
/// الفلاتر الموجودة هنا مستقلة عن القص.
/// ===============================================================

class ImageEnhancer {
  static img.Image apply(
    img.Image source,
    EnhanceMode mode,
  ) {
    switch (mode) {
      case EnhanceMode.none:
        return source;

      case EnhanceMode.soft:
        return _soft(
          source,
        );

      case EnhanceMode.gray:
        return img.grayscale(
          source,
        );

      case EnhanceMode.bw:
        return _blackWhite(
          source,
        );

      case EnhanceMode.document:
        return _document(
          source,
        );
    }
  }

  static img.Image _soft(
    img.Image source,
  ) {
    final result =
        img.Image.from(
      source,
    );

    for (int y = 0;
        y < result.height;
        y++) {
      for (int x = 0;
          x < result.width;
          x++) {
        final p =
            result.getPixel(
          x,
          y,
        );

        final r =
            (p.r * 1.04)
                .round()
                .clamp(0, 255);

        final g =
            (p.g * 1.04)
                .round()
                .clamp(0, 255);

        final b =
            (p.b * 1.04)
                .round()
                .clamp(0, 255);

        result.setPixelRgba(
          x,
          y,
          r,
          g,
          b,
          p.a.toInt(),
        );
      }
    }

    return result;
  }

  static img.Image _blackWhite(
    img.Image source,
  ) {
    final gray =
        img.grayscale(
      source,
    );

    final result =
        img.Image(
      width: gray.width,
      height: gray.height,
    );

    for (int y = 0;
        y < gray.height;
        y++) {
      for (int x = 0;
          x < gray.width;
          x++) {
        final p =
            gray.getPixel(
          x,
          y,
        );

        final value =
            p.r.toInt();

        final bw =
            value >= 155
                ? 255
                : 0;

        result.setPixelRgba(
          x,
          y,
          bw,
          bw,
          bw,
          p.a.toInt(),
        );
      }
    }

    return result;
  }

  static img.Image _document(
    img.Image source,
  ) {
    final gray =
        img.grayscale(
      source,
    );

    final blurred =
        img.gaussianBlur(
      gray,
      radius: 1,
    );

    final result =
        img.Image(
      width: blurred.width,
      height: blurred.height,
    );

    for (int y = 0;
        y < blurred.height;
        y++) {
      for (int x = 0;
          x < blurred.width;
          x++) {
        final p =
            blurred.getPixel(
          x,
          y,
        );

        final v =
            p.r.toInt();

        /// رفع التباين بطريقة ناعمة
        /// حتى لا تختفي الكتابة الخفيفة.
        final enhanced =
            ((v - 128) *
                    1.22 +
                128)
                .round()
                .clamp(
                  0,
                  255,
                );

        result.setPixelRgba(
          x,
          y,
          enhanced,
          enhanced,
          enhanced,
          p.a.toInt(),
        );
      }
    }

    return result;
  }
}

/// ===============================================================
/// ImageUtils
/// ===============================================================

class ImageUtils {
  static List<int> encodeJpg(
    img.Image source, {
    int quality = 92,
  }) {
    final safeQuality =
        quality.clamp(
      1,
      100,
    );

    return img.encodeJpg(
      source,
      quality: safeQuality,
    );
  }

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

  static bool isValid(
    img.Image? image,
  ) {
    if (image == null) {
      return false;
    }

    return image.width >= 10 &&
        image.height >= 10;
  }

  static img.Image resizeForProcessing(
    img.Image source, {
    int maxSize = 1800,
  }) {
    final longest =
        max(
      source.width,
      source.height,
    );

    if (longest <= maxSize) {
      return source;
    }

    final scale =
        maxSize / longest;

    return img.copyResize(
      source,
      width: max(
        1,
        (source.width * scale)
            .round(),
      ),
      height: max(
        1,
        (source.height * scale)
            .round(),
      ),
      interpolation:
          img.Interpolation.average,
    );
  }
}

/// ===============================================================
/// GoogleScanner
///
/// يبقى موجوداً كخيار مستقل.
/// لا نعتمد عليه كمحرك القص الرئيسي.
/// ===============================================================

class GoogleScanner {
  static Future<List<String>?> scan() async {
    DocumentScanner? scanner;

    try {
      scanner =
          DocumentScanner(
        options:
            DocumentScannerOptions(
          documentFormats: {
            DocumentFormat.jpeg,
          },
          mode:
              ScannerMode.filter,
          pageLimit: 10,
          isGalleryImport: true,
        ),
      );

      final result =
          await scanner.scanDocument();

      if (result.images == null ||
          result.images!.isEmpty) {
        return null;
      }

      return result.images;
    } catch (_) {
      return null;
    } finally {
      if (scanner != null) {
        try {
          scanner.close();
        } catch (_) {}
      }
    }
  }
}
