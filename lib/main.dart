import 'dart:io';
import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:google_mlkit_document_scanner/google_mlkit_document_scanner.dart';
import 'package:image/image.dart' as img;
import 'package:image_picker/image_picker.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';

import 'edge_detector.dart';
import 'perspective_warp.dart';

// ==============================================================
// GOOGLE SCANNER
// ==============================================================

class GoogleScanner {
  static Future<List<String>?> scan() async {
    final options = DocumentScannerOptions(
      documentFormats: {DocumentFormat.jpeg, DocumentFormat.pdf},
      mode: ScannerMode.full,
      pageLimit: 2,
      isGalleryImport: false,
    );

    final scanner = DocumentScanner(options: options);

    try {
      final result = await scanner.scanDocument();
      return result.images;
    } catch (e) {
      debugPrint('Google Document Scanner Error: $e');
      return null;
    } finally {
      try {
        await scanner.close();
      } catch (_) {}
    }
  }
}

// ==============================================================
// IMAGE UTILS
// ==============================================================

class ImageUtils {
  static img.Image? decodeBytes(Uint8List bytes) {
    try {
      return img.decodeImage(bytes);
    } catch (e) {
      debugPrint('Image decode error: $e');
      return null;
    }
  }

  static Uint8List encodeJpg(img.Image image, {int quality = 92}) {
    // JPEG لا يدعم الشفافية. إذا كانت الصورة 4 قنوات (RGBA)
    // نحولها إلى RGB قبل الترميز لتجنب الصورة السوداء.
    img.Image toEncode = image;
    if (image.numChannels == 4) {
      try {
        toEncode = image.convert(numChannels: 3);
      } catch (e) {
        debugPrint('RGBA->RGB convert error: $e');
        toEncode = image;
      }
    }
    try {
      return Uint8List.fromList(img.encodeJpg(toEncode, quality: quality));
    } catch (e) {
      debugPrint('JPEG encode error: $e');
      return Uint8List(0);
    }
  }

  static bool isValid(img.Image? image) {
    return image != null && image.width >= 10 && image.height >= 10;
  }
}

// ==============================================================
// ENHANCE
// ==============================================================

enum EnhanceMode { none, magic, bw }

class ImageEnhancer {
  static img.Image apply(img.Image source, EnhanceMode mode, double intensity) {
    final image = img.Image.from(source);

    switch (mode) {
      case EnhanceMode.none:
        return image;

      case EnhanceMode.magic:
        try {
          final normalized = img.normalize(image, min: 0, max: 255);
          return img.adjustColor(
            normalized,
            contrast: 1.1 + (0.3 * intensity),
            brightness: 1.0 + (0.1 * intensity),
            saturation: 1.0 + (0.2 * intensity),
          );
        } catch (_) {
          return image;
        }

      case EnhanceMode.bw:
        try {
          final gray = img.grayscale(image);
          final normalized = img.normalize(gray, min: 0, max: 255);
          return img.adjustColor(
            normalized,
            contrast: 1.2 + (0.4 * intensity),
            brightness: 1.0 + (0.1 * intensity),
          );
        } catch (_) {
          return image;
        }
    }
  }
}

// ==============================================================
// MANUAL CROP
// ==============================================================

class ManualCrop {
  static img.Image cropPerspective(
    img.Image source,
    double x1, double y1, double x2, double y2,
    double x3, double y3, double x4, double y4,
  ) {
    if (!ImageUtils.isValid(source)) {
      return img.Image.from(source);
    }
    final w = source.width.toDouble();
    final h = source.height.toDouble();

    final corners = [
      WarpPoint(x1.clamp(0.0, 1.0) * w, y1.clamp(0.0, 1.0) * h),
      WarpPoint(x2.clamp(0.0, 1.0) * w, y2.clamp(0.0, 1.0) * h),
      WarpPoint(x3.clamp(0.0, 1.0) * w, y3.clamp(0.0, 1.0) * h),
      WarpPoint(x4.clamp(0.0, 1.0) * w, y4.clamp(0.0, 1.0) * h),
    ];

    try {
      return PerspectiveWarp.warp(source, corners);
    } catch (e) {
      debugPrint('Perspective warp error: $e');
      return img.Image.from(source);
    }
  }
}

// ==============================================================
// TOP-LEVEL ISOLATE
// ==============================================================

List<double>? detectDocumentCornersIsolate(Uint8List imageBytes) {
  return DocumentEdgeDetector.detect(imageBytes);
}

// ==============================================================
// APP
// ==============================================================

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(const MosulScannerApp());
}

