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
    cachedBytes = Uint8List.fromList(img.encodeJpg(image, quality: 90));
    final tmp = widthMm;
    widthMm = heightMm;
    heightMm = tmp;
    rotation = 0;
  }
}

// ═══════════════════════════════════════════════════════
// خوارزمية المسح الذكي (Computer Vision محلية)
// ═══════════════════════════════════════════════════════
class SmartScanner {
  /// كشف الحواف Sobel
  static img.Image _sobel(img.Image gray) {
    final w = gray.width, h = gray.height;
    final e = img.Image(width: w, height: h);
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
        final m = sqrt(gx * gx + gy * gy).toInt().clamp(0, 255);
        e.setPixelRgba(x, y, m, m, m, 255);
      }
    }
    return e;
  }

  /// البحث عن حدود المستند من صورة الحواف → نسب 0.0–1.0
  static List<double>? _findBounds(img.Image edge) {
    final w = edge.width, h = edge.height;
    const t = 45;
    final hp = List<int>.filled(h, 0), vp = List<int>.filled(w, 0);
    for (int y = 0; y < h; y++) {
      for (int x = 0; x < w; x++) {
        final v = (edge.getPixel(x, y).r + edge.getPixel(x, y).g + edge.getPixel(x, y).b) ~/ 3;
        if (v > t) { hp[y]++; vp[x]++; }
      }
    }
    final th = hp.reduce((a, b) => a > b ? a : b) * 0.12;
    final tv = vp.reduce((a, b) => a > b ? a : b) * 0.12;
    int? top, bot, lft, rgt;
    for (int y = 0; y < h; y++) { if (hp[y] > th) { top = y; break; } }
    for (int y = h - 1; y >= 0; y--) { if (hp[y] > th) { bot = y; break; } }
    for (int x = 0; x < w; x++) { if (vp[x] > tv) { lft = x; break; } }
    for (int x = w - 1; x >= 0; x--) { if (vp[x] > tv) { rgt = x; break; } }
    if (top == null || bot == null || lft == null || rgt == null) return null;
    final dw = rgt - lft, dh = bot - top;
    if (dw < w * 0.06 || dh < h * 0.06 || (dw > w * 0.95 && dh > h * 0.95)) return null;
    const m = 0.008;
    return [(lft / w - m).clamp(0.0, 1.0), (top / h - m).clamp(0.0, 1.0),
            (rgt / w + m).clamp(0.0, 1.0), (bot / h + m).clamp(0.0, 1.0)];
  }

  /// خط الأنابيب الكامل: Grayscale → Blur → Sobel → Find → Crop → Soft Enhance
  static img.Image autoCrop(img.Image src) {
    final w = src.width, h = src.height;
    // تصغير للتحليل
    img.Image small;
    double ratio;
    if (w > 400) {
      ratio = w / 400.0;
      small = img.copyResize(src, width: 400);
    } else {
      ratio = 1;
      small = src;
    }
    final gray = img.grayscale(small);
    final blur = img.gaussianBlur(gray, radius: 2);
    final edges = _sobel(blur);
    final bounds = _findBounds(edges);

    if (bounds != null) {
      final l = (bounds[0] * small.width).toInt().clamp(0, small.width - 1);
      final t = (bounds[1] * small.height).toInt().clamp(0, small.height - 1);
      final r = (bounds[2] * small.width).toInt().clamp(1, small.width);
      final b = (bounds[3] * small.height).toInt().clamp(1, small.height);
      if (ratio > 1) {
        final ol = (l * ratio).toInt().clamp(0, src.width - 1);
        final ot = (t * ratio).toInt().clamp(0, src.height - 1);
        final or = (r * ratio).toInt().clamp(1, src.width);
        final ob = (b * ratio).toInt().clamp(1, src.height);
        final cw = or - ol, ch = ob - ot;
        if (cw > 20 && ch > 20 && cw < src.width * 0.94) {
          return img.copyCrop(src, x: ol, y: ot, width: cw, height: ch);
        }
      } else {
        final cw = r - l, ch = b - t;
        if (cw > 20 && ch > 20 && cw < src.width * 0.94) {
          return img.copyCrop(src, x: l, y: t, width: cw, height: ch);
        }
      }
    }
    return src; // فشل = إرجاع الأصلية
  }

  /// تحسين ناعم (Soft Enhancement) — لا يتلف التفاصيل
  static img.Image softEnhance(img.Image src) {
    return img.adjustColor(src, brightness: 1.04, contrast: 1.10);
  }
}

