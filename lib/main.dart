import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:google_mlkit_document_scanner/google_mlkit_document_scanner.dart';
import 'package:image_picker/image_picker.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';
import 'package:opencv_dart/opencv_dart.dart' as cv;

/// ===============================================================
/// 1. CROP ENGINE CLASSES (مدمجة هنا لتجنب أخطاء الملفات)
/// ===============================================================

class ImageUtils {
  static cv.Mat? decodeBytes(Uint8List bytes) {
    try {
      final mat = cv.imdecode(bytes, cv.IMREAD_COLOR);
      if (mat.isEmpty) return null;
      return mat;
    } catch (e) {
      debugPrint('MOSUL SCANNER OpenCV decode error: $e');
      return null;
    }
  }

  static Uint8List encodeJpg(cv.Mat image, {int quality = 95}) {
    try {
      if (image.isEmpty) return Uint8List(0);
      // تم الإصلاح 1: استخدام cv.VecI32.fromList
      final result = cv.imencode('.jpg', image, params: cv.VecI32.fromList([cv.IMWRITE_JPEG_QUALITY, quality]));
      return result.$2; 
    } catch (e) {
      debugPrint('MOSUL SCANNER OpenCV encode error: $e');
      return Uint8List(0);
    }
  }
}

enum EnhanceMode { none, soft, bw }

class ImageEnhancer {
  static cv.Mat apply(cv.Mat source, EnhanceMode mode) {
    if (source.isEmpty) return source;

    switch (mode) {
      case EnhanceMode.none:
        return source.clone();

      case EnhanceMode.soft:
        try {
          // تم الإصلاح 2: convertTo ترجع القيمة مباشرة
          return source.convertTo(-1, alpha: 1.1, beta: 10);
        } catch (e) {
          return source;
        }

      case EnhanceMode.bw:
        try {
          final gray = cv.cvtColor(source, cv.COLOR_BGR2GRAY);
          // تم الإصلاح 3
          return gray.convertTo(-1, alpha: 1.5, beta: 20);
        } catch (e) {
          return source;
        }
    }
  }
}

class ManualCrop {
  static cv.Mat? cropPerspective(
    cv.Mat source,
    double x1, double y1, 
    double x2, double y2, 
    double x3, double y3, 
    double x4, double y4, 
  ) {
    if (source.isEmpty) return null;

    final w = source.cols.toDouble();
    final h = source.rows.toDouble();

    final srcPts = [
      cv.Point2f(x1 * w, y1 * h),
      cv.Point2f(x2 * w, y2 * h),
      cv.Point2f(x3 * w, y3 * h),
      cv.Point2f(x4 * w, y4 * h),
    ];

    final dstPts = [
      cv.Point2f(0, 0),
      cv.Point2f(w, 0),
      cv.Point2f(w, h),
      cv.Point2f(0, h),
    ];

    try {
      final matrix = cv.getPerspectiveTransform2f(srcPts.cvd, dstPts.cvd);
      // تم الإصلاح 4: استخدام Record (cols, rows) بدلاً من cv.Size
      final result = cv.warpPerspective(source, matrix, (source.cols, source.rows));
      return result;
    } catch (e) {
      debugPrint('MOSUL SCANNER Perspective Crop error: $e');
      return source.clone();
    }
  }
}

class SmartCrop {
  static List<double>? detectCorners(cv.Mat source) {
    if (source.isEmpty) return null;
    return [
      0.05, 0.05, 
      0.95, 0.05, 
      0.95, 0.95, 
      0.05, 0.95, 
    ];
  }
}

/// ===============================================================
/// 2. MOSUL SCANNER - PROFESSIONAL EDITION
/// ===============================================================

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
      theme: ThemeData(
        useMaterial3: true,
        colorSchemeSeed: Colors.blueGrey,
      ),
      home: const MainScannerScreen(),
    );
  }
}

class DocumentItem {
  final String id;
  Uint8List cachedBytes;
  double widthMm;
  double heightMm;
  double xMm;
  double yMm;
  int rotationAngle;
  bool isPhotoMode;
  bool hasCurvedCorners;

