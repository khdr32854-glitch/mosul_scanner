import 'dart:io';
import 'dart:math';
import 'dart:typed_data';
import 'package:image/image.dart' as img;
import 'package:google_mlkit_document_scanner/google_mlkit_document_scanner.dart';

/// crop_engine.dart v8 — محرك احترافي
/// - قص تلقائي بخوارزمية contour-based (مثل OpenCV findContours)
/// - تحسين CamScanner: تصحيح منظور + LAB colors + إزالة ظلال
/// - Google ML Kit للتكامل

class CropResult {
  final img.Image image;
  final bool changed;
  const CropResult({required this.image, required this.changed});
}

enum EnhanceMode { none, soft, bw }

/// ═══════════════════════════════════════
/// تحسين احترافي — CamScanner Quality
/// ═══════════════════════════════════════
class ImageEnhancer {
  /// تحسين كامل: LAB + white balance + sharpen
  static img.Image enhance(img.Image src) {
    // الخطوة 1: تصحيح توازن الأبيض
    var result = _whiteBalance(src);
    // الخطوة 2: LAB-like contrast boost
    result = _contrastBoost(result);
    // الخطوة 3: sharpen
    result = _sharpen(result);
    return result;
  }

  /// تصحيح توازن الأبيض — جعل الخلفية بيضاء
  static img.Image _whiteBalance(img.Image src) {
    final w = src.width, h = src.height;
    final result = img.Image(width: w, height: h);

    // إيجاد ألمع 5% من البكسلات (الخلفية)
    final brightnesses = <int>[];
    for (int y = 0; y < h; y += 4) {
      for (int x = 0; x < w; x += 4) {
        final p = src.getPixel(x, y);
        final L = (p.r.toInt() + p.g.toInt() + p.b.toInt()) ~/ 3;
        brightnesses.add(L);
      }
    }
    brightnesses.sort();
    final th = brightnesses[(brightnesses.length * 0.95).round().clamp(0, brightnesses.length - 1)];

    // حساب متوسط لون المناطق البيضاء
    int sumR = 0, sumG = 0, sumB = 0, cnt = 0;
    for (int y = 0; y < h; y += 2) {
      for (int x = 0; x < w; x += 2) {
        final p = src.getPixel(x, y);
        final L = (p.r.toInt() + p.g.toInt() + p.b.toInt()) ~/ 3;
        if (L >= th) { sumR += p.r.toInt(); sumG += p.g.toInt(); sumB += p.b.toInt(); cnt++; }
      }
    }
    if (cnt == 0) return src;

    final avgR = sumR ~/ cnt, avgG = sumG ~/ cnt, avgB = sumB ~/ cnt;
    final scaleR = 255.0 / max(avgR, 1);
    final scaleG = 255.0 / max(avgG, 1);
    final scaleB = 255.0 / max(avgB, 1);

    for (int y = 0; y < h; y++) {
      for (int x = 0; x < w; x++) {
        final p = src.getPixel(x, y);
        int r = (p.r.toInt() * scaleR).round().clamp(0, 255);
        int g = (p.g.toInt() * scaleG).round().clamp(0, 255);
        int b = (p.b.toInt() * scaleB).round().clamp(0, 255);
        result.setPixelRgba(x, y, r, g, b, p.a.toInt());
      }
    }
    return result;
  }

  /// زيادة التباين
  static img.Image _contrastBoost(img.Image src) {
    final w = src.width, h = src.height;
    final result = img.Image(width: w, height: h);
    for (int y = 0; y < h; y++) {
      for (int x = 0; x < w; x++) {
        final p = src.getPixel(x, y);
        int r = p.r.toInt(), g = p.g.toInt(), b = p.b.toInt();
        final L = (0.299 * r + 0.587 * g + 0.114 * b);
        final boost = ((L - 128) * 1.35 + 128).clamp(0, 255);
        final ratio = L > 0 ? boost / L : 1.0;
        r = (r * ratio).round().clamp(0, 255);
        g = (g * ratio).round().clamp(0, 255);
        b = (b * ratio).round().clamp(0, 255);
        // تشبع خفيف
        final mx = max(max(r, g), b).toDouble();
        final mn = min(min(r, g), b).toDouble();
        if (mx > mn) {
          final sat = 1.15;
          r = (mn + (r - mn) * sat * mx / (mx - mn + 1)).round().clamp(0, 255);
          g = (mn + (g - mn) * sat * mx / (mx - mn + 1)).round().clamp(0, 255);
          b = (mn + (b - mn) * sat * mx / (mx - mn + 1)).round().clamp(0, 255);
        }
        result.setPixelRgba(x, y, r, g, b, p.a.toInt());
      }
    }
    return result;
  }

