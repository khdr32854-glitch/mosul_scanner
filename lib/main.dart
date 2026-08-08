import 'dart:io';
import 'dart:math';
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:image/image.dart' as img;
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';

void main() {
  runApp(const MosulScannerApp());
}

class MosulScannerApp extends StatelessWidget {
  const MosulScannerApp({super.key});
  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'مكتب علاء الحديدي - الماسح والطباعة الذكية',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(primarySwatch: Colors.blue, useMaterial3: true),
      home: const MainScannerScreen(),
    );
  }
}

// ═══════════════════════════════════════════════════════
// DATA MODEL
// ═══════════════════════════════════════════════════════
class DocumentItem {
  String id;
  img.Image image;
  Uint8List cachedBytes;
  double widthMm;
  double heightMm;
  double xMm;
  double yMm;
  double rotation;
  bool isPhotoStyle;

  DocumentItem({
    required this.id,
    required this.image,
    required this.cachedBytes,
    required this.widthMm,
    required this.heightMm,
    required this.xMm,
    required this.yMm,
    this.rotation = 0,
    this.isPhotoStyle = false,
  });

  img.Image get rotatedImage {
    if (rotation % 360 == 0) return image;
    final r = (rotation % 360 + 360) % 360;
    if (r == 90) return img.copyRotate(image, angle: 90);
    if (r == 180) return img.copyRotate(image, angle: 180);
    if (r == 270) return img.copyRotate(image, angle: 270);
    return image;
  }

  void applyRotation() {
    if (rotation % 360 == 0) return;
    image = rotatedImage;
    cachedBytes = Uint8List.fromList(img.encodeJpg(image, quality: 92));
    final tmp = widthMm; widthMm = heightMm; heightMm = tmp;
    rotation = 0;
  }
}

// ═══════════════════════════════════════════════════════
// خوارزمية القص الذكي (بدون اعتماديات خارجية)
// تستخدم مقاربة CamScanner:
//   Grayscale → Gaussian Blur → Canny-like → Contour finding → Crop
// ═══════════════════════════════════════════════════════
class SmartScanner {
  /// الخوارزمية الرئيسية
  static img.Image autoCrop(img.Image src) {
    final w = src.width, h = src.height;
    if (w < 50 || h < 50) return src;

    // تصغير للتحليل السريع
    const maxDim = 256;
    final ratio = max(w, h) / maxDim;
    final img.Image small;
    if (ratio > 1) {
      small = img.copyResize(src, width: (w / ratio).round());
    } else {
      small = img.copyResize(src, width: w); // نسخة للتحليل
    }

    // 1. Grayscale
    final gray = img.grayscale(small);
    // 2. Gaussian Blur (إزالة الضوضاء)
    final blur = img.gaussianBlur(gray, radius: 2);

    // 3. Canny-like edge detection (Sobel + threshold)
    final edges = _sobelEdges(blur);

    // 4. البحث عن حدود المستند عبر الإسقاطات
    final bounds = _findDocumentBoundsFromEdges(edges);

    if (bounds == null) return src;

    // 5. تطبيق القص على الصورة الأصلية
    if (ratio > 1) {
      return _cropOriginal(src, bounds, ratio);
    } else {
      return _cropDirect(small, bounds);
    }
  }

  /// Sobel edge detection
  static img.Image _sobelEdges(img.Image gray) {
    final w = gray.width, h = gray.height;
    final e = img.Image(width: w, height: h);
    for (int y = 1; y < h - 1; y++) {
      for (int x = 1; x < w - 1; x++) {
        final a = gray.getPixel(x - 1, y - 1).r.toInt();
        final b = gray.getPixel(x, y - 1).r.toInt();
        final c = gray.getPixel(x + 1, y - 1).r.toInt();
        final d = gray.getPixel(x - 1, y).r.toInt();
        final f = gray.getPixel(x + 1, y).r.toInt();
        final g = gray.getPixel(x - 1, y + 1).r.toInt();
        final h = gray.getPixel(x, y + 1).r.toInt();
        final i = gray.getPixel(x + 1, y + 1).r.toInt();
        final gx = (c + 2 * f + i) - (a + 2 * d + g);
        final gy = (g + 2 * h + i) - (a + 2 * b + c);
        final m = sqrt(gx * gx + gy * gy).toInt().clamp(0, 255);
        e.setPixelRgba(x, y, m, m, m, 255);
      }
    }
    return e;
  }

