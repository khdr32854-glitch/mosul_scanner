import 'dart:math';
import 'dart:typed_data';
import 'package:image/image.dart' as img;

/// crop_engine.dart — محرك القص والتحسين المستقل
/// معزول تماماً. جاهز لإضافة C++ FFI لاحقاً.

class CropResult {
  final img.Image image;
  final bool changed;
  const CropResult({required this.image, required this.changed});
}

enum EnhanceMode { none, soft, bw }

/// تحسين الصور
class ImageEnhancer {
  static img.Image enhance(img.Image src) => img.adjustColor(src, brightness: 1.04, contrast: 1.12);
  static img.Image blackWhite(img.Image src) {
    var r = img.grayscale(src);
    return img.adjustColor(r, brightness: 0.02, contrast: 1.2);
  }
  static img.Image apply(img.Image src, EnhanceMode mode) {
    switch (mode) {
      case EnhanceMode.soft: return enhance(src);
      case EnhanceMode.bw: return blackWhite(src);
      case EnhanceMode.none: return src;
    }
  }
}

/// قص تلقائي
class SmartCrop {
  static CropResult adaptiveThreshold(img.Image src) {
    if (src.width < 50 || src.height < 50) return CropResult(image: src, changed: false);
    final gray = img.grayscale(src);
    final blur = img.gaussianBlur(gray, radius: 3);
    final bin = _adaptiveThreshold(blur, 15, 12);
    final rect = _findCentralRect(bin, src.width, src.height);
    if (rect == null) return CropResult(image: src, changed: false);
    const pad = 8;
    final x = (rect[0] - pad).clamp(0, src.width - 1);
    final y = (rect[1] - pad).clamp(0, src.height - 1);
    final w = (rect[2] - rect[0] + pad * 2).clamp(20, src.width - x);
    final h = (rect[3] - rect[1] + pad * 2).clamp(20, src.height - y);
    final ca = w * h, sa = src.width * src.height;
    if (ca < sa * 0.02 || ca > sa * 0.96) return CropResult(image: src, changed: false);
    return CropResult(image: img.copyCrop(src, x: x, y: y, width: w, height: h), changed: true);
  }

  static CropResult sobelEdges(img.Image src) {
    if (src.width < 50 || src.height < 50) return CropResult(image: src, changed: false);
    const md = 256;
    final ratio = max(src.width, src.height) / md;
    final small = img.copyResize(src, width: (src.width / ratio).round());
    final gray = img.grayscale(small);
    final blur = img.gaussianBlur(gray, radius: 2);
    final edges = _sobelEdges(blur);
    final rect = _findCentralRect(edges, small.width, small.height);
    if (rect == null) return CropResult(image: src, changed: false);
    final l = (rect[0] * ratio).round().clamp(0, src.width - 1);
    final t = (rect[1] * ratio).round().clamp(0, src.height - 1);
    final r = (rect[2] * ratio).round().clamp(1, src.width);
    final b = (rect[3] * ratio).round().clamp(1, src.height);
    final cw = r - l, ch = b - t;
    if (cw < 20 || ch < 20) return CropResult(image: src, changed: false);
    final ca = cw * ch, sa = src.width * src.height;
    if (ca < sa * 0.02 || ca > sa * 0.96) return CropResult(image: src, changed: false);
    return CropResult(image: img.copyCrop(src, x: l, y: t, width: cw, height: ch), changed: true);
  }

  static img.Image _adaptiveThreshold(img.Image gray, int bs, int c) {
    final w = gray.width, h = gray.height, half = bs ~/ 2;
    final dst = img.Image(width: w, height: h);
    for (int y = 0; y < h; y++) {
      for (int x = 0; x < w; x++) {
        int sum = 0, cnt = 0;
        for (int dy = -half; dy <= half; dy++) {
          for (int dx = -half; dx <= half; dx++) {
            final nx = (x + dx).clamp(0, w - 1), ny = (y + dy).clamp(0, h - 1);
            sum += gray.getPixel(nx, ny).r.toInt(); cnt++;
          }
        }
        final mean = sum ~/ cnt, val = gray.getPixel(x, y).r.toInt();
        final bw = val > mean - c ? 255 : 0;
        dst.setPixelRgba(x, y, bw, bw, bw, 255);
      }
    }
    return dst;
  }

