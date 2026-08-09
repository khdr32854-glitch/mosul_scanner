import 'dart:math' as math;
import 'dart:typed_data';

import 'package:image/image.dart' as img;
import 'package:google_mlkit_document_scanner/google_mlkit_document_scanner.dart';

/// ===============================================================
/// MOSUL SCANNER - CROP ENGINE
/// ===============================================================
///
/// النسخة:
/// 3.0
///
/// الهدف:
/// - Auto Crop قوي
/// - التعامل مع الحواف الضعيفة
/// - التعامل مع الخلفيات المختلفة
/// - Perspective Correction
/// - Manual Crop
/// - Google ML Kit Scanner
/// - عدم إظهار فشل لمجرد أن الحواف ضعيفة
///
/// ===============================================================

/// ===============================================================
/// GOOGLE DOCUMENT SCANNER
/// ===============================================================

class GoogleScanner {
  static Future<List<String>> scan() async {
    final scanner = DocumentScanner(
      options: DocumentScannerOptions(
        documentFormats: const <DocumentFormat>{
          DocumentFormat.jpeg,
        },
        pageLimit: 20,
        mode: ScannerMode.full,
        isGalleryImport: true,
      ),
    );

    try {
      final result = await scanner.scanDocument();

      return List<String>.from(
        result.images ?? const <String>[],
      );
    } finally {
      await scanner.close();
    }
  }
}

/// ===============================================================
/// IMAGE UTILITIES
/// ===============================================================

class ImageUtils {
  static img.Image? decodeBytes(dynamic bytes) {
    try {
      if (bytes is Uint8List) {
        return img.decodeImage(bytes);
      }

      if (bytes is List<int>) {
        return img.decodeImage(
          Uint8List.fromList(bytes),
        );
      }

      return null;
    } catch (_) {
      return null;
    }
  }

  static List<int> encodeJpg(
    img.Image source, {
    int quality = 92,
  }) {
    final safeQuality =
        quality.clamp(1, 100).toInt();

    try {
      return img.encodeJpg(
        source,
        quality: safeQuality,
      );
    } catch (_) {
      return <int>[];
    }
  }

  static Uint8List encodeJpgBytes(
    img.Image source, {
    int quality = 92,
  }) {
    return Uint8List.fromList(
      encodeJpg(
        source,
        quality: quality,
      ),
    );
  }

  static bool isValid(img.Image? image) {
    if (image == null) {
      return false;
    }

    return image.width >= 10 &&
        image.height >= 10;
  }

  static img.Image clone(img.Image image) {
    return img.Image.from(image);
  }
}

/// ===============================================================
/// ENHANCE
/// ===============================================================

enum EnhanceMode {
  none,
  soft,
  bw,
}

class ImageEnhancer {
  static img.Image apply(
    img.Image source,
    EnhanceMode mode,
  ) {
    final image = source.clone();

    switch (mode) {
      case EnhanceMode.none:
        return image;

      case EnhanceMode.soft:
        return _soft(image);

      case EnhanceMode.bw:
        return _blackWhite(image);
    }
  }

  static img.Image _soft(img.Image image) {
    try {
      return img.adjustColor(
        image,
        contrast: 1.12,
        brightness: 1.04,
        saturation: 1.03,
      );
    } catch (_) {
      return image;
    }
  }

  static img.Image _blackWhite(img.Image image) {
    try {
      final gray = img.grayscale(image);

      return img.adjustColor(
        gray,
        contrast: 1.22,
        brightness: 1.03,
      );
    } catch (_) {
      return image;
    }
  }
}

/// ===============================================================
/// CROP RESULT
/// ===============================================================

class CropResult {
  final img.Image image;

  final bool changed;

  final double confidence;

  const CropResult({
    required this.image,
    required this.changed,
    required this.confidence,
  });
}

/// ===============================================================
/// INTERNAL POINT
/// ===============================================================

class _Point {
  final double x;
  final double y;

  const _Point(
    this.x,
    this.y,
  );
}

/// ===============================================================
/// INTERNAL LINE
/// ===============================================================

class _Line {
  final double a;
  final double b;

  const _Line(
    this.a,
    this.b,
  );

  double y(double x) {
    return a * x + b;
  }
}

/// ===============================================================
/// CROP CANDIDATE
/// ===============================================================

class _CropCandidate {
  final List<double> corners;

  final double score;

  final String source;

  const _CropCandidate({
    required this.corners,
    required this.score,
    required this.source,
  });
}

/// ===============================================================
/// SMART CROP
/// ===============================================================

class SmartCrop {
  /// صورة التحليل صغيرة حتى تبقى السرعة عالية.
  static const int _analysisSize = 760;

  /// أقل مساحة مقبولة.
  static const double _minArea = 0.12;

  /// =============================================================
  /// AUTO CROP
  /// =============================================================

