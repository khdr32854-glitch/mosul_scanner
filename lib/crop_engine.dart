import 'dart:io';
import 'dart:math';
import 'dart:typed_data';
import 'package:image/image.dart' as img;
import 'package:google_mlkit_document_scanner/google_mlkit_document_scanner.dart';

/// crop_engine.dart v4 — المحرك السريع والخفيف
/// - تحسين LAB (مثل CamScanner)
/// - قص بسيط وسريع (بدون خوارزميات ثقيلة)
/// - جاهز لإضافة Google ML Kit لاحقاً

class CropResult {
  final img.Image image;
  final bool changed;
  const CropResult({required this.image, required this.changed});
}

enum EnhanceMode { none, soft, bw }

/// ═══════════════════════════════════════
/// تحسين LAB — مثل CamScanner تماماً
/// ═══════════════════════════════════════
class ImageEnhancer {
  /// تحسين ناعم باستخدام LAB color space
  static img.Image enhance(img.Image src) {
    try {
      return _enhanceLab(src);
    } catch (_) {
      // fallback: simple adjust
      return img.adjustColor(src, brightness: 1.05, contrast: 1.15);
    }
  }

  /// تحسين LAB حقيقي — يزيد التباين والوضوح
  static img.Image _enhanceLab(img.Image src) {
    // 1. Convert RGB to LAB manually (simplified but effective)
    final w = src.width, h = src.height;
    final result = img.Image(width: w, height: h);

    // 2. Apply unsharp mask for sharpening
    final blurred = img.gaussianBlur(src, radius: 1);

    for (int y = 0; y < h; y++) {
      for (int x = 0; x < w; x++) {
        final p = src.getPixel(x, y);
        final bp = blurred.getPixel(x, y);

        // Unsharp mask: original + (original - blurred) * amount
        final amount = 0.3;
        int r = (p.r + (p.r - bp.r) * amount).round().clamp(0, 255);
        int g = (p.g + (p.g - bp.g) * amount).round().clamp(0, 255);
        int b = (p.b + (p.b - bp.b) * amount).round().clamp(0, 255);

        // Boost contrast in LAB-like space
        final L = (0.299 * r + 0.587 * g + 0.114 * b);
        final Lboost = ((L - 128) * 1.2 + 128).clamp(0, 255);

        // Adjust colors based on luminance boost ratio
        final ratio = L > 0 ? Lboost / L : 1.0;
        r = (r * ratio).round().clamp(0, 255);
        g = (g * ratio).round().clamp(0, 255);
        b = (b * ratio).round().clamp(0, 255);

        result.setPixelRgba(x, y, r, g, b, p.a.toInt());
      }
    }
    return result;
  }