class MosulScannerApp extends StatelessWidget {
  const MosulScannerApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Mosul Scanner Pro',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(useMaterial3: true, colorSchemeSeed: Colors.blueGrey),
      home: const MainScannerScreen(),
    );
  }
}

// ==============================================================
// DOCUMENT ITEM
// ==============================================================

class DocumentItem {
  final String id;
  img.Image image;
  Uint8List cachedBytes;
  double widthMm, heightMm, xMm, yMm;
  int rotationAngle;
  bool isPhotoMode, hasCurvedCorners;

  DocumentItem({
    required this.id,
    required this.image,
    required this.cachedBytes,
    required this.widthMm,
    required this.heightMm,
    required this.xMm,
    required this.yMm,
    this.rotationAngle = 0,
    this.isPhotoMode = false,
    this.hasCurvedCorners = false,
  });

  img.Image get rotatedImage {
    final angle = ((rotationAngle % 360) + 360) % 360;
    if (angle == 90 || angle == 180 || angle == 270) {
      return img.copyRotate(image, angle: angle);
    }
    return image;
  }

  void applyRotation() {
    final angle = ((rotationAngle % 360) + 360) % 360;
    if (angle == 0) return;
    image = rotatedImage;
    cachedBytes = Uint8List.fromList(img.encodeJpg(image, quality: 95));
    if (angle == 90 || angle == 270) {
      final t = widthMm; widthMm = heightMm; heightMm = t;
    }
    rotationAngle = 0;
  }

  void replaceImage(img.Image newImage) {
    image = newImage;
    cachedBytes = Uint8List.fromList(img.encodeJpg(newImage, quality: 95));
    rotationAngle = 0;
    if (newImage.width > 0) {
      heightMm = (newImage.height / newImage.width) * widthMm;
    }
  }
}

// ==============================================================
// MAIN SCANNER SCREEN
// ==============================================================

class MainScannerScreen extends StatefulWidget {
  const MainScannerScreen({super.key});
  @override
  State<MainScannerScreen> createState() => _MainScannerScreenState();
}

class _MainScannerScreenState extends State<MainScannerScreen> {
  final List<DocumentItem> _items = [];
  DocumentItem? _activeItem;
  final ImagePicker _picker = ImagePicker();
  String _activeTabMode = 'docs';
  bool _isScanning = false;

  static const double pageWidthMm = 210.0;
  static const double pageHeightMm = 297.0;
  static const double pageMarginMm = 10.0;

  Future<void> _openGoogleScanner() async {
    if (_isScanning) return;
    setState(() => _isScanning = true);
    try {
      final paths = await GoogleScanner.scan();
      if (!mounted) return;
      if (paths != null && paths.isNotEmpty) {
        int added = 0;
        for (final path in paths) {
          try {
            final file = File(path);
            if (!await file.exists()) continue;
            final bytes = await file.readAsBytes();
            final decoded = ImageUtils.decodeBytes(bytes);
            if (decoded == null) continue;
            _addDecodedImage(decoded, isPhoto: false, curved: false);
            added++;
          } catch (e) {
            debugPrint('Google image error: $e');
          }
        }
        _showMessage(added > 0 ? 'تم المسح بواسطة Google Scanner بنجاح' : 'لم يتم العثور على صور صالحة', error: added == 0);
      }
    } catch (e) {
      debugPrint('Google Scanner error: $e');
      if (mounted) _showMessage('تعذر تشغيل ماسح Google', error: true);
    } finally {
      if (mounted) setState(() => _isScanning = false);
    }
  }

  /// ❌ تم إلغاء التوجيه المباشر إلى أداة القص.
  /// الآن كل الصور تذهب مباشرة إلى workspace الرئيسي،
  /// والمستخدم يضغط على "قص وتوضيح سحري" إذا أراد القص.
  Future<void> _addManualImages(ImageSource source) async {
    try {
      if (source == ImageSource.camera) {
        final photo = await _picker.pickImage(source: ImageSource.camera, imageQuality: 95);
        if (photo == null) return;
        final bytes = await File(photo.path).readAsBytes();
        final decoded = ImageUtils.decodeBytes(bytes);
        if (decoded != null) {
          _addDecodedImage(decoded, isPhoto: _activeTabMode == 'photos', curved: false);
        }
        return;
      }
      final files = await _picker.pickMultiImage(imageQuality: 95);
      for (final file in files) {
        final bytes = await File(file.path).readAsBytes();
        final decoded = ImageUtils.decodeBytes(bytes);
        if (decoded != null) {
          _addDecodedImage(decoded, isPhoto: _activeTabMode == 'photos', curved: false);
        }
      }
    } catch (e) {
      if (mounted) _showMessage('خطأ في جلب الصور: $e', error: true);
    }
  }