  static CropResult detect(
    img.Image source,
  ) {
    if (!ImageUtils.isValid(source)) {
      return CropResult(
        image: source.clone(),
        changed: false,
        confidence: 0,
      );
    }

    final candidates =
        <_CropCandidate>[];

    /// -----------------------------------------------------------
    /// 1. كشف الحواف والخطوط
    /// -----------------------------------------------------------

    final detected =
        detectCorners(source);

    if (detected != null &&
        _validateNormalizedCorners(
          detected,
        )) {
      candidates.add(
        _CropCandidate(
          corners: detected,
          score: 0.95,
          source: 'edge',
        ),
      );
    }

    /// -----------------------------------------------------------
    /// 2. كشف المستند عن طريق اختلاف الخلفية
    /// -----------------------------------------------------------

    final foreground =
        _findBestForegroundBox(
      source,
    );

    if (foreground != null) {
      candidates.add(
        _CropCandidate(
          corners: foreground,
          score: 0.82,
          source: 'foreground',
        ),
      );
    }

    /// -----------------------------------------------------------
    /// 3. كشف صندوق المستند عن طريق projection
    /// -----------------------------------------------------------

    final projection =
        _projectionBox(
      source,
    );

    if (projection != null) {
      candidates.add(
        _CropCandidate(
          corners: projection,
          score: 0.76,
          source: 'projection',
        ),
      );
    }

    /// -----------------------------------------------------------
    /// 4. اختيار أفضل نتيجة
    /// -----------------------------------------------------------

    if (candidates.isNotEmpty) {
      candidates.sort(
        (
          a,
          b,
        ) =>
            b.score.compareTo(
          a.score,
        ),
      );

      final best =
          candidates.first;

      final result =
          ManualCrop.cropPerspective(
        source,
        best.corners[0],
        best.corners[1],
        best.corners[2],
        best.corners[3],
        best.corners[4],
        best.corners[5],
        best.corners[6],
        best.corners[7],
      );

      final changed =
          result.width != source.width ||
          result.height != source.height;

      return CropResult(
        image: result,
        changed: changed,
        confidence: best.score,
      );
    }

    /// -----------------------------------------------------------
    /// 5. آخر حل
    ///
    /// لا نرجع null.
    /// لا نقول للمستخدم:
    /// "لم يتم اكتشاف حدود واضحة".
    ///
    /// نرجع الصورة مع هامش صغير جدًا.
    /// -----------------------------------------------------------

    final fallback =
        _fullImageSafeCrop(
      source,
    );

    final result =
        ManualCrop.cropPerspective(
      source,
      fallback[0],
      fallback[1],
      fallback[2],
      fallback[3],
      fallback[4],
      fallback[5],
      fallback[6],
      fallback[7],
    );

    return CropResult(
      image: result,
      changed:
          result.width != source.width ||
          result.height != source.height,
      confidence: 0.25,
    );
  }

  /// =============================================================
  /// DETECT CORNERS
  /// =============================================================

  static List<double>? detectCorners(
    img.Image source,
  ) {
    if (!ImageUtils.isValid(source)) {
      return null;
    }

    final scale = math.min(
      1.0,
      _analysisSize /
          math.max(
            source.width,
            source.height,
          ),
    );

    final small =
        scale < 1.0
            ? img.copyResize(
                source,
                width: math.max(
                  1,
                  (source.width * scale)
                      .round(),
                ),
                height: math.max(
                  1,
                  (source.height * scale)
                      .round(),
                ),
              )
            : source.clone();

    final w = small.width;
    final h = small.height;

    if (w < 80 || h < 80) {
      return null;
    }

    final topPoints =
        <_Point>[];

    final bottomPoints =
        <_Point>[];

    final leftPoints =
        <_Point>[];

    final rightPoints =
        <_Point>[];

    const samples = 100;

    /// threshold أفضل من النسخة القديمة.
    final threshold =
        _edgeThreshold(
      small,
    );

    /// -----------------------------------------------------------
    /// TOP / BOTTOM
    /// -----------------------------------------------------------

    for (
      int i = 0;
      i < samples;
      i++
    ) {
      final x =
          ((i + 0.5) *
                  w /
                  samples)
              .round()
              .clamp(
                3,
                w - 4,
              );

      /// TOP
      var bestTopScore =
          0.0;

      var bestTopY =
          (h * 0.04)
              .round();

      final topStart =
          (h * 0.015)
              .round();

      final topEnd =
          (h * 0.48)
              .round();

      for (
        int y = topStart;
        y <= topEnd;
        y++
      ) {
        final edge =
            _verticalEdge(
          small,
          x,
          y,
        );

        /// نعطي أفضلية للحواف القريبة من الخارج.
        final positionWeight =
            1.0 +
                ((topEnd - y) /
                        topEnd) *
                    0.35;

        final score =
            edge *
                positionWeight;

        if (score >
            bestTopScore) {
          bestTopScore =
              score;

          bestTopY = y;
        }
      }

      if (bestTopScore >=
          threshold) {
        topPoints.add(
          _Point(
            x.toDouble(),
            bestTopY.toDouble(),
          ),
        );
      }

      /// BOTTOM
      var bestBottomScore =
          0.0;

      var bestBottomY =
          (h * 0.96)
              .round();

      final bottomStart =
          (h * 0.52)
              .round();

      final bottomEnd =
          (h * 0.985)
              .round();

      for (
        int y = bottomStart;
        y <= bottomEnd;
        y++
      ) {
        final edge =
            _verticalEdge(
          small,
          x,
          y,
        );

        final positionWeight =
            1.0 +
                ((y - bottomStart) /
                        math.max(
                          1,
                          bottomEnd -
                              bottomStart,
                        )) *
                    0.35;

        final score =
            edge *
                positionWeight;

        if (score >
            bestBottomScore) {
          bestBottomScore =
              score;

          bestBottomY = y;
        }
      }

      if (bestBottomScore >=
          threshold) {
        bottomPoints.add(
          _Point(
            x.toDouble(),
            bestBottomY.toDouble(),
          ),
        );
      }
    }

    /// -----------------------------------------------------------
    /// LEFT / RIGHT
    /// -----------------------------------------------------------

    for (
      int i = 0;
      i < samples;
      i++
    ) {
      final y =
          ((i + 0.5) *
                  h /
                  samples)
              .round()
              .clamp(
                3,
                h - 4,
              );

      /// LEFT
      var bestLeftScore =
          0.0;

      var bestLeftX =
          (w * 0.04)
              .round();

      final leftStart =
          (w * 0.015)
              .round();

      final leftEnd =
          (w * 0.48)
              .round();

      for (
        int x = leftStart;
        x <= leftEnd;
        x++
      ) {
        final edge =
            _horizontalEdge(
          small,
          x,
          y,
        );

        final positionWeight =
            1.0 +
                ((leftEnd - x) /
                        leftEnd) *
                    0.35;

        final score =
            edge *
                positionWeight;

        if (score >
            bestLeftScore) {
          bestLeftScore =
              score;

          bestLeftX = x;
        }
      }

      if (bestLeftScore >=
          threshold) {
        leftPoints.add(
          _Point(
            bestLeftX.toDouble(),
            y.toDouble(),
          ),
        );
      }

      /// RIGHT
      var bestRightScore =
          0.0;

      var bestRightX =
          (w * 0.96)
              .round();

      final rightStart =
          (w * 0.52)
              .round();

      final rightEnd =
          (w * 0.985)
              .round();

      for (
        int x = rightStart;
        x <= rightEnd;
        x++
      ) {
        final edge =
            _horizontalEdge(
          small,
          x,
          y,
        );

        final positionWeight =
            1.0 +
                ((x - rightStart) /
                        math.max(
                          1,
                          rightEnd -
                              rightStart,
                        )) *
                    0.35;

        final score =
            edge *
                positionWeight;

        if (score >
            bestRightScore) {
          bestRightScore =
              score;

          bestRightX = x;
        }
      }

      if (bestRightScore >=
          threshold) {
        rightPoints.add(
          _Point(
            bestRightX.toDouble(),
            y.toDouble(),
          ),
        );
      }
    }

    /// -----------------------------------------------------------
    /// نحتاج عدد معقول من النقاط
    /// -----------------------------------------------------------

    if (topPoints.length < 12 ||
        bottomPoints.length < 12 ||
        leftPoints.length < 12 ||
        rightPoints.length < 12) {
      return null;
    }

    final top =
        _fitHorizontal(
      topPoints,
      w,
      h,
      upper: true,
    );

    final bottom =
        _fitHorizontal(
      bottomPoints,
      w,
      h,
      upper: false,
    );

    final left =
        _fitVertical(
      leftPoints,
      w,
      h,
      leftSide: true,
    );

    final right =
        _fitVertical(
      rightPoints,
      w,
      h,
      leftSide: false,
    );

    if (top == null ||
        bottom == null ||
        left == null ||
        right == null) {
      return null;
    }

    final tl =
        _intersect(
      top,
      left,
    );

    final tr =
        _intersect(
      top,
      right,
    );

    final br =
        _intersect(
      bottom,
      right,
    );

    final bl =
        _intersect(
      bottom,
      left,
    );

    if (tl == null ||
        tr == null ||
        br == null ||
        bl == null) {
      return null;
    }

    final normalized =
        <double>[
      tl.x / w,
      tl.y / h,

      tr.x / w,
      tr.y / h,

      br.x / w,
      br.y / h,

      bl.x / w,
      bl.y / h,
    ];

    if (!_validateNormalizedCorners(
      normalized,
    )) {
      return null;
    }

    return normalized;
  }