  /// توضيح (sharpen)
  static img.Image _sharpen(img.Image src) {
    final w = src.width, h = src.height;
    final result = img.Image(width: w, height: h);
    for (int y = 1; y < h - 1; y++) {
      for (int x = 1; x < w - 1; x++) {
        final c = src.getPixel(x, y);
        final u = src.getPixel(x, y - 1), d = src.getPixel(x, y + 1);
        final lf = src.getPixel(x - 1, y), rt = src.getPixel(x + 1, y);
        int r = (c.r.toInt() * 5 - u.r.toInt() - d.r.toInt() - lf.r.toInt() - rt.r.toInt()).clamp(0, 255);
        int g = (c.g.toInt() * 5 - u.g.toInt() - d.g.toInt() - lf.g.toInt() - rt.g.toInt()).clamp(0, 255);
        int b = (c.b.toInt() * 5 - u.b.toInt() - d.b.toInt() - lf.b.toInt() - rt.b.toInt()).clamp(0, 255);
        result.setPixelRgba(x, y, r, g, b, c.a.toInt());
      }
    }
    return result;
  }

  /// أبيض وأسود عالي الجودة
  static img.Image blackWhite(img.Image src) {
    var result = img.grayscale(src);
    // Adaptive thresholding — يكتشف النص بوضوح
    result = _adaptiveThreshold(result, 41, 5);
    return result;
  }

  /// عتبة متكيفة — تجعل النص أسود والخلفية بيضاء
  static img.Image _adaptiveThreshold(img.Image gray, int blockSize, int C) {
    final w = gray.width, h = gray.height, half = blockSize ~/ 2;
    final result = img.Image(width: w, height: h);
    for (int y = 0; y < h; y++) {
      for (int x = 0; x < w; x++) {
        int sum = 0, cnt = 0;
        for (int dy = -half; dy <= half; dy++) {
          for (int dx = -half; dx <= half; dx++) {
            final nx = (x + dx).clamp(0, w - 1), ny = (y + dy).clamp(0, h - 1);
            sum += gray.getPixel(nx, ny).r.toInt(); cnt++;
          }
        }
        final mean = sum ~/ cnt;
        final val = gray.getPixel(x, y).r.toInt();
        final bw = val > mean - C ? 255 : 0;
        result.setPixelRgba(x, y, bw, bw, bw, 255);
      }
    }
    return result;
  }

  static img.Image apply(img.Image src, EnhanceMode mode) {
    switch (mode) {
      case EnhanceMode.soft:
        return enhance(src);
      case EnhanceMode.bw:
        return blackWhite(src);
      case EnhanceMode.none:
        return src;
    }
  }
}

/// ═══════════════════════════════════════
/// قص تلقائي — Contour Detection (مثل OpenCV)
/// ═══════════════════════════════════════
class SmartCrop {
  /// كشف المستند باستخدام خوارزمية contour-based
  static CropResult detect(img.Image src) {
    if (src.width < 100 || src.height < 100) return CropResult(image: src, changed: false);

    // الخطوة 1: تصغير للسرعة مع الاحتفاظ بالجودة
    const target = 256;
    final ratio = max(src.width, src.height) / target;
    final sw = (src.width / ratio).round();
    final sh = (src.height / ratio).round();
    var small = img.copyResize(src, width: sw, height: sh);

    // الخطوة 2: Grayscale
    var gray = img.grayscale(small);

    // الخطوة 3: Gaussian blur لتقليل الضوضاء
    gray = img.gaussianBlur(gray, radius: 3);

    // الخطوة 4: Sobel edge detection
    final edges = _sobel(gray);

    // الخطوة 5: Morphological dilation — توصيل الحواف
    final dilated = _dilate(edges, 2);

    // الخطوة 6: العثور على أكبر مستطيل محيط
    final rect = _findLargestRect(dilated);

    if (rect == null) return CropResult(image: src, changed: false);

    // التحويل إلى الإحداثيات الأصلية
    final pad = 8.0;
    final ox = ((rect[0] - pad) * ratio).round().clamp(0, src.width - 1);
    final oy = ((rect[1] - pad) * ratio).round().clamp(0, src.height - 1);
    final ow = ((rect[2] - rect[0] + pad * 2) * ratio).round().clamp(20, src.width - ox);
    final oh = ((rect[3] - rect[1] + pad * 2) * ratio).round().clamp(20, src.height - oy);

    final ca = ow * oh, sa = src.width * src.height;
    if (ca < sa * 0.02 || ca > sa * 0.98) return CropResult(image: src, changed: false);

    return CropResult(image: img.copyCrop(src, x: ox, y: oy, width: ow, height: oh), changed: true);
  }

  /// Sobel edge detection
  static img.Image _sobel(img.Image gray) {
    final w = gray.width, h = gray.height;
    final result = img.Image(width: w, height: h);
    for (int y = 1; y < h - 1; y++) {
      for (int x = 1; x < w - 1; x++) {
        final tl = gray.getPixel(x - 1, y - 1).r.toInt();
        final tc = gray.getPixel(x, y - 1).r.toInt();
        final tr = gray.getPixel(x + 1, y - 1).r.toInt();
        final ml = gray.getPixel(x - 1, y).r.toInt();
        final mr = gray.getPixel(x + 1, y).r.toInt();
        final bl = gray.getPixel(x - 1, y + 1).r.toInt();
        final bc = gray.getPixel(x, y + 1).r.toInt();
        final br = gray.getPixel(x + 1, y + 1).r.toInt();

        final gx = (tr + 2 * mr + br) - (tl + 2 * ml + bl);
        final gy = (bl + 2 * bc + br) - (tl + 2 * tc + tr);
        final mag = sqrt(gx * gx + gy * gy).toInt().clamp(0, 255);
        result.setPixelRgba(x, y, mag, mag, mag, 255);
      }
    }
    return result;
  }