  /// تم إلغاء هذه الدالة لأننا لم نعد نوجه إلى CropScreen مباشرة.
  /// الصور تذهب إلى workspace أولاً.
  // ignore: unused_element
  Future<void> _processImageWithCropScreen(img.Image decoded, {bool isPhoto = false}) async {
    if (!mounted) return;
    _addDecodedImage(decoded, isPhoto: isPhoto, curved: false);
  }

  void _addDecodedImage(img.Image decodedImage, {bool isPhoto = false, bool curved = false}) {
    if (!ImageUtils.isValid(decodedImage)) { _showMessage('الصورة غير صالحة', error: true); return; }
    final encodedBytes = ImageUtils.encodeJpg(decodedImage, quality: 95);
    if (!mounted) return;
    setState(() {
      final photoMode = isPhoto || _activeTabMode == 'photos';
      final width = photoMode ? 36.0 : 85.0;
      final ratio = decodedImage.height / decodedImage.width;
      final height = photoMode ? 45.0 : width * ratio;
      final offset = _items.length * 4.0;
      final item = DocumentItem(
        id: DateTime.now().microsecondsSinceEpoch.toString(),
        image: decodedImage, cachedBytes: encodedBytes,
        widthMm: width, heightMm: height,
        xMm: pageMarginMm + offset, yMm: pageMarginMm + offset,
        isPhotoMode: photoMode, hasCurvedCorners: curved,
      );
      _items.add(item);
      _activeItem = item;
    });
  }

  void _resizeActiveItem(double width, double height, {bool isPhoto = false, bool curved = false}) {
    if (_activeItem == null) return;
    setState(() {
      _activeItem!.widthMm = width; _activeItem!.heightMm = height;
      _activeItem!.isPhotoMode = isPhoto; _activeItem!.hasCurvedCorners = curved;
    });
  }

  void _rotateActiveItem() {
    if (_activeItem == null) return;
    setState(() { _activeItem!.rotationAngle = (_activeItem!.rotationAngle + 90) % 360; _activeItem!.applyRotation(); });
  }

  void _duplicateActiveItem() {
    final s = _activeItem; if (s == null) return;
    setState(() {
      final dup = DocumentItem(
        id: DateTime.now().microsecondsSinceEpoch.toString(),
        image: img.Image.from(s.image), cachedBytes: Uint8List.fromList(s.cachedBytes),
        widthMm: s.widthMm, heightMm: s.heightMm, xMm: s.xMm + 5, yMm: s.yMm + 5,
        rotationAngle: s.rotationAngle, isPhotoMode: s.isPhotoMode, hasCurvedCorners: s.hasCurvedCorners,
      );
      _items.add(dup); _activeItem = dup;
    });
  }

  void _autoAlignItems() {
    if (_items.isEmpty) return;
    setState(() {
      double cx = pageMarginMm, cy = pageMarginMm, rh = 0;
      for (final item in _items) {
        if (cx + item.widthMm > pageWidthMm - pageMarginMm) { cx = pageMarginMm; cy += rh + 5; rh = 0; }
        item.xMm = cx; item.yMm = cy;
        cx += item.widthMm + 5; rh = math.max(rh, item.heightMm);
      }
    });
  }

  Future<void> _manualCropActiveItem() async {
    final a = _activeItem; if (a == null) return;
    final result = await Navigator.push<img.Image>(
      context, MaterialPageRoute(builder: (_) => CropScreen(image: a.rotatedImage)),
    );
    if (result != null && mounted) setState(() => a.replaceImage(result));
  }

  void _deleteActiveItem() {
    if (_activeItem == null) return;
    setState(() { _items.remove(_activeItem); _activeItem = _items.isEmpty ? null : _items.last; });
  }

  Future<void> _exportAndPrint() async {
    if (_items.isEmpty) { _showMessage('لا توجد مستندات للطباعة', error: true); return; }
    try {
      final pdf = pw.Document();
      pdf.addPage(pw.Page(
        pageFormat: PdfPageFormat.a4, margin: pw.EdgeInsets.zero,
        build: (ctx) => pw.Stack(
          children: _items.map((item) {
            final bytes = ImageUtils.encodeJpg(item.rotatedImage, quality: 95);
            return pw.Positioned(
              left: item.xMm * PdfPageFormat.mm, top: item.yMm * PdfPageFormat.mm,
              child: pw.ClipRRect(
                horizontalRadius: item.hasCurvedCorners ? 3.5 * PdfPageFormat.mm : 0,
                verticalRadius: item.hasCurvedCorners ? 3.5 * PdfPageFormat.mm : 0,
                child: pw.SizedBox(
                  width: item.widthMm * PdfPageFormat.mm,
                  height: item.heightMm * PdfPageFormat.mm,
                  child: pw.Image(pw.MemoryImage(bytes), fit: pw.BoxFit.fill),
                ),
              ),
            );
          }).toList(),
        ),
      ));
      await Printing.layoutPdf(onLayout: (fmt) async => pdf.save());
    } catch (e) {
      if (mounted) _showMessage('خطأ أثناء تجهيز الطباعة: $e', error: true);
    }
  }