  /// =============================================================
  /// EDGE THRESHOLD
  /// =============================================================

  static double _edgeThreshold(
    img.Image image,
  ) {
    final values =
        <double>[];

    final stepX =
        math.max(
      1,
      image.width ~/ 36,
    );

    final stepY =
        math.max(
      1,
      image.height ~/ 36,
    );

    for (
      int y = 3;
      y < image.height - 3;
      y += stepY
    ) {
      for (
        int x = 3;
        x < image.width - 3;
        x += stepX
      ) {
        values.add(
          _verticalEdge(
            image,
            x,
            y,
          ),
        );

        values.add(
          _horizontalEdge(
            image,
            x,
            y,
          ),
        );
      }
    }

    if (values.isEmpty) {
      return 8;
    }

    values.sort();

    final median =
        values[
          values.length ~/ 2
        ];

    final p75 =
        values[
          ((values.length - 1) *
                  0.75)
              .round()
        ];

    /// لا نجعل threshold عاليًا جدًا.
    return math.max(
      6.0,
      math.min(
        42.0,
        math.max(
          median * 1.45,
          p75 * 0.48,
        ),
      ),
    );
  }

  /// =============================================================
  /// VERTICAL EDGE
  /// =============================================================

  static double _verticalEdge(
    img.Image image,
    int x,
    int y,
  ) {
    final a =
        _lum(
      image.getPixel(
        x,
        y - 2,
      ),
    );

    final b =
        _lum(
      image.getPixel(
        x,
        y + 2,
      ),
    );

    final c =
        _lum(
      image.getPixel(
        x,
        y - 1,
      ),
    );

    final d =
        _lum(
      image.getPixel(
        x,
        y + 1,
      ),
    );

    return ((a - b).abs() * 0.65) +
        ((c - d).abs() * 0.35);
  }

  /// =============================================================
  /// HORIZONTAL EDGE
  /// =============================================================

  static double _horizontalEdge(
    img.Image image,
    int x,
    int y,
  ) {
    final a =
        _lum(
      image.getPixel(
        x - 2,
        y,
      ),
    );

    final b =
        _lum(
      image.getPixel(
        x + 2,
        y,
      ),
    );

    final c =
        _lum(
      image.getPixel(
        x - 1,
        y,
      ),
    );

    final d =
        _lum(
      image.getPixel(
        x + 1,
        y,
      ),
    );

    return ((a - b).abs() * 0.65) +
        ((c - d).abs() * 0.35);
  }

  static double _lum(
    img.Pixel p,
  ) {
    return 0.2126 * p.r +
        0.7152 * p.g +
        0.0722 * p.b;
  }

