import 'dart:io';
import 'dart:math';
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:image/image.dart' as img;
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';
import 'crop_engine.dart';

void main() => runApp(const MosulScannerApp());

class MosulScannerApp extends StatelessWidget {
  const MosulScannerApp({super.key});
  @override
  Widget build(BuildContext c) => MaterialApp(
    title: 'مكتب علاء الحديدي - الماسح والطباعة',
    debugShowCheckedModeBanner: false,
    theme: ThemeData(primarySwatch: Colors.blue, useMaterial3: true),
    home: const MainScreen(),
  );
}

class DocItem {
  String id;
  img.Image image;
  Uint8List bytes;
  double wMm, hMm, xMm, yMm;
  int rot;
  bool photo;
  DocItem({required this.id, required this.image, required this.bytes, required this.wMm, required this.hMm, required this.xMm, required this.yMm, this.rot = 0, this.photo = false});

  img.Image get rotated {
    if (rot % 360 == 0) return image;
    final r = (rot % 360 + 360) % 360;
    if (r == 90) return img.copyRotate(image, angle: 90);
    if (r == 180) return img.copyRotate(image, angle: 180);
    if (r == 270) return img.copyRotate(image, angle: 270);
    return image;
  }

  void applyRot() {
    if (rot % 360 == 0) return;
    image = rotated;
    bytes = Uint8List.fromList(ImageUtils.encodeJpg(image));
    final t = wMm; wMm = hMm; hMm = t; rot = 0;
  }

  void replaceImage(img.Image newImg) {
    image = newImg;
    bytes = Uint8List.fromList(ImageUtils.encodeJpg(newImg));
    rot = 0;
    hMm = newImg.height / newImg.width * wMm;
  }
}

class MainScreen extends StatefulWidget {
  const MainScreen({super.key});
  @override State<MainScreen> createState() => _MainScreenState();
}

class _MainScreenState extends State<MainScreen> {
  final List<DocItem> _items = [];
  DocItem? _sel;
  final ImagePicker _picker = ImagePicker();
  String _mode = 'docs';
  static const pwM = 210.0, phM = 297.0, mM = 10.0;