  void _showMessage(String msg, {bool error = false}) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)..hideCurrentSnackBar()..showSnackBar(
      SnackBar(content: Text(msg, textDirection: TextDirection.rtl),
               backgroundColor: error ? Colors.red.shade800 : null),
    );
  }

  // ============================================================
  // BUILD
  // ============================================================

  @override
  Widget build(BuildContext ctx) {
    return Scaffold(
      backgroundColor: const Color(0xFF0F172A),
      appBar: AppBar(
        title: const Text('مكتب علاء الحديدي - نظام الطباعة الاحترافي',
          style: TextStyle(fontSize: 13, fontWeight: FontWeight.bold)),
        backgroundColor: const Color(0xFF1E293B), foregroundColor: Colors.white, elevation: 0,
        actions: [
          IconButton(tooltip: 'طباعة', icon: const Icon(Icons.print_outlined), onPressed: _exportAndPrint),
          IconButton(
            tooltip: 'ماسح Google الذكي',
            icon: _isScanning
                ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                : const Icon(Icons.document_scanner),
            onPressed: _isScanning ? null : _openGoogleScanner,
          ),
          IconButton(tooltip: 'المعرض', icon: const Icon(Icons.photo_library_outlined),
            onPressed: () => _addManualImages(ImageSource.gallery)),
        ],
      ),
      body: Column(children: [
        // TOP TOOLBAR
        Container(height: 48, color: const Color(0xFF111827),
          child: ListView(scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
            children: [
              _toolBtn('المستمسكات', Icons.badge_outlined, _activeTabMode == 'docs',
                () => setState(() => _activeTabMode = 'docs')),
              _toolBtn('الصور الشخصية', Icons.person_outline, _activeTabMode == 'photos',
                () => setState(() => _activeTabMode = 'photos')),
              const VerticalDivider(color: Colors.white24, indent: 4, endIndent: 4),
              _actBtn('قص وتوضيح سحري', Icons.crop, _manualCropActiveItem, const Color(0xFF0EA5E9)),
              _actBtn('تنسيق تلقائي', Icons.grid_view, _autoAlignItems, const Color(0xFF10B981)),
              _actBtn('تدوير', Icons.rotate_right, _rotateActiveItem, const Color(0xFF64748B)),
              _actBtn('نسخ', Icons.copy_all, _duplicateActiveItem, const Color(0xFF8B5CF6)),
            ],
          ),
        ),
        // WORKSPACE
        Expanded(child: Row(children: [
          // LEFT PANEL
          Container(width: 110, color: const Color(0xFF1E293B),
            child: Column(children: [
              Container(padding: const EdgeInsets.symmetric(vertical: 8),
                width: double.infinity, color: const Color(0xFF0F172A),
                child: const Text('المقاسات القياسية', textAlign: TextAlign.center,
                  style: TextStyle(color: Colors.white70, fontSize: 10, fontWeight: FontWeight.bold)),
              ),
              Expanded(child: ListView(padding: const EdgeInsets.all(6),
                children: _activeTabMode == 'docs' ? [
                  _sizeBtn('بطاقة موحدة', '8.5 × 5.4 سم', () => _resizeActiveItem(85, 54, curved: true)),
                  _sizeBtn('بطاقة سكن', '8.8 × 5.8 سم', () => _resizeActiveItem(88, 58, curved: true)),
                  _sizeBtn('ورقة A4', '21 × 29.7 سم', () => _resizeActiveItem(210, 297), clr: const Color(0xFF0D9488)),
                ] : [
                  _sizeBtn('صورة معاملة', '3.6 × 4.5 سم', () => _resizeActiveItem(36, 45, isPhoto: true)),
                  _sizeBtn('صورة مصغرة', '2.5 × 3.4 سم', () => _resizeActiveItem(25, 34, isPhoto: true)),
                ],
              )),
              if (_activeItem != null) Padding(padding: const EdgeInsets.all(6),
                child: SizedBox(width: double.infinity,
                  child: ElevatedButton.icon(
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFFDC2626), foregroundColor: Colors.white, elevation: 0,
                      padding: const EdgeInsets.symmetric(vertical: 8),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(6)),
                    ),
                    onPressed: _deleteActiveItem,
                    icon: const Icon(Icons.delete_sweep_outlined, size: 16),
                    label: const Text('حذف العنصر', style: TextStyle(fontSize: 10, fontWeight: FontWeight.bold)),
                  ),
                ),
              ),
            ]),
          ),
          // A4 CANVAS
          Expanded(child: Container(color: const Color(0xFF090D16),
            child: Center(child: LayoutBuilder(builder: (ctx, c) {
              final sx = (c.maxWidth - 30) / pageWidthMm;
              final sy = (c.maxHeight - 30) / pageHeightMm;
              final s = math.min(sx, sy);
              return Container(
                width: pageWidthMm * s, height: pageHeightMm * s,
                decoration: BoxDecoration(color: Colors.white,
                  boxShadow: [BoxShadow(color: Colors.black.withAlpha(153), blurRadius: 16, offset: const Offset(0, 4))]),
                child: Stack(children: _items.map((item) {
                  final active = _activeItem?.id == item.id;
                  final radius = item.hasCurvedCorners ? BorderRadius.circular(3.5 * s) : BorderRadius.zero;
                  return Positioned(
                    left: item.xMm * s, top: item.yMm * s,
                    width: item.widthMm * s, height: item.heightMm * s,
                    child: GestureDetector(
                      onTap: () => setState(() => _activeItem = item),
                      onPanUpdate: (d) => setState(() { item.xMm += d.delta.dx / s; item.yMm += d.delta.dy / s; }),
                      child: Container(
                        decoration: BoxDecoration(borderRadius: radius,
                          border: Border.all(color: active ? const Color(0xFF0284C7) : Colors.transparent, width: active ? 2 : 1)),
                        child: ClipRRect(borderRadius: radius, child: Image.memory(item.cachedBytes, fit: BoxFit.fill)),
                      ),
                    ),
                  );
                }).toList()),
              );
            })),
          )),
        ])),
      ]),
    );
  }

  // ---------- helpers ----------

  Widget _toolBtn(String l, IconData i, bool sel, VoidCallback t) => Padding(
    padding: const EdgeInsets.symmetric(horizontal: 3),
    child: InkWell(onTap: t, borderRadius: BorderRadius.circular(6),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
        decoration: BoxDecoration(
          color: sel ? const Color(0xFF0284C7).withAlpha(51) : Colors.transparent,
          borderRadius: BorderRadius.circular(6),
          border: Border.all(color: sel ? const Color(0xFF0284C7) : Colors.white24),
        ),
        child: Row(children: [
          Icon(i, size: 14, color: sel ? const Color(0xFF38BDF8) : Colors.white70),
          const SizedBox(width: 5),
          Text(l, style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold,
            color: sel ? const Color(0xFF38BDF8) : Colors.white70)),
        ]),
      ),
    ),
  );

  Widget _actBtn(String l, IconData i, VoidCallback t, Color c) => Padding(
    padding: const EdgeInsets.symmetric(horizontal: 3),
    child: InkWell(onTap: t, borderRadius: BorderRadius.circular(6),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
        decoration: BoxDecoration(color: c.withAlpha(38), borderRadius: BorderRadius.circular(6),
          border: Border.all(color: c.withAlpha(102))),
        child: Row(children: [
          Icon(i, size: 14, color: c), const SizedBox(width: 4),
          Text(l, style: TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: c)),
        ]),
      ),
    ),
  );

  Widget _sizeBtn(String t, String sub, VoidCallback tap, {Color clr = const Color(0xFF0284C7)}) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 3),
    child: ElevatedButton(
      style: ElevatedButton.styleFrom(
        padding: const EdgeInsets.symmetric(vertical: 6, horizontal: 4),
        backgroundColor: clr.withAlpha(30), foregroundColor: clr,
        side: BorderSide(color: clr.withAlpha(76)),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(6)),
        elevation: 0,
      ),
      onPressed: tap,
      child: Column(children: [
        Text(t, style: TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: clr)),
        const SizedBox(height: 2),
        Text(sub, style: TextStyle(fontSize: 8, color: clr.withAlpha(204))),
      ]),
    ),
  );
}