  /// =============================================================
  /// FIT HORIZONTAL
  /// =============================================================

  static _Line? _fitHorizontal(
    List<_Point> points,
    int width,
    int height, {
    required bool upper,
  }) {
    if (points.length < 8) {
      return null;
    }

    _Line? best;

    int bestInliers = 0;

    double bestError =
        double.infinity;

    final maxIterations =
        math.min(
      220,
      points.length * 4,
    );

    for (
      int i = 0;
      i < maxIterations;
      i++
    ) {
      final p1 =
          points[
            (i * 7) %
                points.length
          ];

      final p2 =
          points[
            (i * 19 + 3) %
                points.length
          ];

      if ((p1.x - p2.x).abs() <
          width * 0.10) {
        continue;
      }

      final a =
          (p2.y - p1.y) /
              (p2.x - p1.x);

      /// لا نقبل ميلان عمودي.
      if (a.abs() > 0.75) {
        continue;
      }

      final b =
          p1.y - a * p1.x;

      int inliers = 0;

      double error = 0;

      for (final p in points) {
        final predicted =
            a * p.x + b;

        final distance =
            (predicted - p.y)
                .abs();

        final tolerance =
            math.max(
          3.0,
          height * 0.014,
        );

        if (distance <= tolerance) {
          inliers++;

          error += distance;
        }
      }

      if (inliers > bestInliers ||
          (inliers == bestInliers &&
              error < bestError)) {
        bestInliers = inliers;

        bestError = error;

        best =
            _Line(
          a,
          b,
        );
      }
    }

    if (best == null) {
      return null;
    }

    if (bestInliers <
        math.max(
          8,
          (points.length * 0.20)
              .round(),
        )) {
      return null;
    }

    /// التأكد أن الخط في المنطقة الصحيحة.
    final yCenter =
        best.y(
          width / 2,
        );

    if (upper &&
        yCenter > height * 0.58) {
      return null;
    }

    if (!upper &&
        yCenter < height * 0.42) {
      return null;
    }

    return best;
  }

  /// =============================================================
  /// FIT VERTICAL
  /// =============================================================

  static _Line? _fitVertical(
    List<_Point> points,
    int width,
    int height, {
    required bool leftSide,
  }) {
    if (points.length < 8) {
      return null;
    }

    _Line? best;

    int bestInliers = 0;

    double bestError =
        double.infinity;

    final maxIterations =
        math.min(
      220,
      points.length * 4,
    );

    for (
      int i = 0;
      i < maxIterations;
      i++
    ) {
      final p1 =
          points[
            (i * 7) %
                points.length
          ];

      final p2 =
          points[
            (i * 17 + 5) %
                points.length
          ];

      if ((p1.y - p2.y).abs() <
          height * 0.10) {
        continue;
      }

      final a =
          (p2.x - p1.x) /
              (p2.y - p1.y);

      if (a.abs() > 0.75) {
        continue;
      }

      final b =
          p1.x - a * p1.y;

      int inliers = 0;

      double error = 0;

      for (final p in points) {
        final predicted =
            a * p.y + b;

        final distance =
            (predicted - p.x)
                .abs();

        final tolerance =
            math.max(
          3.0,
          width * 0.014,
        );

        if (distance <= tolerance) {
          inliers++;

          error += distance;
        }
      }

      if (inliers > bestInliers ||
          (inliers == bestInliers &&
              error < bestError)) {
        bestInliers = inliers;

        bestError = error;

        best =
            _Line(
          a,
          b,
        );
      }
    }

    if (best == null) {
      return null;
    }

    if (bestInliers <
        math.max(
          8,
          (points.length * 0.20)
              .round(),
        )) {
      return null;
    }

    final xCenter =
        best.y(
          height / 2,
        );

    if (leftSide &&
        xCenter > width * 0.58) {
      return null;
    }

    if (!leftSide &&
        xCenter < width * 0.42) {
      return null;
    }

    return best;
  }

  /// =============================================================
  /// INTERSECTION
  /// =============================================================

  static _Point? _intersect(
    _Line horizontal,
    _Line vertical,
  ) {
    final ah =
        horizontal.a;

    final bh =
        horizontal.b;

    final av =
        vertical.a;

    final bv =
        vertical.b;

    final denominator =
        1.0 - av * ah;

    if (denominator.abs() <
        0.000001) {
      return null;
    }

    final x =
        (av * bh + bv) /
            denominator;

    final y =
        ah * x + bh;

    if (!x.isFinite ||
        !y.isFinite) {
      return null;
    }

    return _Point(
      x,
      y,
    );
  }

  /// =============================================================
  /// VALIDATE CORNERS
  /// =============================================================

  static bool _validateNormalizedCorners(
    List<double> p,
  ) {
    if (p.length != 8) {
      return false;
    }

    for (final value in p) {
      if (!value.isFinite ||
          value < -0.12 ||
          value > 1.12) {
        return false;
      }
    }

    final tl =
        _Point(
      p[0],
      p[1],
    );

    final tr =
        _Point(
      p[2],
      p[3],
    );

    final br =
        _Point(
      p[4],
      p[5],
    );

    final bl =
        _Point(
      p[6],
      p[7],
    );

    final area =
        _polygonArea([
      tl,
      tr,
      br,
      bl,
    ]);

    if (area < _minArea) {
      return false;
    }

    final topWidth =
        _distance(
      tl,
      tr,
    );

    final bottomWidth =
        _distance(
      bl,
      br,
    );

    final leftHeight =
        _distance(
      tl,
      bl,
    );

    final rightHeight =
        _distance(
      tr,
      br,
    );

    if (topWidth < 0.10 ||
        bottomWidth < 0.10 ||
        leftHeight < 0.10 ||
        rightHeight < 0.10) {
      return false;
    }

    final ratio1 =
        topWidth /
            math.max(
              0.001,
              leftHeight,
            );

    final ratio2 =
        bottomWidth /
            math.max(
              0.001,
              rightHeight,
            );

    if (ratio1 < 0.12 ||
        ratio1 > 9.0 ||
        ratio2 < 0.12 ||
        ratio2 > 9.0) {
      return false;
    }

    return true;
  }

