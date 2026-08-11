 import 'dart:math' as math;
import 'dart:ui' show Offset;

import 'package:image/image.dart' as img;

/// ===============================================================
/// PERSPECTIVE WARP - تسوية المنظور الحقيقية
/// ===============================================================
///
/// ينفذ تحويل المنظور (Homography) بالكامل بلغة Dart، بدون أي
/// اعتماد على مكتبات أصلية (NDK/C++)، لتحويل شكل رباعي مائل
/// (نتيجة تحديد 4 زوايا يدوياً أو تلقائياً) إلى صورة مستطيلة
/// مسطحة ومصححة تماماً - بنفس مبدأ خاصية "مساواة" في تطبيقات
/// مسح المستندات المعروفة.
///
/// هذا يختلف جوهرياً عن القص العادي (bounding box) الذي كان
/// مستخدماً سابقاً: هنا يتم تصحيح الانحراف الحقيقي الناتج عن
/// زاوية التصوير، وليس فقط اقتصاص مستطيل محيط بالنقاط.
/// ===============================================================

class PerspectiveWarp {
  /// يحوّل الشكل الرباعي [corners] (بالترتيب: أعلى-يسار، أعلى-يمين،
  /// أسفل-يمين، أسفل-يسار) داخل الصورة [source] إلى صورة مستطيلة
  /// مسطحة تماماً.
  ///
  /// ملاحظة: يجب أن تكون [corners] بإحداثيات بكسل حقيقية داخل
  /// [source] (وليست نسباً طبيعية 0..1).
  static img.Image warp(img.Image source, List<Offset> corners) {
    assert(corners.length == 4);

    final topLeft = corners[0];
    final topRight = corners[1];
    final bottomRight = corners[2];
    final bottomLeft = corners[3];

    final widthTop = _distance(topLeft, topRight);
    final widthBottom = _distance(bottomLeft, bottomRight);
    final outWidth =
        math.max(widthTop, widthBottom).round().clamp(10, 6000);

    final heightLeft = _distance(topLeft, bottomLeft);
    final heightRight = _distance(topRight, bottomRight);
    final outHeight =
        math.max(heightLeft, heightRight).round().clamp(10, 6000);

    return _warpPerspective(
      source,
      [topLeft, topRight, bottomRight, bottomLeft],
      outWidth,
      outHeight,
    );
  }

  static double _distance(Offset a, Offset b) {
    final dx = a.dx - b.dx;
    final dy = a.dy - b.dy;
    return math.sqrt(dx * dx + dy * dy);
  }

  /// يبني صورة الوجهة بالحجم [outWidth]x[outHeight]، ولكل بكسل
  /// فيها يحسب البكسل المقابل له داخل [srcQuad] (Inverse Mapping)
  /// عبر استيفاء ثنائي خطي (bilinear) لنتيجة ناعمة بدون تعرّجات.
  static img.Image _warpPerspective(
    img.Image source,
    List<Offset> srcQuad,
    int outWidth,
    int outHeight,
  ) {
    final destImage = img.Image(
      width: outWidth,
      height: outHeight,
      numChannels: source.numChannels,
    );

    final rectCorners = [
      const Offset(0, 0),
      Offset(outWidth - 1, 0),
      Offset(outWidth - 1, outHeight - 1),
      Offset(0, outHeight - 1),
    ];

    // homography تحوّل مباشرة من إحداثيات المستطيل الناتج إلى
    // إحداثيات الشكل الرباعي داخل الصورة الأصلية (Inverse Mapping)،
    // بحيث نمسح كل بكسل ناتج ونجلب مصدره مباشرة بخطوة واحدة.
    final h = _solveHomography(rectCorners, srcQuad);

    final a = h[0], b = h[1], c = h[2];
    final d = h[3], e = h[4], f = h[5];
    final g = h[6], k = h[7];

    for (int oy = 0; oy < outHeight; oy++) {
      for (int ox = 0; ox < outWidth; ox++) {
        final denom = g * ox + k * oy + 1.0;

        if (denom.abs() < 1e-9) {
          continue;
        }

        final sx = (a * ox + b * oy + c) / denom;
        final sy = (d * ox + e * oy + f) / denom;

        final sample = _bilinearSample(source, sx, sy);

        destImage.setPixelRgba(
          ox,
          oy,
          sample[0].round(),
          sample[1].round(),
          sample[2].round(),
          sample[3].round(),
        );
      }
    }

    return destImage;
  }