// ═══════════════════════════════════════════════════════
// MAIN SCREEN — واجهة 80% ورقة + 20% قائمة
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

  static const double pwMm = 210, phMm = 297, marginMm = 10;

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
      // ❌ لا قص تلقائي — الصورة تدخل كما هي
      final encoded = Uint8List.fromList(img.encodeJpg(decoded, quality: 92));
      setState(() {
        final item = DocumentItem(
          id: '${DateTime.now().millisecondsSinceEpoch}$i',
          image: decoded,
          cachedBytes: encoded,
          widthMm: _mode == 'photos' ? 36 : 85,
          heightMm: _mode == 'photos' ? 45 : (decoded.height / decoded.width * 85),
          xMm: marginMm + (_items.length * 4),
          yMm: marginMm + (_items.length * 4),
          isPhotoStyle: _mode == 'photos',
        );
        _items.add(item);
        _activeItem = item;
      });
    }
  }

  void _resizeActive(double w, double h, {bool isPhoto = false}) {
    if (_activeItem == null) return;
    setState(() { _activeItem!.widthMm = w; _activeItem!.heightMm = h; _activeItem!.isPhotoStyle = isPhoto; });
  }

  void _rotateActive() {
    if (_activeItem == null) return;
    setState(() => _activeItem!.applyRotation());
  }

  void _duplicateActive() {
    if (_activeItem == null) return;
    final src = _activeItem!;
    setState(() {
      final n = DocumentItem(
        id: '${DateTime.now().millisecondsSinceEpoch}',
        image: img.copyResize(src.image, width: src.image.width),
        cachedBytes: Uint8List.fromList(src.cachedBytes),
        widthMm: src.widthMm, heightMm: src.heightMm,
        xMm: src.xMm + 5, yMm: src.yMm + 5,
        rotation: src.rotation, isPhotoStyle: src.isPhotoStyle,
      );
      _items.add(n);
      _activeItem = n;
    });
  }

  void _autoAlign() {
    setState(() {
      double cx = marginMm, cy = marginMm, mh = 0;
      for (var item in _items) {
        if (cx + item.widthMm > pwMm - marginMm) { cx = marginMm; cy += mh + 5; mh = 0; }
        item.xMm = cx; item.yMm = cy;
        cx += item.widthMm + 5;
        if (item.heightMm > mh) mh = item.heightMm;
      }
    });
  }

  /// ✅ زر "قص ذكي تلقائي" — يستدعي الخوارزمية عند الطلب فقط
  void _smartCropActive() {
    if (_activeItem == null) return;
    final cropped = SmartScanner.autoCrop(_activeItem!.rotatedImage);
    setState(() {
      _activeItem!.image = cropped;
      _activeItem!.cachedBytes = Uint8List.fromList(img.encodeJpg(cropped, quality: 92));
      _activeItem!.rotation = 0;
      _activeItem!.heightMm = cropped.height / cropped.width * _activeItem!.widthMm;
    });
  }

  void _openManualCrop() async {
    if (_activeItem == null) return;
    final item = _activeItem!;
    final rotated = item.rotatedImage;
    final result = await Navigator.push<img.Image>(
      context,
      MaterialPageRoute(builder: (_) => ManualCropScreen(image: rotated)),
    );
    if (result != null && mounted) {
      setState(() {
        item.image = result;
        item.cachedBytes = Uint8List.fromList(img.encodeJpg(result, quality: 92));
        item.rotation = 0;
        item.heightMm = result.height / result.width * item.widthMm;
      });
    }
  }

  void _exportAndPrint() async {
    final pdf = pw.Document();
    pdf.addPage(pw.Page(pageFormat: PdfPageFormat.a4, margin: pw.EdgeInsets.zero, build: (ctx) {
      final ws = <pw.Widget>[];
      for (final item in _items) {
        final pi = item.rotatedImage;
        ws.add(pw.Positioned(
          left: item.xMm * PdfPageFormat.mm, top: item.yMm * PdfPageFormat.mm,
          child: pw.SizedBox(
            width: item.widthMm * PdfPageFormat.mm, height: item.heightMm * PdfPageFormat.mm,
            child: pw.Image(pw.MemoryImage(Uint8List.fromList(img.encodeJpg(pi, quality: 95))), fit: pw.BoxFit.fill),
          ),
        ));
      }
      return pw.Stack(children: List<pw.Widget>.from(ws));
    }));
    await Printing.layoutPdf(onLayout: (fmt) async => pdf.save());
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
          IconButton(icon: const Icon(Icons.print, size: 20), tooltip: 'طباعة', onPressed: _exportAndPrint),
          IconButton(icon: const Icon(Icons.add_a_photo, size: 20), onPressed: () => _addImages(ImageSource.camera)),
          IconButton(icon: const Icon(Icons.photo_library, size: 20), onPressed: () => _addImages(ImageSource.gallery)),
        ],
      ),
      body: LayoutBuilder(
        builder: (context, constraints) {
          final totalW = constraints.maxWidth;
          final totalH = constraints.maxHeight;
          // ✅ 80% لورقة A4 — 20% للقائمة الجانبية (مصغرة)
          final sidebarW = totalW * 0.20;
          final canvasW = totalW - sidebarW;

          // حساب مقياس ورقة A4 ليملأ 80% المساحة
          final scaleX = (canvasW - 16) / pwMm;
          final scaleY = (totalH - 16) / phMm;
          final scale = min(scaleX, scaleY);

          return Row(children: [
            // ── SIDEBAR (20%) — مصغرة ──────────────────
            SizedBox(
              width: sidebarW,
              child: Container(
                color: const Color(0xFFF8FAFC),
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 6),
                child: SingleChildScrollView(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      // Mode toggle
                      SegmentedButton<String>(
                        segments: const [
                          ButtonSegment(value: 'docs', label: Text('مستمسكات', style: TextStyle(fontSize: 10))),
                          ButtonSegment(value: 'photos', label: Text('صور', style: TextStyle(fontSize: 10))),
                        ],
                        selected: {_mode},
                        onSelectionChanged: (s) { if (s.isNotEmpty) setState(() => _mode = s.first); },
                        style: const ButtonStyle(tapTargetSize: MaterialTapTargetSize.shrinkWrap),
                      ),
                      const SizedBox(height: 4),

                      _btn('ترتيب تلقائي', Icons.auto_awesome, const Color(0xFF10B981), _autoAlign),
                      _btn('قص ذكي تلقائي', Icons.auto_fix_high, const Color(0xFFD97706), _smartCropActive),
                      _btn('قص يدوي', Icons.crop_free, const Color(0xFF0891B2), _openManualCrop),

                      Row(children: [
                        Expanded(child: _btn2('تدوير', Icons.rotate_right, const Color(0xFF475569), _rotateActive)),
                        const SizedBox(width: 3),
                        Expanded(child: _btn2('نسخ', Icons.copy, const Color(0xFF8B5CF6), _duplicateActive)),
                      ]),

                      const SizedBox(height: 4),
                      const Text('القياسات (سم)', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 10, color: Color(0xFF0369A1))),
                      const SizedBox(height: 2),

                      if (_mode == 'docs') ...[
                        _sizeBtn('بطاقة موحدة 5.4×8.5', () => _resizeActive(85, 54)),
                        _sizeBtn('بطاقة سكن 5.8×8.8', () => _resizeActive(88, 58)),
                        _sizeBtn('A4 كامل', () => _resizeActive(210, 297)),
                      ] else ...[
                        _sizeBtn('معاملة 3.6×4.5', () => _resizeActive(36, 45, isPhoto: true)),
                        _sizeBtn('مصغر 2.5×3.4', () => _resizeActive(25, 34, isPhoto: true)),
                      ],

                      if (_activeItem != null) ...[
                        const SizedBox(height: 6),
                        _btn('حذف', Icons.delete, Colors.red, () {
                          setState(() { _items.remove(_activeItem); _activeItem = null; });
                        }),
                      ],
                    ],
                  ),
                ),
              ),
            ),

            // ── CANVAS (80%) — ورقة A4 تملأ المساحة ────
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
                              onPanUpdate: (d) => setState(() {
                                item.xMm += d.delta.dx / scale;
                                item.yMm += d.delta.dy / scale;
                              }),
                              child: Container(
                                decoration: BoxDecoration(
                                  border: Border.all(
                                    color: active ? Colors.blue : (item.isPhotoStyle ? Colors.red : Colors.transparent),
                                    width: active ? 2 : 1,
                                  ),
                                ),
                                child: Transform.rotate(
                                  angle: item.rotation * pi / 180,
                                  child: Image.memory(item.cachedBytes, fit: BoxFit.fill),
                                ),
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
          ]);
        },
      ),
    );
  }

  // ── أزرار مصغرة ────────────────────────────────────
  Widget _btn(String label, IconData icon, Color color, VoidCallback onTap) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 3),
      child: ElevatedButton.icon(
        style: ElevatedButton.styleFrom(
          backgroundColor: color, foregroundColor: Colors.white,
          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 6),
          minimumSize: const Size(0, 28),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(6)),
        ),
        onPressed: onTap,
        icon: Icon(icon, size: 14),
        label: Text(label, style: const TextStyle(fontSize: 9)),
      ),
    );
  }

  Widget _btn2(String label, IconData icon, Color color, VoidCallback onTap) {
    return ElevatedButton.icon(
      style: ElevatedButton.styleFrom(
        backgroundColor: color, foregroundColor: Colors.white,
        padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 6),
        minimumSize: const Size(0, 28),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(6)),
      ),
      onPressed: onTap,
      icon: Icon(icon, size: 13),
      label: Text(label, style: const TextStyle(fontSize: 9)),
    );
  }

  Widget _sizeBtn(String label, VoidCallback onTap) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 2),
      child: SizedBox(
        height: 26,
        child: ElevatedButton(
          style: ElevatedButton.styleFrom(
            padding: const EdgeInsets.symmetric(horizontal: 4),
            minimumSize: const Size(0, 26),
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(5)),
            backgroundColor: Colors.white,
            foregroundColor: const Color(0xFF0369A1),
            side: const BorderSide(color: Color(0xFFCBD5E1)),
          ),
          onPressed: onTap,
          child: Text(label, style: const TextStyle(fontSize: 9)),
        ),
      ),
    );
  }
}