  /// البحث عن حدود المستند من صورة الحواف
  static List<double>? _findDocumentBoundsFromEdges(img.Image edges) {
    final w = edges.width, h = edges.height;
    // إسقاطات أفقية وعمودية
    final hp = List.filled(h, 0), vp = List.filled(w, 0);
    const edgeThreshold = 50; // عتبة الحواف

    for (int y = 0; y < h; y++) {
      for (int x = 0; x < w; x++) {
        final v = edges.getPixel(x, y).r.toInt();
        if (v > edgeThreshold) { hp[y]++; vp[x]++; }
      }
    }

    final maxH = hp.reduce(max), maxV = vp.reduce(max);
    if (maxH < 6 || maxV < 6) return null;

    // عتبة ديناميكية
    final thH = (maxH * 0.10).ceilToDouble();
    final thV = (maxV * 0.10).ceilToDouble();

    int? top, bot, lft, rgt;
    for (int y = 0; y < h; y++) if (hp[y] >= thH) { top = y; break; }
    for (int y = h - 1; y >= 0; y--) if (hp[y] >= thH) { bot = y; break; }
    for (int x = 0; x < w; x++) if (vp[x] >= thV) { lft = x; break; }
    for (int x = w - 1; x >= 0; x--) if (vp[x] >= thV) { rgt = x; break; }

    if (top == null || bot == null || lft == null || rgt == null) return null;

    final dw = rgt - lft, dh = bot - top;
    if (dw < w * 0.04 || dh < h * 0.04) return null;
    if (dw > w * 0.96 && dh > h * 0.96) return null; // كل الصورة = لا مستند

    // هامش أمان طفيف
    const pad = 0.01;
    return [
      (lft / w - pad).clamp(0.0, 1.0),
      (top / h - pad).clamp(0.0, 1.0),
      (rgt / w + pad).clamp(0.0, 1.0),
      (bot / h + pad).clamp(0.0, 1.0),
    ];
  }

  static img.Image _cropOriginal(img.Image src, List<double> b, double ratio) {
    final l = (b[0] * src.width / ratio).round().clamp(0, src.width - 1);
    final t = (b[1] * src.height / ratio).round().clamp(0, src.height - 1);
    final r = (b[2] * src.width / ratio).round().clamp(1, src.width);
    final bt = (b[3] * src.height / ratio).round().clamp(1, src.height);
    final cw = r - l, ch = bt - t;
    if (cw < 20 || ch < 20) return src;
    return img.copyCrop(src, x: l, y: t, width: cw, height: ch);
  }

  static img.Image _cropDirect(img.Image img, List<double> b) {
    final l = (b[0] * img.width).round().clamp(0, img.width - 1);
    final t = (b[1] * img.height).round().clamp(0, img.height - 1);
    final r = (b[2] * img.width).round().clamp(1, img.width);
    final bt = (b[3] * img.height).round().clamp(1, img.height);
    final cw = r - l, ch = bt - t;
    if (cw < 20 || ch < 20) return img;
    return img.copyCrop(img, x: l, y: t, width: cw, height: ch);
  }

  /// تحسين ناعم
  static img.Image softEnhance(img.Image src) {
    return img.adjustColor(src, brightness: 1.04, contrast: 1.10);
  }
}

