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
// خوارزمية قص ذكي — تحليل التباين (Euclidean Distance)
// ═══════════════════════════════════════════════════════
class SmartScanner {
  /// الخوارزمية الرئيسية — تكتشف البطاقة من أي خلفية
  static img.Image autoCrop(img.Image src) {
    final w = src.width, h = src.height;
    if (w < 50 || h < 50) return src;

    // تصغير الصورة للتحليل
    const maxDim = 300;
    double ratio = max(w, h) / maxDim;
    img.Image small;
    if (ratio > 1) {
      small = img.copyResize(src, width: (w / ratio).round());
    } else {
      small = src;
      ratio = 1.0;
    }

    // 1. تقدير لون الخلفية من الحواف
    final bg = _estimateBackground(small);
    if (bg == null) return src;

    // 2. بناء خريطة الفرق الإقليدي
    final diffMap = _buildDiffMap(small, bg);

    // 3. البحث عن حدود المستند
    final bounds = _findBounds(diffMap) ?? _scanFromEdges(small, bg);
    if (bounds == null) return src;

    // 4. تطبيق القص على الصورة الأصلية بالأبعاد الأصلية
    if (ratio > 1) {
      return _applyCrop(src, bounds, ratio);
    } else {
      return _applyCropDirect(small, bounds);
    }
  }

  static List<double>? _estimateBackground(img.Image src) {
    final w = src.width, h = src.height;
    final edge = max(6, min(w, h) ~/ 15);
    double rs = 0, gs = 0, bs = 0;
    int n = 0;
    for (int x = 0; x < w; x++) {
      for (int y = 0; y < edge && y < h; y++) { final p = src.getPixel(x, y); rs += p.r; gs += p.g; bs += p.b; n++; }
      for (int y = max(0, h - edge); y < h; y++) { final p = src.getPixel(x, y); rs += p.r; gs += p.g; bs += p.b; n++; }
    }
    for (int y = edge; y < h - edge; y++) {
      for (int x = 0; x < edge && x < w; x++) { final p = src.getPixel(x, y); rs += p.r; gs += p.g; bs += p.b; n++; }
      for (int x = max(0, w - edge); x < w; x++) { final p = src.getPixel(x, y); rs += p.r; gs += p.g; bs += p.b; n++; }
    }
    if (n == 0) return null;
    return [rs / n, gs / n, bs / n];
  }

  static List<List<int>> _buildDiffMap(img.Image src, List<double> bg) {
    final w = src.width, h = src.height;
    final map = List.generate(h, (_) => List.filled(w, 0));
    for (int y = 0; y < h; y++) {
      for (int x = 0; x < w; x++) {
        final p = src.getPixel(x, y);
        final dr = p.r - bg[0], dg = p.g - bg[1], db = p.b - bg[2];
        map[y][x] = sqrt(dr * dr + dg * dg + db * db).round();
      }
    }
    return map;
  }

  static List<double>? _findBounds(List<List<int>> map) {
    final h = map.length, w = map[0].length;
    final hp = List<int>.filled(h, 0), vp = List<int>.filled(w, 0);
    const diffThreshold = 35;
    for (int y = 0; y < h; y++) {
      for (int x = 0; x < w; x++) {
        if (map[y][x] > diffThreshold) { hp[y]++; vp[x]++; }
      }
    }
    final mh = hp.reduce(max), mv = vp.reduce(max);
    if (mh < 8 || mv < 8) return null;
    final th = mh * 0.08, tv = mv * 0.08;
    int? top, bot, lft, rgt;
    for (int y = 0; y < h; y++) { if (hp[y] > th) { top = y; break; } }
    for (int y = h - 1; y >= 0; y--) { if (hp[y] > th) { bot = y; break; } }
    for (int x = 0; x < w; x++) { if (vp[x] > tv) { lft = x; break; } }
    for (int x = w - 1; x >= 0; x--) { if (vp[x] > tv) { rgt = x; break; } }
    if (top == null || bot == null || lft == null || rgt == null) return null;
    final dw = rgt - lft, dh = bot - top;
    if (dw < w * 0.04 || dh < h * 0.04) return null;
    if (dw > w * 0.97 && dh > h * 0.97) return null;
    return [lft / w, top / h, rgt / w, bot / h];
  }