  static List<double> _bilinearSample(img.Image src, double x, double y) {
    if (x < 0 || y < 0 || x > src.width - 1 || y > src.height - 1) {
      return [255, 255, 255, 0];
    }

    final x0 = x.floor();
    final y0 = y.floor();

    final x1 = math.min(x0 + 1, src.width - 1);
    final y1 = math.min(y0 + 1, src.height - 1);

    final fx = x - x0;
    final fy = y - y0;

    final p00 = src.getPixel(x0, y0);
    final p10 = src.getPixel(x1, y0);
    final p01 = src.getPixel(x0, y1);
    final p11 = src.getPixel(x1, y1);

    double lerp(double v0, double v1, double t) => v0 + (v1 - v0) * t;

    double channel(num c00, num c10, num c01, num c11) {
      final top = lerp(c00.toDouble(), c10.toDouble(), fx);
      final bottom = lerp(c01.toDouble(), c11.toDouble(), fx);
      return lerp(top, bottom, fy);
    }

    return [
      channel(p00.r, p10.r, p01.r, p11.r),
      channel(p00.g, p10.g, p01.g, p11.g),
      channel(p00.b, p10.b, p01.b, p11.b),
      channel(p00.a, p10.a, p01.a, p11.a),
    ];
  }

  /// يحل معادلة homography القياسية (8 مجاهيل) التي تحوّل 4 نقاط
  /// [from] إلى 4 نقاط [to] المقابلة لها، عبر حل نظام معادلات خطي
  /// بطريقة الحذف الغاوسي (Gauss-Jordan) - دون أي مكتبة خارجية.
  static List<double> _solveHomography(
    List<Offset> from,
    List<Offset> to,
  ) {
    // كل صف: 8 معاملات + عمود النتيجة (augmented column) = 9 أعمدة.
    final matrix = List.generate(8, (_) => List<double>.filled(9, 0.0));

    for (int i = 0; i < 4; i++) {
      final x = from[i].dx;
      final y = from[i].dy;
      final u = to[i].dx;
      final v = to[i].dy;

      final rowU = matrix[2 * i];
      rowU[0] = x;
      rowU[1] = y;
      rowU[2] = 1;
      rowU[6] = -x * u;
      rowU[7] = -y * u;
      rowU[8] = u;

      final rowV = matrix[2 * i + 1];
      rowV[3] = x;
      rowV[4] = y;
      rowV[5] = 1;
      rowV[6] = -x * v;
      rowV[7] = -y * v;
      rowV[8] = v;
    }

    return _gaussJordanSolve(matrix);
  }

  static List<double> _gaussJordanSolve(List<List<double>> matrix) {
    const n = 8;

    for (int col = 0; col < n; col++) {
      int pivotRow = col;
      double maxAbs = matrix[col][col].abs();

      for (int r = col + 1; r < n; r++) {
        final value = matrix[r][col].abs();

        if (value > maxAbs) {
          maxAbs = value;
          pivotRow = r;
        }
      }

      if (pivotRow != col) {
        final temp = matrix[col];
        matrix[col] = matrix[pivotRow];
        matrix[pivotRow] = temp;
      }

      final pivot = matrix[col][col];

      if (pivot.abs() < 1e-12) {
        // شكل رباعي شبه منحل هندسياً (نقطتان متطابقتان تقريباً)،
        // نتجاوز هذا العمود لتفادي القسمة على صفر.
        continue;
      }

      for (int c = col; c <= n; c++) {
        matrix[col][c] /= pivot;
      }

      for (int r = 0; r < n; r++) {
        if (r == col) {
          continue;
        }

        final factor = matrix[r][col];

        if (factor == 0) {
          continue;
        }

        for (int c = col; c <= n; c++) {
          matrix[r][c] -= factor * matrix[col][c];
        }
      }
    }

    return List<double>.generate(n, (i) => matrix[i][n]);
  }
}
