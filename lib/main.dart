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
import 'hybrid_engine.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  HybridEngine.init();
  runApp(const MosulScannerApp());
}

class MosulScannerApp extends StatelessWidget {
  const MosulScannerApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'مكتب علاء الحديدي - الماسح الاحترافي',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(primarySwatch: Colors.teal, useMaterial3: true),
      home: const MainScannerScreen(),
    );
  }
}

class DocumentItem {
  String id;
  img.Image originalImage;
  img.Image currentImage;
  Uint8List cachedBytes;
  double widthMm;
  double heightMm;
  double xMm;
  double yMm;
  EnhanceMode filterMode;
  bool hasCurvedCorners;

  DocumentItem({
    required this.id,
    required this.originalImage,
    required this.currentImage,
    required this.cachedBytes,
    required this.widthMm,
    required this.heightMm,
    required this.xMm,
    required this.yMm,
    this.filterMode = EnhanceMode.soft,
    this.hasCurvedCorners = true,
  });

  void applyFilter(EnhanceMode mode) {
    filterMode = mode;
    currentImage = ImageEnhancer.apply(originalImage, mode);
    cachedBytes = Uint8List.fromList(ImageUtils.encodeJpg(currentImage));
  }

  void updateCrop(img.Image newCropped) {
    originalImage = newCropped;
    applyFilter(filterMode);
  }
}

class MainScannerScreen extends StatefulWidget {
  const MainScannerScreen({super.key});

  @override
  State<MainScannerScreen> createState() => _MainScannerScreenState();
}

class _MainScannerScreenState extends State<MainScannerScreen> {
  final List<DocumentItem> _items = [];
  DocumentItem? _activeItem;
  final ImagePicker _picker = ImagePicker();

  static const double pageWidthMm = 210.0;
  static const double pageHeightMm = 297.0;

  void _addImages(ImageSource source) async {
    final List<XFile> pickedFiles = [];
    if (source == ImageSource.gallery) {
      final files = await _picker.pickMultiImage();
      pickedFiles.addAll(files);
    } else {
      final file = await _picker.pickImage(source: source, imageQuality: 98);
      if (file != null) pickedFiles.add(file);
    }

    for (int i = 0; i < pickedFiles.length; i++) {
      final bytes = await File(pickedFiles[i].path).readAsBytes();
      final decoded = ImageUtils.decodeBytes(bytes);
      if (decoded == null) continue;

      // تطبيق قص تلقائي مبدئي
      final cropRes = HybridEngine.autoCrop(decoded);
      final finalImg = cropRes.changed ? cropRes.image : decoded;
      final enhanced = ImageEnhancer.apply(finalImg, EnhanceMode.soft);
      final encoded = Uint8List.fromList(ImageUtils.encodeJpg(enhanced));

      setState(() {
        final item = DocumentItem(
          id: '${DateTime.now().millisecondsSinceEpoch}_$i',
          originalImage: finalImg,
          currentImage: enhanced,
          cachedBytes: encoded,
          widthMm: 85.0,
          heightMm: (finalImg.height / finalImg.width) * 85.0,
          xMm: 10.0 + (_items.length * 4.0),
          yMm: 10.0 + (_items.length * 4.0),
        );
        _items.add(item);
        _activeItem = item;
      });
    }
  }

  void _openManualCrop() async {
    if (_activeItem == null) return;
    final result = await Navigator.push<img.Image>(
      context,
      MaterialPageRoute(
        builder: (_) => ProfessionalCropScreen(image: _activeItem!.originalImage),
      ),
    );
    if (result != null && mounted) {
      setState(() {
        _activeItem!.updateCrop(result);
      });
    }
  }

