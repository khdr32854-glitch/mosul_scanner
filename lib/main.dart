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
      theme: ThemeData(
        primarySwatch: Colors.blue,
        useMaterial3: true,
      ),
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
  String _currentMode = 'docs';

  void _addNewImages(ImageSource source) async {
    final List<XFile> pickedFiles = [];
    if (source == ImageSource.gallery) {
      final List<XFile> galleryFiles = await _picker.pickMultiImage();
      pickedFiles.addAll(galleryFiles);
    } else {
      final XFile? cameraFile = await _picker.pickImage(source: source);
      if (cameraFile != null) pickedFiles.add(cameraFile);
    }

    for (int i = 0; i < pickedFiles.length; i++) {
      final bytes = await File(pickedFiles[i].path).readAsBytes();
      final decodedImg = img.decodeImage(bytes);

      if (decodedImg != null) {
        final autoCropped = _autoDetectAndCrop(decodedImg);
        final encodedBytes =
            Uint8List.fromList(img.encodeJpg(autoCropped, quality: 85));

        setState(() {
          final newItem = DocumentItem(
            id: DateTime.now().millisecondsSinceEpoch.toString() + i.toString(),
            image: autoCropped,
            cachedBytes: encodedBytes,
            widthMm: _currentMode == 'photos' ? 36 : 85,
            heightMm: _currentMode == 'photos'
                ? 45
                : (autoCropped.height / autoCropped.width * 85),
            xMm: 10.0 + (_items.length * 4),
            yMm: 10.0 + (_items.length * 4),
            isPhotoStyle: _currentMode == 'photos',
          );
          _items.add(newItem);
          _activeItem = newItem;
        });
      }
    }
  }

  img.Image _autoDetectAndCrop(img.Image src) {
    int marginX = (src.width * 0.05).toInt();
    int marginY = (src.height * 0.05).toInt();
    int cropW = src.width - (marginX * 2);
    int cropH = src.height - (marginY * 2);

    if (cropW > 50 && cropH > 50) {
      return img.copyCrop(
          src, x: marginX, y: marginY, width: cropW, height: cropH);
    }
    return src;
  }

  void _resizeActive(double w, double h, {bool isPhoto = false}) {
    if (_activeItem == null) return;
    setState(() {
      _activeItem!.widthMm = w;
      _activeItem!.heightMm = h;
      _activeItem!.isPhotoStyle = isPhoto;
    });
  }

  void _rotateActive() {
    if (_activeItem == null) return;
    setState(() {
      _activeItem!.rotation = (_activeItem!.rotation + 90) % 360;
    });
  }

  void _duplicateActive() {
    if (_activeItem == null) return;
    setState(() {
      final newItem = DocumentItem(
        id: DateTime.now().millisecondsSinceEpoch.toString(),
        image: _activeItem!.image,
        cachedBytes: _activeItem!.cachedBytes,
        widthMm: _activeItem!.widthMm,
        heightMm: _activeItem!.heightMm,
        xMm: _activeItem!.xMm + 5,
        yMm: _activeItem!.yMm + 5,
        rotation: _activeItem!.rotation,
        isPhotoStyle: _activeItem!.isPhotoStyle,
      );
      _items.add(newItem);
      _activeItem = newItem;
    });
  }

  void _autoAlign() {
    setState(() {
      double curX = 10;
      double curY = 10;
      double maxH = 0;

      for (var item in _items) {
        if (curX + item.widthMm > 200) {
          curX = 10;
          curY += maxH + 5;
          maxH = 0;
        }
        item.xMm = curX;
        item.yMm = curY;
        curX += item.widthMm + 5;
        if (item.heightMm > maxH) maxH = item.heightMm;
      }
    });
  }

  void _openCropOverlay() async {
    if (_activeItem == null) return;

    final img.Image? cropped = await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => SmartCropScreen(image: _activeItem!.image),
      ),
    );

    if (cropped != null) {
      final encodedBytes =
          Uint8List.fromList(img.encodeJpg(cropped, quality: 85));
      setState(() {
        _activeItem!.image = cropped;
        _activeItem!.cachedBytes = encodedBytes;
        _activeItem!.heightMm =
            (cropped.height / cropped.width * _activeItem!.widthMm);
      });
    }
  }

  // ── PDF EXPORT (مُصلح لحزمة pdf 3.x) ──────────────────
  //    في pdf >= 3.10 لم يعد Positioned يقبل width/height؛
  //    استخدم SizedBox بداخله. وأيضاً استخدام
  //    List<pw.Widget>.from() بدل .toList()
  //    لتجنب خطأ List<dynamic> ≠ List<Widget>.

  void _exportAndPrint() async {
    final pdf = pw.Document();

    pdf.addPage(
      pw.Page(
        pageFormat: PdfPageFormat.a4,
        margin: pw.EdgeInsets.zero,
        build: (pw.Context context) {
          final List<pw.Widget> widgets = [];

          for (final item in _items) {
            widgets.add(
              pw.Positioned(
                left: item.xMm * PdfPageFormat.mm,
                top: item.yMm * PdfPageFormat.mm,
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
          }

          return pw.Stack(
            children: List<pw.Widget>.from(widgets),
          );
        },
      ),
    );

    await Printing.layoutPdf(
      onLayout: (PdfPageFormat format) async => pdf.save(),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('مكتب علاء الحديدي - الماسح الذكي',
                style: TextStyle(fontSize: 15, fontWeight: FontWeight.bold)),
            Text('Telegram: @Oo_qp',
                style: TextStyle(fontSize: 10, color: Colors.white70)),
          ],
        ),
        backgroundColor: const Color(0xFF0284C7),
        foregroundColor: Colors.white,
        actions: [
          IconButton(
            icon: const Icon(Icons.print),
            tooltip: 'طباعة A4',
            onPressed: _exportAndPrint,
          ),
          IconButton(
            icon: const Icon(Icons.add_a_photo),
            onPressed: () => _addNewImages(ImageSource.camera),
          ),
          IconButton(
            icon: const Icon(Icons.photo_library),
            onPressed: () => _addNewImages(ImageSource.gallery),
          ),
        ],
      ),
      body: Row(
        children: [
          // ── SIDEBAR ──────────────────────────────────────────
          Container(
            width: 230,
            color: Colors.white,
            padding: const EdgeInsets.all(8.0),
            child: SingleChildScrollView(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  SegmentedButton<String>(
                    segments: const [
                      ButtonSegment(
                          value: 'docs',
                          label: Text('مستمسكات',
                              style: TextStyle(fontSize: 11))),
                      ButtonSegment(
                          value: 'photos',
                          label: Text('صور معاملة',
                              style: TextStyle(fontSize: 11))),
                    ],
                    selected: {_currentMode},
                    onSelectionChanged: (Set<String> newSelection) {
                      if (newSelection.isNotEmpty) {
                        setState(
                            () => _currentMode = newSelection.elementAt(0));
                      }
                    },
                  ),
                  const SizedBox(height: 8),

                  ElevatedButton.icon(
                    style: ElevatedButton.styleFrom(
                        backgroundColor: const Color(0xFF10B981),
                        foregroundColor: Colors.white),
                    onPressed: _autoAlign,
                    icon: const Icon(Icons.auto_awesome, size: 16),
                    label: const Text('ترتيب وتسوية تلقائية',
                        style: TextStyle(fontSize: 11)),
                  ),
                  const SizedBox(height: 4),

                  ElevatedButton.icon(
                    style: ElevatedButton.styleFrom(
                        backgroundColor: const Color(0xFFD97706),
                        foregroundColor: Colors.white),
                    onPressed: _openCropOverlay,
                    icon: const Icon(Icons.crop_rotate, size: 16),
                    label: const Text('القص الذكي والتعديل',
                        style: TextStyle(fontSize: 11)),
                  ),
                  const SizedBox(height: 4),

                  Row(
                    children: [
                      Expanded(
                        child: ElevatedButton(
                          style: ElevatedButton.styleFrom(
                              backgroundColor: const Color(0xFF475569),
                              foregroundColor: Colors.white),
                          onPressed: _rotateActive,
                          child: const Text('تدوير 90°',
                              style: TextStyle(fontSize: 10)),
                        ),
                      ),
                      const SizedBox(width: 4),
                      Expanded(
                        child: ElevatedButton(
                          style: ElevatedButton.styleFrom(
                              backgroundColor: const Color(0xFF8B5CF6),
                              foregroundColor: Colors.white),
                          onPressed: _duplicateActive,
                          child: const Text('نسخ',
                              style: TextStyle(fontSize: 10)),
                        ),
                      ),
                    ],
                  ),
                  const Divider(),

                  // ── SIZES ──────────────────────────────────────
                  if (_currentMode == 'docs') ...[
                    const Text('قياسات المستمسكات (سم)',
                        style: TextStyle(
                            fontWeight: FontWeight.bold,
                            fontSize: 12,
                            color: Color(0xFF0369A1))),
                    const SizedBox(height: 4),
                    ElevatedButton(
                      onPressed: () => _resizeActive(85, 54),
                      child: const Text('بطاقة موحدة (8.5×5.4)',
                          style: TextStyle(fontSize: 11)),
                    ),
                    ElevatedButton(
                      onPressed: () => _resizeActive(88, 58),
                      child: const Text('بطاقة سكن (8.8×5.8)',
                          style: TextStyle(fontSize: 11)),
                    ),
                    ElevatedButton(
                      onPressed: () => _resizeActive(210, 297),
                      child: const Text('ورقة كاملة (A4)',
                          style: TextStyle(fontSize: 11)),
                    ),
                  ] else ...[
                    const Text('قياسات الصور الشخصية',
                        style: TextStyle(
                            fontWeight: FontWeight.bold,
                            fontSize: 12,
                            color: Color(0xFF0369A1))),
                    const SizedBox(height: 4),
                    ElevatedButton(
                      onPressed: () =>
                          _resizeActive(36, 45, isPhoto: true),
                      child: const Text('معاملة (3.6 × 4.5 سم)',
                          style: TextStyle(fontSize: 11)),
                    ),
                    ElevatedButton(
                      onPressed: () =>
                          _resizeActive(25, 34, isPhoto: true),
                      child: const Text('مصغر (2.5 × 3.4 سم)',
                          style: TextStyle(fontSize: 11)),
                    ),
                  ],
                  const Divider(),

                  if (_activeItem != null)
                    ElevatedButton.icon(
                      style: ElevatedButton.styleFrom(
                          backgroundColor: Colors.red,
                          foregroundColor: Colors.white),
                      onPressed: () {
                        setState(() {
                          _items.remove(_activeItem);
                          _activeItem = null;
                        });
                      },
                      icon: const Icon(Icons.delete, size: 16),
                      label: const Text('حذف العنصر',
                          style: TextStyle(fontSize: 11)),
                    ),
                ],
              ),
            ),
          ),

          // ── PAGE CANVAS ───────────────────────────────────────
          Expanded(
            child: Container(
              color: const Color(0xFF475569),
              child: Center(
                child: InteractiveViewer(
                  maxScale: 3.0,
                  minScale: 0.5,
                  child: AspectRatio(
                    aspectRatio: 210 / 297,
                    child: Container(
                      decoration: BoxDecoration(
                        color: Colors.white,
                        boxShadow: [
                          BoxShadow(
                              color: Colors.black.withOpacity(0.4),
                              blurRadius: 12),
                        ],
                      ),
                      child: Stack(
                        children: List.generate(_items.length, (index) {
                          final item = _items[index];
                          final isActive = _activeItem?.id == item.id;
                          return Positioned(
                            left: item.xMm * 2,
                            top: item.yMm * 2,
                            width: item.widthMm * 2,
                            height: item.heightMm * 2,
                            child: GestureDetector(
                              onTap: () =>
                                  setState(() => _activeItem = item),
                              onPanUpdate: (details) {
                                setState(() {
                                  item.xMm += details.delta.dx / 2;
                                  item.yMm += details.delta.dy / 2;
                                });
                              },
                              child: Container(
                                decoration: BoxDecoration(
                                  border: Border.all(
                                    color: isActive
                                        ? Colors.blue
                                        : (item.isPhotoStyle
                                            ? Colors.red
                                            : Colors.transparent),
                                    width: isActive ? 2 : 1,
                                  ),
                                ),
                                child: Transform.rotate(
                                  angle: item.rotation * pi / 180,
                                  child: Image.memory(
                                    item.cachedBytes,
                                    fit: BoxFit.fill,
                                  ),
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
          ),
        ],
      ),
    );
  }
}

// ═══════════════════════════════════════════════════════
// SMART CROP SCREEN
// ═══════════════════════════════════════════════════════
class SmartCropScreen extends StatefulWidget {
  final img.Image image;
  const SmartCropScreen({super.key, required this.image});

  @override
  State<SmartCropScreen> createState() => _SmartCropScreenState();
}

class _SmartCropScreenState extends State<SmartCropScreen> {
  late List<Offset> points;
  String _selectedFilter = 'magic';

  @override
  void initState() {
    super.initState();
    points = [
      const Offset(0.05, 0.05),
      const Offset(0.95, 0.05),
      const Offset(0.95, 0.95),
      const Offset(0.05, 0.95),
    ];
  }

  void _processCrop() {
    final src = widget.image;

    int minX = (points.map((p) => p.dx).reduce(min) * src.width)
        .toInt()
        .clamp(0, src.width - 1);
    int maxX = (points.map((p) => p.dx).reduce(max) * src.width)
        .toInt()
        .clamp(1, src.width);
    int minY = (points.map((p) => p.dy).reduce(min) * src.height)
        .toInt()
        .clamp(0, src.height - 1);
    int maxY = (points.map((p) => p.dy).reduce(max) * src.height)
        .toInt()
        .clamp(1, src.height);

    int cropW = max(10, maxX - minX);
    int cropH = max(10, maxY - minY);

    img.Image cropped =
        img.copyCrop(src, x: minX, y: minY, width: cropW, height: cropH);

    if (_selectedFilter == 'magic') {
      cropped = img.adjustColor(cropped, brightness: 1.12, contrast: 1.25);
    } else if (_selectedFilter == 'bw') {
      cropped = img.grayscale(cropped);
    }

    Navigator.pop(context, cropped);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF0F172A),
      appBar: AppBar(
        title: const Text('القص الذكي وتعديل الألوان'),
        backgroundColor: Colors.black,
        foregroundColor: Colors.white,
        actions: [
          IconButton(
            icon:
                const Icon(Icons.check, color: Colors.greenAccent, size: 28),
            onPressed: _processCrop,
          ),
        ],
      ),
      body: Column(
        children: [
          Container(
            color: Colors.black87,
            padding:
                const EdgeInsets.symmetric(vertical: 8, horizontal: 16),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceEvenly,
              children: [
                DropdownButton<String>(
                  value: _selectedFilter,
                  dropdownColor: Colors.black87,
                  style: const TextStyle(color: Colors.white, fontSize: 12),
                  items: const [
                    DropdownMenuItem(
                        value: 'magic', child: Text('✨ تبييض سحري')),
                    DropdownMenuItem(
                        value: 'original', child: Text('🎨 ألوان أصلية')),
                    DropdownMenuItem(
                        value: 'bw', child: Text('📄 أبيض وأسود')),
                  ],
                  onChanged: (val) =>
                      setState(() => _selectedFilter = val!),
                ),
                ElevatedButton.icon(
                  onPressed: () {
                    setState(() {
                      points = [
                        const Offset(0.05, 0.05),
                        const Offset(0.95, 0.05),
                        const Offset(0.95, 0.95),
                        const Offset(0.05, 0.95),
                      ];
                    });
                  },
                  icon: const Icon(Icons.center_focus_strong, size: 16),
                  label: const Text('ضبط المربع',
                      style: TextStyle(fontSize: 11)),
                ),
              ],
            ),
          ),
          Expanded(
            child: LayoutBuilder(
              builder: (context, constraints) {
                final w = constraints.maxWidth;
                final h = constraints.maxHeight;

                return Stack(
                  children: [
                    Center(
                      child: Image.memory(
                        Uint8List.fromList(img.encodeJpg(widget.image)),
                        fit: BoxFit.contain,
                      ),
                    ),
                    CustomPaint(
                      size: Size(w, h),
                      painter: CropLinesPainter(points: points),
                    ),
                    ...List.generate(4, (index) {
                      return Positioned(
                        left: points[index].dx * w - 18,
                        top: points[index].dy * h - 18,
                        child: GestureDetector(
                          onPanUpdate: (details) {
                            setState(() {
                              double newX = (points[index].dx +
                                      details.delta.dx / w)
                                  .clamp(0.0, 1.0);
                              double newY = (points[index].dy +
                                      details.delta.dy / h)
                                  .clamp(0.0, 1.0);
                              points[index] = Offset(newX, newY);
                            });
                          },
                          child: Container(
                            width: 36,
                            height: 36,
                            decoration: BoxDecoration(
                              color: const Color(0xFF0284C7),
                              shape: BoxShape.circle,
                              border: Border.all(
                                  color: Colors.white, width: 3),
                              boxShadow: const [
                                BoxShadow(
                                    color: Colors.black54, blurRadius: 4),
                              ],
                            ),
                          ),
                        ),
                      );
                    }),
                  ],
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}

class CropLinesPainter extends CustomPainter {
  final List<Offset> points;
  CropLinesPainter({required this.points});

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = const Color(0xFF0284C7)
      ..strokeWidth = 2.5
      ..style = PaintingStyle.stroke;

    final path = Path();
    path.moveTo(points[0].dx * size.width, points[0].dy * size.height);
    path.lineTo(points[1].dx * size.width, points[1].dy * size.height);
    path.lineTo(points[2].dx * size.width, points[2].dy * size.height);
    path.lineTo(points[3].dx * size.width, points[3].dy * size.height);
    path.close();

    canvas.drawPath(path, paint);
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => true;
}
    setState(() {
      final newItem = DocumentItem(
        id: DateTime.now().millisecondsSinceEpoch.toString(),
        image: _activeItem!.image,
        cachedBytes: _activeItem!.cachedBytes,
        widthMm: _activeItem!.widthMm,
        heightMm: _activeItem!.heightMm,
        xMm: _activeItem!.xMm + 5,
        yMm: _activeItem!.yMm + 5,
        rotation: _activeItem!.rotation,
        isPhotoStyle: _activeItem!.isPhotoStyle,
      );
      _items.add(newItem);
      _activeItem = newItem;
    });
  }

  void _autoAlign() {
    setState(() {
      double curX = 10;
      double curY = 10;
      double maxH = 0;

      for (var item in _items) {
        if (curX + item.widthMm > 200) {
          curX = 10;
          curY += maxH + 5;
          maxH = 0;
        }
        item.xMm = curX;
        item.yMm = curY;
        curX += item.widthMm + 5;
        if (item.heightMm > maxH) maxH = item.heightMm;
      }
    });
  }

  void _openCropOverlay() async {
    if (_activeItem == null) return;

    final img.Image? cropped = await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => SmartCropScreen(image: _activeItem!.image),
      ),
    );

    if (cropped != null) {
      final encodedBytes = Uint8List.fromList(img.encodeJpg(cropped, quality: 85));
      setState(() {
        _activeItem!.image = cropped;
        _activeItem!.cachedBytes = encodedBytes;
        _activeItem!.heightMm = (cropped.height / cropped.width * _activeItem!.widthMm);
      });
    }
  }

  void _exportAndPrint() async {
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
                width: item.widthMm * PdfPageFormat.mm,
                height: item.heightMm * PdfPageFormat.mm,
                child: pw.Image(
                  pw.MemoryImage(item.cachedBytes),
                  fit: pw.BoxFit.fill,
                ),
              );
            }).toList(),
          );
        },
      ),
    );

    await Printing.layoutPdf(
      onLayout: (PdfPageFormat format) async => pdf.save(),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('مكتب علاء الحديدي - الماسح الذكي', style: TextStyle(fontSize: 15, fontWeight: FontWeight.bold)),
            Text('Telegram: @Oo_qp', style: TextStyle(fontSize: 10, color: Colors.white70)),
          ],
        ),
        backgroundColor: const Color(0xFF0284C7),
        foregroundColor: Colors.white,
        actions: [
          IconButton(
            icon: const Icon(Icons.print),
            tooltip: 'طباعة A4',
            onPressed: _exportAndPrint,
          ),
          IconButton(
            icon: const Icon(Icons.add_a_photo),
            onPressed: () => _addNewImages(ImageSource.camera),
          ),
          IconButton(
            icon: const Icon(Icons.photo_library),
            onPressed: () => _addNewImages(ImageSource.gallery),
          ),
        ],
      ),
      body: Row(
        children: [
          Container(
            width: 230,
            color: Colors.white,
            padding: const EdgeInsets.all(8.0),
            child: SingleChildScrollView(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  SegmentedButton<String>(
                    segments: const [
                      ButtonSegment(value: 'docs', label: Text('مستمسكات', style: TextStyle(fontSize: 11))),
                      ButtonSegment(value: 'photos', label: Text('صور معاملة', style: TextStyle(fontSize: 11))),
                    ],
                    selected: {_currentMode},
                    onSelectionChanged: (Set<String> newSelection) {
                      if (newSelection.isNotEmpty) {
                        setState(() => _currentMode = newSelection.elementAt(0));
                      }
                    },
                  ),
                  const SizedBox(height: 8),
                  ElevatedButton.icon(
                    style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFF10B981), foregroundColor: Colors.white),
                    onPressed: _autoAlign,
                    icon: const Icon(Icons.auto_awesome, size: 16),
                    label: const Text('ترتيب وتسوية تلقائية', style: TextStyle(fontSize: 11)),
                  ),
                  const SizedBox(height: 4),
                  ElevatedButton.icon(
                    style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFFD97706), foregroundColor: Colors.white),
                    onPressed: _openCropOverlay,
                    icon: const Icon(Icons.crop_rotate, size: 16),
                    label: const Text('القص الذكي والتعديل', style: TextStyle(fontSize: 11)),
                  ),
                  const SizedBox(height: 4),
                  Row(
                    children: [
                      Expanded(
                        child: ElevatedButton(
                          style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFF475569), foregroundColor: Colors.white),
                          onPressed: _rotateActive,
                          child: const Text('تدوير 90°', style: TextStyle(fontSize: 10)),
                        ),
                      ),
                      const SizedBox(width: 4),
                      Expanded(
                        child: ElevatedButton(
                          style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFF8B5CF6), foregroundColor: Colors.white),
                          onPressed: _duplicateActive,
                          child: const Text('نسخ', style: TextStyle(fontSize: 10)),
                        ),
                      ),
                    ],
                  ),
                  const Divider(),
                  if (_currentMode == 'docs') ...[
                    const Text('قياسات المستمسكات (سم)', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12, color: Color(0xFF0369A1))),
                    const SizedBox(height: 4),
                    ElevatedButton(
                      onPressed: () => _resizeActive(85, 54),
                      child: const Text('بطاقة موحدة (8.5×5.4)', style: TextStyle(fontSize: 11)),
                    ),
                    ElevatedButton(
                      onPressed: () => _resizeActive(88, 58),
                      child: const Text('بطاقة سكن (8.8×5.8)', style: TextStyle(fontSize: 11)),
                    ),
                    ElevatedButton(
                      onPressed: () => _resizeActive(210, 297),
                      child: const Text('ورقة كاملة (A4)', style: TextStyle(fontSize: 11)),
                    ),
                  ] else ...[
                    const Text('قياسات الصور الشخصية', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12, color: Color(0xFF0369A1))),
                    const SizedBox(height: 4),
                    ElevatedButton(
                      onPressed: () => _resizeActive(36, 45, isPhoto: true),
                      child: const Text('معاملة (3.6 × 4.5 سم)', style: TextStyle(fontSize: 11)),
                    ),
                    ElevatedButton(
                      onPressed: () => _resizeActive(25, 34, isPhoto: true),
                      child: const Text('مصغر (2.5 × 3.4 سم)', style: TextStyle(fontSize: 11)),
                    ),
                  ],
                  const Divider(),
                  if (_activeItem != null)
                    ElevatedButton.icon(
                      style: ElevatedButton.styleFrom(backgroundColor: Colors.red, foregroundColor: Colors.white),
                      onPressed: () {
                        setState(() {
                          _items.remove(_activeItem);
                          _activeItem = null;
                        });
                      },
                      icon: const Icon(Icons.delete, size: 16),
                      label: const Text('حذف العنصر', style: TextStyle(fontSize: 11)),
                    ),
                ],
              ),
            ),
          ),
          Expanded(
            child: Container(
              color: const Color(0xFF475569),
              child: Center(
                child: InteractiveViewer(
                  maxScale: 3.0,
                  minScale: 0.5,
                  child: AspectRatio(
                    aspectRatio: 210 / 297,
                    child: Container(
                      decoration: BoxDecoration(
                        color: Colors.white,
                        boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.4), blurRadius: 12)],
                      ),
                      child: Stack(
                        children: _items.map((item) {
                          final isActive = _activeItem?.id == item.id;
                          return Positioned(
                            left: item.xMm * 2,
                            top: item.yMm * 2,
                            width: item.widthMm * 2,
                            height: item.heightMm * 2,
                            child: GestureDetector(
                              onTap: () => setState(() => _activeItem = item),
                              onPanUpdate: (details) {
                                setState(() {
                                  item.xMm += details.delta.dx / 2;
                                  item.yMm += details.delta.dy / 2;
                                });
                              },
                              child: Container(
                                decoration: BoxDecoration(
                                  border: Border.all(
                                    color: isActive
                                        ? Colors.blue
                                        : (item.isPhotoStyle ? Colors.red : Colors.transparent),
                                    width: isActive ? 2 : 1,
                                  ),
                                ),
                                child: Transform.rotate(
                                  angle: item.rotation * pi / 180,
                                  child: Image.memory(
                                    item.cachedBytes,
                                    fit: BoxFit.fill,
                                  ),
                                ),
                              ),
                            ),
                          );
                        }).toList(),
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

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
}

class SmartCropScreen extends StatefulWidget {
  final img.Image image;
  const SmartCropScreen({super.key, required this.image});

  @override
  State<SmartCropScreen> createState() => _SmartCropScreenState();
}

class _SmartCropScreenState extends State<SmartCropScreen> {
  late List<Offset> points;
  String _selectedFilter = 'magic';

  @override
  void initState() {
    super.initState();
    points = [
      const Offset(0.05, 0.05),
      const Offset(0.95, 0.05),
      const Offset(0.95, 0.95),
      const Offset(0.05, 0.95),
    ];
  }

  void _processCrop() {
    final src = widget.image;

    int minX = (points.map((p) => p.dx).reduce(min) * src.width).toInt().clamp(0, src.width - 1);
    int maxX = (points.map((p) => p.dx).reduce(max) * src.width).toInt().clamp(1, src.width);
    int minY = (points.map((p) => p.dy).reduce(min) * src.height).toInt().clamp(0, src.height - 1);
    int maxY = (points.map((p) => p.dy).reduce(max) * src.height).toInt().clamp(1, src.height);

    int cropW = max(10, maxX - minX);
    int cropH = max(10, maxY - minY);

    img.Image cropped = img.copyCrop(src, x: minX, y: minY, width: cropW, height: cropH);

    if (_selectedFilter == 'magic') {
      cropped = img.adjustColor(cropped, brightness: 1.12, contrast: 1.25);
    } else if (_selectedFilter == 'bw') {
      cropped = img.grayscale(cropped);
    }

    Navigator.pop(context, cropped);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF0F172A),
      appBar: AppBar(
        title: const Text('القص الذكي وتعديل الألوان'),
        backgroundColor: Colors.black,
        foregroundColor: Colors.white,
        actions: [
          IconButton(
            icon: const Icon(Icons.check, color: Colors.greenAccent, size: 28),
            onPressed: _processCrop,
          ),
        ],
      ),
      body: Column(
        children: [
          Container(
            color: Colors.black87,
            padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 16),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceEvenly,
              children: [
                DropdownButton<String>(
                  value: _selectedFilter,
                  dropdownColor: Colors.black87,
                  style: const TextStyle(color: Colors.white, fontSize: 12),
                  items: const [
                    DropdownMenuItem(value: 'magic', child: Text('✨ تبييض سحري')),
                    DropdownMenuItem(value: 'original', child: Text('🎨 ألوان أصلية')),
                    DropdownMenuItem(value: 'bw', child: Text('📄 أبيض وأسود')),
                  ],
                  onChanged: (val) => setState(() => _selectedFilter = val!),
                ),
                ElevatedButton.icon(
                  onPressed: () {
                    setState(() {
                      points = [
                        const Offset(0.05, 0.05),
                        const Offset(0.95, 0.05),
                        const Offset(0.95, 0.95),
                        const Offset(0.05, 0.95),
                      ];
                    });
                  },
                  icon: const Icon(Icons.center_focus_strong, size: 16),
                  label: const Text('ضبط المربع', style: TextStyle(fontSize: 11)),
                ),
              ],
            ),
          ),
          Expanded(
            child: LayoutBuilder(
              builder: (context, constraints) {
                final w = constraints.maxWidth;
                final h = constraints.maxHeight;

                return Stack(
                  children: [
                    Center(
                      child: Image.memory(
                        Uint8List.fromList(img.encodeJpg(widget.image)),
                        fit: BoxFit.contain,
                      ),
                    ),
                    CustomPaint(
                      size: Size(w, h),
                      painter: CropLinesPainter(points: points),
                    ),
                    ...List.generate(4, (index) {
                      return Positioned(
                        left: points[index].dx * w - 18,
                        top: points[index].dy * h - 18,
                        child: GestureDetector(
                          onPanUpdate: (details) {
                            setState(() {
                              double newX = (points[index].dx + details.delta.dx / w).clamp(0.0, 1.0);
                              double newY = (points[index].dy + details.delta.dy / h).clamp(0.0, 1.0);
                              points[index] = Offset(newX, newY);
                            });
                          },
                          child: Container(
                            width: 36,
                            height: 36,
                            decoration: BoxDecoration(
                              color: const Color(0xFF0284C7),
                              shape: BoxShape.circle,
                              border: Border.all(color: Colors.white, width: 3),
                              boxShadow: const [
                                BoxShadow(color: Colors.black54, blurRadius: 4),
                              ],
                            ),
                          ),
                        ),
                      );
                    }),
                  ],
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}

class CropLinesPainter extends CustomPainter {
  final List<Offset> points;
  CropLinesPainter({required this.points});

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = const Color(0xFF0284C7)
      ..strokeWidth = 2.5
      ..style = PaintingStyle.stroke;

    final path = Path();
    path.moveTo(points[0].dx * size.width, points[0].dy * size.height);
    path.lineTo(points[1].dx * size.width, points[1].dy * size.height);
    path.lineTo(points[2].dx * size.width, points[2].dy * size.height);
    path.lineTo(points[3].dx * size.width, points[3].dy * size.height);
    path.close();

    canvas.drawPath(path, paint);
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => true;
}
      double curY = 10;
      double maxH = 0;

      for (var item in _items) {
        if (curX + item.widthMm > 200) {
          curX = 10;
          curY += maxH + 5;
          maxH = 0;
        }
        item.xMm = curX;
        item.yMm = curY;
        curX += item.widthMm + 5;
        if (item.heightMm > maxH) maxH = item.heightMm;
      }
    });
  }

  void _openCropOverlay() async {
    if (_activeItem == null) return;

    final img.Image? cropped = await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => SmartCropScreen(image: _activeItem!.image),
      ),
    );

    if (cropped != null) {
      final encodedBytes = Uint8List.fromList(img.encodeJpg(cropped, quality: 85));
      setState(() {
        _activeItem!.image = cropped;
        _activeItem!.cachedBytes = encodedBytes;
        _activeItem!.heightMm = (cropped.height / cropped.width * _activeItem!.widthMm);
      });
    }
  }

  void _exportAndPrint() async {
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
                width: item.widthMm * PdfPageFormat.mm,
                height: item.heightMm * PdfPageFormat.mm,
                child: pw.Image(
                  pw.MemoryImage(item.cachedBytes),
                  fit: pw.BoxFit.fill,
                ),
              );
            }).toList(),
          );
        },
      ),
    );

    await Printing.layoutPdf(
      onLayout: (PdfPageFormat format) async => pdf.save(),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('مكتب علاء الحديدي - الماسح الذكي', style: TextStyle(fontSize: 15, fontWeight: FontWeight.bold)),
            Text('Telegram: @Oo_qp', style: TextStyle(fontSize: 10, color: Colors.white70)),
          ],
        ),
        backgroundColor: const Color(0xFF0284C7),
        foregroundColor: Colors.white,
        actions: [
          IconButton(
            icon: const Icon(Icons.print),
            tooltip: 'طباعة A4',
            onPressed: _exportAndPrint,
          ),
          IconButton(
            icon: const Icon(Icons.add_a_photo),
            onPressed: () => _addNewImages(ImageSource.camera),
          ),
          IconButton(
            icon: const Icon(Icons.photo_library),
            onPressed: () => _addNewImages(ImageSource.gallery),
          ),
        ],
      ),
      body: Row(
        children: [
          Container(
            width: 230,
            color: Colors.white,
            padding: const EdgeInsets.all(8.0),
            child: SingleChildScrollView(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  SegmentedButton<String>(
                    segments: const [
                      ButtonSegment(value: 'docs', label: Text('مستمسكات', style: TextStyle(fontSize: 11))),
                      ButtonSegment(value: 'photos', label: Text('صور معاملة', style: TextStyle(fontSize: 11))),
                    ],
                    selected: {_currentMode},
                    onSelectionChanged: (Set<String> newSelection) {
                      if (newSelection.isNotEmpty) {
                        setState(() => _currentMode = newSelection.elementAt(0));
                      }
                    },
                  ),
                  const SizedBox(height: 8),
                  ElevatedButton.icon(
                    style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFF10B981), foregroundColor: Colors.white),
                    onPressed: _autoAlign,
                    icon: const Icon(Icons.auto_awesome, size: 16),
                    label: const Text('ترتيب وتسوية تلقائية', style: TextStyle(fontSize: 11)),
                  ),
                  const SizedBox(height: 4),
                  ElevatedButton.icon(
                    style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFFD97706), foregroundColor: Colors.white),
                    onPressed: _openCropOverlay,
                    icon: const Icon(Icons.crop_rotate, size: 16),
                    label: const Text('القص الذكي والتعديل', style: TextStyle(fontSize: 11)),
                  ),
                  const SizedBox(height: 4),
                  Row(
                    children: [
                      Expanded(
                        child: ElevatedButton(
                          style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFF475569), foregroundColor: Colors.white),
                          onPressed: _rotateActive,
                          child: const Text('تدوير 90°', style: TextStyle(fontSize: 10)),
                        ),
                      ),
                      const SizedBox(width: 4),
                      Expanded(
                        child: ElevatedButton(
                          style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFF8B5CF6), foregroundColor: Colors.white),
                          onPressed: _duplicateActive,
                          child: const Text('نسخ', style: TextStyle(fontSize: 10)),
                        ),
                      ),
                    ],
                  ),
                  const Divider(),
                  if (_currentMode == 'docs') ...[
                    const Text('قياسات المستمسكات (سم)', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12, color: Color(0xFF0369A1))),
                    const SizedBox(height: 4),
                    ElevatedButton(
                      onPressed: () => _resizeActive(85, 54),
                      child: const Text('بطاقة موحدة (8.5×5.4)', style: TextStyle(fontSize: 11)),
                    ),
                    ElevatedButton(
                      onPressed: () => _resizeActive(88, 58),
                      child: const Text('بطاقة سكن (8.8×5.8)', style: TextStyle(fontSize: 11)),
                    ),
                    ElevatedButton(
                      onPressed: () => _resizeActive(210, 297),
                      child: const Text('ورقة كاملة (A4)', style: TextStyle(fontSize: 11)),
                    ),
                  ] else ...[
                    const Text('قياسات الصور الشخصية', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12, color: Color(0xFF0369A1))),
                    const SizedBox(height: 4),
                    ElevatedButton(
                      onPressed: () => _resizeActive(36, 45, isPhoto: true),
                      child: const Text('معاملة (3.6 × 4.5 سم)', style: TextStyle(fontSize: 11)),
                    ),
                    ElevatedButton(
                      onPressed: () => _resizeActive(25, 34, isPhoto: true),
                      child: const Text('مصغر (2.5 × 3.4 سم)', style: TextStyle(fontSize: 11)),
                    ),
                  ],
                  const Divider(),
                  if (_activeItem != null)
                    ElevatedButton.icon(
                      style: ElevatedButton.styleFrom(backgroundColor: Colors.red, foregroundColor: Colors.white),
                      onPressed: () {
                        setState(() {
                          _items.remove(_activeItem);
                          _activeItem = null;
                        });
                      },
                      icon: const Icon(Icons.delete, size: 16),
                      label: const Text('حذف العنصر', style: TextStyle(fontSize: 11)),
                    ),
                ],
              ),
            ),
          ),
          Expanded(
            child: Container(
              color: const Color(0xFF475569),
              child: Center(
                child: InteractiveViewer(
                  maxScale: 3.0,
                  minScale: 0.5,
                  child: AspectRatio(
                    aspectRatio: 210 / 297,
                    child: Container(
                      decoration: BoxDecoration(
                        color: Colors.white,
                        boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.4), blurRadius: 12)],
                      ),
                      child: Stack(
                        children: _items.map((item) {
                          final isActive = _activeItem?.id == item.id;
                          return Positioned(
                            left: item.xMm * 2,
                            top: item.yMm * 2,
                            width: item.widthMm * 2,
                            height: item.heightMm * 2,
                            child: GestureDetector(
                              onTap: () => setState(() => _activeItem = item),
                              onPanUpdate: (details) {
                                setState(() {
                                  item.xMm += details.delta.dx / 2;
                                  item.yMm += details.delta.dy / 2;
                                });
                              },
                              child: Container(
                                decoration: BoxDecoration(
                                  border: Border.all(
                                    color: isActive
                                        ? Colors.blue
                                        : (item.isPhotoStyle ? Colors.red : Colors.transparent),
                                    width: isActive ? 2 : 1,
                                  ),
                                ),
                                child: Transform.rotate(
                                  angle: item.rotation * pi / 180,
                                  child: Image.memory(
                                    item.cachedBytes,
                                    fit: BoxFit.fill,
                                  ),
                                ),
                              ),
                            ),
                          );
                        }).toList(),
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

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
}

class SmartCropScreen extends StatefulWidget {
  final img.Image image;
  const SmartCropScreen({super.key, required this.image});

  @override
  State<SmartCropScreen> createState() => _SmartCropScreenState();
}

class _SmartCropScreenState extends State<SmartCropScreen> {
  late List<Offset> points;
  String _selectedFilter = 'magic';

  @override
  void initState() {
    super.initState();
    points = [
      const Offset(0.05, 0.05),
      const Offset(0.95, 0.05),
      const Offset(0.95, 0.95),
      const Offset(0.05, 0.95),
    ];
  }

  void _processCrop() {
    final src = widget.image;

    int minX = (points.map((p) => p.dx).reduce(min) * src.width).toInt().clamp(0, src.width - 1);
    int maxX = (points.map((p) => p.dx).reduce(max) * src.width).toInt().clamp(1, src.width);
    int minY = (points.map((p) => p.dy).reduce(min) * src.height).toInt().clamp(0, src.height - 1);
    int maxY = (points.map((p) => p.dy).reduce(max) * src.height).toInt().clamp(1, src.height);

    int cropW = max(10, maxX - minX);
    int cropH = max(10, maxY - minY);

    img.Image cropped = img.copyCrop(src, x: minX, y: minY, width: cropW, height: cropH);

    if (_selectedFilter == 'magic') {
      cropped = img.adjustColor(cropped, brightness: 1.12, contrast: 1.25);
    } else if (_selectedFilter == 'bw') {
      cropped = img.grayscale(cropped);
    }

    Navigator.pop(context, cropped);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF0F172A),
      appBar: AppBar(
        title: const Text('القص الذكي وتعديل الألوان'),
        backgroundColor: Colors.black,
        foregroundColor: Colors.white,
        actions: [
          IconButton(
            icon: const Icon(Icons.check, color: Colors.greenAccent, size: 28),
            onPressed: _processCrop,
          ),
        ],
      ),
      body: Column(
        children: [
          Container(
            color: Colors.black87,
            padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 16),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceEvenly,
              children: [
                DropdownButton<String>(
                  value: _selectedFilter,
                  dropdownColor: Colors.black87,
                  style: const TextStyle(color: Colors.white, fontSize: 12),
                  items: const [
                    DropdownMenuItem(value: 'magic', child: Text('✨ تبييض سحري')),
                    DropdownMenuItem(value: 'original', child: Text('🎨 ألوان أصلية')),
                    DropdownMenuItem(value: 'bw', child: Text('📄 أبيض وأسود')),
                  ],
                  onChanged: (val) => setState(() => _selectedFilter = val!),
                ),
                ElevatedButton.icon(
                  onPressed: () {
                    setState(() {
                      points = [
                        const Offset(0.05, 0.05),
                        const Offset(0.95, 0.05),
                        const Offset(0.95, 0.95),
                        const Offset(0.05, 0.95),
                      ];
                    });
                  },
                  icon: const Icon(Icons.center_focus_strong, size: 16),
                  label: const Text('ضبط المربع', style: TextStyle(fontSize: 11)),
                ),
              ],
            ),
          ),
          Expanded(
            child: LayoutBuilder(
              builder: (context, constraints) {
                final w = constraints.maxWidth;
                final h = constraints.maxHeight;

                return Stack(
                  children: [
                    Center(
                      child: Image.memory(
                        Uint8List.fromList(img.encodeJpg(widget.image)),
                        fit: BoxFit.contain,
                      ),
                    ),
                    CustomPaint(
                      size: Size(w, h),
                      painter: CropLinesPainter(points: points),
                    ),
                    ...List.generate(4, (index) {
                      return Positioned(
                        left: points[index].dx * w - 18,
                        top: points[index].dy * h - 18,
                        child: GestureDetector(
                          onPanUpdate: (details) {
                            setState(() {
                              double newX = (points[index].dx + details.delta.dx / w).clamp(0.0, 1.0);
                              double newY = (points[index].dy + details.delta.dy / h).clamp(0.0, 1.0);
                              points[index] = Offset(newX, newY);
                            });
                          },
                          child: Container(
                            width: 36,
                            height: 36,
                            decoration: BoxDecoration(
                              color: const Color(0xFF0284C7),
                              shape: BoxShape.circle,
                              border: Border.all(color: Colors.white, width: 3),
                              boxShadow: const [
                                BoxShadow(color: Colors.black54, blurRadius: 4),
                              ],
                            ),
                          ),
                        ),
                      );
                    }),
                  ],
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}

class CropLinesPainter extends CustomPainter {
  final List<Offset> points;
  CropLinesPainter({required this.points});

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = const Color(0xFF0284C7)
      ..strokeWidth = 2.5
      ..style = PaintingStyle.stroke;

    final path = Path();
    path.moveTo(points[0].dx * size.width, points[0].dy * size.height);
    path.lineTo(points[1].dx * size.width, points[1].dy * size.height);
    path.lineTo(points[2].dx * size.width, points[2].dy * size.height);
    path.lineTo(points[3].dx * size.width, points[3].dy * size.height);
    path.close();

    canvas.drawPath(path, paint);
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => true;
}
