import 'dart:math' as math;
import 'dart:typed_data';

import 'package:image/image.dart' as img;
import 'package:google_mlkit_document_scanner/google_mlkit_document_scanner.dart';

/// ===============================================================
/// MOSUL SCANNER - CROP ENGINE
/// Version: 2.0
///
/// الوظائف:
/// 1. قص تلقائي محافظ على كامل المستند.
/// 2. كشف زوايا المستند.
/// 3. تصحيح Perspective / الميلان.
/// 4. قص يدوي بأربع نقاط.
/// 5. تحسين الصورة.
/// 6. أبيض وأسود.
/// 7. أدوات فك وترميز JPEG.
/// 8. Google ML Kit Document Scanner wrapper.
/// ===============================================================

/// ===============================================================
/// Google Scanner
/// ===============================================================

class GoogleScanner {
  static Future<List<String>> scan() async {
    final scanner = DocumentScanner(
      options: const DocumentScannerOptions(
        documentFormats: <DocumentFormat>{
          DocumentFormat.jpeg,
        },
        pageLimit: 20,
        mode: ScannerMode.full,
        isGalleryImport: true,
      ),
    );

    try {
      final result = await scanner.scanDocument();
      return List<String>.from(result.images ?? const <String>[]);
    } finally {
      await scanner.close();
    }
  }
}

/// ===============================================================
/// Image Utilities
/// ===============================================================

class ImageUtils {
  /// فك صورة من bytes.
  static img.Image? decodeBytes(dynamic bytes) {
    try {
      if (bytes is Uint8List) {
        return img.decodeImage(bytes);
      }

      if (bytes is List<int>) {
        return img.decodeImage(Uint8List.fromList(bytes));
      }

      return null;
    } catch (_) {
      return null;
    }
  }

  /// ترميز JPEG.
  static List<int> encodeJpg(
    img.Image src, {
    int quality = 92,
  }) {
    final safeQuality = quality.clamp(1, 100).toInt();

    try {
      return img.encodeJpg(
        src,
        quality: safeQuality,
      );
    } catch (_) {
      return <int>[];
    }
  }

  /// ترميز JPEG إلى Uint8List.
  static Uint8List encodeJpgBytes(
    img.Image src, {
    int quality = 92,
  }) {
    return Uint8List.fromList(
      encodeJpg(
        src,
        quality: quality,
      ),
    );
  }

  /// التحقق من الصورة.
  static bool isValid(img.Image? image) {
    if (image == null) return false;

    return image.width >= 10 &&
        image.height >= 10;
  }

  /// نسخ آمن.
  static img.Image clone(img.Image image) {
    return img.Image.from(image);
  }
}

/// ===============================================================
/// Enhance
/// ===============================================================

enum EnhanceMode {
  none,
  soft,
  bw,
}

/// ===============================================================
/// Image Enhancer
/// ===============================================================

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

  /// تحسين ناعم:
  /// - رفع بسيط للتباين
  /// - تحسين الإضاءة
  /// - الحفاظ على الألوان
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

  /// أبيض وأسود مناسب للمستندات.
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
/// Crop Result
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
/// Point
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
/// Line
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
/// Smart Crop
/// ===============================================================

class SmartCrop {
  /// الحد الأقصى لحجم صورة التحليل.
  static const int _analysisSize = 720;

  /// الحد الأدنى لمساحة المستند المقبولة.
  static const double _minArea = 0.22;

  /// الحد الأقصى للحواف التي تسمح بالقص.
  static const double _maxMargin = 0.49;