  static List<double>? _scanFromEdges(img.Image src, List<double> bg) {
    final w = src.width, h = src.height;
    final step = max(2, min(w, h) ~/ 40);
    final threshold = 30.0;

    int countRow(int y) {
      int c = 0;
      for (int x = 0; x < w; x += 2) {
        final p = src.getPixel(x, y);
        final d = sqrt((p.r-bg[0])*(p.r-bg[0]) + (p.g-bg[1])*(p.g-bg[1]) + (p.b-bg[2])*(p.b-bg[2]));
        if (d > threshold) c++;
      }
      return c;
    }
    int countCol(int x) {
      int c = 0;
      for (int y = 0; y < h; y += 2) {
        final p = src.getPixel(x, y);
        final d = sqrt((p.r-bg[0])*(p.r-bg[0]) + (p.g-bg[1])*(p.g-bg[1]) + (p.b-bg[2])*(p.b-bg[2]));
        if (d > threshold) c++;
      }
      return c;
    }

    int? top, bot, lft, rgt;
    for (int y = 0; y < h; y += step) { if (countRow(y) > w * 0.15 / 2) { top = y; break; } }
    for (int y = h - 1; y >= 0; y -= step) { if (countRow(y) > w * 0.15 / 2) { bot = y; break; } }
    for (int x = 0; x < w; x += step) { if (countCol(x) > h * 0.15 / 2) { lft = x; break; } }
    for (int x = w - 1; x >= 0; x -= step) { if (countCol(x) > h * 0.15 / 2) { rgt = x; break; } }
    if (top == null || bot == null || lft == null || rgt == null) return null;
    if ((rgt! - lft!) < 20 || (bot! - top!) < 20) return null;
    return [lft / w, top / h, rgt / w, bot / h];
  }

  static img.Image _applyCrop(img.Image src, List<double> b, double ratio) {
    final l = (b[0] * src.width / ratio).round().clamp(0, src.width - 1);
    final t = (b[1] * src.height / ratio).round().clamp(0, src.height - 1);
    final r = (b[2] * src.width / ratio).round().clamp(1, src.width);
    final bt = (b[3] * src.height / ratio).round().clamp(1, src.height);
    final cw = r - l, ch = bt - t;
    if (cw < 20 || ch < 20 || cw > src.width * 0.97) return src;
    return img.copyCrop(src, x: l, y: t, width: cw, height: ch);
  }

  static img.Image _applyCropDirect(img.Image image, List<double> b) {
    final l = (b[0] * image.width).round().clamp(0, image.width - 1);
    final t = (b[1] * image.height).round().clamp(0, image.height - 1);
    final r = (b[2] * image.width).round().clamp(1, image.width);
    final bt = (b[3] * image.height).round().clamp(1, image.height);
    final cw = r - l, ch = bt - t;
    if (cw < 20 || ch < 20) return image;
    return img.copyCrop(image, x: l, y: t, width: cw, height: ch);
  }

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
      // ❌ لا قص تلقائي
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