// ==============================================================
// CROP BOX PAINTER
// ==============================================================

class CropBoxPainter extends CustomPainter {
  final Offset p1, p2, p3, p4;
  CropBoxPainter(this.p1, this.p2, this.p3, this.p4);

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = const Color(0xFF0284C7).withAlpha(220)
      ..strokeWidth = 2.5
      ..style = PaintingStyle.stroke
      ..strokeJoin = StrokeJoin.round;
    final path = Path()..moveTo(p1.dx, p1.dy)..lineTo(p2.dx, p2.dy)
      ..lineTo(p3.dx, p3.dy)..lineTo(p4.dx, p4.dy)..close();
    canvas.drawPath(path, paint);
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => true;
}

// ==============================================================
// CROP SCREEN
// ==============================================================

class CropScreen extends StatefulWidget {
  final img.Image image;
  const CropScreen({super.key, required this.image});
  @override
  State<CropScreen> createState() => _CropScreenState();
}

class _CropScreenState extends State<CropScreen> {
  double _x1 = 0.05, _y1 = 0.05, _x2 = 0.95, _y2 = 0.05;
  double _x3 = 0.95, _y3 = 0.95, _x4 = 0.05, _y4 = 0.95;
  EnhanceMode _filter = EnhanceMode.none;
  double _filterIntensity = 0.8;
  late Uint8List _displayBytes;
  Offset? _dragFocalPoint;
  bool _isDetecting = false;