  /// -----------------------------------------------------------
  /// القص التلقائي
  /// -----------------------------------------------------------
  static CropResult detect(img.Image source) {
    if (!ImageUtils.isValid(source)) {
      return CropResult(
        image: source.clone(),
        changed: false,
        confidence: 0,
      );
    }

    final corners = detectCorners(source);

    if (corners == null) {
      return CropResult(
        image: source.clone(),
        changed: false,
        confidence: 0,
      );
    }

    final result = ManualCrop.cropPerspective(
      source,
      corners[0],
      corners[1],
      corners[2],
      corners[3],
      corners[4],
      corners[5],
      corners[6],
      corners[7],
    );

    final changed =
        result.width != source.width ||
        result.height != source.height;

    return CropResult(
      image: result,
      changed: changed,
      confidence: 0.86,
    );
  }

  /// -----------------------------------------------------------
  /// كشف الزوايا
  ///
  /// يرجع:
  ///
  /// TL.x, TL.y,
  /// TR.x, TR.y,
  /// BR.x, BR.y,
  /// BL.x, BL.y
  ///
  /// القيم normalized من 0 إلى 1.
  /// -----------------------------------------------------------
  static List<double>? detectCorners(img.Image source) {
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

    final small = scale < 1.0
        ? img.copyResize(
            source,
            width: math.max(
              1,
              (source.width * scale).round(),
            ),
            height: math.max(
              1,
              (source.height * scale).round(),
            ),
          )
        : source.clone();

    final w = small.width;
    final h = small.height;

    if (w < 80 || h < 80) {
      return null;
    }

    /// نقاط الحواف الأفقية.
    final topPoints = <_Point>[];
    final bottomPoints = <_Point>[];

    /// نقاط الحواف العمودية.
    final leftPoints = <_Point>[];
    final rightPoints = <_Point>[];

    const samples = 90;

    final threshold = _edgeThreshold(
      small,
    );

    for (int i = 0; i < samples; i++) {
      final x = ((i + 0.5) * w / samples)
          .round()
          .clamp(2, w - 3);

      /// TOP
      var bestTopScore = 0.0;
      var bestTopY = 0;

      final topStart = (h * 0.025).round();
      final topEnd = (h * 0.62).round();

      for (int y = topStart; y <= topEnd; y++) {
        final score = _verticalEdge(
          small,
          x,
          y,
        );

        if (score > bestTopScore) {
          bestTopScore = score;
          bestTopY = y;
        }
      }

      if (bestTopScore >= threshold) {
        topPoints.add(
          _Point(
            x.toDouble(),
            bestTopY.toDouble(),
          ),
        );
      }

      /// BOTTOM
      var bestBottomScore = 0.0;
      var bestBottomY = h - 1;

      final bottomStart = (h * 0.38).round();
      final bottomEnd = (h * 0.975).round();

      for (int y = bottomStart; y <= bottomEnd; y++) {
        final score = _verticalEdge(
          small,
          x,
          y,
        );

        if (score > bestBottomScore) {
          bestBottomScore = score;
          bestBottomY = y;
        }
      }

      if (bestBottomScore >= threshold) {
        bottomPoints.add(
          _Point(
            x.toDouble(),
            bestBottomY.toDouble(),
          ),
        );
      }
    }

    for (int i = 0; i < samples; i++) {
      final y = ((i + 0.5) * h / samples)
          .round()
          .clamp(2, h - 3);

      /// LEFT
      var bestLeftScore = 0.0;
      var bestLeftX = 0;

      final leftStart = (w * 0.025).round();
      final leftEnd = (w * 0.62).round();

      for (int x = leftStart; x <= leftEnd; x++) {
        final score = _horizontalEdge(
          small,
          x,
          y,
        );

        if (score > bestLeftScore) {
          bestLeftScore = score;
          bestLeftX = x;
        }
      }

      if (bestLeftScore >= threshold) {
        leftPoints.add(
          _Point(
            bestLeftX.toDouble(),
            y.toDouble(),
          ),
        );
      }

      /// RIGHT
      var bestRightScore = 0.0;
      var bestRightX = w - 1;

      final rightStart = (w * 0.38).round();
      final rightEnd = (w * 0.975).round();

      for (int x = rightStart; x <= rightEnd; x++) {
        final score = _horizontalEdge(
          small,
          x,
          y,
        );

        if (score > bestRightScore) {
          bestRightScore = score;
          bestRightX = x;
        }
      }

      if (bestRightScore >= threshold) {
        rightPoints.add(
          _Point(
            bestRightX.toDouble(),
            y.toDouble(),
          ),
        );
      }
    }

    if (topPoints.length < 18 ||
        bottomPoints.length < 18 ||
        leftPoints.length < 18 ||
        rightPoints.length < 18) {
      return _safeRectangleFallback(
        small,
        source,
        scale,
      );
    }

    final top = _fitHorizontal(
      topPoints,
      w,
      h,
      upper: true,
    );

    final bottom = _fitHorizontal(
      bottomPoints,
      w,
      h,
      upper: false,
    );

    final left = _fitVertical(
      leftPoints,
      w,
      h,
      leftSide: true,
    );

    final right = _fitVertical(
      rightPoints,
      w,
      h,
      leftSide: false,
    );

    if (top == null ||
        bottom == null ||
        left == null ||
        right == null) {
      return _safeRectangleFallback(
        small,
        source,
        scale,
      );
    }

    final tl = _intersect(
      top,
      left,
    );

    final tr = _intersect(
      top,
      right,
    );

    final br = _intersect(
      bottom,
      right,
    );

    final bl = _intersect(
      bottom,
      left,
    );

    if (tl == null ||
        tr == null ||
        br == null ||
        bl == null) {
      return _safeRectangleFallback(
        small,
        source,
        scale,
      );
    }

    final normalized = <double>[
      tl.x / w,
      tl.y / h,
      tr.x / w,
      tr.y / h,
      br.x / w,
      br.y / h,
      bl.x / w,
      bl.y / h,
    ];

    if (!_validateNormalizedCorners(normalized)) {
      return _safeRectangleFallback(
        small,
        source,
        scale,
      );
    }

    /// تحويل الزوايا من التحليل إلى الصورة الأصلية لا نحتاجه
    /// لأن ManualCrop يستقبل normalized coordinates.
    return normalized;
  }