// ═══════════════════════════════════════════════════════
// MAIN SCREEN
// ═══════════════════════════════════════════════════════
class MainScannerScreen extends StatefulWidget {
  const MainScannerScreen({super.key});
  @override
  State<MainScannerScreen> createState() => _MainScannerScreenState();
}

class _MainScannerScreenState extends State<MainScannerScreen> {
  final List<DocumentItem> _items = [];
  DocumentItem? _activeItem;
  final ImagePicker _picker = ImagePicker();
  String _mode = 'docs';
  bool _processing = false;

  static const double pwMm = 210, phMm = 297, mMm = 10;

  void _addImages(ImageSource source) async {
    final List<XFile> files = [];
    if (source == ImageSource.gallery) {
      files.addAll(await _picker.pickMultiImage());
    } else {
      final f = await _picker.pickImage(source: source, imageQuality: 95);
      if (f != null) files.add(f);
    }
    for (int i = 0; i < files.length; i++) {
      final bytes = await File(files[i].path).readAsBytes();
      final decoded = img.decodeImage(bytes);
      if (decoded == null) continue;
      final encoded = Uint8List.fromList(img.encodeJpg(decoded, quality: 92));
      setState(() {
        final item = DocumentItem(
          id: '${DateTime.now().millisecondsSinceEpoch}$i',
          image: decoded,
          cachedBytes: encoded,
          widthMm: _mode == 'photos' ? 36 : 85,
          heightMm: _mode == 'photos' ? 45 : (decoded.height / decoded.width * 85),
          xMm: mMm + (_items.length * 4), yMm: mMm + (_items.length * 4),
          isPhotoStyle: _mode == 'photos',
        );
        _items.add(item); _activeItem = item;
      });
    }
  }

  void _resize(double w, double h, {bool p = false}) {
    if (_activeItem == null) return;
    setState(() { _activeItem!.widthMm = w; _activeItem!.heightMm = h; _activeItem!.isPhotoStyle = p; });
  }
  void _rotate() { if (_activeItem != null) setState(() => _activeItem!.applyRotation()); }
  void _duplicate() {
    if (_activeItem == null) return;
    final s = _activeItem!;
    setState(() {
      _items.add(DocumentItem(
        id: '${DateTime.now().millisecondsSinceEpoch}',
        image: img.copyResize(s.image, width: s.image.width),
        cachedBytes: Uint8List.fromList(s.cachedBytes),
        widthMm: s.widthMm, heightMm: s.heightMm,
        xMm: s.xMm + 5, yMm: s.yMm + 5,
        rotation: s.rotation, isPhotoStyle: s.isPhotoStyle,
      ));
      _activeItem = _items.last;
    });
  }
  void _align() {
    setState(() {
      double cx = mMm, cy = mMm, mh = 0;
      for (var i in _items) {
        if (cx + i.widthMm > pwMm - mMm) { cx = mMm; cy += mh + 5; mh = 0; }
        i.xMm = cx; i.yMm = cy; cx += i.widthMm + 5;
        if (i.heightMm > mh) mh = i.heightMm;
      }
    });
  }

  void _smartCrop() {
    if (_activeItem == null) return;
    setState(() => _processing = true);
    // استخدام Isolate-like approach: ننفذ في نفس الثريد مع مؤشر تحميل
    Future.delayed(const Duration(milliseconds: 50), () {
      final cropped = SmartScanner.autoCrop(_activeItem!.rotatedImage);
      if (mounted) {
        setState(() {
          _activeItem!.image = cropped;
          _activeItem!.cachedBytes = Uint8List.fromList(img.encodeJpg(cropped, quality: 92));
          _activeItem!.rotation = 0;
          _activeItem!.heightMm = cropped.height / cropped.width * _activeItem!.widthMm;
          _processing = false;
        });
      }
    });
  }