// ═══════════════════════════════════════════════════════
// MANUAL CROP SCREEN — قص يدوي مستقر ومستجيب
// ═══════════════════════════════════════════════════════
class ManualCropScreen extends StatefulWidget {
  final img.Image image;
  const ManualCropScreen({super.key, required this.image});

  @override
  State<ManualCropScreen> createState() => _ManualCropScreenState();
}

class _ManualCropScreenState extends State<ManualCropScreen> {
  late Offset tl, tr, br, bl;
  String _filter = 'soft'; // original, soft, bw
  late Uint8List _displayBytes; // ✅ مخزنة مرة واحدة — لا إعادة تشفير

  @override
  void initState() {
    super.initState();
    tl = const Offset(0.05, 0.05);
    tr = const Offset(0.95, 0.05);
    br = const Offset(0.95, 0.95);
    bl = const Offset(0.05, 0.95);
    // تشفير مرة واحدة للعرض
    _displayBytes = Uint8List.fromList(img.encodeJpg(widget.image, quality: 85));
  }

  void _applyAndPop() {
    final src = widget.image;
    final xs = [tl.dx, tr.dx, br.dx, bl.dx].map((v) => (v * src.width).toInt()).toList();
    final ys = [tl.dy, tr.dy, br.dy, bl.dy].map((v) => (v * src.height).toInt()).toList();
    final minX = xs.reduce(min).clamp(0, src.width - 1);
    final maxX = xs.reduce(max).clamp(1, src.width);
    final minY = ys.reduce(min).clamp(0, src.height - 1);
    final maxY = ys.reduce(max).clamp(1, src.height);
    final cw = max(10, maxX - minX);
    final ch = max(10, maxY - minY);
    var cropped = img.copyCrop(src, x: minX, y: minY, width: cw, height: ch);

    if (_filter == 'soft') {
      cropped = SmartScanner.softEnhance(cropped);
    } else if (_filter == 'bw') {
      cropped = img.grayscale(cropped);
    }
    Navigator.pop(context, cropped);
  }

