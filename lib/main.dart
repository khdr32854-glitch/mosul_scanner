import 'dart:io';
import 'dart:math';
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:image/image.dart' as img;
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';
import 'package:edge_detection/edge_detection.dart' as edge;
import 'package:path_provider/path_provider.dart';

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
    final tmp = widthMm;
    widthMm = heightMm;
    heightMm = tmp;
    rotation = 0;
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
  bool _isProcessing = false;

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
          xMm: mMm + (_items.length * 4),
          yMm: mMm + (_items.length * 4),
          isPhotoStyle: _mode == 'photos',
        );
        _items.add(item);
        _activeItem = item;
      });
    }
  }

  void _resize(double w, double h, {bool isPhoto = false}) {
    if (_activeItem == null) return;
    setState(() {
      _activeItem!.widthMm = w;
      _activeItem!.heightMm = h;
      _activeItem!.isPhotoStyle = isPhoto;
    });
  }

  void _rotate() {
    if (_activeItem != null) setState(() => _activeItem!.applyRotation());
  }

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
      _items.add(n);
      _activeItem = n;
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

  // ════════════════ قص تلقائي باستخدام OpenCV الأصلي ════════════════
  void _smartCrop() async {
    if (_activeItem == null) return;
    setState(() => _isProcessing = true);
    try {
      final dir = await getApplicationDocumentsDirectory();
      final path = '${dir.path}/crop_${DateTime.now().millisecondsSinceEpoch}.jpg';

      // حفظ الصورة الحالية
      await File(path).writeAsBytes(_activeItem!.cachedBytes);

      // استدعاء OpenCV الأصلي للكشف عن الحواف والقص
      final result = await edge.EdgeDetection.detectEdge(
        path,
//        androidScanTitle: 'مسح',
//        androidCropTitle: 'قص',
//        androidCropBlackWhiteTitle: 'أبيض وأسود',
//        androidCropReset: 'إعادة',
      );

      if (result != null && mounted) {
        final bytes = await File(path).readAsBytes();
        final cropped = img.decodeImage(bytes);
        if (cropped != null) {
          setState(() {
            _activeItem!.image = cropped;
            _activeItem!.cachedBytes = Uint8List.fromList(img.encodeJpg(cropped, quality: 92));
            _activeItem!.rotation = 0;
            _activeItem!.heightMm = cropped.height / cropped.width * _activeItem!.widthMm;
          });
        }
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('فشل القص التلقائي: $e'), backgroundColor: Colors.red),
        );
      }
    } finally {
      if (mounted) setState(() => _isProcessing = false);
    }
  }

  // ════════════════ قص يدوي ════════════════
  void _manualCrop() async {
    if (_activeItem == null) return;
    final r = _activeItem!.rotatedImage;
    final result = await Navigator.push<img.Image>(
      context,
      MaterialPageRoute(builder: (_) => ManualCropScreen(image: r)),
    );
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
        ws.add(pw.Positioned(
          left: i.xMm * PdfPageFormat.mm, top: i.yMm * PdfPageFormat.mm,
          child: pw.SizedBox(
            width: i.widthMm * PdfPageFormat.mm, height: i.heightMm * PdfPageFormat.mm,
            child: pw.Image(pw.MemoryImage(Uint8List.fromList(img.encodeJpg(pi, quality: 95))), fit: pw.BoxFit.fill),
          ),
        ));
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
          Text('مكتب علاء الحديدي - الماسح الذكي', style: TextStyle(fontSize: 13, fontWeight: FontWeight.bold)),
          Text('Telegram: @Oo_qp', style: TextStyle(fontSize: 9, color: Colors.white70)),
        ]),
        backgroundColor: const Color(0xFF0284C7),
        foregroundColor: Colors.white,
        actions: [
          IconButton(icon: const Icon(Icons.print, size: 18), tooltip: 'طباعة', onPressed: _print),
          IconButton(icon: const Icon(Icons.add_a_photo, size: 18), onPressed: () => _addImages(ImageSource.camera)),
          IconButton(icon: const Icon(Icons.photo_library, size: 18), onPressed: () => _addImages(ImageSource.gallery)),
        ],
      ),
      body: LayoutBuilder(
        builder: (context, constraints) {
          final tw = constraints.maxWidth;
          final th = constraints.maxHeight;
          final sidebarW = tw * 0.19;
          final canvasW = tw - sidebarW;
          final topBarH = 44.0;
          final canvasH = th - topBarH;
          final sx = (canvasW - 12) / pwMm;
          final sy = (canvasH - 12) / phMm;
          final scale = min(sx, sy);

          return Column(children: [
            // ── شريط أدوات علوي ──────────────────────
            Container(
              height: topBarH,
              padding: const EdgeInsets.symmetric(horizontal: 8),
              decoration: const BoxDecoration(
                color: Color(0xFF1E293B),
                border: Border(bottom: BorderSide(color: Color(0xFF334155))),
              ),
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
                const SizedBox(width: 10),
                _tb('قص ذكي', Icons.auto_fix_high, const Color(0xFFD97706), _smartCrop, _isProcessing),
                _tb('قص يدوي', Icons.crop_free, const Color(0xFF0891B2), _manualCrop, false),
                _tb('ترتيب', Icons.auto_awesome, const Color(0xFF10B981), _align, false),
                const Spacer(),
                _tb('تدوير', Icons.rotate_right, const Color(0xFF94A3B8), _rotate, false),
                _tb('نسخ', Icons.copy, const Color(0xFFA78BFA), _duplicate, false),
              ]),
            ),

            // ── المحتوى الرئيسي ──────────────────────
            Expanded(
              child: Row(children: [
                // ── SIDEBAR ──────────────────────────
                SizedBox(
                  width: sidebarW,
                  child: Container(
                    color: const Color(0xFFF1F5F9),
                    padding: const EdgeInsets.all(6),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
                          decoration: BoxDecoration(color: const Color(0xFF0369A1), borderRadius: BorderRadius.circular(4)),
                          child: const Text('القياسات (سم)', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 10, color: Colors.white)),
                        ),
                        const SizedBox(height: 4),
                        if (_mode == 'docs') ...[
                          _sz('بطاقة موحدة\n8.5 × 5.4', () => _resize(85, 54)),
                          _sz('بطاقة سكن\n8.8 × 5.8', () => _resize(88, 58)),
                          _sz('ورقة كاملة\nA4', () => _resize(210, 297), color: const Color(0xFF0F766E)),
                        ] else ...[
                          _sz('معاملة\n3.6 × 4.5', () => _resize(36, 45, isPhoto: true)),
                          _sz('مصغر\n2.5 × 3.4', () => _resize(25, 34, isPhoto: true)),
                        ],
                        const Spacer(),
                        if (_activeItem != null)
                          SizedBox(
                            height: 32,
                            child: ElevatedButton.icon(
                              style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFFDC2626), foregroundColor: Colors.white, shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(6))),
                              onPressed: () => setState(() { _items.remove(_activeItem); _activeItem = null; }),
                              icon: const Icon(Icons.delete_outline, size: 14),
                              label: const Text('حذف العنصر', style: TextStyle(fontSize: 10, fontWeight: FontWeight.bold)),
                            ),
                          ),
                      ],
                    ),
                  ),
                ),

                // ── CANVAS ───────────────────────────
                Expanded(
                  child: Container(
                    color: const Color(0xFF1E293B),
                    child: Center(
                      child: Container(
                        width: pwMm * scale,
                        height: phMm * scale,
                        decoration: BoxDecoration(
                          color: Colors.white,
                          boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.6), blurRadius: 14, offset: const Offset(0, 4))],
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
                                    decoration: BoxDecoration(
                                      border: Border.all(color: active ? Colors.blue : (item.isPhotoStyle ? Colors.red.withOpacity(0.5) : Colors.transparent), width: active ? 2.5 : 1),
                                      boxShadow: active ? [BoxShadow(color: Colors.blue.withOpacity(0.3), blurRadius: 6)] : null,
                                    ),
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

  Widget _tb(String label, IconData icon, Color color, VoidCallback onTap, bool loading) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 2),
      child: TextButton(
        style: TextButton.styleFrom(padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 4), minimumSize: Size.zero, tapTargetSize: MaterialTapTargetSize.shrinkWrap),
        onPressed: loading ? null : onTap,
        child: Row(mainAxisSize: MainAxisSize.min, children: [
          loading ? const SizedBox(width: 14, height: 14, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white)) : Icon(icon, size: 15, color: color),
          const SizedBox(width: 3),
          Text(label, style: TextStyle(fontSize: 10, fontWeight: FontWeight.w600, color: loading ? Colors.white54 : Colors.white)),
        ]),
      ),
    );
  }

  Widget _sz(String label, VoidCallback onTap, {Color color = const Color(0xFF0369A1)}) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 3),
      child: SizedBox(
        height: 34,
        child: ElevatedButton(
          style: ElevatedButton.styleFrom(
            padding: const EdgeInsets.symmetric(horizontal: 2),
            minimumSize: const Size(0, 34),
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(5)),
            backgroundColor: color.withOpacity(0.08),
            foregroundColor: color,
            side: BorderSide(color: color.withOpacity(0.3)),
            elevation: 0,
          ),
          onPressed: onTap,
          child: Text(label, textAlign: TextAlign.center, style: TextStyle(fontSize: 9, fontWeight: FontWeight.w600, color: color, height: 1.2)),
        ),
      ),
    );
  }
}