  /// =============================================================
  /// FOREGROUND DETECTION
  ///
  /// هذه النسخة أهم من الموجودة عندك.
  ///
  /// لا يوجد شرط الـ 0.49 القديم الذي كان يرفض
  /// المستند الموجود في منتصف الصورة.
  /// =============================================================

  static List<double>? _findBestForegroundBox(
    img.Image source,
  ) {
    final scale =
        math.min(
      1.0,
      720 /
          math.max(
            source.width,
            source.height,
          ),
    );

    final image =
        scale < 1.0
            ? img.copyResize(
                source,
                width: math.max(
                  1,
                  (source.width *
                          scale)
                      .round(),
                ),
                height: math.max(
                  1,
                  (source.height *
                          scale)
                      .round(),
                ),
              )
            : source.clone();

    final w =
        image.width;

    final h =
        image.height;

    if (w < 50 ||
        h < 50) {
      return null;
    }

    final bg =
        _estimateBackground(
      image,
    );

    final thresholds =
        <double>[
      10,
      15,
      20,
      25,
      32,
      40,
    ];

    List<double>? best;

    double bestScore =
        -double.infinity;

    for (final threshold
        in thresholds) {
      final box =
          _findBoxWithThreshold(
        image,
        bg,
        threshold,
      );

      if (box == null) {
        continue;
      }

      final corners =
          _boxToNormalized(
        box,
        w,
        h,
      );

      if (!_validateNormalizedCorners(
        corners,
      )) {
        continue;
      }

      final area =
          _polygonArea([
        _Point(
          corners[0],
          corners[1],
        ),
        _Point(
          corners[2],
          corners[3],
        ),
        _Point(
          corners[4],
          corners[5],
        ),
        _Point(
          corners[6],
          corners[7],
        ),
      ]);

      /// الأفضل أن يكون المستند كبيرًا،
      /// لكن ليس الصورة كلها.
      double score = area;

      if (area > 0.96) {
        score -= 0.25;
      }

      if (area > 0.90) {
        score -= 0.08;
      }

      if (score > bestScore) {
        bestScore = score;

        best = corners;
      }
    }

    return best;
  }

  /// =============================================================
  /// BACKGROUND ESTIMATION
  /// =============================================================

  static _Rgb _estimateBackground(
    img.Image image,
  ) {
    final values =
        <_Rgb>[];

    final w =
        image.width;

    final h =
        image.height;

    final step =
        math.max(
      1,
      math.min(w, h) ~/ 25,
    );

    /// الحواف الخارجية فقط.
    for (
      int x = 0;
      x < w;
      x += step
    ) {
      values.add(
        _pixelRgb(
          image.getPixel(
            x,
            1,
          ),
        ),
      );

      values.add(
        _pixelRgb(
          image.getPixel(
            x,
            h - 2,
          ),
        ),
      );
    }

    for (
      int y = 0;
      y < h;
      y += step
    ) {
      values.add(
        _pixelRgb(
          image.getPixel(
            1,
            y,
          ),
        ),
      );

      values.add(
        _pixelRgb(
          image.getPixel(
            w - 2,
            y,
          ),
        ),
      );
    }

    if (values.isEmpty) {
      return const _Rgb(
        128,
        128,
        128,
      );
    }

    final rs =
        values.map((e) => e.r).toList();

    final gs =
        values.map((e) => e.g).toList();

    final bs =
        values.map((e) => e.b).toList();

    rs.sort();
    gs.sort();
    bs.sort();

    return _Rgb(
      rs[rs.length ~/ 2],
      gs[gs.length ~/ 2],
      bs[bs.length ~/ 2],
    );
  }

  /// =============================================================
  /// FIND BOX WITH THRESHOLD
  /// =============================================================

  static List<int>? _findBoxWithThreshold(
    img.Image image,
    _Rgb background,
    double threshold,
  ) {
    final w =
        image.width;

    final h =
        image.height;

    final step =
        math.max(
      1,
      math.min(w, h) ~/ 220,
    );

    int minX = w;

    int minY = h;

    int maxX = -1;

    int maxY = -1;

    for (
      int y = 2;
      y < h - 2;
      y += step
    ) {
      for (
        int x = 2;
        x < w - 2;
        x += step
      ) {
        final pixel =
            _pixelRgb(
          image.getPixel(
            x,
            y,
          ),
        );

        final distance =
            _colorDistance(
          pixel,
          background,
        );

        if (distance >
            threshold) {
          if (x < minX) {
            minX = x;
          }

          if (y < minY) {
            minY = y;
          }

          if (x > maxX) {
            maxX = x;
          }

          if (y > maxY) {
            maxY = y;
          }
        }
      }
    }

    if (maxX <= minX ||
        maxY <= minY) {
      return null;
    }

    /// توسيع بسيط حتى لا نقص الورقة.
    final paddingX =
        math.max(
      2,
      ((maxX - minX) *
              0.018)
          .round(),
    );

    final paddingY =
        math.max(
      2,
      ((maxY - minY) *
              0.018)
          .round(),
    );

    minX =
        math.max(
      1,
      minX - paddingX,
    );

    minY =
        math.max(
      1,
      minY - paddingY,
    );

    maxX =
        math.min(
      w - 2,
      maxX + paddingX,
    );

    maxY =
        math.min(
      h - 2,
      maxY + paddingY,
    );

    final area =
        ((maxX - minX) *
            (maxY - minY)) /
        (w * h);

    if (area < 0.10) {
      return null;
    }

    return <int>[
      minX,
      minY,
      maxX,
      maxY,
    ];
  }