  /// فتح Google ML Kit Document Scanner
  void _googleScan() async {
    final available = await GoogleScanner.isAvailable();
    if (!available && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Google Scanner غير متوفر — استخدام الكاميرا العادية'), backgroundColor: Colors.blue, duration: Duration(seconds: 2)),
      );
      _addImgs(ImageSource.camera);
      return;
    }
    if (!mounted) return;
    final paths = await GoogleScanner.scan();
    if (paths == null || paths.isEmpty) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('تم إلغاء المسح'), backgroundColor: Colors.grey, duration: Duration(seconds: 1)),
      );
      return;
    }
    for (int i = 0; i < paths.length; i++) {
      final raw = await File(paths[i]).readAsBytes();
      final dec = ImageUtils.decodeBytes(raw);
      if (dec == null) continue;
      final enc = Uint8List.fromList(ImageUtils.encodeJpg(dec));
      if (!mounted) return;
      setState(() {
        final item = DocItem(
          id: 'gs_${DateTime.now().millisecondsSinceEpoch}$i',
          image: dec, bytes: enc,
          wMm: _mode == 'photos' ? 36 : 85,
          hMm: _mode == 'photos' ? 45 : (dec.height / dec.width * 85),
          xMm: mM + _items.length * 4, yMm: mM + _items.length * 4,
          photo: _mode == 'photos',
        );
        _items.add(item); _sel = item;
      });
      try { File(paths[i]).deleteSync(); } catch (_) {}
    }
  }

  void _addImgs(ImageSource src) async {
    final List<XFile> files;
    if (src == ImageSource.gallery) {
      files = await _picker.pickMultiImage();
    } else {
      final f = await _picker.pickImage(source: src, imageQuality: 95);
      files = f != null ? [f] : [];
    }
    for (int i = 0; i < files.length; i++) {
      final raw = await File(files[i].path).readAsBytes();
      final dec = ImageUtils.decodeBytes(raw);
      if (dec == null) continue;
      final enc = Uint8List.fromList(ImageUtils.encodeJpg(dec));
      if (!mounted) return;
      setState(() {
        final item = DocItem(
          id: '${DateTime.now().millisecondsSinceEpoch}$i',
          image: dec, bytes: enc,
          wMm: _mode == 'photos' ? 36 : 85,
          hMm: _mode == 'photos' ? 45 : (dec.height / dec.width * 85),
          xMm: mM + _items.length * 4, yMm: mM + _items.length * 4,
          photo: _mode == 'photos',
        );
        _items.add(item); _sel = item;
      });
    }
  }

  void _resz(double w, double h, {bool p = false}) {
    if (_sel != null) setState(() { _sel!.wMm = w; _sel!.hMm = h; _sel!.photo = p; });
  }

  void _rot() { if (_sel != null) setState(() => _sel!.applyRot()); }

  void _dup() {
    if (_sel == null) return;
    final s = _sel!;
    setState(() {
      _items.add(DocItem(
        id: '${DateTime.now().millisecondsSinceEpoch}',
        image: img.copyResize(s.image, width: s.image.width),
        bytes: Uint8List.fromList(s.bytes),
        wMm: s.wMm, hMm: s.hMm, xMm: s.xMm + 5, yMm: s.yMm + 5,
        rot: s.rot, photo: s.photo,
      ));
      _sel = _items.last;
    });
  }

  void _aln() {
    setState(() {
      double cx = mM, cy = mM, mh = 0;
      for (var i in _items) {
        if (cx + i.wMm > pwM - mM) { cx = mM; cy += mh + 5; mh = 0; }
        i.xMm = cx; i.yMm = cy; cx += i.wMm + 5; if (i.hMm > mh) mh = i.hMm;
      }
    });
  }

  void _autoCrop() {
    if (_sel == null) return;
    final result = SmartCrop.detect(_sel!.rotated);
    if (result.changed) {
      setState(() => _sel!.replaceImage(result.image));
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('لم يتم اكتشاف مستند'), backgroundColor: Colors.orange, duration: Duration(seconds: 1)),
      );
    }
  }

  void _manualCrop() async {
    if (_sel == null) return;
    final ri = _sel!.rotated;
    final res = await Navigator.push<img.Image>(context, MaterialPageRoute(builder: (_) => CropScreen(image: ri)));
    if (res != null && mounted) setState(() => _sel!.replaceImage(res));
  }

  void _prnt() async {
    final doc = pw.Document();
    doc.addPage(pw.Page(pageFormat: PdfPageFormat.a4, margin: pw.EdgeInsets.zero, build: (_) {
      final ws = <pw.Widget>[];
      for (final i in _items) {
        final pi = i.rotated;
        ws.add(pw.Positioned(left: i.xMm * PdfPageFormat.mm, top: i.yMm * PdfPageFormat.mm,
          child: pw.SizedBox(width: i.wMm * PdfPageFormat.mm, height: i.hMm * PdfPageFormat.mm,
            child: pw.Image(pw.MemoryImage(Uint8List.fromList(ImageUtils.encodeJpg(pi, quality: 95))), fit: pw.BoxFit.fill))));
      }
      return pw.Stack(children: List<pw.Widget>.from(ws));
    }));
    await Printing.layoutPdf(onLayout: (_) async => doc.save());
  }

  @override
  Widget build(BuildContext c) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('مكتب علاء الحديدي - الماسح الذكي', style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold)),
        backgroundColor: const Color(0xFF0284C7), foregroundColor: Colors.white,
        actions: [
          IconButton(icon: const Icon(Icons.print, size: 18), tooltip: 'طباعة', onPressed: _prnt),
          // Google ML Kit Scanner — الزر الرئيسي للمسح
          IconButton(
            icon: const Icon(Icons.document_scanner, size: 20, color: Color(0xFF4ADE80)),
            tooltip: 'مسح Google الذكي',
            onPressed: _googleScan,
          ),
          IconButton(icon: const Icon(Icons.add_a_photo, size: 18), onPressed: () => _addImgs(ImageSource.camera)),
          IconButton(icon: const Icon(Icons.photo_library, size: 18), onPressed: () => _addImgs(ImageSource.gallery)),
        ],
      ),
      body: LayoutBuilder(builder: (_, cc) {
        final sw = cc.maxWidth * 0.19, cw = cc.maxWidth - sw, tbh = 48.0;
        final sc = min((cw - 20) / pwM, (cc.maxHeight - tbh - 20) / phM);
        return Column(children: [
          // شريط الأدوات
          Container(height: tbh, padding: const EdgeInsets.symmetric(horizontal: 4),
            decoration: const BoxDecoration(color: Color(0xFF1E293B)),
            child: Row(children: [
              const SizedBox(width: 4),
              _tb('مستمسكات', _mode == 'docs', () => setState(() => _mode = 'docs')),
              _tb('صور', _mode == 'photos', () => setState(() => _mode = 'photos')),
              const Spacer(),
              _tb('قص تلقائي', false, const Color(0xFFF59E0B), _autoCrop),
              _tb('قص يدوي', false, const Color(0xFF06B6D4), _manualCrop),
              _tb('ترتيب', false, const Color(0xFF10B981), _aln),
              _tb('تدوير', false, const Color(0xFF94A3B8), _rot),
              _tb('نسخ', false, const Color(0xFFA78BFA), _dup),
            ])),
          Expanded(child: Row(children: [
            // Sidebar
            SizedBox(width: sw, child: Container(color: const Color(0xFFF1F5F9),
              child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                Container(margin: const EdgeInsets.all(4), padding: const EdgeInsets.all(6),
                  decoration: BoxDecoration(color: const Color(0xFF0369A1), borderRadius: BorderRadius.circular(4)),
                  child: const Text('القياسات (سم)', textAlign: TextAlign.center,
                    style: TextStyle(fontWeight: FontWeight.bold, fontSize: 10, color: Colors.white))),
                if (_mode == 'docs') ...[
                  _sz('بطاقة موحدة', '8.5 × 5.4', () => _resz(85, 54)),
                  _sz('بطاقة سكن', '8.8 × 5.8', () => _resz(88, 58)),
                  _sz('ورقة كاملة A4', '21 × 29.7', () => _resz(210, 297), clr: const Color(0xFF0F766E)),
                ] else ...[
                  _sz('معاملة', '3.6 × 4.5', () => _resz(36, 45, p: true)),
                  _sz('مصغر', '2.5 × 3.4', () => _resz(25, 34, p: true)),
                ],
                const Spacer(),
                if (_sel != null)
                  Padding(padding: const EdgeInsets.all(4), child: SizedBox(height: 30, child: ElevatedButton.icon(
                    style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFFDC2626), foregroundColor: Colors.white,
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(6)), padding: const EdgeInsets.symmetric(horizontal: 6)),
                    onPressed: () => setState(() { _items.remove(_sel); _sel = null; }),
                    icon: const Icon(Icons.delete_outline, size: 14),
                    label: const Text('حذف', style: TextStyle(fontSize: 10, fontWeight: FontWeight.bold))))),
              ]))),
            // Canvas
            Expanded(child: RepaintBoundary(child: Container(color: const Color(0xFF1E293B),
              child: Center(child: Container(width: pwM * sc, height: phM * sc,
                decoration: BoxDecoration(color: Colors.white, boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.4), blurRadius: 12)]),
                child: ClipRect(child: Stack(children: [
                  for (int i = 0; i < _items.length; i++)
                    _buildItem(_items[i], sc),
                ]))))),
            )),
          ])),
        ]);
      }),
    );
  }

  Widget _buildItem(DocItem it, double sc) {
    final act = _sel?.id == it.id;
    return Positioned(
      left: it.xMm * sc, top: it.yMm * sc, width: it.wMm * sc, height: it.hMm * sc,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: () => setState(() => _sel = it),
        onPanUpdate: (d) => setState(() { it.xMm += d.delta.dx / sc; it.yMm += d.delta.dy / sc; }),
        child: Container(
          decoration: BoxDecoration(
            border: Border.all(color: act ? Colors.blue : (it.photo ? Colors.red.withOpacity(0.4) : Colors.transparent), width: act ? 3 : 1),
            boxShadow: act ? [BoxShadow(color: Colors.blue.withOpacity(0.4), blurRadius: 8)] : null),
          child: Transform.rotate(angle: it.rot * pi / 180, child: Image.memory(it.bytes, fit: BoxFit.fill)),
        ),
      ),
    );
  }

  Widget _tb(String l, bool sel, VoidCallback fn) => Padding(padding: const EdgeInsets.symmetric(horizontal: 2),
    child: Material(color: Colors.transparent, child: InkWell(onTap: fn, borderRadius: BorderRadius.circular(6),
      child: Container(padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
        decoration: BoxDecoration(color: sel ? const Color(0xFF0284C7).withOpacity(0.25) : Colors.transparent,
          borderRadius: BorderRadius.circular(6), border: Border.all(color: sel ? const Color(0xFF0284C7) : Colors.white24, width: 1)),
        child: Text(l, style: TextStyle(fontSize: 10, fontWeight: FontWeight.w700, color: sel ? const Color(0xFF38BDF8) : Colors.white))))));

  Widget _sz(String t, String sub, VoidCallback fn, {Color clr = const Color(0xFF0369A1)}) => Padding(
    padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2), child: SizedBox(height: 38, child: ElevatedButton(
      style: ElevatedButton.styleFrom(padding: EdgeInsets.zero, minimumSize: Size.zero,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(6)),
        backgroundColor: clr.withOpacity(0.06), foregroundColor: clr, side: BorderSide(color: clr.withOpacity(0.35)), elevation: 0),
      onPressed: fn, child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
        Text(t, style: TextStyle(fontSize: 9, fontWeight: FontWeight.w700, color: clr)),
        Text(sub, style: TextStyle(fontSize: 7, fontWeight: FontWeight.w500, color: clr.withOpacity(0.7)))]))));
}