// ═══════════════════════════════════════════════════════
// MANUAL CROP — 4 نقاط دائرية مع سحب سلس
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
  late Uint8List _displayBytes;

  @override
  void initState() {
    super.initState();
    _tlX = 0.05; _tlY = 0.05; _trX = 0.95; _trY = 0.05;
    _brX = 0.95; _brY = 0.95; _blX = 0.05; _blY = 0.95;
    _displayBytes = Uint8List.fromList(img.encodeJpg(widget.image, quality: 82));
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
    if (_filter == 'soft') {
      c = img.adjustColor(c, brightness: 1.03, contrast: 1.08);
    } else if (_filter == 'bw') {
      c = img.grayscale(c);
    }
    Navigator.pop(context, c);
  }

  // ✅ نقطة بحجم 44px لسهولة اللمس
  Widget _dot(double x, double y, double w, double h, void Function(double, double) set) {
    return Positioned(
      left: x * w - 22,
      top: y * h - 22,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onPanUpdate: (d) {
          setState(() {
            set((x + d.delta.dx / w).clamp(0.0, 1.0), (y + d.delta.dy / h).clamp(0.0, 1.0));
          });
        },
        child: Container(
          width: 44,
          height: 44,
          decoration: BoxDecoration(
            color: const Color(0xFF2563EB),
            shape: BoxShape.circle,
            border: Border.all(color: Colors.white, width: 3),
            boxShadow: const [BoxShadow(color: Colors.black54, blurRadius: 6)],
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF0B1121),
      appBar: AppBar(
        title: const Text('القص اليدوي', style: TextStyle(fontSize: 14)),
        centerTitle: true,
        backgroundColor: Colors.black,
        foregroundColor: Colors.white,
        actions: [
          Padding(
            padding: const EdgeInsets.only(right: 8),
            child: IconButton(icon: const Icon(Icons.check_circle, color: Color(0xFF10B981), size: 30), onPressed: _apply),
          ),
        ],
      ),
      body: Column(children: [
        Container(
          color: const Color(0xFF1A1F2E),
          padding: const EdgeInsets.symmetric(vertical: 6, horizontal: 10),
          child: Row(mainAxisAlignment: MainAxisAlignment.center, children: [
            const Text('الفلتر:  ', style: TextStyle(color: Colors.white70, fontSize: 11)),
            _chip('أصلي', _filter == 'original', () => setState(() => _filter = 'original')),
            _chip('ناعم ✨', _filter == 'soft', () => setState(() => _filter = 'soft')),
            _chip('أبيض وأسود', _filter == 'bw', () => setState(() => _filter = 'bw')),
            const SizedBox(width: 8),
            TextButton.icon(
              onPressed: () => setState(() { _tlX = _tlY = 0.05; _trX = 0.95; _trY = 0.05; _brX = _brY = 0.95; _blX = 0.05; _blY = 0.95; }),
              icon: const Icon(Icons.refresh, size: 14, color: Colors.white60),
              label: const Text('إعادة', style: TextStyle(fontSize: 10, color: Colors.white60)),
            ),
          ]),
        ),
        Expanded(
          child: LayoutBuilder(builder: (_, c) {
            final w = c.maxWidth, h = c.maxHeight;
            return Stack(children: [
              Center(child: Image.memory(_displayBytes, fit: BoxFit.contain)),
              // تراكب شفاف خارج منطقة القص
              Positioned.fill(
                child: IgnorePointer(
                  child: CustomPaint(
                    painter: _OverlayPainter(_tlX * w, _tlY * h, _trX * w, _trY * h, _brX * w, _brY * h, _blX * w, _blY * h),
                  ),
                ),
              ),
              // خطوط القص
              CustomPaint(size: Size(w, h), painter: _LP([
                Offset(_tlX * w, _tlY * h), Offset(_trX * w, _trY * h),
                Offset(_brX * w, _brY * h), Offset(_blX * w, _blY * h),
              ])),
              // نقاط السحب
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

  Widget _chip(String label, bool sel, VoidCallback onTap) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 2),
      child: ChoiceChip(
        label: Text(label, style: TextStyle(fontSize: 10, fontWeight: FontWeight.w600, color: sel ? Colors.white : Colors.white70)),
        selected: sel,
        onSelected: (_) => onTap(),
        selectedColor: const Color(0xFF2563EB),
        backgroundColor: const Color(0xFF1E293B),
        side: BorderSide.none,
        padding: const EdgeInsets.symmetric(horizontal: 4),
        visualDensity: VisualDensity.compact,
      ),
    );
  }
}

// ════════════════ رسام التراكب الشفاف خارج منطقة القص ════════════════
class _OverlayPainter extends CustomPainter {
  final double x1, y1, x2, y2, x3, y3, x4, y4;
  _OverlayPainter(this.x1, this.y1, this.x2, this.y2, this.x3, this.y3, this.x4, this.y4);

  @override
  void paint(Canvas c, Size s) {
    final outer = Path()..addRect(Rect.fromLTWH(0, 0, s.width, s.height));
    final inner = Path()
      ..moveTo(x1, y1)..lineTo(x2, y2)..lineTo(x3, y3)..lineTo(x4, y4)..close();
    final combined = Path.combine(PathOperation.difference, outer, inner);
    c.drawPath(combined, Paint()..color = Colors.black.withOpacity(0.55));
  }

  @override
  bool shouldRepaint(_) => true;
}

// ════════════════ رسام خطوط القص ════════════════
class _LP extends CustomPainter {
  final List<Offset> pts;
  _LP(this.pts);
  @override
  void paint(Canvas c, Size s) {
    final p = Paint()..color = const Color(0xFF22D3EE)..strokeWidth = 2.5..style = PaintingStyle.stroke;
    final path = Path()..moveTo(pts[0].dx, pts[0].dy);
    for (int i = 1; i < 4; i++) path.lineTo(pts[i].dx, pts[i].dy);
    path.close();
    c.drawPath(path, p);
  }
  @override
  bool shouldRepaint(_) => true;
}