  /// =============================================================
  /// PROJECTION BOX
  ///
  /// مفيد عندما لا توجد حافة قوية ولكن يوجد اختلاف واضح
  /// بين الخلفية والمستند.
  /// =============================================================

  static List<double>? _projectionBox(
    img.Image source,
  ) {
    final scale =
        math.min(
      1.0,
      680 /
          math.max(
            source.width,
            source.height,
          ),
    );

    final image =
        scale < 1.0
            ? img.copyResize(
                source,
                width: math.max(
                  1,
                  (source.width *
                          scale)
                      .round(),
                ),
                height: math.max(
                  1,
                  (source.height *
                          scale)
                      .round(),
                ),
              )
            : source.clone();

    final w =
        image.width;

    final h =
        image.height;

    final bg =
        _estimateBackground(
      image,
    );

    final col =
        List<double>.filled(
      w,
      0,
    );

    final row =
        List<double>.filled(
      h,
      0,
    );

    final sampleStep =
        math.max(
      1,
      math.min(w, h) ~/ 100,
    );

    for (
      int y = 0;
      y < h;
      y += sampleStep
    ) {
      for (
        int x = 0;
        x < w;
        x += sampleStep
      ) {
        final p =
            _pixelRgb(
          image.getPixel(
            x,
            y,
          ),
        );

        final d =
            _colorDistance(
          p,
          bg,
        );

        row[y] += d;
        col[x] += d;
      }
    }

    final smoothRow =
        _smooth(
      row,
      math.max(
        2,
        h ~/ 70,
      ),
    );

    final smoothCol =
        _smooth(
      col,
      math.max(
        2,
        w ~/ 70,
      ),
    );

    final top =
        _findProjectionBoundary(
      smoothRow,
      fromStart: true,
    );

    final bottom =
        _findProjectionBoundary(
      smoothRow,
      fromStart: false,
    );

    final left =
        _findProjectionBoundary(
      smoothCol,
      fromStart: true,
    );

    final right =
        _findProjectionBoundary(
      smoothCol,
      fromStart: false,
    );

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

    final corners =
        <double>[
      left / w,
      top / h,

      right / w,
      top / h,

      right / w,
      bottom / h,

      left / w,
      bottom / h,
    ];

    if (!_validateNormalizedCorners(
      corners,
    )) {
      return null;
    }

    return corners;
  }

  /// =============================================================
  /// PROJECTION BOUNDARY
  /// =============================================================

  static int? _findProjectionBoundary(
    List<double> values, {
    required bool fromStart,
  }) {
    if (values.length < 10) {
      return null;
    }

    final sorted =
        List<double>.from(values)
          ..sort();

    final reference =
        sorted[
          ((sorted.length - 1) *
                  0.35)
              .round()
        ];

    final threshold =
        math.max(
      reference * 1.20,
      reference + 4,
    );

    if (fromStart) {
      for (
        int i = 3;
        i < values.length * 0.60;
        i++
      ) {
        if (values[i] >
            threshold) {
          return i;
        }
      }
    } else {
      for (
        int i = values.length - 4;
        i > values.length * 0.40;
        i--
      ) {
        if (values[i] >
            threshold) {
          return i;
        }
      }
    }

    return null;
  }

  /// =============================================================
  /// SMOOTH
  /// =============================================================

  static List<double> _smooth(
    List<double> values,
    int radius,
  ) {
    if (values.isEmpty) {
      return <double>[];
    }

    final result =
        List<double>.filled(
      values.length,
      0,
    );

    for (
      int i = 0;
      i < values.length;
      i++
    ) {
      final start =
          math.max(
        0,
        i - radius,
      );

      final end =
          math.min(
        values.length - 1,
        i + radius,
      );

      double sum = 0;

      int count = 0;

      for (
        int j = start;
        j <= end;
        j++
      ) {
        sum += values[j];
        count++;
      }

      result[i] =
          sum / count;
    }

    return result;
  }

  /// =============================================================
  /// BOX TO NORMALIZED
  /// =============================================================

  static List<double> _boxToNormalized(
    List<int> box,
    int width,
    int height,
  ) {
    final left =
        box[0] / width;

    final top =
        box[1] / height;

    final right =
        box[2] / width;

    final bottom =
        box[3] / height;

    return <double>[
      left,
      top,

      right,
      top,

      right,
      bottom,

      left,
      bottom,
    ];
  }

  /// =============================================================
  /// LAST SAFE CROP
  ///
  /// مهم جدًا:
  /// لا نرجع null.
  /// =============================================================

  static List<double> _fullImageSafeCrop(
    img.Image source,
  ) {
    /// هامش صغير جدًا.
    ///
    /// الهدف:
    /// إذا فشل كل شيء، لا نخرب الصورة.
    const margin = 0.008;

    return <double>[
      margin,
      margin,

      1.0 - margin,
      margin,

      1.0 - margin,
      1.0 - margin,

      margin,
      1.0 - margin,
    ];
  }

  /// =============================================================
  /// RGB
  /// =============================================================

  static _Rgb _pixelRgb(
    img.Pixel p,
  ) {
    return _Rgb(
      p.r.toDouble(),
      p.g.toDouble(),
      p.b.toDouble(),
    );
  }