  void _manualCrop() async {
    if (_activeItem == null) return;
    final r = _activeItem!.rotatedImage;
    final result = await Navigator.push<img.Image>(context, MaterialPageRoute(builder: (_) => ManualCropScreen(image: r)));
    if (result != null && mounted) {
      setState(() {
        _activeItem!.image = result;
        _activeItem!.cachedBytes = Uint8List.fromList(img.encodeJpg(result, quality: 92));
        _activeItem!.rotation = 0;
        _activeItem!.heightMm = result.height / result.width * _activeItem!.widthMm;
      });
    }
  }
  void _print() async {
    final pdf = pw.Document();
    pdf.addPage(pw.Page(pageFormat: PdfPageFormat.a4, margin: pw.EdgeInsets.zero, build: (_) {
      final ws = <pw.Widget>[];
      for (final i in _items) {
        final pi = i.rotatedImage;
        ws.add(pw.Positioned(left: i.xMm * PdfPageFormat.mm, top: i.yMm * PdfPageFormat.mm,
          child: pw.SizedBox(width: i.widthMm * PdfPageFormat.mm, height: i.heightMm * PdfPageFormat.mm,
            child: pw.Image(pw.MemoryImage(Uint8List.fromList(img.encodeJpg(pi, quality: 95))), fit: pw.BoxFit.fill))));
      }
      return pw.Stack(children: List<pw.Widget>.from(ws));
    }));
    await Printing.layoutPdf(onLayout: (_) async => pdf.save());
  }