  void _resize(double w, double h, {bool isPhoto = false}) {
    if (_activeItem == null) return;
    setState(() { _activeItem!.widthMm = w; _activeItem!.heightMm = h; _activeItem!.isPhotoStyle = isPhoto; });
  }
  void _rotate() { if (_activeItem != null) setState(() => _activeItem!.applyRotation()); }
  void _duplicate() {
    if (_activeItem == null) return;
    final s = _activeItem!;
    setState(() {
      final n = DocumentItem(
        id: '${DateTime.now().millisecondsSinceEpoch}',
        image: img.copyResize(s.image, width: s.image.width),
        cachedBytes: Uint8List.fromList(s.cachedBytes),
        widthMm: s.widthMm, heightMm: s.heightMm,
        xMm: s.xMm + 5, yMm: s.yMm + 5,
        rotation: s.rotation, isPhotoStyle: s.isPhotoStyle,
      );
      _items.add(n); _activeItem = n;
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
    final cropped = SmartScanner.autoCrop(_activeItem!.rotatedImage);
    setState(() {
      _activeItem!.image = cropped;
      _activeItem!.cachedBytes = Uint8List.fromList(img.encodeJpg(cropped, quality: 92));
      _activeItem!.rotation = 0;
      _activeItem!.heightMm = cropped.height / cropped.width * _activeItem!.widthMm;
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

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text('مكتب علاء الحديدي - الماسح الذكي', style: TextStyle(fontSize: 14, fontWeight: FontWeight.bold)),
          Text('Telegram: @Oo_qp', style: TextStyle(fontSize: 9, color: Colors.white70)),
        ]),
        backgroundColor: const Color(0xFF0284C7),
        foregroundColor: Colors.white,
        actions: [
          IconButton(icon: const Icon(Icons.print, size: 20), tooltip: 'طباعة', onPressed: _print),
          IconButton(icon: const Icon(Icons.add_a_photo, size: 20), onPressed: () => _addImages(ImageSource.camera)),
          IconButton(icon: const Icon(Icons.photo_library, size: 20), onPressed: () => _addImages(ImageSource.gallery)),
        ],
      ),
      body: LayoutBuilder(
        builder: (context, constraints) {
          final tw = constraints.maxWidth, th = constraints.maxHeight;
          final sidebarW = tw * 0.20;
          final canvasW = tw - sidebarW;
          final topBarH = 48.0; // ✅ شريط أدوات علوي في المساحة الرمادية
          final canvasH = th - topBarH;
          final sx = (canvasW - 16) / pwMm;
          final sy = (canvasH - 16) / phMm;
          final scale = min(sx, sy);

          return Column(children: [
            // ── ✅ شريط أدوات علوي (المساحة الرمادية) ────
            Container(
              height: topBarH,
              color: const Color(0xFF1E293B),
              padding: const EdgeInsets.symmetric(horizontal: 12),
              child: Row(children: [
                // Mode toggle
                SegmentedButton<String>(
                  segments: const [
                    ButtonSegment(value: 'docs', label: Text('مستمسكات', style: TextStyle(fontSize: 11))),
                    ButtonSegment(value: 'photos', label: Text('صور معاملة', style: TextStyle(fontSize: 11))),
                  ],
                  selected: {_mode},
                  onSelectionChanged: (s) { if (s.isNotEmpty) setState(() => _mode = s.first); },
                  style: const ButtonStyle(tapTargetSize: MaterialTapTargetSize.shrinkWrap, visualDensity: VisualDensity.compact),
                ),
                const SizedBox(width: 16),
                _topBtn('قص ذكي تلقائي', Icons.auto_fix_high, const Color(0xFFD97706), _smartCrop),
                _topBtn('قص يدوي', Icons.crop_free, const Color(0xFF0891B2), _manualCrop),
                _topBtn('ترتيب تلقائي', Icons.auto_awesome, const Color(0xFF10B981), _align),
                const Spacer(),
                _topBtn('تدوير', Icons.rotate_right, const Color(0xFF64748B), _rotate),
                _topBtn('نسخ', Icons.copy, const Color(0xFF8B5CF6), _duplicate),
              ]),
            ),

            // ── المحتوى الرئيسي ─────────────────────────
            Expanded(
              child: Row(children: [
                // ── SIDEBAR (20%) — القياسات فقط ──────────
                SizedBox(
                  width: sidebarW,
                  child: Container(
                    color: const Color(0xFFF8FAFC),
                    padding: const EdgeInsets.all(6),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        const Text('القياسات (سم)', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 11, color: Color(0xFF0369A1))),
                        const SizedBox(height: 4),
                        if (_mode == 'docs') ...[
                          _szBtn('بطاقة موحدة 5.4×8.5', () => _resize(85, 54)),
                          _szBtn('بطاقة سكن 5.8×8.8', () => _resize(88, 58)),
                          _szBtn('ورقة كاملة A4', () => _resize(210, 297)),
                        ] else ...[
                          _szBtn('معاملة 3.6×4.5', () => _resize(36, 45, isPhoto: true)),
                          _szBtn('مصغر 2.5×3.4', () => _resize(25, 34, isPhoto: true)),
                        ],
                        const Spacer(),
                        if (_activeItem != null)
                          ElevatedButton.icon(
                            style: ElevatedButton.styleFrom(backgroundColor: Colors.red, foregroundColor: Colors.white, minimumSize: const Size(0, 32)),
                            onPressed: () => setState(() { _items.remove(_activeItem); _activeItem = null; }),
                            icon: const Icon(Icons.delete, size: 14),
                            label: const Text('حذف', style: TextStyle(fontSize: 10)),
                          ),
                      ],
                    ),
                  ),
                ),

                // ── CANVAS (80%) — ورقة A4 ─────────────────
                Expanded(
                  child: Container(
                    color: const Color(0xFF334155),
                    child: Center(
                      child: Container(
                        width: pwMm * scale,
                        height: phMm * scale,
                        decoration: BoxDecoration(
                          color: Colors.white,
                          boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.5), blurRadius: 12, offset: const Offset(0, 3))],
                        ),
                        child: ClipRect(
                          child: Stack(
                            children: List.generate(_items.length, (i) {
                              final item = _items[i];
                              final active = _activeItem?.id == item.id;
                              return Positioned(
                                left: item.xMm * scale,
                                top: item.yMm * scale,
                                width: item.widthMm * scale,
                                height: item.heightMm * scale,
                                child: GestureDetector(
                                  onTap: () => setState(() => _activeItem = item),
                                  onPanUpdate: (d) => setState(() { item.xMm += d.delta.dx / scale; item.yMm += d.delta.dy / scale; }),
                                  child: Container(
                                    decoration: BoxDecoration(border: Border.all(color: active ? Colors.blue : (item.isPhotoStyle ? Colors.red : Colors.transparent), width: active ? 2 : 1)),
                                    child: Transform.rotate(angle: item.rotation * pi / 180, child: Image.memory(item.cachedBytes, fit: BoxFit.fill)),
                                  ),
                                ),
                              );
                            }),
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              ]),
            ),
          ]);
        },
      ),
    );
  }