  @override
  void initState() { super.initState(); _updateDisplayBytes(); }

  void _updateDisplayBytes() {
    final p = ImageEnhancer.apply(widget.image, _filter, _filterIntensity);
    _displayBytes = ImageUtils.encodeJpg(p, quality: 92);
  }

  void _selectAll() {
    setState(() { _x1=0;_y1=0;_x2=1;_y2=0;_x3=1;_y3=1;_x4=0;_y4=1; });
  }

  Future<void> _runAutoDetect() async {
    if (_isDetecting) return;
    setState(() => _isDetecting = true);
    try {
      final bytes = ImageUtils.encodeJpg(widget.image, quality: 90);
      final flat = await compute(detectDocumentCornersIsolate, bytes);
      if (!mounted) return;
      if (flat != null && flat.length == 8) {
        final w = widget.image.width.toDouble();
        final h = widget.image.height.toDouble();
        setState(() {
          _x1=(flat[0]/w).clamp(0.0,1.0); _y1=(flat[1]/h).clamp(0.0,1.0);
          _x2=(flat[2]/w).clamp(0.0,1.0); _y2=(flat[3]/h).clamp(0.0,1.0);
          _x3=(flat[4]/w).clamp(0.0,1.0); _y3=(flat[5]/h).clamp(0.0,1.0);
          _x4=(flat[6]/w).clamp(0.0,1.0); _y4=(flat[7]/h).clamp(0.0,1.0);
        });
      } else {
        _snack('تعذر اكتشاف حواف المستند تلقائياً، يمكنك تحديدها يدوياً');
      }
    } catch (e) {
      debugPrint('Auto detect error: $e');
      _snack('تعذر تشغيل الكشف التلقائي');
    } finally {
      if (mounted) setState(() => _isDetecting = false);
    }
  }