  // ════════════ UI ════════════
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text('مكتب علاء الحديدي - الماسح الذكي', style: TextStyle(fontSize: 13, fontWeight: FontWeight.bold)),
          Text('Telegram: @Oo_qp', style: TextStyle(fontSize: 9, color: Colors.white70)),
        ]),
        backgroundColor: const Color(0xFF0284C7), foregroundColor: Colors.white,
        actions: [
          IconButton(icon: const Icon(Icons.print, size: 18), tooltip: 'طباعة', onPressed: _print),
          IconButton(icon: const Icon(Icons.add_a_photo, size: 18), onPressed: () => _addImages(ImageSource.camera)),
          IconButton(icon: const Icon(Icons.photo_library, size: 18), onPressed: () => _addImages(ImageSource.gallery)),
        ],
      ),
      body: LayoutBuilder(builder: (_, c) {
        final tw = c.maxWidth, th = c.maxHeight;
        final sw = tw * 0.19;
        final cw = tw - sw;
        final tbh = 44.0;
        final ch = th - tbh;
        final sc = min((cw - 12) / pwMm, (ch - 12) / phMm);
        return Column(children: [
          // شريط علوي
          Container(height: tbh, padding: const EdgeInsets.symmetric(horizontal: 6),
            decoration: const BoxDecoration(color: Color(0xFF1E293B), border: Border(bottom: BorderSide(color: Color(0xFF334155)))),
            child: Row(children: [
              SegmentedButton<String>(
                segments: const [
                  ButtonSegment(value: 'docs', label: Text('مستمسكات', style: TextStyle(fontSize: 10, fontWeight: FontWeight.bold))),
                  ButtonSegment(value: 'photos', label: Text('صور معاملة', style: TextStyle(fontSize: 10, fontWeight: FontWeight.bold))),
                ],
                selected: {_mode},
                onSelectionChanged: (s) { if (s.isNotEmpty) setState(() => _mode = s.first); },
                style: const ButtonStyle(tapTargetSize: MaterialTapTargetSize.shrinkWrap, visualDensity: VisualDensity.compact),
              ),
              const SizedBox(width: 8),
              _tb('قص ذكي', Icons.auto_fix_high, const Color(0xFFF59E0B), _smartCrop, _processing),
              _tb('قص يدوي', Icons.crop_free, const Color(0xFF06B6D4), _manualCrop, false),
              _tb('ترتيب', Icons.auto_awesome, const Color(0xFF10B981), _align, false),
              const Spacer(),
              _tb('تدوير', Icons.rotate_right, const Color(0xFF94A3B8), _rotate, false),
              _tb('نسخ', Icons.copy, const Color(0xFFA78BFA), _duplicate, false),
            ])),
          // المحتوى
          Expanded(child: Row(children: [
            // Sidebar
            SizedBox(width: sw, child: Container(color: const Color(0xFFF1F5F9), padding: const EdgeInsets.all(5),
              child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                Container(padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
                  decoration: BoxDecoration(color: const Color(0xFF0369A1), borderRadius: BorderRadius.circular(4)),
                  child: const Text('القياسات (سم)', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 10, color: Colors.white))),
                const SizedBox(height: 4),
                if (_mode == 'docs') ...[
                  _sz('بطاقة موحدة\n8.5 × 5.4', () => _resize(85, 54)),
                  _sz('بطاقة سكن\n8.8 × 5.8', () => _resize(88, 58)),
                  _sz('ورقة كاملة\nA4', () => _resize(210, 297), c: const Color(0xFF0F766E)),
                ] else ...[
                  _sz('معاملة\n3.6 × 4.5', () => _resize(36, 45, p: true)),
                  _sz('مصغر\n2.5 × 3.4', () => _resize(25, 34, p: true)),
                ],
                const Spacer(),
                if (_activeItem != null)
                  SizedBox(height: 32, child: ElevatedButton.icon(
                    style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFFDC2626), foregroundColor: Colors.white, shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(6))),
                    onPressed: () => setState(() { _items.remove(_activeItem); _activeItem = null; }),
                    icon: const Icon(Icons.delete_outline, size: 14),
                    label: const Text('حذف العنصر', style: TextStyle(fontSize: 10, fontWeight: FontWeight.bold)),
                  )),
              ]),
            )),
            // Canvas
            Expanded(child: Container(color: const Color(0xFF1E293B),
              child: Center(child: Container(width: pwMm * sc, height: phMm * sc,
                decoration: BoxDecoration(color: Colors.white, boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.6), blurRadius: 14, offset: const Offset(0, 4))]),
                child: ClipRect(child: Stack(children: List.generate(_items.length, (i) {
                  final it = _items[i];
                  final act = _activeItem?.id == it.id;
                  return Positioned(left: it.xMm * sc, top: it.yMm * sc, width: it.widthMm * sc, height: it.heightMm * sc,
                    child: GestureDetector(
                      onTap: () => setState(() => _activeItem = it),
                      onPanUpdate: (d) => setState(() { it.xMm += d.delta.dx / sc; it.yMm += d.delta.dy / sc; }),
                      child: Container(
                        decoration: BoxDecoration(border: Border.all(color: act ? Colors.blue : (it.isPhotoStyle ? Colors.red.withOpacity(0.5) : Colors.transparent), width: act ? 2.5 : 1),
                          boxShadow: act ? [BoxShadow(color: Colors.blue.withOpacity(0.3), blurRadius: 6)] : null),
                        child: Transform.rotate(angle: it.rotation * pi / 180, child: Image.memory(it.cachedBytes, fit: BoxFit.fill)),
                      ),
                    ),
                  );
                }))),
              )),
            )),
          ])),
        ]);
      }),
    );
  }

  Widget _tb(String label, IconData icon, Color color, VoidCallback onTap, bool loading) {
    return Padding(padding: const EdgeInsets.symmetric(horizontal: 2),
      child: TextButton(
        style: TextButton.styleFrom(padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 4), minimumSize: Size.zero, tapTargetSize: MaterialTapTargetSize.shrinkWrap),
        onPressed: loading ? null : onTap,
        child: Row(mainAxisSize: MainAxisSize.min, children: [
          loading ? const SizedBox(width: 14, height: 14, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
              : Icon(icon, size: 15, color: color),
          const SizedBox(width: 3),
          Text(label, style: TextStyle(fontSize: 10, fontWeight: FontWeight.w600, color: loading ? Colors.white54 : Colors.white)),
        ]),
      ),
    );
  }

  Widget _sz(String label, VoidCallback onTap, {Color c = const Color(0xFF0369A1)}) {
    return Padding(padding: const EdgeInsets.only(bottom: 3),
      child: SizedBox(height: 34, child: ElevatedButton(
        style: ElevatedButton.styleFrom(padding: const EdgeInsets.symmetric(horizontal: 2), minimumSize: const Size(0, 34),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(5)),
          backgroundColor: c.withOpacity(0.08), foregroundColor: c, side: BorderSide(color: c.withOpacity(0.3)), elevation: 0),
        onPressed: onTap,
        child: Text(label, textAlign: TextAlign.center, style: TextStyle(fontSize: 9, fontWeight: FontWeight.w600, color: c, height: 1.2)),
      )),
    );
  }
}