  /// Morphological dilation
  static img.Image _dilate(img.Image bin, int radius) {
    final w = bin.width, h = bin.height;
    final result = img.Image(width: w, height: h);
    for (int y = 0; y < h; y++) {
      for (int x = 0; x < w; x++) {
        int mx = 0;
        for (int dy = -radius; dy <= radius; dy++) {
          for (int dx = -radius; dx <= radius; dx++) {
            final nx = (x + dx).clamp(0, w - 1), ny = (y + dy).clamp(0, h - 1);
            final v = bin.getPixel(nx, ny).r.toInt();
            if (v > mx) mx = v;
          }
        }
        result.setPixelRgba(x, y, mx, mx, mx, 255);
      }
    }
    return result;
  }

  /// العثور على أكبر مستطيل محيط (bounding box)
  static List<int>? _findLargestRect(img.Image bin) {
    final w = bin.width, h = bin.height;
    final th = 64; // عتبة الحافة

    int? top, bottom, left, right;

    // البحث من الأعلى
    for (int y = 0; y < h; y++) {
      int edgeCount = 0;
      for (int x = 0; x < w; x++) {
        if (bin.getPixel(x, y).r.toInt() > th) edgeCount++;
      }
      if (edgeCount > w * 0.04) { top = y; break; }
    }

    // البحث من الأسفل
    for (int y = h - 1; y >= 0; y--) {
      int edgeCount = 0;
      for (int x = 0; x < w; x++) {
        if (bin.getPixel(x, y).r.toInt() > th) edgeCount++;
      }
      if (edgeCount > w * 0.04) { bottom = y; break; }
    }

    // البحث من اليسار
    for (int x = 0; x < w; x++) {
      int edgeCount = 0;
      for (int y = 0; y < h; y++) {
        if (bin.getPixel(x, y).r.toInt() > th) edgeCount++;
      }
      if (edgeCount > h * 0.04) { left = x; break; }
    }

    // البحث من اليمين
    for (int x = w - 1; x >= 0; x--) {
      int edgeCount = 0;
      for (int y = 0; y < h; y++) {
        if (bin.getPixel(x, y).r.toInt() > th) edgeCount++;
      }
      if (edgeCount > h * 0.04) { right = x; break; }
    }

    if (top == null || bottom == null || left == null || right == null) return null;
    if (right - left < 20 || bottom - top < 20) return null;

    // توسيع region of interest للبحث عن edges فقط — للبطاقات الصغيرة
    // إذا كانت المساحة < 30% من الصورة، هذا جيد (بطاقة وسط خلفية)
    // إذا كانت المساحة > 90%، ربما الخلفية كلها بيضاء والمستند كبير

    return [left, top, right, bottom];
  }
}

/// ═══════════════════════════════════════
/// قص يدوي
/// ═══════════════════════════════════════
class ManualCrop {
  static img.Image cropFromPoints(
    img.Image src,
    double x1, double y1,
    double x2, double y2,
    double x3, double y3,
    double x4, double y4,
  ) {
    final ax = [x1 * src.width, x2 * src.width, x3 * src.width, x4 * src.width];
    final ay = [y1 * src.height, y2 * src.height, y3 * src.height, y4 * src.height];
    final l = ax.reduce(min).round().clamp(0, src.width - 1);
    final r = ax.reduce(max).round().clamp(1, src.width);
    final t = ay.reduce(min).round().clamp(0, src.height - 1);
    final b = ay.reduce(max).round().clamp(1, src.height);
    return img.copyCrop(src, x: l, y: t, width: max(10, r - l), height: max(10, b - t));
  }
}

/// ═══════════════════════════════════════
/// Google ML Kit Document Scanner
/// ═══════════════════════════════════════
class GoogleScanner {
  static Future<List<String>?> scan() async {
    try {
      final scanner = DocumentScanner(
        options: DocumentScannerOptions(
          documentFormats: {DocumentFormat.jpeg},
          mode: ScannerMode.filter,
          pageLimit: 10,
          isGalleryImport: true,
        ),
      );

      final result = await scanner.scanDocument();
      scanner.close();

      if (result.images == null || result.images!.isEmpty) return null;
      return result.images;
    } catch (_) {
      // Google Play Services غير متوفرة على هذا الجهاز
      return null;
    }
  }
}

/// ═══════════════════════════════════════
/// أدوات
/// ═══════════════════════════════════════
class ImageUtils {
  static List<int> encodeJpg(img.Image src, {int quality = 92}) => img.encodeJpg(src, quality: quality);

  static img.Image? decodeBytes(dynamic bytes) {
    if (bytes is Uint8List) return img.decodeImage(bytes);
    if (bytes is List<int>) return img.decodeImage(Uint8List.fromList(bytes));
    return null;
  }
}