  // ✅ نقطة سحب دائرية
  Widget _handle(Offset pos, double w, double h, void Function(double dx, double dy) onMove) {
    return Positioned(
      left: pos.dx * w - 15,
      top: pos.dy * h - 15,
      child: GestureDetector(
        onPanUpdate: (d) => setState(() {
          onMove(
            (pos.dx + d.delta.dx / w).clamp(0.0, 1.0),
            (pos.dy + d.delta.dy / h).clamp(0.0, 1.0),
          );
        }),
        child: Container(
          width: 30, height: 30,
          decoration: BoxDecoration(
            color: Colors.blueAccent,
            shape: BoxShape.circle,
            border: Border.all(color: Colors.white, width: 2.5),
            boxShadow: const [BoxShadow(color: Colors.black45, blurRadius: 4)],
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF0F172A),
      appBar: AppBar(
        title: const Text('القص اليدوي', style: TextStyle(fontSize: 14)),
        backgroundColor: Colors.black,
        foregroundColor: Colors.white,
        actions: [
          IconButton(icon: const Icon(Icons.check, color: Colors.greenAccent, size: 26), onPressed: _applyAndPop),
        ],
      ),
      body: Column(children: [
        Container(
          color: Colors.black87,
          padding: const EdgeInsets.symmetric(vertical: 6, horizontal: 12),
          child: Row(mainAxisAlignment: MainAxisAlignment.center, children: [
            const Text('الفلتر: ', style: TextStyle(color: Colors.white70, fontSize: 11)),
            const SizedBox(width: 6),
            ChoiceChip(label: const Text('أصلي', style: TextStyle(fontSize: 10)), selected: _filter == 'original', onSelected: (_) => setState(() => _filter = 'original'), selectedColor: Colors.blueGrey),
            const SizedBox(width: 4),
            ChoiceChip(label: const Text('تحسين ناعم', style: TextStyle(fontSize: 10)), selected: _filter == 'soft', onSelected: (_) => setState(() => _filter = 'soft'), selectedColor: Colors.blueGrey),
            const SizedBox(width: 4),
            ChoiceChip(label: const Text('أبيض وأسود', style: TextStyle(fontSize: 10)), selected: _filter == 'bw', onSelected: (_) => setState(() => _filter = 'bw'), selectedColor: Colors.blueGrey),
            const SizedBox(width: 10),
            TextButton.icon(
              onPressed: () => setState(() {
                tl = Offset(0.05, 0.05); tr = Offset(0.95, 0.05);
                br = Offset(0.95, 0.95); bl = Offset(0.05, 0.95);
              }),
              icon: const Icon(Icons.center_focus_strong, size: 14, color: Colors.white),
              label: const Text('إعادة', style: TextStyle(fontSize: 10, color: Colors.white)),
            ),
          ]),
        ),
        Expanded(
          child: LayoutBuilder(
            builder: (c, constraints) {
              final w = constraints.maxWidth, h = constraints.maxHeight;
              return Stack(children: [
                Center(child: Image.memory(_displayBytes, fit: BoxFit.contain)),
                // خطوط القص
                CustomPaint(size: Size(w, h), painter: _LinePainter([tl, tr, br, bl])),
                // نقاط السحب
                _handle(tl, w, h, (dx, dy) => tl = Offset(dx, dy)),
                _handle(tr, w, h, (dx, dy) => tr = Offset(dx, dy)),
                _handle(br, w, h, (dx, dy) => br = Offset(dx, dy)),
                _handle(bl, w, h, (dx, dy) => bl = Offset(dx, dy)),
              ]);
            },
          ),
        ),
      ]),
    );
  }
}

class _LinePainter extends CustomPainter {
  final List<Offset> pts;
  _LinePainter(this.pts);
  @override
  void paint(Canvas canvas, Size size) {
    final p = Paint()..color = Colors.cyanAccent..strokeWidth = 2..style = PaintingStyle.stroke;
    final path = Path()..moveTo(pts[0].dx * size.width, pts[0].dy * size.height);
    for (int i = 1; i < 4; i++) path.lineTo(pts[i].dx * size.width, pts[i].dy * size.height);
    path.close();
    canvas.drawPath(path, p);
  }
  @override
  bool shouldRepaint(covariant CustomPainter o) => true;
}
