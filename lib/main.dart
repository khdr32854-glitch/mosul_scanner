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

  /// يُعيد الصورة مدورة فعلياً لاستخدامها في PDF والقص
  img.Image get rotatedImage {
    if (rotation % 360 == 0) return image;
    final r = (rotation % 360 + 360) % 360;
    if (r == 90) return img.copyRotate(image, angle: 90);
    if (r == 180) return img.copyRotate(image, angle: 180);
    if (r == 270) return img.copyRotate(image, angle: 270);
    return image;
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
  String _currentMode = 'docs';
  double _zoom = 2.0; // عامل التكبير الافتراضي

  // ── إعادة بناء cachedBytes من الصورة المعدلة ─────────
  void _refreshCachedBytes(DocumentItem item) {
    item.cachedBytes = Uint8List.fromList(img.encodeJpg(item.image, quality: 90));
  }

  /// قص ذكي حقيقي: يبحث عن حدود المستند في الصورة
  img.Image _smartCrop(img.Image src) {
    final w = src.width;
    final h = src.height;
    if (w < 100 || h < 100) return src;

    // الخطوة 1: حساب متوسط الخلفية من الحواف الأربعة
    double bgSum = 0;
    int bgCount = 0;
    const borderWidth = 20;
    for (int x = 0; x < w; x++) {
      for (int by = 0; by < borderWidth && by < h; by++) {
        final p = src.getPixel(x, by);
        bgSum += img.getLuminanceRgb(p.r, p.g, p.b);
        bgCount++;
      }
      for (int by = max(0, h - borderWidth); by < h; by++) {
        final p = src.getPixel(x, by);
        bgSum += img.getLuminanceRgb(p.r, p.g, p.b);
        bgCount++;
      }
    }
    for (int y = borderWidth; y < h - borderWidth; y++) {
      for (int bx = 0; bx < borderWidth && bx < w; bx++) {
        final p = src.getPixel(bx, y);
        bgSum += img.getLuminanceRgb(p.r, p.g, p.b);
        bgCount++;
      }
      for (int bx = max(0, w - borderWidth); bx < w; bx++) {
        final p = src.getPixel(bx, y);
        bgSum += img.getLuminanceRgb(p.r, p.g, p.b);
        bgCount++;
      }
    }
    // إذا كانت الصورة كلها خلفية تقريباً
    if (bgCount < 100) return src;
    final double bgLum = bgSum / bgCount;

    // الخطوة 2: البحث عن الحدود (بكسل يختلف عن الخلفية)
    // نستخدم عتبة فرق 25 (من 0-255) لكشف أي خلفية
    const double threshold = 25.0;

    int findLeft() {
      for (int x = 0; x < w; x++) {
        int diffCount = 0;
        for (int y = h ~/ 4; y < h * 3 ~/ 4; y += 3) {
          final p = src.getPixel(x, y);
          final lum = img.getLuminanceRgb(p.r, p.g, p.b);
          if ((lum - bgLum).abs() > threshold) diffCount++;
        }
        // 30% من العينات مختلفة = بداية المستند
        if (diffCount > (h ~/ 2) / 3 * 0.30) return max(0, x - 5);
      }
      return 0;
    }

    int findRight() {
      for (int x = w - 1; x >= 0; x--) {
        int diffCount = 0;
        for (int y = h ~/ 4; y < h * 3 ~/ 4; y += 3) {
          final p = src.getPixel(x, y);
          final lum = img.getLuminanceRgb(p.r, p.g, p.b);
          if ((lum - bgLum).abs() > threshold) diffCount++;
        }
        if (diffCount > (h ~/ 2) / 3 * 0.30) return min(w, x + 5);
      }
      return w;
    }

    int findTop() {
      for (int y = 0; y < h; y++) {
        int diffCount = 0;
        for (int x = w ~/ 4; x < w * 3 ~/ 4; x += 3) {
          final p = src.getPixel(x, y);
          final lum = img.getLuminanceRgb(p.r, p.g, p.b);
          if ((lum - bgLum).abs() > threshold) diffCount++;
        }
        if (diffCount > (w ~/ 2) / 3 * 0.30) return max(0, y - 5);
      }
      return 0;
    }

    int findBottom() {
      for (int y = h - 1; y >= 0; y--) {
        int diffCount = 0;
        for (int x = w ~/ 4; x < w * 3 ~/ 4; x += 3) {
          final p = src.getPixel(x, y);
          final lum = img.getLuminanceRgb(p.r, p.g, p.b);
          if ((lum - bgLum).abs() > threshold) diffCount++;
        }
        if (diffCount > (w ~/ 2) / 3 * 0.30) return min(h, y + 5);
      }
      return h;
    }

    final left = findLeft();
    final right = findRight();
    final top = findTop();
    final bottom = findBottom();

    final cropW = right - left;
    final cropH = bottom - top;

    // التحقق من صحة القص
    if (cropW < 20 || cropH < 20 || cropW > w * 0.95 || cropH > h * 0.95) {
      // فشل الكشف - نستخدم قص بسيط 3%
      final mx = (w * 0.03).toInt();
      final my = (h * 0.03).toInt();
      return img.copyCrop(src, x: mx, y: my, width: w - mx * 2, height: h - my * 2);
    }

    return img.copyCrop(src, x: left, y: top, width: cropW, height: cropH);
  }

  void _addNewImages(ImageSource source) async {
    final List<XFile> pickedFiles = [];
    if (source == ImageSource.gallery) {
      final files = await _picker.pickMultiImage();
      pickedFiles.addAll(files);
    } else {
      final file = await _picker.pickImage(source: source);
      if (file != null) pickedFiles.add(file);
    }

    for (int i = 0; i < pickedFiles.length; i++) {
      final bytes = await File(pickedFiles[i].path).readAsBytes();
      final decodedImg = img.decodeImage(bytes);

      if (decodedImg != null) {
        // تطبيق القص الذكي
        final autoCropped = _smartCrop(decodedImg);
        // تحسين الألوان
        final enhanced = img.adjustColor(autoCropped,
            brightness: 1.08, contrast: 1.18);
        final encodedBytes =
            Uint8List.fromList(img.encodeJpg(enhanced, quality: 90));

        setState(() {
          final newItem = DocumentItem(
            id: DateTime.now().millisecondsSinceEpoch.toString() +
                i.toString(),
            image: enhanced,
            cachedBytes: encodedBytes,
            widthMm: _currentMode == 'photos' ? 36 : 85,
            heightMm: _currentMode == 'photos'
                ? 45
                : (enhanced.height / enhanced.width * 85),
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

  void _resizeActive(double w, double h, {bool isPhoto = false}) {
    if (_activeItem == null) return;
    setState(() {
      _activeItem!.widthMm = w;
      _activeItem!.heightMm = h;
      _activeItem!.isPhotoStyle = isPhoto;
    });
  }

  /// ✅ تدوير حقيقي: يغير الصورة فعلياً + يعيد cachedBytes
  void _rotateActive() {
    if (_activeItem == null) return;
    setState(() {
      final item = _activeItem!;
      // تدوير الصورة فعلياً 90°
      item.image = img.copyRotate(item.image, angle: 90);
      // تحديث cachedBytes لتعكس الصورة المدورة
      _refreshCachedBytes(item);
      // تبديل العرض والارتفاع
      final tmp = item.widthMm;
      item.widthMm = item.heightMm;
      item.heightMm = tmp;
      // إعادة تعيين زاوية الدوران البصري إلى الصفر
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
      double curX = 10;
      double curY = 10;
      double maxH = 0;
      const margin = 5.0;

      for (var item in _items) {
        if (curX + item.widthMm > 200) {
          curX = 10;
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

  /// ✅ يفتح القص - يمرر الصورة المدورة فعلياً
  void _openCropOverlay() async {
    if (_activeItem == null) return;
    final item = _activeItem!;
    // تمرير الصورة المدورة فعلياً بدلاً من استخدام cachedBytes
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
        item.heightMm =
            (cropped.height / cropped.width * item.widthMm);
        // إعادة تعيين الدوران لأن الصورة أصبحت مدورة فعلاً
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
            // ✅ استخدام الصورة المدورة فعلياً في PDF
            final printImage = item.rotatedImage;
            final printBytes =
                Uint8List.fromList(img.encodeJpg(printImage, quality: 95));

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
        title: const Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('مكتب علاء الحديدي - الماسح الذكي',
                style:
                    TextStyle(fontSize: 15, fontWeight: FontWeight.bold)),
            Text('Telegram: @Oo_qp',
                style: TextStyle(fontSize: 10, color: Colors.white70)),
          ],
        ),
        backgroundColor: const Color(0xFF0284C7),
        foregroundColor: Colors.white,
        actions: [
          // ✅ زر التكبير +
          IconButton(
            icon: const Icon(Icons.zoom_in),
            tooltip: 'تكبير',
            onPressed: () =>
                setState(() => _zoom = (_zoom + 0.25).clamp(0.5, 4.0)),
          ),
          // ✅ زر التصغير -
          IconButton(
            icon: const Icon(Icons.zoom_out),
            tooltip: 'تصغير',
            onPressed: () =>
                setState(() => _zoom = (_zoom - 0.25).clamp(0.5, 4.0)),
          ),
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
          // ── SIDEBAR ──────────────────────────────────────
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
                        setState(() =>
                            _currentMode = newSelection.elementAt(0));
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

                  // ── SIZES ─────────────────────────────────
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

          // ── PAGE CANVAS ───────────────────────────────────
          Expanded(
            child: Container(
              color: const Color(0xFF475569),
              child: Center(
                child: InteractiveViewer(
                  maxScale: 4.0,
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
                        children:
                            List.generate(_items.length, (index) {
                          final item = _items[index];
                          final isActive =
                              _activeItem?.id == item.id;
                          return Positioned(
                            left: item.xMm * _zoom,
                            top: item.yMm * _zoom,
                            width: item.widthMm * _zoom,
                            height: item.heightMm * _zoom,
                            child: GestureDetector(
                              onTap: () => setState(
                                  () => _activeItem = item),
                              onPanUpdate: (details) {
                                setState(() {
                                  item.xMm += details.delta.dx / _zoom;
                                  item.yMm += details.delta.dy / _zoom;
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
// SMART CROP SCREEN — محسّن الأداء
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

  // ✅ تخزين البايتات مرة واحدة لتجنب إعادة التشفير مع كل تحديث
  late Uint8List _imageBytes;

  @override
  void initState() {
    super.initState();
    points = [
      const Offset(0.05, 0.05),
      const Offset(0.95, 0.05),
      const Offset(0.95, 0.95),
      const Offset(0.05, 0.95),
    ];
    // تشفير الصورة مرة واحدة فقط
    _imageBytes = Uint8List.fromList(img.encodeJpg(widget.image, quality: 85));
  }

  void _processCrop() {
    final src = widget.image;

    // تحويل النقاط النسبية إلى إحداثيات بكسل
    final xs = points.map((p) => (p.dx * src.width).toInt()).toList();
    final ys = points.map((p) => (p.dy * src.height).toInt()).toList();

    final minX = xs.reduce(min).clamp(0, src.width - 1);
    final maxX = xs.reduce(max).clamp(1, src.width);
    final minY = ys.reduce(min).clamp(0, src.height - 1);
    final maxY = ys.reduce(max).clamp(1, src.height);

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
                  label:
                      const Text('ضبط المربع', style: TextStyle(fontSize: 11)),
                ),
              ],
            ),
          ),
          Expanded(
            child: LayoutBuilder(
              builder: (context, constraints) {
                final w = constraints.maxWidth;
                final h = constraints.maxHeight;

                // ✅ الصورة تستخدم _imageBytes المخزن مسبقاً — لا إعادة تشفير
                return Stack(
                  children: [
                    Center(
                      child: Image.memory(
                        _imageBytes,
                        fit: BoxFit.contain,
                      ),
                    ),
                    // خطوط القص
                    CustomPaint(
                      size: Size(w, h),
                      painter: CropLinesPainter(points: points),
                    ),
                    // نقاط السحب الأربعة
                    ...List.generate(4, (index) {
                      return Positioned(
                        left: points[index].dx * w - 18,
                        top: points[index].dy * h - 18,
                        child: GestureDetector(
                          onPanUpdate: (details) {
                            setState(() {
                              final newX = (points[index].dx +
                                      details.delta.dx / w)
                                  .clamp(0.0, 1.0);
                              final newY = (points[index].dy +
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
                              border:
                                  Border.all(color: Colors.white, width: 3),
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