  Widget _topBtn(String label, IconData icon, Color color, VoidCallback onTap) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 3),
      child: TextButton.icon(
        style: TextButton.styleFrom(foregroundColor: Colors.white, padding: const EdgeInsets.symmetric(horizontal: 8)),
        onPressed: onTap,
        icon: Icon(icon, size: 16, color: color),
        label: Text(label, style: const TextStyle(fontSize: 10, color: Colors.white)),
      ),
    );
  }

  Widget _szBtn(String label, VoidCallback onTap) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 3),
      child: SizedBox(
        height: 30,
        child: ElevatedButton(
          style: ElevatedButton.styleFrom(
            padding: const EdgeInsets.symmetric(horizontal: 4), minimumSize: const Size(0, 30),
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(5)),
            backgroundColor: Colors.white, foregroundColor: const Color(0xFF0369A1),
            side: const BorderSide(color: Color(0xFFCBD5E1)),
          ),
          onPressed: onTap,
          child: Text(label, style: const TextStyle(fontSize: 10)),
        ),
      ),
    );
  }
}

// ═══════════════════════════════════════════════════════
// MANUAL CROP — سريع ومستقر
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
  late Uint8List _bytes; // ✅ مشفرة مرة واحدة

  @override
  void initState() {
    super.initState();
    _tlX = 0.05; _tlY = 0.05; _trX = 0.95; _trY = 0.05;
    _brX = 0.95; _brY = 0.95; _blX = 0.05; _blY = 0.95;
    _bytes = Uint8List.fromList(img.encodeJpg(widget.image, quality: 85));
  }

  void _apply() {
    final src = widget.image;
    final xs = [(_tlX * src.width).round(), (_trX * src.width).round(), (_brX * src.width).round(), (_blX * src.width).round()];
    final ys = [(_tlY * src.height).round(), (_trY * src.height).round(), (_brY * src.height).round(), (_blY * src.height).round()];
    final minX = xs.reduce(min).clamp(0, src.width - 1);
    final maxX = xs.reduce(max).clamp(1, src.width);
    final minY = ys.reduce(min).clamp(0, src.height - 1);
    final maxY = ys.reduce(max).clamp(1, src.height);
    var c = img.copyCrop(src, x: minX, y: minY, width: max(10, maxX - minX), height: max(10, maxY - minY));
    if (_filter == 'soft') c = SmartScanner.softEnhance(c);
    else if (_filter == 'bw') c = img.grayscale(c);
    Navigator.pop(context, c);
  }

  Widget _dot(double x, double y, double w, double h, Function(double, double) set) {
    return Positioned(
      left: x * w - 15, top: y * h - 15,
      child: GestureDetector(
        onPanUpdate: (d) => setState(() { set((x + d.delta.dx / w).clamp(0.0, 1.0), (y + d.delta.dy / h).clamp(0.0, 1.0)); }),
        child: Container(width: 30, height: 30,
          decoration: BoxDecoration(color: Colors.blueAccent, shape: BoxShape.circle,
            border: Border.all(color: Colors.white, width: 2.5),
            boxShadow: const [BoxShadow(color: Colors.black45, blurRadius: 4)])),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF0F172A),
      appBar: AppBar(
        title: const Text('القص اليدوي', style: TextStyle(fontSize: 14)),
        backgroundColor: Colors.black, foregroundColor: Colors.white,
        actions: [IconButton(icon: const Icon(Icons.check, color: Colors.greenAccent, size: 26), onPressed: _apply)],
      ),
      body: Column(children: [
        Container(color: Colors.black87, padding: const EdgeInsets.symmetric(vertical: 6, horizontal: 12),
          child: Row(mainAxisAlignment: MainAxisAlignment.center, children: [
            const Text('الفلتر: ', style: TextStyle(color: Colors.white70, fontSize: 11)),
            ChoiceChip(label: const Text('أصلي', style: TextStyle(fontSize: 10)), selected: _filter == 'original', onSelected: (_) => setState(() => _filter = 'original')),
            const SizedBox(width: 4),
            ChoiceChip(label: const Text('تحسين ناعم', style: TextStyle(fontSize: 10)), selected: _filter == 'soft', onSelected: (_) => setState(() => _filter = 'soft')),
            const SizedBox(width: 4),
            ChoiceChip(label: const Text('أبيض وأسود', style: TextStyle(fontSize: 10)), selected: _filter == 'bw', onSelected: (_) => setState(() => _filter = 'bw')),
            const SizedBox(width: 12),
            TextButton.icon(
              onPressed: () => setState(() { _tlX=_tlY=0.05; _trX=0.95; _trY=0.05; _brX=_brY=0.95; _blX=0.05; _blY=0.95; }),
              icon: const Icon(Icons.center_focus_strong, size: 14, color: Colors.white),
              label: const Text('إعادة', style: TextStyle(fontSize: 10, color: Colors.white)),
            ),
          ])),
        Expanded(
          child: LayoutBuilder(builder: (_, c) {
            final w = c.maxWidth, h = c.maxHeight;
            return Stack(children: [
              Center(child: Image.memory(_bytes, fit: BoxFit.contain)),
              CustomPaint(size: Size(w, h), painter: _LP([
                Offset(_tlX * w, _tlY * h), Offset(_trX * w, _trY * h),
                Offset(_brX * w, _brY * h), Offset(_blX * w, _blY * h),
              ])),
              _dot(_tlX, _tlY, w, h, (dx, dy) { _tlX = dx; _tlY = dy; }),
              _dot(_trX, _trY, w, h, (dx, dy) { _trX = dx; _trY = dy; }),
              _dot(_brX, _brY, w, h, (dx, dy) { _brX = dx; _brY = dy; }),
              _dot(_blX, _blY, w, h, (dx, dy) { _blX = dx; _blY = dy; }),
            ]);
          }),
        ),
      ]),
    );
  }
}

class _LP extends CustomPainter {
  final List<Offset> pts;
  _LP(this.pts);
  @override
  void paint(Canvas c, Size s) {
    final p = Paint()..color = Colors.cyanAccent..strokeWidth = 2..style = PaintingStyle.stroke;
    final path = Path()..moveTo(pts[0].dx, pts[0].dy);
    for (int i = 1; i < 4; i++) path.lineTo(pts[i].dx, pts[i].dy);
    path.close(); c.drawPath(path, p);
  }
  @override
  bool shouldRepaint(_) => true;
}