  static img.Image _sobelEdges(img.Image gray) {
    final w = gray.width, h = gray.height;
    final e = img.Image(width: w, height: h);
    for (int y = 1; y < h - 1; y++) {
      for (int x = 1; x < w - 1; x++) {
        final a = gray.getPixel(x-1,y-1).r.toInt(), b = gray.getPixel(x,y-1).r.toInt(), c = gray.getPixel(x+1,y-1).r.toInt();
        final d = gray.getPixel(x-1,y).r.toInt(), f = gray.getPixel(x+1,y).r.toInt();
        final g = gray.getPixel(x-1,y+1).r.toInt(), hh = gray.getPixel(x,y+1).r.toInt(), i = gray.getPixel(x+1,y+1).r.toInt();
        final gx = (c+2*f+i)-(a+2*d+g), gy = (g+2*hh+i)-(a+2*b+c);
        final m = sqrt(gx*gx+gy*gy).toInt().clamp(0,255);
        e.setPixelRgba(x,y,m,m,m,255);
      }
    }
    return e;
  }

  static List<int>? _findCentralRect(img.Image bin, int iw, int ih) {
    int wp = 0;
    for (int y = 0; y < ih; y++) for (int x = 0; x < iw; x++) if (bin.getPixel(x,y).r.toInt() > 128) wp++;
    if (wp < iw * ih * 0.01 || wp > iw * ih * 0.99) return null;
    final hp = List.filled(ih, 0), vp = List.filled(iw, 0);
    for (int y = 0; y < ih; y++) for (int x = 0; x < iw; x++) if (bin.getPixel(x,y).r.toInt() > 128) { hp[y]++; vp[x]++; }
    final thH = hp.reduce(max) * 0.06, thV = vp.reduce(max) * 0.06;
    int? t, b, l, r;
    for (int y = 0; y < ih; y++) if (hp[y] >= thH) { t = y; break; }
    for (int y = ih-1; y >= 0; y--) if (hp[y] >= thH) { b = y; break; }
    for (int x = 0; x < iw; x++) if (vp[x] >= thV) { l = x; break; }
    for (int x = iw-1; x >= 0; x--) if (vp[x] >= thV) { r = x; break; }
    if (t == null || b == null || l == null || r == null) return null;
    if (r - l < 30 || b - t < 30) return null;
    return [l, t, r, b];
  }
}

/// قص يدوي
class ManualCrop {
  static img.Image cropFromPoints(img.Image src, double x1, double y1, double x2, double y2, double x3, double y3, double x4, double y4) {
    final ax = [x1*src.width, x2*src.width, x3*src.width, x4*src.width];
    final ay = [y1*src.height, y2*src.height, y3*src.height, y4*src.height];
    final l = ax.reduce(min).round().clamp(0, src.width-1), r = ax.reduce(max).round().clamp(1, src.width);
    final t = ay.reduce(min).round().clamp(0, src.height-1), b = ay.reduce(max).round().clamp(1, src.height);
    return img.copyCrop(src, x: l, y: t, width: max(10, r-l), height: max(10, b-t));
  }
}

/// أدوات مساعدة
class ImageUtils {
  static List<int> encodeJpg(img.Image src, {int quality = 92}) => img.encodeJpg(src, quality: quality);
  static img.Image? decodeJpg(dynamic bytes) {
    if (bytes is Uint8List) return img.decodeImage(bytes);
    if (bytes is List<int>) return img.decodeImage(Uint8List.fromList(bytes));
    return null;
  }
}