// ═══════════════════════════════════════
// شاشة القص اليدوي — خفيفة وسريعة
// ═══════════════════════════════════════
class CropScreen extends StatefulWidget {
  final img.Image image;
  const CropScreen({super.key, required this.image});
  @override State<CropScreen> createState() => _CropScreenState();
}

class _CropScreenState extends State<CropScreen> {
  double _x1 = 0.05, _y1 = 0.05;
  double _x2 = 0.95, _y2 = 0.05;
  double _x3 = 0.95, _y3 = 0.95;
  double _x4 = 0.05, _y4 = 0.95;
  EnhanceMode _filt = EnhanceMode.soft;
  late Uint8List _disp;

  @override
  void initState() {
    super.initState();
    _disp = Uint8List.fromList(ImageUtils.encodeJpg(widget.image, quality: 92));
  }

  void _done() {
    var res = ManualCrop.cropFromPoints(widget.image, _x1, _y1, _x2, _y2, _x3, _y3, _x4, _y4);
    res = ImageEnhancer.apply(res, _filt);
    Navigator.pop(context, res);
  }

  void _reset() {
    setState(() { _x1 = _y1 = 0.05; _x2 = 0.95; _y2 = 0.05; _x3 = 0.95; _y3 = 0.95; _x4 = 0.05; _y4 = 0.95; });
  }