  /// -----------------------------------------------------------
  /// حساب threshold للحواف
  /// -----------------------------------------------------------
  static double _edgeThreshold(img.Image image) {
    final values = <double>[];

    final stepX = math.max(
      1,
      image.width ~/ 40,
    );

    final stepY = math.max(
      1,
      image.height ~/ 40,
    );

    for (int y = 2; y < image.height - 2; y += stepY) {
      for (int x = 2; x < image.width - 2; x += stepX) {
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
      return 12;
    }

    values.sort();

    final median =
        values[values.length ~/ 2];

    return math.max(
      10.0,
      median * 1.8,
    );
  }

  /// -----------------------------------------------------------
  /// Vertical edge
  /// -----------------------------------------------------------
  static double _verticalEdge(
    img.Image image,
    int x,
    int y,
  ) {
    final a = _lum(
      image.getPixel(
        x,
        y - 2,
      ),
    );

    final b = _lum(
      image.getPixel(
        x,
        y + 2,
      ),
    );

    return (a - b).abs();
  }

  /// -----------------------------------------------------------
  /// Horizontal edge
  /// -----------------------------------------------------------
  static double _horizontalEdge(
    img.Image image,
    int x,
    int y,
  ) {
    final a = _lum(
      image.getPixel(
        x - 2,
        y,
      ),
    );

    final b = _lum(
      image.getPixel(
        x + 2,
        y,
      ),
    );

    return (a - b).abs();
  }

  static double _lum(img.Pixel p) {
    return 0.2126 * p.r +
        0.7152 * p.g +
        0.0722 * p.b;
  }

  /// -----------------------------------------------------------
  /// Fit horizontal line
  /// -----------------------------------------------------------
  static _Line? _fitHorizontal(
    List<_Point> points,
    int width,
    int height, {
    required bool upper,
  }) {
    if (points.length < 10) {
      return null;
    }

    _Line? best;
    int bestInliers = 0;

    final maxIterations =
        math.min(
          160,
          points.length * 3,
        );

    for (int i = 0; i < maxIterations; i++) {
      final p1 = points[
        (i * 7) % points.length
      ];

      final p2 = points[
        (i * 13 + 11) % points.length
      ];

      if ((p1.x - p2.x).abs() < width * 0.08) {
        continue;
      }

      final a =
          (p2.y - p1.y) /
          (p2.x - p1.x);

      if (a.abs() > 0.65) {
        continue;
      }

      final b = p1.y - a * p1.x;

      int inliers = 0;

      for (final p in points) {
        final predicted =
            a * p.x + b;

        if ((predicted - p.y).abs() <=
            math.max(2.5, height * 0.012)) {
          inliers++;
        }
      }

      if (inliers > bestInliers) {
        bestInliers = inliers;

        best = _Line(
          a,
          b,
        );
      }
    }

    if (best == null ||
        bestInliers < points.length * 0.22) {
      return null;
    }

    return best;
  }

  /// -----------------------------------------------------------
  /// Fit vertical line
  /// -----------------------------------------------------------
  static _Line? _fitVertical(
    List<_Point> points,
    int width,
    int height, {
    required bool leftSide,
  }) {
    if (points.length < 10) {
      return null;
    }

    _Line? best;
    int bestInliers = 0;

    final maxIterations =
        math.min(
          160,
          points.length * 3,
        );

    for (int i = 0; i < maxIterations; i++) {
      final p1 = points[
        (i * 7) % points.length
      ];

      final p2 = points[
        (i * 13 + 17) % points.length
      ];

      if ((p1.y - p2.y).abs() < height * 0.08) {
        continue;
      }

      final a =
          (p2.x - p1.x) /
          (p2.y - p1.y);

      if (a.abs() > 0.65) {
        continue;
      }

      final b = p1.x - a * p1.y;

      int inliers = 0;

      for (final p in points) {
        final predicted =
            a * p.y + b;

        if ((predicted - p.x).abs() <=
            math.max(2.5, width * 0.012)) {
          inliers++;
        }
      }

      if (inliers > bestInliers) {
        bestInliers = inliers;

        best = _Line(
          a,
          b,
        );
      }
    }

    if (best == null ||
        bestInliers < points.length * 0.22) {
      return null;
    }

    return best;
  }

  /// -----------------------------------------------------------
  /// Line intersection
  /// -----------------------------------------------------------
  static _Point? _intersect(
    _Line horizontal,
    _Line vertical,
  ) {
    /// y = ah*x + bh
    /// x = av*y + bv

    final ah = horizontal.a;
    final bh = horizontal.b;

    final av = vertical.a;
    final bv = vertical.b;

    final denominator =
        1.0 - av * ah;

    if (denominator.abs() < 0.000001) {
      return null;
    }

    final x =
        (av * bh + bv) /
        denominator;

    final y =
        ah * x + bh;

    if (!x.isFinite || !y.isFinite) {
      return null;
    }

    return _Point(
      x,
      y,
    );
  }

  /// -----------------------------------------------------------
  /// Validation
  /// -----------------------------------------------------------
  static bool _validateNormalizedCorners(
    List<double> p,
  ) {
    if (p.length != 8) {
      return false;
    }

    for (final v in p) {
      if (!v.isFinite ||
          v < -0.05 ||
          v > 1.05) {
        return false;
      }
    }

    final tl = _Point(
      p[0],
      p[1],
    );

    final tr = _Point(
      p[2],
      p[3],
    );

    final br = _Point(
      p[4],
      p[5],
    );

    final bl = _Point(
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

    final widthTop =
        _distance(
          tl,
          tr,
        );

    final widthBottom =
        _distance(
          bl,
          br,
        );

    final heightLeft =
        _distance(
          tl,
          bl,
        );

    final heightRight =
        _distance(
          tr,
          br,
        );

    if (widthTop < 0.12 ||
        widthBottom < 0.12 ||
        heightLeft < 0.12 ||
        heightRight < 0.12) {
      return false;
    }

    final ratio1 =
        widthTop / heightLeft;

    final ratio2 =
        widthBottom / heightRight;

    if (ratio1 < 0.15 ||
        ratio1 > 8.0 ||
        ratio2 < 0.15 ||
        ratio2 > 8.0) {
      return false;
    }

    return true;
  }

  /// -----------------------------------------------------------
  /// Fallback محافظ
  ///
  /// لا نقص الصورة بشكل عشوائي.
  /// -----------------------------------------------------------
  static List<double>? _safeRectangleFallback(
    img.Image small,
    img.Image source,
    double scale,
  ) {
    final box = _findForegroundBox(
      small,
    );

    if (box == null) {
      return null;
    }

    final left =
        box[0] / small.width;

    final top =
        box[1] / small.height;

    final right =
        box[2] / small.width;

    final bottom =
        box[3] / small.height;

    final result = <double>[
      left,
      top,
      right,
      top,
      right,
      bottom,
      left,
      bottom,
    ];

    if (!_validateNormalizedCorners(result)) {
      return null;
    }

    return result;
  }

  /// -----------------------------------------------------------
  /// Foreground box
  ///
  /// fallback فقط، وليس الاختيار الأول.
  /// -----------------------------------------------------------
  static List<int>? _findForegroundBox(
    img.Image image,
  ) {
    final w = image.width;
    final h = image.height;

    if (w < 50 || h < 50) {
      return null;
    }

    final borderValues = <double>[];

    final borderStep =
        math.max(
          1,
          math.min(w, h) ~/ 50,
        );

    for (
      int x = 0;
      x < w;
      x += borderStep
    ) {
      borderValues.add(
        _lum(
          image.getPixel(
            x,
            0,
          ),
        ),
      );

      borderValues.add(
        _lum(
          image.getPixel(
            x,
            h - 1,
          ),
        ),
      );
    }

    for (
      int y = 0;
      y < h;
      y += borderStep
    ) {
      borderValues.add(
        _lum(
          image.getPixel(
            0,
            y,
          ),
        ),
      );

      borderValues.add(
        _lum(
          image.getPixel(
            w - 1,
            y,
          ),
        ),
      );
    }

    if (borderValues.isEmpty) {
      return null;
    }

    borderValues.sort();

    final bg =
        borderValues[
          borderValues.length ~/ 2
        ];

    final threshold = 22.0;

    int minX = w;
    int minY = h;
    int maxX = -1;
    int maxY = -1;

    final step = math.max(
      1,
      math.min(w, h) ~/ 180,
    );

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
        final l = _lum(
          image.getPixel(
            x,
            y,
          ),
        );

        if ((l - bg).abs() > threshold) {
          minX = math.min(
            minX,
            x,
          );

          minY = math.min(
            minY,
            y,
          );

          maxX = math.max(
            maxX,
            x,
          );

          maxY = math.max(
            maxY,
            y,
          );
        }
      }
    }

    if (maxX <= minX ||
        maxY <= minY) {
      return null;
    }

    final area =
        ((maxX - minX) *
            (maxY - minY)) /
        (w * h);

    if (area < 0.20 ||
        area > 0.99) {
      return null;
    }

    /// لا نسمح fallback بقص قريب جدًا من الحافة
    /// إذا كان الكشف غير واضح.
    if (minX < w * _maxMargin &&
        maxX > w * (1.0 - _maxMargin) &&
        minY < h * _maxMargin &&
        maxY > h * (1.0 - _maxMargin)) {
      return null;
    }

    return <int>[
      minX,
      minY,
      maxX,
      maxY,
    ];
  }