  void _printPDF() async {
    final pdf = pw.Document();
    pdf.addPage(
      pw.Page(
        pageFormat: PdfPageFormat.a4,
        margin: pw.EdgeInsets.zero,
        build: (pw.Context context) {
          return pw.Stack(
            children: _items.map((item) {
              return pw.Positioned(
                left: item.xMm * PdfPageFormat.mm,
                top: item.yMm * PdfPageFormat.mm,
                child: pw.ClipRRect(
                  horizontalRadius: item.hasCurvedCorners ? 3.5 * PdfPageFormat.mm : 0,
                  verticalRadius: item.hasCurvedCorners ? 3.5 * PdfPageFormat.mm : 0,
                  child: pw.SizedBox(
                    width: item.widthMm * PdfPageFormat.mm,
                    height: item.heightMm * PdfPageFormat.mm,
                    child: pw.Image(
                      pw.MemoryImage(item.cachedBytes),
                      fit: pw.BoxFit.fill,
                    ),
                  ),
                ),
              );
            }).toList(),
          );
        },
      ),
    );
    await Printing.layoutPdf(onLayout: (format) async => pdf.save());
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF111827),
      appBar: AppBar(
        title: const Text('مكتب علاء الحديدي - الماسح السحري الاحترافي', style: TextStyle(fontSize: 13, fontWeight: FontWeight.bold)),
        backgroundColor: const Color(0xFF0F766E),
        foregroundColor: Colors.white,
        actions: [
          IconButton(icon: const Icon(Icons.print), onPressed: _printPDF),
          IconButton(icon: const Icon(Icons.crop_rotate), onPressed: _openManualCrop),
          IconButton(icon: const Icon(Icons.add_a_photo), onPressed: () => _addImages(ImageSource.camera)),
          IconButton(icon: const Icon(Icons.photo_library), onPressed: () => _addImages(ImageSource.gallery)),
        ],
      ),
      body: Column(
        children: [
          Expanded(
            child: Row(
              children: [
                // الشريط الجانبي المقاسات
                Container(
                  width: 95,
                  color: const Color(0xFF1F2937),
                  child: Column(
                    children: [
                      const Padding(
                        padding: EdgeInsets.all(6.0),
                        child: Text('القياسات', style: TextStyle(color: Colors.white70, fontSize: 11, fontWeight: FontWeight.bold)),
                      ),
                      _sizeButton('بطاقة موحدة', 85, 54),
                      _sizeButton('بطاقة سكن', 88, 58),
                      _sizeButton('ورقة A4', 210, 297, curved: false),
                      const Spacer(),
                      if (_activeItem != null)
                        IconButton(
                          icon: const Icon(Icons.delete, color: Colors.redAccent),
                          onPressed: () => setState(() {
                            _items.remove(_activeItem);
                            _activeItem = null;
                          }),
                        )
                    ],
                  ),
                ),
                // مساحة العمل A4
                Expanded(
                  child: Center(
                    child: LayoutBuilder(
                      builder: (context, constraints) {
                        final scaleX = (constraints.maxWidth - 20) / pageWidthMm;
                        final scaleY = (constraints.maxHeight - 20) / pageHeightMm;
                        final scale = min(scaleX, scaleY);

                        return Container(
                          width: pageWidthMm * scale,
                          height: pageHeightMm * scale,
                          color: Colors.white,
                          child: Stack(
                            children: _items.map((item) {
                              final isActive = _activeItem?.id == item.id;
                              final radius = item.hasCurvedCorners ? BorderRadius.circular(3.5 * scale) : BorderRadius.zero;
                              return Positioned(
                                left: item.xMm * scale,
                                top: item.yMm * scale,
                                width: item.widthMm * scale,
                                height: item.heightMm * scale,
                                child: GestureDetector(
                                  onTap: () => setState(() => _activeItem = item),
                                  onPanUpdate: (d) {
                                    setState(() {
                                      item.xMm += d.delta.dx / scale;
                                      item.yMm += d.delta.dy / scale;
                                    });
                                  },
                                  child: Container(
                                    decoration: BoxDecoration(
                                      borderRadius: radius,
                                      border: Border.all(color: isActive ? Colors.teal : Colors.transparent, width: 2.0),
                                    ),
                                    child: ClipRRect(
                                      borderRadius: radius,
                                      child: Image.memory(item.cachedBytes, fit: BoxFit.fill),
                                    ),
                                  ),
                                ),
                              );
                            }).toList(),
                          ),
                        );
                      },
                    ),
                  ),
                ),
              ],
            ),
          ),
          // شريط الفلاتر السفلية المباشرة مثل الفيديو
          if (_activeItem != null)
            Container(
              height: 75,
              color: const Color(0xFF1F2937),
              child: ListView(
                scrollDirection: Axis.horizontal,
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
                children: [
                  _filterButton('الأصلي', EnhanceMode.none),
                  _filterButton('أداة سحرية ✨', EnhanceMode.soft),
                  _filterButton('أبيض وأسود', EnhanceMode.bw),
                ],
              ),
            ),
        ],
      ),
    );
  }

  Widget _sizeButton(String label, double w, double h, {bool curved = true}) {
    return Padding(
      padding: const EdgeInsets.all(4.0),
      child: ElevatedButton(
        style: ElevatedButton.styleFrom(
          backgroundColor: const Color(0xFF374151),
          foregroundColor: Colors.white,
          padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 4),
        ),
        onPressed: () {
          if (_activeItem != null) {
            setState(() {
              _activeItem!.widthMm = w;
              _activeItem!.heightMm = h;
              _activeItem!.hasCurvedCorners = curved;
            });
          }
        },
        child: Text(label, style: const TextStyle(fontSize: 9), textAlign: TextAlign.center),
      ),
    );
  }

  Widget _filterButton(String label, EnhanceMode mode) {
    final isSel = _activeItem?.filterMode == mode;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 4.0),
      child: ChoiceChip(
        label: Text(label, style: TextStyle(color: isSel ? Colors.white : Colors.white70, fontSize: 11)),
        selected: isSel,
        selectedColor: const Color(0xFF0F766E),
        backgroundColor: const Color(0xFF374151),
        onSelected: (_) {
          setState(() {
            _activeItem!.applyFilter(mode);
          });
        },
      ),
    );
  }
}