  static double _colorDistance(
    _Rgb a,
    _Rgb b,
  ) {
    final dr =
        a.r - b.r;

    final dg =
        a.g - b.g;

    final db =
        a.b - b.b;

    return math.sqrt(
      dr * dr +
          dg * dg +
          db * db,
    );
  }

  /// =============================================================
  /// POLYGON AREA
  /// =============================================================

  static double _polygonArea(
    List<_Point> points,
  ) {
    double sum = 0;

    for (
      int i = 0;
      i < points.length;
      i++
    ) {
      final j =
          (i + 1) %
              points.length;

      sum +=
          points[i].x *
              points[j].y -
          points[j].x *
              points[i].y;
    }

    return sum.abs() / 2;
  }

  /// =============================================================
  /// DISTANCE
  /// =============================================================

  static double _distance(
    _Point a,
    _Point b,
  ) {
    final dx =
        a.x - b.x;

    final dy =
        a.y - b.y;

    return math.sqrt(
      dx * dx +
          dy * dy,
    );
  }
}

/// ===============================================================
/// RGB
/// ===============================================================

class _Rgb {
  final double r;
  final double g;
  final double b;

  const _Rgb(
    this.r,
    this.g,
    this.b,
  );
}

/// ===============================================================
/// MANUAL CROP
/// ===============================================================

class ManualCrop {
  /// =============================================================
  /// PERSPECTIVE CROP
  ///
  /// الترتيب:
  /// TL
  /// TR
  /// BR
  /// BL
  /// =============================================================

  static img.Image cropPerspective(
    img.Image source,
    double x1,
    double y1,
    double x2,
    double y2,
    double x3,
    double y3,
    double x4,
    double y4,
  ) {
    if (!ImageUtils.isValid(source)) {
      return source.clone();
    }

    final points =
        <_Point>[
      _Point(
        x1.clamp(
          0.0,
          1.0,
        ),
        y1.clamp(
          0.0,
          1.0,
        ),
      ),
      _Point(
        x2.clamp(
          0.0,
          1.0,
        ),
        y2.clamp(
          0.0,
          1.0,
        ),
      ),
      _Point(
        x3.clamp(
          0.0,
          1.0,
        ),
        y3.clamp(
          0.0,
          1.0,
        ),
      ),
      _Point(
        x4.clamp(
          0.0,
          1.0,
        ),
        y4.clamp(
          0.0,
          1.0,
        ),
      ),
    ];

    final tl =
        _Point(
      points[0].x *
          source.width,
      points[0].y *
          source.height,
    );

    final tr =
        _Point(
      points[1].x *
          source.width,
      points[1].y *
          source.height,
    );

    final br =
        _Point(
      points[2].x *
          source.width,
      points[2].y *
          source.height,
    );

    final bl =
        _Point(
      points[3].x *
          source.width,
      points[3].y *
          source.height,
    );

    final quad =
        <_Point>[
      tl,
      tr,
      br,
      bl,
    ];

    if (!_validQuad(
      quad,
    )) {
      return source.clone();
    }

    final topWidth =
        _distance(
      tl,
      tr,
    );

    final bottomWidth =
        _distance(
      bl,
      br,
    );

    final leftHeight =
        _distance(
      tl,
      bl,
    );

    final rightHeight =
        _distance(
      tr,
      br,
    );

    int outWidth =
        math.max(
      1,
      ((topWidth +
                  bottomWidth) /
              2)
          .round(),
    );

    int outHeight =
        math.max(
      1,
      ((leftHeight +
                  rightHeight) /
              2)
          .round(),
    );

    /// لا نسمح بإخراج ضخم جدًا.
    const maxDimension =
        3200;

    final longest =
        math.max(
      outWidth,
      outHeight,
    );

    if (longest >
        maxDimension) {
      final factor =
          maxDimension /
              longest;

      outWidth =
          math.max(
        1,
        (outWidth * factor)
            .round(),
      );

      outHeight =
          math.max(
        1,
        (outHeight * factor)
            .round(),
      );
    }

    final homography =
        _computeHomography(
      quad,
      <_Point>[
        const _Point(
          0,
          0,
        ),
        _Point(
          outWidth - 1,
          0,
        ),
        _Point(
          outWidth - 1,
          outHeight - 1,
        ),
        _Point(
          0,
          outHeight - 1,
        ),
      ],
    );

    if (homography ==
        null) {
      return source.clone();
    }

    final inverse =
        _invertHomography(
      homography,
    );

    if (inverse == null) {
      return source.clone();
    }

    final output =
        img.Image(
      width: outWidth,
      height: outHeight,
      numChannels: 3,
    );

    for (
      int y = 0;
      y < outHeight;
      y++
    ) {
      for (
        int x = 0;
        x < outWidth;
        x++
      ) {
        final mapped =
            _mapPoint(
          inverse,
          x.toDouble(),
          y.toDouble(),
        );

        if (mapped ==
            null) {
          output.setPixelRgb(
            x,
            y,
            255,
            255,
            255,
          );

          continue;
        }

        final sx =
            mapped.x;

        final sy =
            mapped.y;

        if (sx < 0 ||
            sy < 0 ||
            sx >
                source.width -
                    1 ||
            sy >
                source.height -
                    1) {
          output.setPixelRgb(
            x,
            y,
            255,
            255,
            255,
          );

          continue;
        }

        final pixel =
            source.getPixelCubic(
          sx,
          sy,
        );

        output.setPixelRgb(
          x,
          y,
          pixel.r,
          pixel.g,
          pixel.b,
        );
      }
    }

    return output;
  }

  /// =============================================================
  /// VALID QUAD
  /// =============================================================