  static double _polygonArea(
    List<_Point> p,
  ) {
    double sum = 0;

    for (int i = 0; i < p.length; i++) {
      final j =
          (i + 1) % p.length;

      sum +=
          p[i].x * p[j].y -
          p[j].x * p[i].y;
    }

    return sum.abs() / 2;
  }

  static double _distance(
    _Point a,
    _Point b,
  ) {
    return math.sqrt(
      math.pow(
            a.x - b.x,
            2,
          ) +
          math.pow(
            a.y - b.y,
            2,
          ),
    );
  }
}

/// ===============================================================
/// Manual Crop
/// ===============================================================

class ManualCrop {
  /// -----------------------------------------------------------
  /// Perspective crop
  ///
  /// x/y normalized من 0 إلى 1.
  ///
  /// الترتيب:
  /// 1 TL
  /// 2 TR
  /// 3 BR
  /// 4 BL
  /// -----------------------------------------------------------
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

    final points = <_Point>[
      _Point(
        x1.clamp(0.0, 1.0),
        y1.clamp(0.0, 1.0),
      ),
      _Point(
        x2.clamp(0.0, 1.0),
        y2.clamp(0.0, 1.0),
      ),
      _Point(
        x3.clamp(0.0, 1.0),
        y3.clamp(0.0, 1.0),
      ),
      _Point(
        x4.clamp(0.0, 1.0),
        y4.clamp(0.0, 1.0),
      ),
    ];