  /// أبيض وأسود واضح
  static img.Image blackWhite(img.Image src) {
    var r = img.grayscale(src);
    // زيادة التباين
    r = img.adjustColor(r, brightness: 0.0, contrast: 1.5);
    return r;
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
/// قص تلقائي — بسيط وسريع
/// ═══════════════════════════════════════
class SmartCrop {
  /// طريقة سريعة: edge density + projections
  static CropResult detect(img.Image src) {
    if (src.width < 100 || src.height < 100) return CropResult(image: src, changed: false);

    // تصغير للتحليل (128px — سريع جداً)
    const target = 128;
    final ratio = max(src.width, src.height) / target;
    final sw = (src.width / ratio).round();
    final sh = (src.height / ratio).round();
    final small = img.copyResize(src, width: sw, height: sh);

    // Grayscale
    final gray = img.grayscale(small);

    // حساب edge density لكل صف وعمود
    final hp = _rowEdgeDensity(gray);
    final vp = _colEdgeDensity(gray);

    // إيجاد حدود المستند
    final maxH = hp.reduce(max);
    final maxV = vp.reduce(max);
    if (maxH < 3 || maxV < 3) return CropResult(image: src, changed: false);

    final thH = maxH * 0.12;
    final thV = maxV * 0.12;

    int? t, b, l, r;
    for (int y = 0; y < sh; y++) if (hp[y] >= thH) { t = y; break; }
    for (int y = sh - 1; y >= 0; y--) if (hp[y] >= thH) { b = y; break; }
    for (int x = 0; x < sw; x++) if (vp[x] >= thV) { l = x; break; }
    for (int x = sw - 1; x >= 0; x--) if (vp[x] >= thV) { r = x; break; }

    if (t == null || b == null || l == null || r == null) return CropResult(image: src, changed: false);
    if (r - l < 15 || b - t < 15) return CropResult(image: src, changed: false);

    // تحويل إلى الإحداثيات الأصلية
    final pad = 4.0;
    final ox = ((l - pad) * ratio).round().clamp(0, src.width - 1);
    final oy = ((t - pad) * ratio).round().clamp(0, src.height - 1);
    final ow = ((r - l + pad * 2) * ratio).round().clamp(20, src.width - ox);
    final oh = ((b - t + pad * 2) * ratio).round().clamp(20, src.height - oy);

    final ca = ow * oh, sa = src.width * src.height;
    if (ca < sa * 0.03 || ca > sa * 0.97) return CropResult(image: src, changed: false);

    return CropResult(image: img.copyCrop(src, x: ox, y: oy, width: ow, height: oh), changed: true);
  }

  /// كثافة الحواف الأفقية
  static List<int> _rowEdgeDensity(img.Image gray) {
    final w = gray.width, h = gray.height;
    final hp = List.filled(h, 0);
    for (int y = 1; y < h - 1; y++) {
      int sum = 0;
      for (int x = 1; x < w - 1; x++) {
        final dy = (gray.getPixel(x, y + 1).r.toInt() - gray.getPixel(x, y - 1).r.toInt()).abs();
        if (dy > 20) sum++;
      }
      hp[y] = sum;
    }
    return hp;
  }

  /// كثافة الحواف العمودية
  static List<int> _colEdgeDensity(img.Image gray) {
    final w = gray.width, h = gray.height;
    final vp = List.filled(w, 0);
    for (int x = 1; x < w - 1; x++) {
      int sum = 0;
      for (int y = 1; y < h - 1; y++) {
        final dx = (gray.getPixel(x + 1, y).r.toInt() - gray.getPixel(x - 1, y).r.toInt()).abs();
        if (dx > 20) sum++;
      }
      vp[x] = sum;
    }
    return vp;
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
  /// التحقق من توفر Google ML Kit على الجهاز
  static Future<bool> isAvailable() async {
    try {
      return await DocumentScanner.isGooglePlayServicesAvailable();
    } catch (_) {
      return false;
    }
  }

  /// فتح ماسح Google الرسمي — يُرجع قائمة بمسارات الصور الممسوحة
  static Future<List<String>?> scan() async {
    try {
      final available = await DocumentScanner.isGooglePlayServicesAvailable();
      if (!available) return null;

      final scanner = DocumentScanner(
        options: DocumentScannerOptions(
          documentFormat: DocumentFormat.jpeg,
          mode: ScannerMode.filter,
          pageLimit: 10,
          isGalleryImport: true,
        ),
      );

      final result = await scanner.scanDocument();
      if (result == null || result.images.isEmpty) return null;

      // نسخ الصور إلى ملفات مؤقتة
      final paths = <String>[];
      for (final img in result.images) {
        final bytes = await img.filePath != null
            ? await File(img.filePath!).readAsBytes()
            : img.bytes;
        if (bytes == null) continue;

        final tmpPath = '${Directory.systemTemp.path}/google_scan_${DateTime.now().millisecondsSinceEpoch}_${paths.length}.jpg';
        await File(tmpPath).writeAsBytes(bytes);
        paths.add(tmpPath);
      }

      return paths.isNotEmpty ? paths : null;
    } catch (_) {
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