// ═══════════════════════════════════════════════════════
// MANUAL CROP — قص يدوي محسّن
// ═══════════════════════════════════════════════════════
class ManualCropScreen extends StatefulWidget {
  final img.Image image;
  const ManualCropScreen({super.key, required this.image});
  @override
  State<ManualCropScreen> createState() => _ManualCropScreenState();
}

class _ManualCropScreenState extends State<ManualCropScreen> {
  late double _tlX, _tlY, _trX, _trY, _brX, _brY, _blX, _blY;
  String _filter = 'soft';
  late Uint8List _bytes;

  @override
  void initState() {
    super.initState();
    _tlX = 0.05; _tlY = 0.05; _trX = 0.95; _trY = 0.05;
    _brX = 0.95; _brY = 0.95; _blX = 0.05; _blY = 0.95;
    _bytes = Uint8List.fromList(img.encodeJpg(widget.image, quality: 82));
  }

  void _apply() {
    final src = widget.image;
    final xs = [(_tlX * src.width).round(), (_trX * src.width).round(), (_brX * src.width).round(), (_blX * src.width).round()];
    final ys = [(_tlY * src.height).round(), (_trY * src.height).round(), (_brY * src.height).round(), (_blY * src.height).round()];
    final minX = xs.reduce(min).clamp(0, src.width - 1), maxX = xs.reduce(max).clamp(1, src.width);
    final minY = ys.reduce(min).clamp(0, src.height - 1), maxY = ys.reduce(max).clamp(1, src.height);
    var c = img.copyCrop(src, x: minX, y: minY, width: max(10, maxX - minX), height: max(10, maxY - minY));
    if (_filter == 'soft') c = SmartScanner.softEnhance(c);
    else if (_filter == 'bw') c = img.grayscale(c);
    Navigator.pop(context, c);
  }