    final tl = _Point(
      points[0].x * source.width,
      points[0].y * source.height,
    );

    final tr = _Point(
      points[1].x * source.width,
      points[1].y * source.height,
    );

    final br = _Point(
      points[2].x * source.width,
      points[2].y * source.height,
    );

    final bl = _Point(
      points[3].x * source.width,
      points[3].y * source.height,
    );

    if (!_validQuad([
      tl,
      tr,
      br,
      bl,
    ])) {
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

    /// حماية من صور ضخمة جدًا.
    const maxDimension = 3200;

    final longest =
        math.max(
          outWidth,
          outHeight,
        );

    if (longest > maxDimension) {
      final factor =
          maxDimension / longest;

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

    /// حساب Homography:
    ///
    /// source -> destination
    final h = _computeHomography(
      <_Point>[
        tl,
        tr,
        br,
        bl,
      ],
      <_Point>[
        const _Point(0, 0),
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

    if (h == null) {
      return source.clone();
    }

    final output = img.Image(
      width: outWidth,
      height: outHeight,
      numChannels: 3,
    );

    /// تحويل inverse:
    /// destination -> source
    final inverse =
        _invertHomography(h);

    if (inverse == null) {
      return source.clone();
    }

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

        if (mapped == null) {
          output.setPixelRgb(
            x,
            y,
            255,
            255,
            255,
          );
          continue;
        }

        final sx = mapped.x;
        final sy = mapped.y;

        if (sx < 0 ||
            sy < 0 ||
            sx > source.width - 1 ||
            sy > source.height - 1) {
          output.setPixelRgb(
            x,
            y,
            255,
            255,
            255,
          );
          continue;
        }

        final p =
            source.getPixelCubic(
          sx,
          sy,
        );

        output.setPixelRgb(
          x,
          y,
          p.r,
          p.g,
          p.b,
        );
      }
    }

    return output;
  }

  /// -----------------------------------------------------------
  /// Quad validation
  /// -----------------------------------------------------------
  static bool _validQuad(
    List<_Point> p,
  ) {
    if (p.length != 4) {
      return false;
    }

    final area =
        _area(p);

    if (area <
        0.01 *
            math.max(
              1,
              _distance(
                p[0],
                p[1],
              ) *
                  _distance(
                    p[1],
                    p[2],
                  ),
            )) {
      return false;
    }

    final signs = <double>[];

    for (int i = 0; i < 4; i++) {
      final a = p[i];
      final b = p[
        (i + 1) % 4
      ];
      final c = p[
        (i + 2) % 4
      ];

      final cross =
          (b.x - a.x) *
              (c.y - b.y) -
          (b.y - a.y) *
              (c.x - b.x);

      signs.add(cross);
    }

    final hasPositive =
        signs.any(
      (v) => v > 0,
    );

    final hasNegative =
        signs.any(
      (v) => v < 0,
    );

    if (hasPositive &&
        hasNegative) {
      return false;
    }

    return true;
  }

  static double _area(
    List<_Point> p,
  ) {
    double value = 0;

    for (int i = 0; i < p.length; i++) {
      final j =
          (i + 1) % p.length;

      value +=
          p[i].x * p[j].y -
          p[j].x * p[i].y;
    }

    return value.abs() / 2;
  }

  /// -----------------------------------------------------------
  /// Homography
  ///
  /// 8 unknowns:
  /// h0..h7
  /// h8 = 1
  /// -----------------------------------------------------------
  static List<double>? _computeHomography(
    List<_Point> src,
    List<_Point> dst,
  ) {
    if (src.length != 4 ||
        dst.length != 4) {
      return null;
    }

    final a =
        List.generate(
      8,
      (_) => List<double>.filled(
        9,
        0,
      ),
    );

    for (int i = 0; i < 4; i++) {
      final x = src[i].x;
      final y = src[i].y;
      final u = dst[i].x;
      final v = dst[i].y;

      final r1 = i * 2;
      final r2 = r1 + 1;

      a[r1][0] = x;
      a[r1][1] = y;
      a[r1][2] = 1;
      a[r1][3] = 0;
      a[r1][4] = 0;
      a[r1][5] = 0;
      a[r1][6] = -u * x;
      a[r1][7] = -u * y;
      a[r1][8] = u;

      a[r2][0] = 0;
      a[r2][1] = 0;
      a[r2][2] = 0;
      a[r2][3] = x;
      a[r2][4] = y;
      a[r2][5] = 1;
      a[r2][6] = -v * x;
      a[r2][7] = -v * y;
      a[r2][8] = v;
    }

    /// Gaussian elimination.
    for (int col = 0; col < 8; col++) {
      int pivot = col;

      for (
        int row = col + 1;
        row < 8;
        row++
      ) {
        if (a[row][col].abs() >
            a[pivot][col].abs()) {
          pivot = row;
        }
      }

      if (a[pivot][col].abs() <
          1e-10) {
        return null;
      }

      if (pivot != col) {
        final tmp = a[pivot];
        a[pivot] = a[col];
        a[col] = tmp;
      }

      final div =
          a[col][col];

      for (
        int j = col;
        j <= 8;
        j++
      ) {
        a[col][j] /= div;
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
            a[row][col];

        if (factor.abs() <
            1e-12) {
          continue;
        }

        for (
          int j = col;
          j <= 8;
          j++
        ) {
          a[row][j] -=
              factor *
                  a[col][j];
        }
      }
    }

    return <double>[
      a[0][8],
      a[1][8],
      a[2][8],
      a[3][8],
      a[4][8],
      a[5][8],
      a[6][8],
      a[7][8],
      1.0,
    ];
  }

  /// -----------------------------------------------------------
  /// Invert 3x3 Homography
  /// -----------------------------------------------------------
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

    final det =
        a * A +
        b * B +
        c * C;

    if (det.abs() < 1e-12) {
      return null;
    }

    final inv = <double>[
      A / det,
      D / det,
      G / det,
      B / det,
      E / det,
      H / det,
      C / det,
      F / det,
      I / det,
    ];

    return inv;
  }

  /// -----------------------------------------------------------
  /// Map point through 3x3 matrix
  /// -----------------------------------------------------------
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

    return _Point(
      nx / denominator,
      ny / denominator,
    );
  }

  static double _distance(
    _Point a,
    _Point b,
  ) {
    return math.sqrt(
      math.pow(
            a.x - b.x,
            2,
          ) +
          math.pow(
            a.y - b.y,
            2,
          ),
    );
  }
}