  @override
  Widget build(BuildContext c) {
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: const Color(0xFF111827),
        leading: IconButton(icon: const Icon(Icons.close, color: Colors.white70), onPressed: () => Navigator.pop(context)),
        title: Row(mainAxisSize: MainAxisSize.min, children: [
          _chip('أصلي', _filt == EnhanceMode.none, () => setState(() => _filt = EnhanceMode.none)),
          const SizedBox(width: 6),
          _chip('تحسين ✨', _filt == EnhanceMode.soft, () => setState(() => _filt = EnhanceMode.soft)),
          const SizedBox(width: 6),
          _chip('أبيض وأسود', _filt == EnhanceMode.bw, () => setState(() => _filt = EnhanceMode.bw)),
        ]),
        actions: [
          TextButton.icon(onPressed: _reset, icon: const Icon(Icons.refresh, size: 16, color: Colors.orange),
            label: const Text('إعادة', style: TextStyle(fontSize: 11, color: Colors.orange))),
          FilledButton.icon(
            style: FilledButton.styleFrom(backgroundColor: const Color(0xFF10B981), padding: const EdgeInsets.symmetric(horizontal: 16)),
            onPressed: _done, icon: const Icon(Icons.check, size: 18),
            label: const Text('تطبيق ✓', style: TextStyle(fontSize: 13, fontWeight: FontWeight.bold)),
          ),
        ],
      ),
      body: LayoutBuilder(builder: (_, cc) {
        final w = cc.maxWidth, h = cc.maxHeight;
        return Stack(children: [
          // الصورة
          Center(child: Image.memory(_disp, fit: BoxFit.contain)),
          // التراكب الداكن + خطوط القص — نستخدم Stack بدل CustomPaint للسرعة
          ..._buildOverlay(w, h),
          // نقاط السحب
          _dot(_x1, _y1, w, h, (dx, dy) => setState(() { _x1 = dx; _y1 = dy; })),
          _dot(_x2, _y2, w, h, (dx, dy) => setState(() { _x2 = dx; _y2 = dy; })),
          _dot(_x3, _y3, w, h, (dx, dy) => setState(() { _x3 = dx; _y3 = dy; })),
          _dot(_x4, _y4, w, h, (dx, dy) => setState(() { _x4 = dx; _y4 = dy; })),
        ]);
      }),
    );
  }

  List<Widget> _buildOverlay(double w, double h) {
    // حساب المنطقة الداخلية
    final left = min(min(_x1, _x4) * w, min(_x2, _x3) * w);
    final top = min(min(_y1, _y2) * h, min(_y3, _y4) * h);
    final right = max(max(_x1, _x4) * w, max(_x2, _x3) * w);
    final bottom = max(max(_y1, _y2) * h, max(_y3, _y4) * h);

    return [
      // أعلى
      Positioned(left: 0, top: 0, width: w, height: top.clamp(0, h),
        child: Container(color: Colors.black54)),
      // أسفل
      Positioned(left: 0, top: bottom.clamp(0, h), width: w, height: (h - bottom).clamp(0, h),
        child: Container(color: Colors.black54)),
      // يسار
      Positioned(left: 0, top: top.clamp(0, h), width: left.clamp(0, w), height: (bottom - top).clamp(0, h),
        child: Container(color: Colors.black54)),
      // يمين
      Positioned(left: right.clamp(0, w), top: top.clamp(0, h), width: (w - right).clamp(0, w), height: (bottom - top).clamp(0, h),
        child: Container(color: Colors.black54)),
      // إطار مضيء حول منطقة القص
      Positioned(left: left.clamp(0, w) - 1, top: top.clamp(0, h) - 1,
        width: (right - left).clamp(0, w) + 2, height: (bottom - top).clamp(0, h) + 2,
        child: IgnorePointer(child: Container(
          decoration: BoxDecoration(border: Border.all(color: const Color(0xFF22D3EE), width: 2)),
        ))),
    ];
  }

  Widget _dot(double x, double y, double w, double h, void Function(double, double) setXY) {
    return Positioned(
      left: x * w - 28, top: y * h - 28,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onPanUpdate: (d) => setXY(
          (x + d.delta.dx / w).clamp(0.0, 1.0),
          (y + d.delta.dy / h).clamp(0.0, 1.0),
        ),
        child: Container(width: 56, height: 56,
          decoration: BoxDecoration(
            color: const Color(0xFF2563EB).withOpacity(0.8),
            shape: BoxShape.circle,
            border: Border.all(color: Colors.white, width: 3),
            boxShadow: const [BoxShadow(color: Colors.black54, blurRadius: 6, offset: Offset(0, 2))],
          ),
          child: const Center(child: Icon(Icons.control_camera, color: Colors.white, size: 22)),
        ),
      ),
    );
  }

  Widget _chip(String t, bool sel, VoidCallback fn) {
    return GestureDetector(
      onTap: fn,
      child: Container(padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
        decoration: BoxDecoration(color: sel ? const Color(0xFF2563EB) : const Color(0xFF1E293B),
          borderRadius: BorderRadius.circular(20), border: Border.all(color: sel ? Colors.transparent : Colors.white24)),
        child: Text(t, style: TextStyle(color: Colors.white, fontSize: 10, fontWeight: sel ? FontWeight.bold : FontWeight.w500))),
    );
  }
}