// ===============================================================
// شاشة القص اليدوي الاحترافية مع العدسة المكبرة (Magnifier)
// ===============================================================
class ProfessionalCropScreen extends StatefulWidget {
  final img.Image image;
  const ProfessionalCropScreen({super.key, required this.image});

  @override
  State<ProfessionalCropScreen> createState() => _ProfessionalCropScreenState();
}

class _ProfessionalCropScreenState extends State<ProfessionalCropScreen> {
  Offset _p1 = const Offset(0.1, 0.1);
  Offset _p2 = const Offset(0.9, 0.1);
  Offset _p3 = const Offset(0.9, 0.9);
  Offset _p4 = const Offset(0.1, 0.9);

  Offset? _activeDragPos;
  late Uint8List _imageBytes;

  @override
  void initState() {
    super.initState();
    _imageBytes = Uint8List.fromList(ImageUtils.encodeJpg(widget.image, quality: 92));
    _autoDetect();
  }

  void _autoDetect() {
    final corners = HybridEngine.detectCorners(widget.image);
    if (corners != null && corners.length == 8) {
      setState(() {
        _p1 = Offset(corners[0], corners[1]);
        _p2 = Offset(corners[2], corners[3]);
        _p3 = Offset(corners[4], corners[5]);
        _p4 = Offset(corners[6], corners[7]);
      });
    }
  }