  DocumentItem({
    required this.id,
    required this.cachedBytes,
    required this.widthMm,
    required this.heightMm,
    required this.xMm,
    required this.yMm,
    this.rotationAngle = 0,
    this.isPhotoMode = false,
    this.hasCurvedCorners = false,
  });

  void applyRotation() {
    final angle = ((rotationAngle % 360) + 360) % 360;
    if (angle == 0) return;

    final mat = ImageUtils.decodeBytes(cachedBytes);
    if (mat != null) {
      int code = -1;
      if (angle == 90) code = cv.ROTATE_90_CLOCKWISE;
      else if (angle == 180) code = cv.ROTATE_180;
      else if (angle == 270) code = cv.ROTATE_90_COUNTERCLOCKWISE;

      if (code != -1) {
        final rotated = cv.rotate(mat, code);
        cachedBytes = ImageUtils.encodeJpg(rotated, quality: 95);
      }
    }

    if (angle == 90 || angle == 270) {
      final temp = widthMm;
      widthMm = heightMm;
      heightMm = temp;
    }
    rotationAngle = 0;
  }

  void replaceImageBytes(Uint8List newBytes) {
    cachedBytes = newBytes;
    rotationAngle = 0;
    final mat = ImageUtils.decodeBytes(newBytes);
    if (mat != null && mat.cols > 0) {
      heightMm = (mat.rows / mat.cols) * widthMm;
    }
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
          final file = File(path);
          if (!await file.exists()) continue;
          final bytes = await file.readAsBytes();
          _addRawBytes(bytes, isPhoto: false, curved: false);
          added++;
        }
        if (added > 0) {
          _showMessage('تم المسح بواسطة Google Scanner بنجاح');
        } else {
          _showMessage('لم يتم العثور على صور صالحة', error: true);
        }
      }
    } catch (e) {
      if (mounted) _showMessage('تعذر تشغيل ماسح Google', error: true);
    } finally {
      if (mounted) setState(() => _isScanning = false);
    }
  }

  Future<void> _addManualImages(ImageSource source) async {
    try {
      if (source == ImageSource.camera) {
        final photo = await _picker.pickImage(source: ImageSource.camera, imageQuality: 95);
        if (photo == null) return;
        final bytes = await File(photo.path).readAsBytes();
        await _processImageWithCropScreen(bytes, isPhoto: _activeTabMode == 'photos');
        return;
      }

      final files = await _picker.pickMultiImage(imageQuality: 95);
      for (final file in files) {
        final bytes = await File(file.path).readAsBytes();
        await _processImageWithCropScreen(bytes, isPhoto: _activeTabMode == 'photos');
      }
    } catch (e) {
      if (mounted) _showMessage('خطأ في جلب الصور', error: true);
    }
  }

  Future<void> _processImageWithCropScreen(Uint8List bytes, {bool isPhoto = false}) async {
    if (!mounted) return;

    if (isPhoto) {
      _addRawBytes(bytes, isPhoto: true, curved: false);
      return;
    }

    final resultBytes = await Navigator.push<Uint8List>(
      context,
      MaterialPageRoute(builder: (_) => CropScreen(imageBytes: bytes)),
    );

    if (resultBytes != null && resultBytes.isNotEmpty && mounted) {
      _addRawBytes(resultBytes, isPhoto: false, curved: true);
    }
  }

  void _addRawBytes(Uint8List bytes, {bool isPhoto = false, bool curved = false}) {
    final mat = ImageUtils.decodeBytes(bytes);
    if (mat == null) {
      _showMessage('الصورة غير صالحة', error: true);
      return;
    }

    final imgWidth = mat.cols.toDouble();
    final imgHeight = mat.rows.toDouble();
    final ratio = imgHeight / imgWidth;

    if (!mounted) return;

    setState(() {
      final photoMode = isPhoto || _activeTabMode == 'photos';
      final width = photoMode ? 36.0 : 85.0;
      final height = photoMode ? 45.0 : width * ratio;
      final offset = _items.length * 4.0;

      final item = DocumentItem(
        id: DateTime.now().microsecondsSinceEpoch.toString(),
        cachedBytes: bytes,
        widthMm: width,
        heightMm: height,
        xMm: pageMarginMm + offset,
        yMm: pageMarginMm + offset,
        isPhotoMode: photoMode,
        hasCurvedCorners: curved,
      );

      _items.add(item);
      _activeItem = item;
    });
  }

  void _resizeActiveItem(double width, double height, {bool isPhoto = false, bool curved = false}) {
    final active = _activeItem;
    if (active == null) return;

    setState(() {
      active.widthMm = width;
      active.heightMm = height;
      active.isPhotoMode = isPhoto;
      active.hasCurvedCorners = curved;
    });
  }

  void _rotateActiveItem() {
    final active = _activeItem;
    if (active == null) return;

    setState(() {
      active.rotationAngle = (active.rotationAngle + 90) % 360;
      active.applyRotation();
    });
  }

  void _duplicateActiveItem() {
    final source = _activeItem;
    if (source == null) return;

    setState(() {
      final duplicate = DocumentItem(
        id: DateTime.now().microsecondsSinceEpoch.toString(),
        cachedBytes: Uint8List.fromList(source.cachedBytes),
        widthMm: source.widthMm,
        heightMm: source.heightMm,
        xMm: source.xMm + 5,
        yMm: source.yMm + 5,
        rotationAngle: source.rotationAngle,
        isPhotoMode: source.isPhotoMode,
        hasCurvedCorners: source.hasCurvedCorners,
      );
      _items.add(duplicate);
      _activeItem = duplicate;
    });
  }

  void _autoAlignItems() {
    if (_items.isEmpty) return;
    setState(() {
      double currentX = pageMarginMm;
      double currentY = pageMarginMm;
      double rowHeight = 0;

      for (final item in _items) {
        if (currentX + item.widthMm > pageWidthMm - pageMarginMm) {
          currentX = pageMarginMm;
          currentY += rowHeight + 5;
          rowHeight = 0;
        }
        item.xMm = currentX;
        item.yMm = currentY;
        currentX += item.widthMm + 5;
        rowHeight = math.max(rowHeight, item.heightMm);
      }
    });
  }

  Future<void> _manualCropActiveItem() async {
    final active = _activeItem;
    if (active == null) return;

    final resultBytes = await Navigator.push<Uint8List>(
      context,
      MaterialPageRoute(builder: (_) => CropScreen(imageBytes: active.cachedBytes)),
    );

    if (resultBytes != null && resultBytes.isNotEmpty && mounted) {
      setState(() {
        active.replaceImageBytes(resultBytes);
      });
    }
  }

  void _deleteActiveItem() {
    final active = _activeItem;
    if (active == null) return;

    setState(() {
      _items.remove(active);
      _activeItem = _items.isEmpty ? null : _items.last;
    });
  }

  Future<void> _exportAndPrint() async {
    if (_items.isEmpty) {
      _showMessage('لا توجد مستندات للطباعة', error: true);
      return;
    }

    try {
      final pdf = pw.Document();
      pdf.addPage(
        pw.Page(
          pageFormat: PdfPageFormat.a4,
          margin: pw.EdgeInsets.zero,
          build: (context) {
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
    } catch (e) {
      if (mounted) _showMessage('خطأ أثناء تجهيز الطباعة: $e', error: true);
    }
  }

  void _showMessage(String message, {bool error = false}) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(
          content: Text(message, textDirection: TextDirection.rtl),
          backgroundColor: error ? Colors.red.shade800 : null,
        ),
      );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF0F172A),
      appBar: AppBar(
        title: const Text(
          'مكتب علاء الحديدي - نظام الطباعة الاحترافي',
          style: TextStyle(fontSize: 13, fontWeight: FontWeight.bold),
        ),
        backgroundColor: const Color(0xFF1E293B),
        foregroundColor: Colors.white,
        actions: [
          IconButton(
            tooltip: 'طباعة المستندات',
            icon: const Icon(Icons.print_outlined),
            onPressed: _exportAndPrint,
          ),
          IconButton(
            tooltip: 'ماسح Google الذكي',
            icon: _isScanning
                ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                : const Icon(Icons.document_scanner),
            onPressed: _isScanning ? null : _openGoogleScanner,
          ),
          IconButton(
            tooltip: 'استيراد من المعرض',
            icon: const Icon(Icons.photo_library_outlined),
            onPressed: () => _addManualImages(ImageSource.gallery),
          ),
        ],
      ),
      body: Column(
        children: [
          Container(
            height: 48,
            color: const Color(0xFF111827),
            child: ListView(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
              children: [
                _buildToolBtn('المستمسكات', Icons.badge_outlined, _activeTabMode == 'docs', () => setState(() => _activeTabMode = 'docs')),
                _buildToolBtn('الصور الشخصية', Icons.person_outline, _activeTabMode == 'photos', () => setState(() => _activeTabMode = 'photos')),
                const VerticalDivider(color: Colors.white24, indent: 4, endIndent: 4),
                _buildActionBtn('قص وتوضيح سحري', Icons.crop, _manualCropActiveItem, const Color(0xFF0EA5E9)),
                _buildActionBtn('تنسيق تلقائي', Icons.grid_view, _autoAlignItems, const Color(0xFF10B981)),
                _buildActionBtn('تدوير', Icons.rotate_right, _rotateActiveItem, const Color(0xFF64748B)),
                _buildActionBtn('نسخ', Icons.copy_all, _duplicateActiveItem, const Color(0xFF8B5CF6)),
              ],
            ),
          ),
          Expanded(
            child: Row(
              children: [
                Container(
                  width: 110,
                  color: const Color(0xFF1E293B),
                  child: Column(
                    children: [
                      Container(
                        padding: const EdgeInsets.symmetric(vertical: 8),
                        width: double.infinity,
                        color: const Color(0xFF0F172A),
                        child: const Text(
                          'المقاسات القياسية',
                          textAlign: TextAlign.center,
                          style: TextStyle(color: Colors.white70, fontSize: 10, fontWeight: FontWeight.bold),
                        ),
                      ),
                      Expanded(
                        child: ListView(
                          padding: const EdgeInsets.all(6),
                          children: _activeTabMode == 'docs'
                              ? [
                                  _buildSizeBtn('بطاقة موحدة', '8.5 × 5.4 سم', () => _resizeActiveItem(85, 54, curved: true)),
                                  _buildSizeBtn('بطاقة سكن', '8.8 × 5.8 سم', () => _resizeActiveItem(88, 58, curved: true)),
                                  _buildSizeBtn('ورقة A4', '21 × 29.7 سم', () => _resizeActiveItem(210, 297, curved: false), clr: const Color(0xFF0D9488)),
                                ]
                              : [
                                  _buildSizeBtn('صورة معاملة', '3.6 × 4.5 سم', () => _resizeActiveItem(36, 45, isPhoto: true)),
                                  _buildSizeBtn('صورة مصغرة', '2.5 × 3.4 سم', () => _resizeActiveItem(25, 34, isPhoto: true)),
                                ],
                        ),
                      ),
                      if (_activeItem != null)
                        Padding(
                          padding: const EdgeInsets.all(6),
                          child: SizedBox(
                            width: double.infinity,
                            child: ElevatedButton.icon(
                              style: ElevatedButton.styleFrom(
                                backgroundColor: const Color(0xFFDC2626),
                                foregroundColor: Colors.white,
                                elevation: 0,
                                padding: const EdgeInsets.symmetric(vertical: 8),
                                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(6)),
                              ),
                              onPressed: _deleteActiveItem,
                              icon: const Icon(Icons.delete_sweep_outlined, size: 16),
                              label: const Text('حذف العنصر', style: TextStyle(fontSize: 10, fontWeight: FontWeight.bold)),
                            ),
                          ),
                        ),
                    ],
                  ),
                ),
                Expanded(
                  child: Container(
                    color: const Color(0xFF090D16),
                    child: Center(
                      child: LayoutBuilder(
                        builder: (context, constraints) {
                          final scaleX = (constraints.maxWidth - 30) / pageWidthMm;
                          final scaleY = (constraints.maxHeight - 30) / pageHeightMm;
                          final scale = math.min(scaleX, scaleY);

                          return Container(
                            width: pageWidthMm * scale,
                            height: pageHeightMm * scale,
                            decoration: BoxDecoration(
                              color: Colors.white,
                              boxShadow: [BoxShadow(color: Colors.black.withAlpha(153), blurRadius: 16, offset: const Offset(0, 4))],
                            ),
                            child: Stack(
                              children: _items.map((item) {
                                final active = _activeItem?.id == item.id;
                                final radius = item.hasCurvedCorners ? BorderRadius.circular(3.5 * scale) : BorderRadius.zero;
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
                                        borderRadius: radius,
                                        border: Border.all(color: active ? const Color(0xFF0284C7) : Colors.transparent, width: active ? 2 : 1),
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
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildToolBtn(String label, IconData icon, bool selected, VoidCallback onTap) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 3),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(6),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
          decoration: BoxDecoration(
            color: selected ? const Color(0xFF0284C7).withAlpha(51) : Colors.transparent,
            borderRadius: BorderRadius.circular(6),
            border: Border.all(color: selected ? const Color(0xFF0284C7) : Colors.white24),
          ),
          child: Row(
            children: [
              Icon(icon, size: 14, color: selected ? const Color(0xFF38BDF8) : Colors.white70),
              const SizedBox(width: 5),
              Text(label, style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: selected ? const Color(0xFF38BDF8) : Colors.white70)),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildActionBtn(String label, IconData icon, VoidCallback onTap, Color color) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 3),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(6),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
          decoration: BoxDecoration(
            color: color.withAlpha(38),
            borderRadius: BorderRadius.circular(6),
            border: Border.all(color: color.withAlpha(102)),
          ),
          child: Row(
            children: [
              Icon(icon, size: 14, color: color),
              const SizedBox(width: 4),
              Text(label, style: TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: color)),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildSizeBtn(String title, String subtitle, VoidCallback onTap, {Color clr = const Color(0xFF0284C7)}) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: ElevatedButton(
        style: ElevatedButton.styleFrom(
          padding: const EdgeInsets.symmetric(vertical: 6, horizontal: 4),
          backgroundColor: clr.withAlpha(30),
          foregroundColor: clr,
          side: BorderSide(color: clr.withAlpha(76)),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(6)),
          elevation: 0,
        ),
        onPressed: onTap,
        child: Column(
          children: [
            Text(title, style: TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: clr)),
            const SizedBox(height: 2),
            Text(subtitle, style: TextStyle(fontSize: 8, color: clr.withAlpha(204))),
          ],
        ),
      ),
    );
  }
}

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
    final path = Path()..moveTo(p1.dx, p1.dy)..lineTo(p2.dx, p2.dy)..lineTo(p3.dx, p3.dy)..lineTo(p4.dx, p4.dy)..close();
    canvas.drawPath(path, paint);
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => true;
}

class CropScreen extends StatefulWidget {
  final Uint8List imageBytes;

  const CropScreen({super.key, required this.imageBytes});

  @override
  State<CropScreen> createState() => _CropScreenState();
}

class _CropScreenState extends State<CropScreen> {
  double _x1 = 0.05, _y1 = 0.05;
  double _x2 = 0.95, _y2 = 0.05;
  double _x3 = 0.95, _y3 = 0.95;
  double _x4 = 0.05, _y4 = 0.95;

  EnhanceMode _filter = EnhanceMode.none;
  late Uint8List _displayBytes;
  int _imgWidth = 100;
  int _imgHeight = 100;
  Offset? _dragFocalPoint;
  bool _isDetecting = false;

  @override
  void initState() {
    super.initState();
    _displayBytes = widget.imageBytes;
    _initializeDimensions();
  }

  void _initializeDimensions() {
    final mat = ImageUtils.decodeBytes(widget.imageBytes);
    if (mat != null) {
      setState(() {
        _imgWidth = mat.cols;
        _imgHeight = mat.rows;
      });
      _updateDisplayBytes(mat);
    }
  }

  void _updateDisplayBytes([cv.Mat? sourceMat]) {
    final mat = sourceMat ?? ImageUtils.decodeBytes(widget.imageBytes);
    if (mat != null) {
      final processed = ImageEnhancer.apply(mat, _filter);
      setState(() {
        _displayBytes = ImageUtils.encodeJpg(processed, quality: 92);
      });
    }
  }

  void _selectAll() {
    setState(() {
      _x1 = 0.0; _y1 = 0.0;
      _x2 = 1.0; _y2 = 0.0;
      _x3 = 1.0; _y3 = 1.0;
      _x4 = 0.0; _y4 = 1.0;
    });
  }

  Future<void> _runAutoDetect() async {
    if (_isDetecting) return;
    setState(() => _isDetecting = true);

    try {
      final mat = ImageUtils.decodeBytes(widget.imageBytes);
      if (mat != null) {
        final corners = SmartCrop.detectCorners(mat);
        if (corners != null && corners.length == 8) {
          setState(() {
            _x1 = corners[0]; _y1 = corners[1];
            _x2 = corners[2]; _y2 = corners[3];
            _x3 = corners[4]; _y3 = corners[5];
            _x4 = corners[6]; _y4 = corners[7];
          });
        }
      }
    } catch (e) {
      _showSnack('تعذر تشغيل الكشف التلقائي');
    } finally {
      if (mounted) setState(() => _isDetecting = false);
    }
  }

  void _showSnack(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(message, textDirection: TextDirection.rtl)));
  }

  void _applyCrop() {
    final mat = ImageUtils.decodeBytes(widget.imageBytes);
    if (mat == null) {
      Navigator.pop(context);
      return;
    }

    var cropped = ManualCrop.cropPerspective(mat, _x1, _y1, _x2, _y2, _x3, _y3, _x4, _y4);
    if (cropped != null) {
       cropped = ImageEnhancer.apply(cropped, _filter);
       final resultBytes = ImageUtils.encodeJpg(cropped, quality: 95);
       Navigator.pop(context, resultBytes);
    } else {
       Navigator.pop(context, widget.imageBytes);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: const Color(0xFF1E293B),
        leading: IconButton(icon: const Icon(Icons.close, color: Colors.white), onPressed: () => Navigator.pop(context)),
        title: SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: Row(
            children: [
              _filterChip('أصلي', _filter == EnhanceMode.none, () { setState(() { _filter = EnhanceMode.none; _updateDisplayBytes(); }); }),
              const SizedBox(width: 4),
              _filterChip('تحسين سحري ✨', _filter == EnhanceMode.soft, () { setState(() { _filter = EnhanceMode.soft; _updateDisplayBytes(); }); }),
              const SizedBox(width: 4),
              _filterChip('أبيض وأسود رسمي', _filter == EnhanceMode.bw, () { setState(() { _filter = EnhanceMode.bw; _updateDisplayBytes(); }); }),
            ],
          ),
        ),
        actions: [
          IconButton(tooltip: 'تحديد الكل', icon: const Icon(Icons.auto_awesome_mosaic, color: Colors.amber), onPressed: _selectAll),
          IconButton(tooltip: 'تم والتصدير', icon: const Icon(Icons.check, color: Colors.greenAccent), onPressed: _applyCrop),
        ],
      ),
      body: Column(
        children: [
          Expanded(
            child: LayoutBuilder(
              builder: (context, constraints) {
                final cw = constraints.maxWidth;
                final ch = constraints.maxHeight;
                final iw = _imgWidth.toDouble();
                final ih = _imgHeight.toDouble();
                final scale = math.min(cw / iw, ch / ih);
                final imgW = iw * scale;
                final imgH = ih * scale;
                final imgL = (cw - imgW) / 2;
                final imgT = (ch - imgH) / 2;

                final p1 = Offset(imgL + _x1 * imgW, imgT + _y1 * imgH);
                final p2 = Offset(imgL + _x2 * imgW, imgT + _y2 * imgH);
                final p3 = Offset(imgL + _x3 * imgW, imgT + _y3 * imgH);
                final p4 = Offset(imgL + _x4 * imgW, imgT + _y4 * imgH);

                return Stack(
                  children: [
                    Positioned(left: imgL, top: imgT, width: imgW, height: imgH, child: Image.memory(_displayBytes, fit: BoxFit.fill)),
                    Positioned.fill(child: CustomPaint(painter: CropBoxPainter(p1, p2, p3, p4))),
                    _buildCornerDot(_x1, _y1, imgL, imgT, imgW, imgH, (nx, ny) => setState(() { _x1 = nx; _y1 = ny; })),
                    _buildCornerDot(_x2, _y2, imgL, imgT, imgW, imgH, (nx, ny) => setState(() { _x2 = nx; _y2 = ny; })),
                    _buildCornerDot(_x3, _y3, imgL, imgT, imgW, imgH, (nx, ny) => setState(() { _x3 = nx; _y3 = ny; })),
                    _buildCornerDot(_x4, _y4, imgL, imgT, imgW, imgH, (nx, ny) => setState(() { _x4 = nx; _y4 = ny; })),
                    _buildEdgeMidHandle(_x1, _y1, _x2, _y2, imgL, imgT, imgW, imgH, (dnx, dny) => setState(() { _x1 = (_x1 + dnx).clamp(0.0, 1.0); _y1 = (_y1 + dny).clamp(0.0, 1.0); _x2 = (_x2 + dnx).clamp(0.0, 1.0); _y2 = (_y2 + dny).clamp(0.0, 1.0); })),
                    _buildEdgeMidHandle(_x2, _y2, _x3, _y3, imgL, imgT, imgW, imgH, (dnx, dny) => setState(() { _x2 = (_x2 + dnx).clamp(0.0, 1.0); _y2 = (_y2 + dny).clamp(0.0, 1.0); _x3 = (_x3 + dnx).clamp(0.0, 1.0); _y3 = (_y3 + dny).clamp(0.0, 1.0); })),
                    _buildEdgeMidHandle(_x3, _y3, _x4, _y4, imgL, imgT, imgW, imgH, (dnx, dny) => setState(() { _x3 = (_x3 + dnx).clamp(0.0, 1.0); _y3 = (_y3 + dny).clamp(0.0, 1.0); _x4 = (_x4 + dnx).clamp(0.0, 1.0); _y4 = (_y4 + dny).clamp(0.0, 1.0); })),
                    _buildEdgeMidHandle(_x4, _y4, _x1, _y1, imgL, imgT, imgW, imgH, (dnx, dny) => setState(() { _x4 = (_x4 + dnx).clamp(0.0, 1.0); _y4 = (_y4 + dny).clamp(0.0, 1.0); _x1 = (_x1 + dnx).clamp(0.0, 1.0); _y1 = (_y1 + dny).clamp(0.0, 1.0); })),
                    _buildMagnifier(cw, ch, imgL, imgT, imgW, imgH),
                  ],
                );
              },
            ),
          ),
          Container(
            color: const Color(0xFF1E293B),
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceEvenly,
              children: [
                _bottomToolButton(label: 'الكل', icon: Icons.crop_free, onTap: _selectAll),
                _bottomToolButton(label: 'القص التلقائي', icon: Icons.auto_fix_high, onTap: _isDetecting ? null : _runAutoDetect, isLoading: _isDetecting),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _bottomToolButton({required String label, required IconData icon, required VoidCallback? onTap, bool isLoading = false}) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(8),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            isLoading ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2, color: Color(0xFF38BDF8))) : Icon(icon, color: const Color(0xFF38BDF8), size: 22),
            const SizedBox(height: 4),
            Text(label, style: const TextStyle(color: Colors.white70, fontSize: 11, fontWeight: FontWeight.bold)),
          ],
        ),
      ),
    );
  }

  Widget _buildEdgeMidHandle(double ax, double ay, double bx, double by, double il, double it, double iw, double ih, void Function(double dnx, double dny) onDelta) {
    final mx = (ax + bx) / 2;
    final my = (ay + by) / 2;
    final centerX = il + mx * iw;
    final centerY = it + my * ih;
    final isHorizontal = (bx - ax).abs() >= (by - ay).abs();
    return Positioned(
      left: centerX - 14, top: centerY - 14,
      child: GestureDetector(
        onPanStart: (_) => setState(() => _dragFocalPoint = Offset(centerX, centerY)),
        onPanUpdate: (details) {
          setState(() { _dragFocalPoint = (_dragFocalPoint ?? Offset(centerX, centerY)) + details.delta; });
          onDelta(details.delta.dx / iw, details.delta.dy / ih);
        },
        onPanEnd: (_) => setState(() => _dragFocalPoint = null),
        child: Container(
          width: 28, height: 28, alignment: Alignment.center,
          child: Container(
            width: isHorizontal ? 26 : 10, height: isHorizontal ? 10 : 26,
            decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(5), border: Border.all(color: const Color(0xFF0284C7), width: 1.5), boxShadow: const [BoxShadow(color: Colors.black45, blurRadius: 3)]),
          ),
        ),
      ),
    );
  }

  Widget _buildMagnifier(double cw, double ch, double il, double it, double iw, double ih) {
    final focus = _dragFocalPoint;
    if (focus == null) return const SizedBox.shrink();
    const double lensSize = 110;
    const double zoom = 2.5;
    final localX = focus.dx - il;
    final localY = focus.dy - it;
    double left = (focus.dx - lensSize / 2).clamp(0.0, math.max(0.0, cw - lensSize));
    double top = focus.dy - lensSize - 40;
    if (top < 0) top = math.min(focus.dy + 40, math.max(0.0, ch - lensSize));
    return Positioned(
      left: left, top: top,
      child: IgnorePointer(
        child: Container(
          width: lensSize, height: lensSize,
          decoration: BoxDecoration(shape: BoxShape.circle, border: Border.all(color: Colors.white, width: 3), boxShadow: const [BoxShadow(color: Colors.black54, blurRadius: 8)]),
          child: ClipOval(
            child: Stack(
              children: [
                Positioned(left: lensSize / 2 - localX * zoom, top: lensSize / 2 - localY * zoom, width: iw * zoom, height: ih * zoom, child: Image.memory(_displayBytes, fit: BoxFit.fill)),
                Center(child: Container(width: 2, height: 16, color: const Color(0xFF0284C7))),
                Center(child: Container(width: 16, height: 2, color: const Color(0xFF0284C7))),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildCornerDot(double rx, double ry, double il, double it, double iw, double ih, void Function(double, double) onMove) {
    return Positioned(
      left: il + rx * iw - 18, top: it + ry * ih - 18,
      child: GestureDetector(
        onPanStart: (_) => setState(() => _dragFocalPoint = Offset(il + rx * iw, it + ry * ih)),
        onPanUpdate: (details) {
          final currentX = il + rx * iw, currentY = it + ry * ih;
          final newX = ((currentX + details.delta.dx - il) / iw).clamp(0.0, 1.0);
          final newY = ((currentY + details.delta.dy - it) / ih).clamp(0.0, 1.0);
          setState(() { _dragFocalPoint = (_dragFocalPoint ?? Offset(currentX, currentY)) + details.delta; });
          onMove(newX, newY);
        },
        onPanEnd: (_) => setState(() => _dragFocalPoint = null),
        child: Container(
          width: 36, height: 36,
          decoration: BoxDecoration(color: const Color(0xFF0284C7).withAlpha(230), shape: BoxShape.circle, border: Border.all(color: Colors.white, width: 2), boxShadow: const [BoxShadow(color: Colors.black45, blurRadius: 4)]),
          child: const Icon(Icons.control_camera, size: 16, color: Colors.white),
        ),
      ),
    );
  }

  Widget _filterChip(String label, bool selected, VoidCallback onTap) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
        decoration: BoxDecoration(color: selected ? const Color(0xFF0284C7) : Colors.white12, borderRadius: BorderRadius.circular(6)),
        child: Text(label, style: TextStyle(color: selected ? Colors.white : Colors.white70, fontSize: 10, fontWeight: FontWeight.bold)),
      ),
    );
  }
}