  Widget _dot(double x, double y, double w, double h, void Function(double, double) s) {
    return Positioned(left: x * w - 22, top: y * h - 22,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onPanUpdate: (d) => setState(() => s((x + d.delta.dx / w).clamp(0.0, 1.0), (y + d.delta.dy / h).clamp(0.0, 1.0))),
        child: Container(width: 44, height: 44,
          decoration: BoxDecoration(color: const Color(0xFF2563EB), shape: BoxShape.circle,
            border: Border.all(color: Colors.white, width: 3), boxShadow: const [BoxShadow(color: Colors.black54, blurRadius: 6)])),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF0B1121),
      appBar: AppBar(title: const Text('القص اليدوي', style: TextStyle(fontSize: 14)), centerTitle: true,
        backgroundColor: Colors.black, foregroundColor: Colors.white,
        actions: [Padding(padding: const EdgeInsets.only(right: 8), child: IconButton(icon: const Icon(Icons.check_circle, color: Color(0xFF10B981), size: 30), onPressed: _apply))]),
      body: Column(children: [
        Container(color: const Color(0xFF1A1F2E), padding: const EdgeInsets.symmetric(vertical: 6, horizontal: 10),
          child: Row(mainAxisAlignment: MainAxisAlignment.center, children: [
            const Text('الفلتر:  ', style: TextStyle(color: Colors.white70, fontSize: 11)),
            _chip('أصلي', _filter == 'original', () => setState(() => _filter = 'original')),
            _chip('ناعم ✨', _filter == 'soft', () => setState(() => _filter = 'soft')),
            _chip('أبيض وأسود', _filter == 'bw', () => setState(() => _filter = 'bw')),
            const SizedBox(width: 8),
            TextButton.icon(onPressed: () => setState(() { _tlX=_tlY=0.05; _trX=0.95; _trY=0.05; _brX=_brY=0.95; _blX=0.05; _blY=0.95; }),
              icon: const Icon(Icons.refresh, size: 14, color: Colors.white60), label: const Text('إعادة', style: TextStyle(fontSize: 10, color: Colors.white60))),
          ])),
        Expanded(child: LayoutBuilder(builder: (_, c) {
          final w = c.maxWidth, h = c.maxHeight;
          return Stack(children: [
            Center(child: Image.memory(_bytes, fit: BoxFit.contain)),
            Positioned.fill(child: IgnorePointer(child: CustomPaint(painter: _Overlay(_tlX*w, _tlY*h, _trX*w, _trY*h, _brX*w, _brY*h, _blX*w, _blY*h)))),
            CustomPaint(size: Size(w, h), painter: _Lines([Offset(_tlX*w, _tlY*h), Offset(_trX*w, _trY*h), Offset(_brX*w, _brY*h), Offset(_blX*w, _blY*h)])),
            _dot(_tlX, _tlY, w, h, (dx, dy) { _tlX=dx; _tlY=dy; }),
            _dot(_trX, _trY, w, h, (dx, dy) { _trX=dx; _trY=dy; }),
            _dot(_brX, _brY, w, h, (dx, dy) { _brX=dx; _brY=dy; }),
            _dot(_blX, _blY, w, h, (dx, dy) { _blX=dx; _blY=dy; }),
          ]);
        })),
      ]),
    );
  }

  Widget _chip(String l, bool sel, VoidCallback t) => Padding(padding: const EdgeInsets.symmetric(horizontal: 2),
    child: ChoiceChip(label: Text(l, style: TextStyle(fontSize: 10, fontWeight: FontWeight.w600, color: sel ? Colors.white : Colors.white70)),
      selected: sel, onSelected: (_) => t(), selectedColor: const Color(0xFF2563EB), backgroundColor: const Color(0xFF1E293B),
      side: BorderSide.none, padding: const EdgeInsets.symmetric(horizontal: 4), visualDensity: VisualDensity.compact));
}

class _Overlay extends CustomPainter {
  final double x1,y1,x2,y2,x3,y3,x4,y4;
  _Overlay(this.x1,this.y1,this.x2,this.y2,this.x3,this.y3,this.x4,this.y4);
  @override void paint(Canvas c, Size s) {
    final o = Path()..addRect(Rect.fromLTWH(0,0,s.width,s.height));
    final i = Path()..moveTo(x1,y1)..lineTo(x2,y2)..lineTo(x3,y3)..lineTo(x4,y4)..close();
    c.drawPath(Path.combine(PathOperation.difference, o, i), Paint()..color = Colors.black.withOpacity(0.55));
  }
  @override bool shouldRepaint(_) => true;
}

class _Lines extends CustomPainter {
  final List<Offset> p;
  _Lines(this.p);
  @override void paint(Canvas c, Size s) {
    final pt = Paint()..color = const Color(0xFF22D3EE)..strokeWidth = 2.5..style = PaintingStyle.stroke;
    final ph = Path()..moveTo(p[0].dx,p[0].dy); for (int i=1;i<4;i++) ph.lineTo(p[i].dx,p[i].dy);
    ph.close(); c.drawPath(ph, pt);
  }
  @override bool shouldRepaint(_) => true;
}
