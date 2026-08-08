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
  String _currentMode = 'docs';

  static const double pageWidthMm = 210;
  static const double pageHeightMm = 297;
  static const double pageMarginMm = 10;

  void _refreshCachedBytes(DocumentItem item) {
    item.cachedBytes = Uint8List.fromList(img.encodeJpg(item.image, quality: 90));
  }

  // ✅ 1. إدخال الصور كما هي دون أي قص أو تبييض تلقائي قسري
  void _addNewImages(ImageSource source) async {
    final List<XFile> pickedFiles = [];
    if (source == ImageSource.gallery) {
      final files = await _picker.pickMultiImage();
      pickedFiles.addAll(files);
    } else {
      final file = await _picker.pickImage(source: source, imageQuality: 95);
      if (file != null) pickedFiles.add(file);
    }

    for (int i = 0; i < pickedFiles.length; i++) {
      final bytes = await File(pickedFiles[i].path).readAsBytes();
      final decodedImg = img.decodeImage(bytes);

      if (decodedImg != null) {
        final encodedBytes = Uint8List.fromList(img.encodeJpg(decodedImg, quality: 90));

        setState(() {
          final newItem = DocumentItem(
            id: DateTime.now().millisecondsSinceEpoch.toString() + i.toString(),
            image: decodedImg, // الصورة كما هي بدون تعديل
            cachedBytes: encodedBytes,
            widthMm: _currentMode == 'photos' ? 36 : 85,
            heightMm: _currentMode == 'photos' ? 45 : (decodedImg.height / decodedImg.width * 85),
            xMm: pageMarginMm + (_items.length * 4),
            yMm: pageMarginMm + (_items.length * 4),
            isPhotoStyle: _currentMode == 'photos',
          );
          _items.add(newItem);
          _activeItem = newItem;
        });
      }
    }
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
      final item = _activeItem!;
      item.image = img.copyRotate(item.image, angle: 90);
      _refreshCachedBytes(item);
      final tmp = item.widthMm;
      item.widthMm = item.heightMm;
      item.heightMm = tmp;
      item.rotation = 0;
    });
  }

  void _duplicateActive() {
    if (_activeItem == null) return;
    setState(() {
      final src = _activeItem!;
      final newItem = DocumentItem(
        id: DateTime.now().millisecondsSinceEpoch.toString(),
        image: img.copyResize(src.image, width: src.image.width),
        cachedBytes: Uint8List.fromList(src.cachedBytes),
        widthMm: src.widthMm,
        heightMm: src.heightMm,
        xMm: src.xMm + 5,
        yMm: src.yMm + 5,
        rotation: src.rotation,
        isPhotoStyle: src.isPhotoStyle,
      );
      _items.add(newItem);
      _activeItem = newItem;
    });
  }

  void _autoAlign() {
    setState(() {
      double curX = pageMarginMm;
      double curY = pageMarginMm;
      double maxH = 0;
      const margin = 5.0;
      final maxX = pageWidthMm - pageMarginMm;

      for (var item in _items) {
        if (curX + item.widthMm > maxX) {
          curX = pageMarginMm;
          curY += maxH + margin;
          maxH = 0;
        }
        item.xMm = curX;
        item.yMm = curY;
        curX += item.widthMm + margin;
        if (item.heightMm > maxH) maxH = item.heightMm;
      }
    });
  }

  void _openCropOverlay() async {
    if (_activeItem == null) return;
    final item = _activeItem!;
    final rotated = item.rotatedImage;

    final img.Image? cropped = await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => SmartCropScreen(image: rotated),
      ),
    );

    if (cropped != null && mounted) {
      setState(() {
        item.image = cropped;
        _refreshCachedBytes(item);
        item.heightMm = (cropped.height / cropped.width * item.widthMm);
        item.rotation = 0;
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
          final List<pw.Widget> widgets = [];

          for (final item in _items) {
            final printImage = item.rotatedImage;
            final printBytes = Uint8List.fromList(img.encodeJpg(printImage, quality: 95));

            widgets.add(
              pw.Positioned(
                left: item.xMm * PdfPageFormat.mm,
                top: item.yMm * PdfPageFormat.mm,
                child: pw.SizedBox(
                  width: item.widthMm * PdfPageFormat.mm,
                  height: item.heightMm * PdfPageFormat.mm,
                  child: pw.Image(
                    pw.MemoryImage(printBytes),
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
        title: const Text('مكتب علاء الحديدي - الماسح الذكي', style: TextStyle(fontSize: 14, fontWeight: FontWeight.bold)),
        backgroundColor: const Color(0xFF0284C7),
        foregroundColor: Colors.white,
        actions: [
          IconButton(
            icon: const Icon(Icons.print, size: 20),
            tooltip: 'طباعة A4',
            onPressed: _exportAndPrint,
          ),
          IconButton(
            icon: const Icon(Icons.add_a_photo, size: 20),
            onPressed: () => _addNewImages(ImageSource.camera),
          ),
          IconButton(
            icon: const Icon(Icons.photo_library, size: 20),
            onPressed: () => _addNewImages(ImageSource.gallery),
          ),
        ],
      ),
      body: Row(
        children: [
          // ✅ 2. تقليل حجم الشريط الجانبي والأزرار لتكبير ورقة العمل
          Container(
            width: 180, // تصغير شريط التحكم من 230 إلى 180
            color: Colors.white,
            padding: const EdgeInsets.all(6.0),
            child: SingleChildScrollView(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  SegmentedButton<String>(
                    segments: const [
                      ButtonSegment(value: 'docs', label: Text('مستمسكات', style: TextStyle(fontSize: 9))),
                      ButtonSegment(value: 'photos', label: Text('صور', style: TextStyle(fontSize: 9))),
                    ],
                    selected: {_currentMode},
                    onSelectionChanged: (Set<String> newSelection) {
                      if (newSelection.isNotEmpty) {
                        setState(() => _currentMode = newSelection.elementAt(0));
                      }
                    },
                  ),
                  const SizedBox(height: 6),
                  ElevatedButton.icon(
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFF10B981),
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(vertical: 8),
                    ),
                    onPressed: _autoAlign,
                    icon: const Icon(Icons.auto_awesome, size: 14),
                    label: const Text('ترتيب تلقائي', style: TextStyle(fontSize: 10)),
                  ),
                  const SizedBox(height: 4),
                  ElevatedButton.icon(
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFFD97706),
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(vertical: 8),
                    ),
                    onPressed: _openCropOverlay,
                    icon: const Icon(Icons.crop_rotate, size: 14),
                    label: const Text('القص والتحسين', style: TextStyle(fontSize: 10)),
                  ),
                  const SizedBox(height: 4),
                  Row(
                    children: [
                      Expanded(
                        child: ElevatedButton(
                          style: ElevatedButton.styleFrom(
                            backgroundColor: const Color(0xFF475569),
                            foregroundColor: Colors.white,
                            padding: const EdgeInsets.symmetric(vertical: 6),
                          ),
                          onPressed: _rotateActive,
                          child: const Text('تدوير', style: TextStyle(fontSize: 9)),
                        ),
                      ),
                      const SizedBox(width: 2),
                      Expanded(
                        child: ElevatedButton(
                          style: ElevatedButton.styleFrom(
                            backgroundColor: const Color(0xFF8B5CF6),
                            foregroundColor: Colors.white,
                            padding: const EdgeInsets.symmetric(vertical: 6),
                          ),
                          onPressed: _duplicateActive,
                          child: const Text('نسخ', style: TextStyle(fontSize: 9)),
                        ),
                      ),
                    ],
                  ),
                  const Divider(),
                  if (_currentMode == 'docs') ...[
                    const Text('قياسات المستمسكات', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 10, color: Color(0xFF0369A1))),
                    const SizedBox(height: 2),
                    ElevatedButton(
                      onPressed: () => _resizeActive(85, 54),
                      child: const Text('بطاقة موحدة', style: TextStyle(fontSize: 10)),
                    ),
                    ElevatedButton(
                      onPressed: () => _resizeActive(88, 58),
                      child: const Text('بطاقة سكن', style: TextStyle(fontSize: 10)),
                    ),
                    ElevatedButton(
                      onPressed: () => _resizeActive(210, 297),
                      child: const Text('ورقة كاملة (A4)', style: TextStyle(fontSize: 10)),
                    ),
                  ] else ...[
                    const Text('قياسات الصور', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 10, color: Color(0xFF0369A1))),
                    const SizedBox(height: 2),
                    ElevatedButton(
                      onPressed: () => _resizeActive(36, 45, isPhoto: true),
                      child: const Text('معاملة (3.6×4.5)', style: TextStyle(fontSize: 10)),
                    ),
                    ElevatedButton(
                      onPressed: () => _resizeActive(25, 34, isPhoto: true),
                      child: const Text('مصغر (2.5×3.4)', style: TextStyle(fontSize: 10)),
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
                      icon: const Icon(Icons.delete, size: 14),
                      label: const Text('حذف العنصر', style: TextStyle(fontSize: 10)),
                    ),
                ],
              ),
            ),
          ),

          // ✅ 3. ورقة العمل A4 تأخذ المساحة الأكبر في الشاشة
          Expanded(
            child: Container(
              color: const Color(0xFF475569),
              child: LayoutBuilder(
                builder: (context, constraints) {
                  final scaleX = (constraints.maxWidth - 10) / pageWidthMm;
                  final scaleY = (constraints.maxHeight - 10) / pageHeightMm;
                  final scale = min(scaleX, scaleY);

                  final pageW = pageWidthMm * scale;
                  final pageH = pageHeightMm * scale;

                  return Center(
                    child: Container(
                      width: pageW,
                      height: pageH,
                      decoration: BoxDecoration(
                        color: Colors.white,
                        boxShadow: [
                          BoxShadow(
                            color: Colors.black.withOpacity(0.5),
                            blurRadius: 16,
                            offset: const Offset(0, 4),
                          ),
                        ],
                      ),
                      child: ClipRect(
                        child: Stack(
                          children: List.generate(_items.length, (index) {
                            final item = _items[index];
                            final isActive = _activeItem?.id == item.id;
                            return Positioned(
                              left: item.xMm * scale,
                              top: item.yMm * scale,
                              width: item.widthMm * scale,
                              height: item.heightMm * scale,
                              child: GestureDetector(
                                onTap: () => setState(() => _activeItem = item),
                                onPanUpdate: (details) {
                                  setState(() {
                                    item.xMm += details.delta.dx / scale;
                                    item.yMm += details.delta.dy / scale;
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
                          }),
                        ),
                      ),
                    ),
                  );
                },
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// ═══════════════════════════════════════════════════════
// شاشة القص والتحسين بحنيه ولين بدون حدة قاسية
// ═══════════════════════════════════════════════════════
class SmartCropScreen extends StatefulWidget {
  final img.Image image;
  const SmartCropScreen({super.key, required this.image});

  @override
  State<SmartCropScreen> createState() => _SmartCropScreenState();
}

class _SmartCropScreenState extends State<SmartCropScreen> {
  late List<Offset> points;
  String _selectedFilter = 'soft'; // افتراضياً تحسين ناعم ولطيف
  late Uint8List _imageBytes;

  @override
  void initState() {
    super.initState();
    points = [
      const Offset(0.02, 0.02),
      const Offset(0.98, 0.02),
      const Offset(0.98, 0.98),
      const Offset(0.02, 0.98),
    ];
    _imageBytes = Uint8List.fromList(img.encodeJpg(widget.image, quality: 85));
  }

  // خيار القص التلقائي فقط عند الطلب داخل شاشة القص
  void _autoDetectCrop() {
    setState(() {
      points = [
        const Offset(0.08, 0.08),
        const Offset(0.92, 0.08),
        const Offset(0.92, 0.92),
        const Offset(0.08, 0.92),
      ];
    });
  }

  void _processCrop() {
    final src = widget.image;

    final xs = points.map((p) => (p.dx * src.width).toInt()).toList();
    final ys = points.map((p) => (p.dy * src.height).toInt()).toList();

    final minX = xs.reduce(min).clamp(0, src.width - 1);
    final maxX = xs.reduce(max).clamp(1, src.width);
    final minY = ys.reduce(min).clamp(0, src.height - 1);
    final maxY = ys.reduce(max).clamp(1, src.height);

    int cropW = max(10, maxX - minX);
    int cropH = max(10, maxY - minY);

    img.Image cropped = img.copyCrop(src, x: minX, y: minY, width: cropW, height: cropH);

    // ✅ 4. التبييض بحنية وبشكل لطيف لا يدمر ألوان التفاصيل
    if (_selectedFilter == 'soft') {
      cropped = img.adjustColor(cropped, brightness: 1.05, contrast: 1.08); // تحسين ناعم خفيف
    } else if (_selectedFilter == 'magic') {
      cropped = img.adjustColor(cropped, brightness: 1.12, contrast: 1.18);
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
        title: const Text('القص والتعديل', style: TextStyle(fontSize: 14)),
        backgroundColor: Colors.black,
        foregroundColor: Colors.white,
        actions: [
          IconButton(
            icon: const Icon(Icons.check, color: Colors.greenAccent, size: 26),
            onPressed: _processCrop,
          ),
        ],
      ),
      body: Column(
        children: [
          Container(
            color: Colors.black87,
            padding: const EdgeInsets.symmetric(vertical: 6, horizontal: 12),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceEvenly,
              children: [
                DropdownButton<String>(
                  value: _selectedFilter,
                  dropdownColor: Colors.black87,
                  style: const TextStyle(color: Colors.white, fontSize: 11),
                  items: const [
                    DropdownMenuItem(value: 'original', child: Text('🎨 بدون فلتر (أصلي)')),
                    DropdownMenuItem(value: 'soft', child: Text('✨ تحسين ناعم (بحنية)')),
                    DropdownMenuItem(value: 'magic', child: Text('📄 تبييض متوسط')),
                    DropdownMenuItem(value: 'bw', child: Text('⚪ أبيض وأسود')),
                  ],
                  onChanged: (val) => setState(() => _selectedFilter = val!),
                ),
                ElevatedButton.icon(
                  onPressed: _autoDetectCrop,
                  icon: const Icon(Icons.auto_awesome, size: 14),
                  label: const Text('قص تلقائي', style: TextStyle(fontSize: 10)),
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
                        _imageBytes,
                        fit: BoxFit.contain,
                      ),
                    ),
                    CustomPaint(
                      size: Size(w, h),
                      painter: CropLinesPainter(points: points),
                    ),
                    ...List.generate(4, (index) {
                      return Positioned(
                        left: points[index].dx * w - 16,
                        top: points[index].dy * h - 16,
                        child: GestureDetector(
                          onPanUpdate: (details) {
                            setState(() {
                              final newX = (points[index].dx + details.delta.dx / w).clamp(0.0, 1.0);
                              final newY = (points[index].dy + details.delta.dy / h).clamp(0.0, 1.0);
                              points[index] = Offset(newX, newY);
                            });
                          },
                          child: Container(
                            width: 32,
                            height: 32,
                            decoration: BoxDecoration(
                              color: const Color(0xFF0284C7),
                              shape: BoxShape.circle,
                              border: Border.all(color: Colors.white, width: 2.5),
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
      ..strokeWidth = 2.0
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
