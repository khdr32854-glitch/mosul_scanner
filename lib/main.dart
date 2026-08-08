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
// خوارزمية المسح الذكي — Computer Vision متكاملة
// ═══════════════════════════════════════════════════════
class SmartScanner {
  /// تحويل إلى تدرج رمادي
  static img.Image toGrayscale(img.Image src) {
    return img.grayscale(src);
  }

  /// Gaussian Blur بسيط (3x3 kernel)
  static img.Image gaussianBlur(img.Image src) {
    return img.gaussianBlur(src, radius: 2);
  }

  /// كشف الحواف عبر Sobel operator
  static img.Image sobelEdgeDetection(img.Image gray) {
    final w = gray.width;
    final h = gray.height;
    final edges = img.Image(width: w, height: h);

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
        final mag = sqrt(gx * gx + gy * gy).toInt().clamp(0, 255);

        edges.setPixelRgba(x, y, mag, mag, mag, 255);
      }
    }
    return edges;
  }

  /// البحث عن حدود المستند من صورة الحواف
  /// يُعيد (left, top, right, bottom) كنسب 0.0 - 1.0
  static List<double>? findDocumentBounds(img.Image edgeImage) {
    final w = edgeImage.width;
    final h = edgeImage.height;

    if (w < 50 || h < 50) return null;

    // كل بكسل حوافي = قيمته > عتبة
    const edgeThreshold = 40;

    // تجميع الإسقاطات الأفقية والعمودية
    final hProj = List<int>.filled(h, 0); // إسقاط أفقي (لكل صف)
    final vProj = List<int>.filled(w, 0); // إسقاط عمودي (لكل عمود)

    for (int y = 0; y < h; y++) {
      for (int x = 0; x < w; x++) {
        final p = edgeImage.getPixel(x, y);
        final val = (p.r + p.g + p.b) ~/ 3;
        if (val > edgeThreshold) {
          hProj[y]++;
          vProj[x]++;
        }
      }
    }

    // البحث عن القمم في الإسقاطات (بداية ونهاية المنطقة ذات الحواف الكثيفة)
    final thresholdH = hProj.reduce((a, b) => a > b ? a : b) * 0.15;
    final thresholdV = vProj.reduce((a, b) => a > b ? a : b) * 0.15;

    int? top, bottom, left, right;

    for (int y = 0; y < h; y++) {
      if (hProj[y] > thresholdH) { top = y; break; }
    }
    for (int y = h - 1; y >= 0; y--) {
      if (hProj[y] > thresholdH) { bottom = y; break; }
    }
    for (int x = 0; x < w; x++) {
      if (vProj[x] > thresholdV) { left = x; break; }
    }
    for (int x = w - 1; x >= 0; x--) {
      if (vProj[x] > thresholdV) { right = x; break; }
    }

    if (top == null || bottom == null || left == null || right == null) {
      return null;
    }

    final docH = bottom - top;
    final docW = right - left;

    // تحقق: المستند يجب أن يكون معقول الحجم
    if (docW < w * 0.08 || docH < h * 0.08) return null;
    if (docW > w * 0.96 && docH > h * 0.96) return null; // كامل الصورة = لا مستند

    // إضافة هامش صغير للأمان
    const marginRatio = 0.01;
    final finalLeft = (left / w - marginRatio).clamp(0.0, 1.0);
    final finalTop = (top / h - marginRatio).clamp(0.0, 1.0);
    final finalRight = (right / w + marginRatio).clamp(0.0, 1.0);
    final finalBottom = (bottom / h + marginRatio).clamp(0.0, 1.0);

    return [finalLeft, finalTop, finalRight, finalBottom];
  }

  /// ✅ خط الأنابيب الكامل:
  /// Grayscale → Blur → Sobel → FindBounds → Crop → Enhance
  static img.Image processDocument(img.Image src) {
    final w = src.width;
    final h = src.height;

    // تصغير الصورة للتحليل السريع (max 500px عرض)
    img.Image small;
    double ratio;
    if (w > 500) {
      ratio = w / 500.0;
      small = img.copyResize(src, width: 500);
    } else {
      ratio = 1.0;
      small = src;
    }

    // 1. Grayscale
    final gray = toGrayscale(small);

    // 2. Gaussian Blur
    final blurred = gaussianBlur(gray);

    // 3. Sobel Edge Detection
    final edges = sobelEdgeDetection(blurred);

    // 4. البحث عن حدود المستند
    final bounds = findDocumentBounds(edges);

    img.Image cropped;
    if (bounds != null) {
      final left = (bounds[0] * small.width).toInt().clamp(0, small.width - 1);
      final top = (bounds[1] * small.height).toInt().clamp(0, small.height - 1);
      final right = (bounds[2] * small.width).toInt().clamp(1, small.width);
      final bottom = (bounds[3] * small.height).toInt().clamp(1, small.height);

      // التحويل إلى الصورة الأصلية إذا كنا نستخدم صورة مصغرة
      if (ratio > 1.0) {
        final origLeft = (left * ratio).toInt().clamp(0, src.width - 1);
        final origTop = (top * ratio).toInt().clamp(0, src.height - 1);
        final origRight = (right * ratio).toInt().clamp(1, src.width);
        final origBottom = (bottom * ratio).toInt().clamp(1, src.height);
        final cw = origRight - origLeft;
        final ch = origBottom - origTop;

        if (cw > 20 && ch > 20 && cw < src.width * 0.95) {
          cropped = img.copyCrop(src, x: origLeft, y: origTop, width: cw, height: ch);
        } else {
          cropped = src;
        }
      } else {
        final cw = right - left;
        final ch = bottom - top;
        if (cw > 20 && ch > 20 && cw < src.width * 0.95) {
          cropped = img.copyCrop(src, x: left, y: top, width: cw, height: ch);
        } else {
          cropped = src;
        }
      }
    } else {
      // فشل الكشف - قص بسيط 4%
      final mx = (src.width * 0.04).toInt();
      final my = (src.height * 0.04).toInt();
      cropped = img.copyCrop(
          src, x: mx, y: my, width: src.width - mx * 2, height: src.height - my * 2);
    }

    // 5. تحسين الألوان (تبييض + تباين)
    return img.adjustColor(cropped, brightness: 1.10, contrast: 1.25);
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

  static const double pageWidthMm = 210; // A4
  static const double pageHeightMm = 297;
  static const double pageMarginMm = 10;

  void _refreshCachedBytes(DocumentItem item) {
    item.cachedBytes =
        Uint8List.fromList(img.encodeJpg(item.image, quality: 90));
  }

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
        // ✅ تطبيق خوارزمية المسح الذكي الكاملة
        final scanned = SmartScanner.processDocument(decodedImg);
        final encodedBytes =
            Uint8List.fromList(img.encodeJpg(scanned, quality: 90));

        setState(() {
          final newItem = DocumentItem(
            id: DateTime.now().millisecondsSinceEpoch.toString() +
                i.toString(),
            image: scanned,
            cachedBytes: encodedBytes,
            widthMm: _currentMode == 'photos' ? 36 : 85,
            heightMm: _currentMode == 'photos'
                ? 45
                : (scanned.height / scanned.width * 85),
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
        item.heightMm =
            (cropped.height / cropped.width * item.widthMm);
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
          IconButton(
            icon: const Icon(Icons.zoom_in),
            tooltip: 'تكبير',
            onPressed: () => setState(() {}),
          ),
          IconButton(
            icon: const Icon(Icons.zoom_out),
            tooltip: 'تصغير',
            onPressed: () => setState(() {}),
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

          // ── ✅ PAGE CANVAS — يملأ كامل المساحة بنسبة A4 ──
          Expanded(
            child: Container(
              color: const Color(0xFF475569),
              child: LayoutBuilder(
                builder: (context, constraints) {
                  final scaleX =
                      (constraints.maxWidth - 20) / pageWidthMm;
                  final scaleY =
                      (constraints.maxHeight - 20) / pageHeightMm;
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
                              offset: const Offset(0, 4)),
                        ],
                      ),
                      child: ClipRect(
                        child: Stack(
                          children: List.generate(
                              _items.length, (index) {
                            final item = _items[index];
                            final isActive =
                                _activeItem?.id == item.id;
                            return Positioned(
                              left: item.xMm * scale,
                              top: item.yMm * scale,
                              width: item.widthMm * scale,
                              height: item.heightMm * scale,
                              child: GestureDetector(
                                onTap: () => setState(
                                    () => _activeItem = item),
                                onPanUpdate: (details) {
                                  setState(() {
                                    item.xMm +=
                                        details.delta.dx / scale;
                                    item.yMm +=
                                        details.delta.dy / scale;
                                  });
                                },
                                child: Container(
                                  decoration: BoxDecoration(
                                    border: Border.all(
                                      color: isActive
                                          ? Colors.blue
                                          : (item.isPhotoStyle
                                              ? Colors.red
                                              : Colors
                                                  .transparent),
                                      width: isActive ? 2 : 1,
                                    ),
                                  ),
                                  child: Transform.rotate(
                                    angle:
                                        item.rotation * pi / 180,
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
    _imageBytes =
        Uint8List.fromList(img.encodeJpg(widget.image, quality: 85));
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
                  style:
                      const TextStyle(color: Colors.white, fontSize: 12),
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
                  icon:
                      const Icon(Icons.center_focus_strong, size: 16),
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
                        left: points[index].dx * w - 18,
                        top: points[index].dy * h - 18,
                        child: GestureDetector(
                          onPanUpdate: (details) {
                            setState(() {
                              final newX =
                                  (points[index].dx +
                                          details.delta.dx / w)
                                      .clamp(0.0, 1.0);
                              final newY =
                                  (points[index].dy +
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
                                    color: Colors.black54,
                                    blurRadius: 4),
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