  void _snack(String msg) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)..hideCurrentSnackBar()..showSnackBar(
      SnackBar(content: Text(msg, textDirection: TextDirection.rtl)));
  }

  void _applyCrop() {
    var c = ManualCrop.cropPerspective(widget.image, _x1,_y1,_x2,_y2,_x3,_y3,_x4,_y4);
    c = ImageEnhancer.apply(c, _filter, _filterIntensity);
    Navigator.pop(context, c);
  }

  @override
  Widget build(BuildContext ctx) {
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: const Color(0xFF1E293B),
        leading: IconButton(icon: const Icon(Icons.close, color: Colors.white),
          onPressed: () => Navigator.pop(context)),
        title: SingleChildScrollView(scrollDirection: Axis.horizontal,
          child: Row(children: [
            _chip('أصلي', _filter == EnhanceMode.none, () { setState(() { _filter = EnhanceMode.none; _updateDisplayBytes(); }); }),
            const SizedBox(width: 4),
            _chip('تحسين سحري ✨', _filter == EnhanceMode.magic, () { setState(() { _filter = EnhanceMode.magic; _updateDisplayBytes(); }); }),
            const SizedBox(width: 4),
            _chip('أبيض وأسود رسمي', _filter == EnhanceMode.bw, () { setState(() { _filter = EnhanceMode.bw; _updateDisplayBytes(); }); }),
          ]),
        ),
        actions: [
          IconButton(tooltip: 'تحديد الكل', icon: const Icon(Icons.auto_awesome_mosaic, color: Colors.amber), onPressed: _selectAll),
          IconButton(tooltip: 'تم والتصدير', icon: const Icon(Icons.check, color: Colors.greenAccent), onPressed: _applyCrop),
        ],
      ),
      body: Column(children: [
        Expanded(child: LayoutBuilder(builder: (ctx, c) {
          final cw = c.maxWidth, ch = c.maxHeight;
          final iw = widget.image.width.toDouble(), ih = widget.image.height.toDouble();
          final scale = math.min(cw / iw, ch / ih);
          final imgW = iw * scale, imgH = ih * scale;
          final imgL = (cw - imgW) / 2, imgT = (ch - imgH) / 2;

          final p1 = Offset(imgL + _x1 * imgW, imgT + _y1 * imgH);
          final p2 = Offset(imgL + _x2 * imgW, imgT + _y2 * imgH);
          final p3 = Offset(imgL + _x3 * imgW, imgT + _y3 * imgH);
          final p4 = Offset(imgL + _x4 * imgW, imgT + _y4 * imgH);

          return Stack(children: [
            Positioned(left: imgL, top: imgT, width: imgW, height: imgH,
              child: Image.memory(_displayBytes, fit: BoxFit.fill)),
            Positioned.fill(child: CustomPaint(painter: CropBoxPainter(p1, p2, p3, p4))),
            _corner(_x1, _y1, imgL, imgT, imgW, imgH, (nx, ny) => setState(() { _x1=nx; _y1=ny; })),
            _corner(_x2, _y2, imgL, imgT, imgW, imgH, (nx, ny) => setState(() { _x2=nx; _y2=ny; })),
            _corner(_x3, _y3, imgL, imgT, imgW, imgH, (nx, ny) => setState(() { _x3=nx; _y3=ny; })),
            _corner(_x4, _y4, imgL, imgT, imgW, imgH, (nx, ny) => setState(() { _x4=nx; _y4=ny; })),
            _edgeMid(_x1, _y1, _x2, _y2, imgL, imgT, imgW, imgH, (dx, dy) => setState(() {
              _x1=(_x1+dx).clamp(0.0,1.0); _y1=(_y1+dy).clamp(0.0,1.0);
              _x2=(_x2+dx).clamp(0.0,1.0); _y2=(_y2+dy).clamp(0.0,1.0);
            })),
            _edgeMid(_x2, _y2, _x3, _y3, imgL, imgT, imgW, imgH, (dx, dy) => setState(() {
              _x2=(_x2+dx).clamp(0.0,1.0); _y2=(_y2+dy).clamp(0.0,1.0);
              _x3=(_x3+dx).clamp(0.0,1.0); _y3=(_y3+dy).clamp(0.0,1.0);
            })),
            _edgeMid(_x3, _y3, _x4, _y4, imgL, imgT, imgW, imgH, (dx, dy) => setState(() {
              _x3=(_x3+dx).clamp(0.0,1.0); _y3=(_y3+dy).clamp(0.0,1.0);
              _x4=(_x4+dx).clamp(0.0,1.0); _y4=(_y4+dy).clamp(0.0,1.0);
            })),
            _edgeMid(_x4, _y4, _x1, _y1, imgL, imgT, imgW, imgH, (dx, dy) => setState(() {
              _x4=(_x4+dx).clamp(0.0,1.0); _y4=(_y4+dy).clamp(0.0,1.0);
              _x1=(_x1+dx).clamp(0.0,1.0); _y1=(_y1+dy).clamp(0.0,1.0);
            })),
            _magnifier(cw, ch, imgL, imgT, imgW, imgH),
          ]);
        })),
        if (_filter != EnhanceMode.none)
          Container(color: const Color(0xFF1E293B),
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            child: Row(children: [
              const Icon(Icons.contrast, color: Colors.white70, size: 18),
              const SizedBox(width: 8),
              Expanded(child: Slider(value: _filterIntensity, min: 0, max: 2, activeColor: const Color(0xFF38BDF8),
                inactiveColor: Colors.white24, onChanged: (v) => setState(() { _filterIntensity = v; _updateDisplayBytes(); }))),
              Text('${(_filterIntensity * 50).toInt()}%', style: const TextStyle(color: Colors.white, fontSize: 12)),
            ])),
        Container(color: const Color(0xFF1E293B),
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
          child: Row(mainAxisAlignment: MainAxisAlignment.spaceEvenly, children: [
            _bottomBtn('الكل', Icons.crop_free, _selectAll),
            _bottomBtn('القص التلقائي', Icons.auto_fix_high, _isDetecting ? null : _runAutoDetect, isLoading: _isDetecting),
          ])),
      ]),
    );
  }

  // ---------- corner dot ----------
  Widget _corner(double rx, double ry, double il, double it, double iw, double ih, void Function(double,double) onMove) {
    return Positioned(left: il + rx * iw - 18, top: it + ry * ih - 18,
      child: GestureDetector(
        onPanStart: (_) => setState(() => _dragFocalPoint = Offset(il + rx * iw, it + ry * ih)),
        onPanUpdate: (d) {
          final cx = il + rx * iw, cy = it + ry * ih;
          final nx = ((cx + d.delta.dx - il) / iw).clamp(0.0, 1.0);
          final ny = ((cy + d.delta.dy - it) / ih).clamp(0.0, 1.0);
          final cur = _dragFocalPoint ?? Offset(cx, cy);
          setState(() => _dragFocalPoint = cur + d.delta);
          onMove(nx, ny);
        },
        onPanEnd: (_) => setState(() => _dragFocalPoint = null),
        child: Container(width: 36, height: 36,
          decoration: BoxDecoration(
            color: const Color(0xFF0284C7).withAlpha(230), shape: BoxShape.circle,
            border: Border.all(color: Colors.white, width: 2),
            boxShadow: const [BoxShadow(color: Colors.black45, blurRadius: 4)],
          ),
          child: const Icon(Icons.control_camera, size: 16, color: Colors.white),
        ),
      ),
    );
  }

  // ---------- edge midpoint handle ----------
  Widget _edgeMid(double ax, double ay, double bx, double by, double il, double it, double iw, double ih,
    void Function(double, double) onDelta) {
    final mx = (ax + bx) / 2, my = (ay + by) / 2;
    final cx = il + mx * iw, cy = it + my * ih;
    final isH = (bx - ax).abs() >= (by - ay).abs();
    return Positioned(left: cx - 14, top: cy - 14,
      child: GestureDetector(
        onPanStart: (_) => setState(() => _dragFocalPoint = Offset(cx, cy)),
        onPanUpdate: (d) {
          final cur = _dragFocalPoint ?? Offset(cx, cy);
          setState(() => _dragFocalPoint = cur + d.delta);
          onDelta(d.delta.dx / iw, d.delta.dy / ih);
        },
        onPanEnd: (_) => setState(() => _dragFocalPoint = null),
        child: Container(width: 28, height: 28, alignment: Alignment.center,
          child: Container(width: isH ? 26 : 10, height: isH ? 10 : 26,
            decoration: BoxDecoration(
              color: Colors.white, borderRadius: BorderRadius.circular(5),
              border: Border.all(color: const Color(0xFF0284C7), width: 1.5),
              boxShadow: const [BoxShadow(color: Colors.black45, blurRadius: 3)],
            ),
          ),
        ),
      ),
    );
  }

  // ---------- magnifier ----------
  Widget _magnifier(double cw, double ch, double il, double it, double iw, double ih) {
    final f = _dragFocalPoint;
    if (f == null) return const SizedBox.shrink();
    const double sz = 110, zoom = 2.5;
    final lx = f.dx - il, ly = f.dy - it;
    double left = f.dx - sz / 2; left = left.clamp(0.0, math.max(0.0, cw - sz));
    double top = f.dy - sz - 40;
    if (top < 0) top = math.min(f.dy + 40, math.max(0.0, ch - sz));
    return Positioned(left: left, top: top,
      child: IgnorePointer(child: Container(width: sz, height: sz,
        decoration: BoxDecoration(shape: BoxShape.circle,
          border: Border.all(color: Colors.white, width: 3),
          boxShadow: const [BoxShadow(color: Colors.black54, blurRadius: 8)]),
        child: ClipOval(child: Stack(children: [
          Positioned(left: sz/2 - lx * zoom, top: sz/2 - ly * zoom,
            width: iw * zoom, height: ih * zoom,
            child: Image.memory(_displayBytes, fit: BoxFit.fill)),
          Center(child: Container(width: 2, height: 16, color: const Color(0xFF0284C7))),
          Center(child: Container(width: 16, height: 2, color: const Color(0xFF0284C7))),
        ])),
      )),
    );
  }

  // ---------- filter chip ----------
  Widget _chip(String l, bool sel, VoidCallback t) => GestureDetector(onTap: t,
    child: Container(padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(color: sel ? const Color(0xFF0284C7) : Colors.white12, borderRadius: BorderRadius.circular(6)),
      child: Text(l, style: TextStyle(color: sel ? Colors.white : Colors.white70, fontSize: 10, fontWeight: FontWeight.bold)),
    ));

  // ---------- bottom button ----------
  Widget _bottomBtn(String l, IconData i, VoidCallback? tap, {bool isLoading = false}) => InkWell(
    onTap: tap, borderRadius: BorderRadius.circular(8),
    child: Padding(padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
      child: Column(mainAxisSize: MainAxisSize.min, children: [
        isLoading
            ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2, color: Color(0xFF38BDF8)))
            : Icon(i, color: const Color(0xFF38BDF8), size: 22),
        const SizedBox(height: 4),
        Text(l, style: const TextStyle(color: Colors.white70, fontSize: 11, fontWeight: FontWeight.bold)),
      ]),
    ),
  );
}