  static bool _validQuad(
    List<_Point> p,
  ) {
    if (p.length != 4) {
      return false;
    }

    final area =
        _area(p);

    if (area <
        1.0) {
      return false;
    }

    final signs =
        <double>[];

    for (
      int i = 0;
      i < 4;
      i++
    ) {
      final a = p[i];

      final b =
          p[
            (i + 1) % 4
          ];

      final c =
          p[
            (i + 2) % 4
          ];

      final cross =
          (b.x - a.x) *
                  (c.y - b.y) -
              (b.y - a.y) *
                  (c.x - b.x);

      signs.add(
        cross,
      );
    }

    final positive =
        signs.any(
      (v) => v > 0,
    );

    final negative =
        signs.any(
      (v) => v < 0,
    );

    if (positive &&
        negative) {
      return false;
    }

    return true;
  }

  /// =============================================================
  /// AREA
  /// =============================================================

  static double _area(
    List<_Point> p,
  ) {
    double value = 0;

    for (
      int i = 0;
      i < p.length;
      i++
    ) {
      final j =
          (i + 1) %
              p.length;

      value +=
          p[i].x *
              p[j].y -
          p[j].x *
              p[i].y;
    }

    return value.abs() / 2;
  }

  /// =============================================================
  /// HOMOGRAPHY
  /// =============================================================

  static List<double>? _computeHomography(
    List<_Point> src,
    List<_Point> dst,
  ) {
    if (src.length != 4 ||
        dst.length != 4) {
      return null;
    }

    final matrix =
        List.generate(
      8,
      (_) =>
          List<double>.filled(
        9,
        0,
      ),
    );

    for (
      int i = 0;
      i < 4;
      i++
    ) {
      final x =
          src[i].x;

      final y =
          src[i].y;

      final u =
          dst[i].x;

      final v =
          dst[i].y;

      final r =
          i * 2;

      matrix[r][0] = x;
      matrix[r][1] = y;
      matrix[r][2] = 1;

      matrix[r][6] =
          -u * x;

      matrix[r][7] =
          -u * y;

      matrix[r][8] = u;

      matrix[r + 1][3] =
          x;

      matrix[r + 1][4] =
          y;

      matrix[r + 1][5] =
          1;

      matrix[r + 1][6] =
          -v * x;

      matrix[r + 1][7] =
          -v * y;

      matrix[r + 1][8] =
          v;
    }

    /// Gaussian elimination
    for (
      int col = 0;
      col < 8;
      col++
    ) {
      int pivot =
          col;

      for (
        int row = col + 1;
        row < 8;
        row++
      ) {
        if (matrix[row][col]
                .abs() >
            matrix[pivot][col]
                .abs()) {
          pivot = row;
        }
      }

      if (matrix[pivot][col]
              .abs() <
          1e-10) {
        return null;
      }

      if (pivot != col) {
        final tmp =
            matrix[pivot];

        matrix[pivot] =
            matrix[col];

        matrix[col] =
            tmp;
      }

      final divisor =
          matrix[col][col];

      for (
        int j = col;
        j <= 8;
        j++
      ) {
        matrix[col][j] /=
            divisor;
      }

      for (
        int row = 0;
        row < 8;
        row++
      ) {
        if (row == col) {
          continue;
        }

        final factor =
            matrix[row][col];

        if (factor.abs() <
            1e-12) {
          continue;
        }

        for (
          int j = col;
          j <= 8;
          j++
        ) {
          matrix[row][j] -=
              factor *
                  matrix[col][j];
        }
      }
    }

    return <double>[
      matrix[0][8],
      matrix[1][8],
      matrix[2][8],
      matrix[3][8],
      matrix[4][8],
      matrix[5][8],
      matrix[6][8],
      matrix[7][8],
      1,
    ];
  }

  /// =============================================================
  /// INVERSE HOMOGRAPHY
  /// =============================================================

  static List<double>? _invertHomography(
    List<double> h,
  ) {
    final a = h[0];
    final b = h[1];
    final c = h[2];

    final d = h[3];
    final e = h[4];
    final f = h[5];

    final g = h[6];
    final i = h[7];
    final j = h[8];

    final A =
        e * j - f * i;

    final B =
        -(d * j - f * g);

    final C =
        d * i - e * g;

    final D =
        -(b * j - c * i);

    final E =
        a * j - c * g;

    final F =
        -(a * i - b * g);

    final G =
        b * f - c * e;

    final H =
        -(a * f - c * d);

    final I =
        a * e - b * d;

    final determinant =
        a * A +
            b * B +
            c * C;

    if (determinant.abs() <
        1e-12) {
      return null;
    }

    return <double>[
      A / determinant,
      D / determinant,
      G / determinant,

      B / determinant,
      E / determinant,
      H / determinant,

      C / determinant,
      F / determinant,
      I / determinant,
    ];
  }

  /// =============================================================
  /// MAP POINT
  /// =============================================================

  static _Point? _mapPoint(
    List<double> h,
    double x,
    double y,
  ) {
    final denominator =
        h[6] * x +
            h[7] * y +
            h[8];

    if (denominator.abs() <
        1e-10) {
      return null;
    }

    final nx =
        h[0] * x +
            h[1] * y +
            h[2];

    final ny =
        h[3] * x +
            h[4] * y +
            h[5];

    final resultX =
        nx / denominator;

    final resultY =
        ny / denominator;

    if (!resultX.isFinite ||
        !resultY.isFinite) {
      return null;
    }

    return _Point(
      resultX,
      resultY,
    );
  }

  /// =============================================================
  /// DISTANCE
  /// =============================================================

  static double _distance(
    _Point a,
    _Point b,
  ) {
    final dx =
        a.x - b.x;

    final dy =
        a.y - b.y;

    return math.sqrt(
      dx * dx +
          dy * dy,
    );
  }
}