  void _applyCrop() {
    final cropped = ManualCrop.cropPerspective(
      widget.image,
      _p1.dx, _p1.dy,
      _p2.dx, _p2.dy,
      _p3.dx, _p3.dy,
      _p4.dx, _p4.dy,
    );
    Navigator.pop(context, cropped);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: const Color(0xFF1F2937),
        title: const Text('ضبط الحدود بدقة', style: TextStyle(fontSize: 14, color: Colors.white)),
        actions: [
          IconButton(icon: const Icon(Icons.auto_fix_high, color: Color(0xFF34D399)), onPressed: _autoDetect),
          IconButton(icon: const Icon(Icons.check, color: Colors.greenAccent), onPressed: _applyCrop),
        ],
      ),
      body: LayoutBuilder(
        builder: (context, constraints) {
          final cw = constraints.maxWidth;
          final ch = constraints.maxHeight;
          final iw = widget.image.width.toDouble();
          final ih = widget.image.height.toDouble();
          final scale = min(cw / iw, ch / ih);
          final imgW = iw * scale;
          final imgH = ih * scale;
          final imgL = (cw - imgW) / 2;
          final imgT = (ch - imgH) / 2;

          return Stack(
            children: [
              // الصورة
              Positioned(
                left: imgL,
                top: imgT,
                width: imgW,
                height: imgH,
                child: Image.memory(_imageBytes, fit: BoxFit.fill),
              ),
              // رسم الحدود المتصلة الخضراء
              CustomPaint(
                size: Size(cw, ch),
                painter: QuadPainter(
                  p1: Offset(imgL + _p1.dx * imgW, imgT + _p1.dy * imgH),
                  p2: Offset(imgL + _p2.dx * imgW, imgT + _p2.dy * imgH),
                  p3: Offset(imgL + _p3.dx * imgW, imgT + _p3.dy * imgH),
                  p4: Offset(imgL + _p4.dx * imgW, imgT + _p4.dy * imgH),
                ),
              ),
              // نقاط السحب الأربع السلسة
              _buildPointHandle(1, _p1, imgL, imgT, imgW, imgH, (np) => setState(() => _p1 = np)),
              _buildPointHandle(2, _p2, imgL, imgT, imgW, imgH, (np) => setState(() => _p2 = np)),
              _buildPointHandle(3, _p3, imgL, imgT, imgW, imgH, (np) => setState(() => _p3 = np)),
              _buildPointHandle(4, _p4, imgL, imgT, imgW, imgH, (np) => setState(() => _p4 = np)),

              // العدسة المكبرة عند السحب (Magnifying Glass)
              if (_activeDragPos != null)
                Positioned(
                  left: (_activeDragPos!.dx - 50).clamp(10, cw - 110),
                  top: (_activeDragPos!.dy - 120).clamp(10, ch - 120),
                  child: Container(
                    width: 100,
                    height: 100,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      border: Border.all(color: Colors.greenAccent, width: 3),
                      boxShadow: const [BoxShadow(color: Colors.black54, blurRadius: 8)],
                    ),
                    child: ClipOval(
                      child: Transform.translate(
                        offset: Offset(-_activeDragPos!.dx * 1.8 + 50, -_activeDragPos!.dy * 1.8 + 50),
                        child: Transform.scale(
                          scale: 2.5,
                          child: Image.memory(_imageBytes, fit: BoxFit.fill),
                        ),
                      ),
                    ),
                  ),
                ),
            ],
          );
        },
      ),
    );
  }

  Widget _buildPointHandle(int id, Offset relPos, double il, double it, double iw, double ih, Function(Offset) onUpdate) {
    final absPos = Offset(il + relPos.dx * iw, it + relPos.dy * ih);
    return Positioned(
      left: absPos.dx - 24,
      top: absPos.dy - 24,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onPanStart: (_) => setState(() => _activeDragPos = absPos),
        onPanEnd: (_) => setState(() => _activeDragPos = null),
        onPanUpdate: (d) {
          final newAbs = absPos + d.delta;
          final newRel = Offset(
            ((newAbs.dx - il) / iw).clamp(0.0, 1.0),
            ((newAbs.dy - it) / ih).clamp(0.0, 1.0),
          );
          onUpdate(newRel);
          setState(() => _activeDragPos = newAbs);
        },
        child: Container(
          width: 48,
          height: 48,
          decoration: BoxDecoration(
            color: Colors.greenAccent.withOpacity(0.3),
            shape: BoxShape.circle,
            border: Border.all(color: Colors.greenAccent, width: 2.5),
          ),
          child: Center(
            child: Container(
              width: 12,
              height: 12,
              decoration: const BoxDecoration(color: Colors.white, shape: BoxShape.circle),
            ),
          ),
        ),
      ),
    );
  }
}

class QuadPainter extends CustomPainter {
  final Offset p1, p2, p3, p4;
  QuadPainter({required this.p1, required this.p2, required this.p3, required this.p4});

  @override
  void paint(Canvas canvas, Size size) {
    final paintLine = Paint()
      ..color = Colors.greenAccent
      ..strokeWidth = 2.5
      ..style = PaintingStyle.stroke;

    final path = Path()
      ..moveTo(p1.dx, p1.dy)
      ..lineTo(p2.dx, p2.dy)
      ..lineTo(p3.dx, p3.dy)
      ..lineTo(p4.dx, p4.dy)
      ..close();

    canvas.drawPath(path, paintLine);
  }

  @override
  bool shouldRepaint(QuadPainter old) => true;
}
