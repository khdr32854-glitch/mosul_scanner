import 'dart:io';
import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:image/image.dart' as img;
import 'package:image_picker/image_picker.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';

import 'crop_engine.dart';   // محرك التسطيح والقص
import 'ai_edge_detector.dart'; // كاشف زوايا المستند بالذكاء الاصطناعي

/// ===============================================================
/// ISOLATES (BACKGROUND TASKS)
/// ===============================================================

img.Image? decodeImageIsolate(Uint8List bytes) {
  return ImageUtils.decodeBytes(bytes);
}

Map<String, dynamic> processPreviewIsolate(Map<String, dynamic> args) {
  final img.Image source = args['image'];
  final EnhanceMode mode = args['mode'];
  final double intensity = args['intensity'];

  final processed = ImageEnhancer.apply(source, mode, intensity);

  img.Image noAlpha = processed;
  if (processed.numChannels == 4) {
    noAlpha = processed.convert(numChannels: 3);
  }

  final bytes = Uint8List.fromList(img.encodeJpg(noAlpha, quality: 85));

  return {
    'bytes': bytes,
    'width': noAlpha.width,
    'height': noAlpha.height,
  };
}

img.Image cropFinalIsolate(Map<String, dynamic> args) {
  final img.Image source = args['image'];
  
  var cropped = CropEngine.cropPerspective(
    source,
    args['x1'], args['y1'],
    args['x2'], args['y2'],
    args['x3'], args['y3'],
    args['x4'], args['y4'],
  );
  
  return ImageEnhancer.apply(cropped, args['mode'], args['intensity']);
}

/// ===============================================================
/// IMAGE UTILS & ENHANCEMENT
/// ===============================================================

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
    img.Image toEncode = image;
    if (image.numChannels == 4) {
      try {
        toEncode = image.convert(numChannels: 3);
      } catch (e) {
        toEncode = image;
      }
    }
    try {
      return Uint8List.fromList(img.encodeJpg(toEncode, quality: quality));
    } catch (e) {
      return Uint8List(0);
    }
  }

  static bool isValid(img.Image? image) {
    return image != null && image.width >= 10 && image.height >= 10;
  }
}

enum EnhanceMode { none, magic, magicPro, noShadow, bw, grayscale }

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
            contrast: 1.2 + (0.3 * intensity),
            brightness: 1.05 + (0.1 * intensity),
            saturation: 1.15 + (0.2 * intensity),
          );
        } catch (_) {
          return image;
        }
      case EnhanceMode.magicPro:
        try {
          final normalized = img.normalize(image, min: 10, max: 245);
          return img.adjustColor(
            normalized,
            contrast: 1.35 + (0.35 * intensity),
            brightness: 1.1 + (0.1 * intensity),
            saturation: 1.25,
          );
        } catch (_) {
          return image;
        }
      case EnhanceMode.noShadow:
        try {
          final normalized = img.normalize(image, min: 15, max: 255);
          return img.adjustColor(
            normalized,
            contrast: 1.1,
            brightness: 1.18 + (0.1 * intensity),
            saturation: 0.95,
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
            contrast: 1.3 + (0.4 * intensity),
            brightness: 1.05 + (0.1 * intensity),
          );
        } catch (_) {
          return image;
        }
      case EnhanceMode.grayscale:
        try {
          return img.grayscale(image);
        } catch (_) {
          return image;
        }
    }
  }
}

/// ===============================================================
/// MAIN ENTRY POINT & APP THEME
/// ===============================================================

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // فحص تشخيصي اختياري لتحميل الموديل عند إقلاع التطبيق
  await AIDocumentDetector.inspectModel();

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
        scaffoldBackgroundColor: const Color(0xFFF8FAFC), 
        colorScheme: ColorScheme.fromSeed(
          seedColor: const Color(0xFF0284C7),
          primary: const Color(0xFF0284C7),
          surface: Colors.white,
        ),
        appBarTheme: const AppBarTheme(
          backgroundColor: Colors.white,
          foregroundColor: Color(0xFF0F172A),
          elevation: 0.5,
        ),
      ),
      home: const MainScannerScreen(),
    );
  }
}

/// ===============================================================
/// DOCUMENT ITEM
/// ===============================================================

class DocumentItem {
  final String id;
  img.Image image;
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
      final temp = widthMm;
      widthMm = heightMm;
      heightMm = temp;
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

/// ===============================================================
/// MAIN SCANNER SCREEN
/// ===============================================================

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
  bool _isLoadingImages = false;

  static const double pageWidthMm = 210.0;
  static const double pageHeightMm = 297.0;
  static const double pageMarginMm = 10.0;

  Future<void> _addManualImages(ImageSource source) async {
    try {
      setState(() => _isLoadingImages = true);

      if (source == ImageSource.camera) {
        final photo = await _picker.pickImage(
          source: ImageSource.camera,
          imageQuality: 95,
        );
        if (photo != null) {
          final bytes = await File(photo.path).readAsBytes();
          final decoded = await compute(decodeImageIsolate, bytes);
          if (decoded != null) {
            await _processImageWithCropScreen(
              decoded,
              isPhoto: _activeTabMode == 'photos',
            );
          }
        }
      } else {
        final files = await _picker.pickMultiImage(imageQuality: 95);
        for (final file in files) {
          final bytes = await File(file.path).readAsBytes();
          final decoded = await compute(decodeImageIsolate, bytes);
          if (decoded != null) {
            await _processImageWithCropScreen(
              decoded,
              isPhoto: _activeTabMode == 'photos',
            );
          }
        }
      }
    } catch (e) {
      if (mounted) _showMessage('خطأ في جلب الصور: $e', error: true);
    } finally {
      if (mounted) setState(() => _isLoadingImages = false);
    }
  }

  Future<void> _processImageWithCropScreen(img.Image decoded, {bool isPhoto = false}) async {
    if (!mounted) return;

    if (isPhoto) {
      _addDecodedImage(decoded, isPhoto: true, curved: false);
      return;
    }

    final result = await Navigator.push<img.Image>(
      context,
      MaterialPageRoute(builder: (_) => CropScreen(image: decoded)),
    );

    if (result != null && mounted) {
      _addDecodedImage(result, isPhoto: false, curved: true);
    }
  }

  void _addDecodedImage(img.Image decodedImage, {bool isPhoto = false, bool curved = false}) {
    if (!ImageUtils.isValid(decodedImage)) {
      _showMessage('الصورة غير صالحة', error: true);
      return;
    }

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
        image: decodedImage,
        cachedBytes: encodedBytes,
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
    if (_activeItem == null) return;
    setState(() {
      _activeItem!.widthMm = width;
      _activeItem!.heightMm = height;
      _activeItem!.isPhotoMode = isPhoto;
      _activeItem!.hasCurvedCorners = curved;
    });
  }

  void _rotateActiveItem() {
    if (_activeItem == null) return;
    setState(() {
      _activeItem!.rotationAngle = (_activeItem!.rotationAngle + 90) % 360;
      _activeItem!.applyRotation();
    });
  }

  void _duplicateActiveItem() {
    final source = _activeItem;
    if (source == null) return;

    setState(() {
      final duplicate = DocumentItem(
        id: DateTime.now().microsecondsSinceEpoch.toString(),
        image: img.Image.from(source.image),
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

    final result = await Navigator.push<img.Image>(
      context,
      MaterialPageRoute(builder: (_) => CropScreen(image: active.rotatedImage)),
    );

    if (result != null && mounted) {
      setState(() {
        active.replaceImage(result);
      });
    }
  }

  void _deleteActiveItem() {
    if (_activeItem == null) return;
    setState(() {
      _items.remove(_activeItem);
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
                final rotated = item.rotatedImage;
                final bytes = ImageUtils.encodeJpg(rotated, quality: 95);
                return pw.Positioned(
                  left: item.xMm * PdfPageFormat.mm,
                  top: item.yMm * PdfPageFormat.mm,
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
          backgroundColor: error ? Colors.red.shade700 : const Color(0xFF0284C7),
        ),
      );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF1F5F9), 
      appBar: AppBar(
        title: const Text(
          'مكتب علاء الحديدي - نظام الطباعة الاحترافي',
          style: TextStyle(fontSize: 14, fontWeight: FontWeight.bold, color: Color(0xFF0F172A)),
        ),
        backgroundColor: Colors.white,
        elevation: 1,
        actions: [
          IconButton(
            tooltip: 'طباعة المستندات',
            icon: const Icon(Icons.print_outlined, color: Color(0xFF0284C7)),
            onPressed: _exportAndPrint,
          ),
          IconButton(
            tooltip: 'التقاط بواسطة الكاميرا',
            icon: const Icon(Icons.camera_alt_outlined, color: Color(0xFF0284C7)),
            onPressed: () => _addManualImages(ImageSource.camera),
          ),
          IconButton(
            tooltip: 'استيراد من المعرض',
            icon: _isLoadingImages
                ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2, color: Color(0xFF0284C7)))
                : const Icon(Icons.photo_library_outlined, color: Color(0xFF0284C7)),
            onPressed: _isLoadingImages ? null : () => _addManualImages(ImageSource.gallery),
          ),
        ],
      ),
      body: Column(
        children: [
          Container(
            height: 50,
            decoration: const BoxDecoration(
              color: Colors.white,
              border: Border(bottom: BorderSide(color: Color(0xFFE2E8F0))),
            ),
            child: ListView(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
              children: [
                _buildToolBtn('المستمسكات', Icons.badge_outlined, _activeTabMode == 'docs', () => setState(() => _activeTabMode = 'docs')),
                _buildToolBtn('الصور الشخصية', Icons.person_outline, _activeTabMode == 'photos', () => setState(() => _activeTabMode = 'photos')),
                const VerticalDivider(color: Color(0xFFCBD5E1), indent: 6, endIndent: 6),
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
                  width: 115,
                  decoration: const BoxDecoration(
                    color: Colors.white,
                    border: Border(left: BorderSide(color: Color(0xFFE2E8F0))),
                  ),
                  child: Column(
                    children: [
                      Container(
                        padding: const EdgeInsets.symmetric(vertical: 10),
                        width: double.infinity,
                        color: const Color(0xFFF8FAFC),
                        child: const Text(
                          'المقاسات القياسية',
                          textAlign: TextAlign.center,
                          style: TextStyle(color: Color(0xFF475569), fontSize: 10, fontWeight: FontWeight.bold),
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
                                backgroundColor: const Color(0xFFFEE2E2),
                                foregroundColor: const Color(0xFFDC2626),
                                elevation: 0,
                                padding: const EdgeInsets.symmetric(vertical: 8),
                                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(6)),
                              ),
                              onPressed: _deleteActiveItem,
                              icon: const Icon(Icons.delete_outline, size: 16),
                              label: const Text('حذف العنصر', style: TextStyle(fontSize: 10, fontWeight: FontWeight.bold)),
                            ),
                          ),
                        ),
                    ],
                  ),
                ),
                Expanded(
                  child: Container(
                    color: const Color(0xFFE2E8F0),
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
                              boxShadow: [
                                BoxShadow(color: Colors.black.withValues(alpha: 0.08), blurRadius: 12, offset: const Offset(0, 4)),
                              ],
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
                                        border: Border.all(
                                          color: active ? const Color(0xFF0284C7) : Colors.transparent,
                                          width: active ? 2 : 1,
                                        ),
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
            color: selected ? const Color(0xFFE0F2FE) : Colors.transparent,
            borderRadius: BorderRadius.circular(6),
            border: Border.all(color: selected ? const Color(0xFF0284C7) : const Color(0xFFCBD5E1)),
          ),
          child: Row(
            children: [
              Icon(icon, size: 14, color: selected ? const Color(0xFF0284C7) : const Color(0xFF64748B)),
              const SizedBox(width: 5),
              Text(label, style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: selected ? const Color(0xFF0284C7) : const Color(0xFF64748B))),
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
            color: color.withValues(alpha: 0.1),
            borderRadius: BorderRadius.circular(6),
            border: Border.all(color: color.withValues(alpha: 0.3)),
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
          backgroundColor: clr.withValues(alpha: 0.08),
          foregroundColor: clr,
          side: BorderSide(color: clr.withValues(alpha: 0.2)),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(6)),
          elevation: 0,
        ),
        onPressed: onTap,
        child: Column(
          children: [
            Text(title, style: TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: clr)),
            const SizedBox(height: 2),
            Text(subtitle, style: TextStyle(fontSize: 8, color: clr.withValues(alpha: 0.8))),
          ],
        ),
      ),
    );
  }
}

/// ===============================================================
/// CROP PAINTER
/// ===============================================================

class CropBoxPainter extends CustomPainter {
  final Offset p1, p2, p3, p4;
  CropBoxPainter(this.p1, this.p2, this.p3, this.p4);

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = const Color(0xFF0284C7)
      ..strokeWidth = 2.5
      ..style = PaintingStyle.stroke
      ..strokeJoin = StrokeJoin.round;

    final path = Path()
      ..moveTo(p1.dx, p1.dy)
      ..lineTo(p2.dx, p2.dy)
      ..lineTo(p3.dx, p3.dy)
      ..lineTo(p4.dx, p4.dy)
      ..close();

    canvas.drawPath(path, paint);
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => true;
}

/// ===============================================================
/// CROP SCREEN
/// ===============================================================

class CropScreen extends StatefulWidget {
  final img.Image image;
  const CropScreen({super.key, required this.image});

  @override
  State<CropScreen> createState() => _CropScreenState();
}

class _CropScreenState extends State<CropScreen> {
  late img.Image _workingImage;
  
  double _x1 = 0.05, _y1 = 0.05;
  double _x2 = 0.95, _y2 = 0.05;
  double _x3 = 0.95, _y3 = 0.95;
  double _x4 = 0.05, _y4 = 0.95;

  EnhanceMode _filter = EnhanceMode.magic;
  final double _filterIntensity = 0.8;
  
  bool _isProcessing = true;
  bool _isSaving = false;
  
  late Uint8List _displayBytes;
  Offset? _dragFocalPoint;
  bool _isDetecting = false;

  @override
  void initState() {
    super.initState();
    _workingImage = widget.image;
    _updateDisplayBytesAsync();
  }

  Future<void> _updateDisplayBytesAsync() async {
    setState(() => _isProcessing = true);

    try {
      final result = await compute(processPreviewIsolate, {
        'image': _workingImage,
        'mode': _filter,
        'intensity': _filterIntensity,
      });

      if (!mounted) return;

      setState(() {
        _displayBytes = result['bytes'];
        _isProcessing = false;
      });

      if (_x1 == 0.05 && _y1 == 0.05 && _x3 == 0.95 && _y3 == 0.95) {
        _runAutoDetect();
      }
    } catch (e) {
      if (mounted) setState(() => _isProcessing = false);
    }
  }

  void _rotateImage(bool clockwise) {
    final angle = clockwise ? 90 : 270;
    setState(() {
      _workingImage = img.copyRotate(_workingImage, angle: angle);
      _x1 = 0.05; _y1 = 0.05;
      _x2 = 0.95; _y2 = 0.05;
      _x3 = 0.95; _y3 = 0.95;
      _x4 = 0.05; _y4 = 0.95;
    });
    _updateDisplayBytesAsync();
  }

  void _resetPerspective() {
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
      final bytes = ImageUtils.encodeJpg(_workingImage, quality: 85);
      final corners = await AIDocumentDetector.detect(bytes);

      if (!mounted) return;

      if (corners != null && corners.length == 4) {
        final w = _workingImage.width.toDouble();
        final h = _workingImage.height.toDouble();
        setState(() {
          _x1 = (corners[0].dx / w).clamp(0.0, 1.0);
          _y1 = (corners[0].dy / h).clamp(0.0, 1.0);
          _x2 = (corners[1].dx / w).clamp(0.0, 1.0);
          _y2 = (corners[1].dy / h).clamp(0.0, 1.0);
          _x3 = (corners[2].dx / w).clamp(0.0, 1.0);
          _y3 = (corners[2].dy / h).clamp(0.0, 1.0);
          _x4 = (corners[3].dx / w).clamp(0.0, 1.0);
          _y4 = (corners[3].dy / h).clamp(0.0, 1.0);
        });
      } else {
        _resetPerspective();
      }

      // عرض معلومات التشخيص مباشرة على الشاشة (وضع اختبار مؤقت)
      _showDebugDialog();
    } catch (e) {
      _resetPerspective();
    } finally {
      if (mounted) setState(() => _isDetecting = false);
    }
  }

  void _showDebugDialog() {
    if (!mounted) return;
    showDialog(
      context: context,
      builder: (_) => AlertDialog(
        backgroundColor: const Color(0xFF1E293B),
        title: const Text('معلومات تشخيصية', style: TextStyle(color: Colors.white, fontSize: 14)),
        content: SizedBox(
          width: double.maxFinite,
          child: SingleChildScrollView(
            child: SelectableText(
              AIDocumentDetector.lastDebugInfo,
              style: const TextStyle(color: Colors.white70, fontSize: 11, fontFamily: 'monospace'),
              textDirection: TextDirection.ltr,
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('إغلاق'),
          ),
        ],
      ),
    );
  }

  Future<void> _applyCropAsync() async {
    setState(() => _isSaving = true);
    
    try {
      final cropped = await compute(cropFinalIsolate, {
        'image': _workingImage,
        'x1': _x1, 'y1': _y1,
        'x2': _x2, 'y2': _y2,
        'x3': _x3, 'y3': _y3,
        'x4': _x4, 'y4': _y4,
        'mode': _filter,
        'intensity': _filterIntensity,
      });

      if (mounted) Navigator.pop(context, cropped);
    } catch (e) {
      if (mounted) setState(() => _isSaving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF0F172A),
      appBar: AppBar(
        backgroundColor: const Color(0xFF1E293B),
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back, color: Colors.white),
          onPressed: () => Navigator.pop(context),
        ),
        title: const Text(
          'تعديل وقص المستند',
          style: TextStyle(color: Colors.white, fontSize: 14, fontWeight: FontWeight.bold),
        ),
        actions: [
          IconButton(
            tooltip: 'تم والتصدير',
            icon: _isSaving 
                ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(color: Color(0xFF38BDF8), strokeWidth: 2))
                : const Icon(Icons.check, color: Color(0xFF38BDF8), size: 28),
            onPressed: _isSaving ? null : _applyCropAsync,
          ),
        ],
      ),
      body: Column(
        children: [
          Expanded(
            child: _isProcessing 
              ? const Center(child: CircularProgressIndicator(color: Color(0xFF0284C7)))
              : LayoutBuilder(
                  builder: (context, constraints) {
                    final cw = constraints.maxWidth;
                    final ch = constraints.maxHeight;
                    final iw = _workingImage.width.toDouble();
                    final ih = _workingImage.height.toDouble();

                    if (iw <= 0 || ih <= 0 || cw <= 0 || ch <= 0) return const SizedBox();

                    final scale = math.min(cw / iw, ch / ih);
                    final imgW = iw * scale;
                    final imgH = ih * scale;
                    final imgL = (cw - imgW) / 2;
                    final imgT = (ch - imgH) / 2;

                    return SizedBox(
                      width: cw,
                      height: ch,
                      child: Stack(
                        clipBehavior: Clip.none,
                        children: _buildCropStackChildren(cw, ch, iw, ih, scale, imgW, imgH, imgL, imgT),
                      ),
                    );
                  },
                ),
          ),
          Container(
            color: const Color(0xFF1E293B),
            padding: const EdgeInsets.symmetric(vertical: 6, horizontal: 12),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceAround,
              children: [
                _actionIconButton(Icons.rotate_left, 'اليسار', () => _rotateImage(false)),
                _actionIconButton(Icons.crop_rotate, 'مساواة', _resetPerspective),
                _actionIconButton(Icons.auto_fix_high, 'قص تلقائي', _runAutoDetect, isLoading: _isDetecting),
                _actionIconButton(Icons.rotate_right, 'اليمين', () => _rotateImage(true)),
              ],
            ),
          ),
          Container(
            height: 85,
            color: const Color(0xFF0F172A),
            child: ListView(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
              children: [
                _buildCamScannerFilter('أصلي', EnhanceMode.none),
                _buildCamScannerFilter('أداة سحرية ✨', EnhanceMode.magic),
                _buildCamScannerFilter('Magic Pro ⭐', EnhanceMode.magicPro),
                _buildCamScannerFilter('بدون ظل', EnhanceMode.noShadow),
                _buildCamScannerFilter('أبيض وأسود', EnhanceMode.bw),
                _buildCamScannerFilter('رمادي', EnhanceMode.grayscale),
              ],
            ),
          ),
          Container(
            width: double.infinity,
            color: const Color(0xFF0F172A),
            padding: const EdgeInsets.only(bottom: 12, left: 16, right: 16),
            child: ElevatedButton(
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFF0284C7),
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(vertical: 12),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
              ),
              onPressed: _isSaving ? null : _applyCropAsync,
              child: const Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(Icons.check, size: 20),
                  SizedBox(width: 8),
                  Text('حفظ واعتتماد التعديل', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _actionIconButton(IconData icon, String label, VoidCallback onTap, {bool isLoading = false}) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(8),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            isLoading 
              ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2, color: Color(0xFF38BDF8)))
              : Icon(icon, color: Colors.white70, size: 20),
            const SizedBox(height: 3),
            Text(label, style: const TextStyle(color: Colors.white60, fontSize: 10)),
          ],
        ),
      ),
    );
  }

  Widget _buildCamScannerFilter(String title, EnhanceMode mode) {
    final selected = _filter == mode;
    return GestureDetector(
      onTap: () {
        setState(() => _filter = mode);
        _updateDisplayBytesAsync();
      },
      child: Container(
        width: 75,
        margin: const EdgeInsets.symmetric(horizontal: 4),
        decoration: BoxDecoration(
          color: selected ? const Color(0xFF0284C7).withValues(alpha: 0.2) : const Color(0xFF1E293B),
          borderRadius: BorderRadius.circular(8),
          border: Border.all(
            color: selected ? const Color(0xFF0284C7) : Colors.white12,
            width: selected ? 2 : 1,
          ),
        ),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              selected ? Icons.auto_awesome : Icons.image_outlined,
              color: selected ? const Color(0xFF38BDF8) : Colors.white54,
              size: 20,
            ),
            const SizedBox(height: 6),
            Text(
              title,
              textAlign: TextAlign.center,
              style: TextStyle(
                color: selected ? Colors.white : Colors.white70,
                fontSize: 9,
                fontWeight: selected ? FontWeight.bold : FontWeight.normal,
              ),
            ),
          ],
        ),
      ),
    );
  }

  List<Widget> _buildCropStackChildren(double cw, double ch, double iw, double ih, double scale, double imgW, double imgH, double imgL, double imgT) {
    final p1 = Offset(imgL + _x1 * imgW, imgT + _y1 * imgH);
    final p2 = Offset(imgL + _x2 * imgW, imgT + _y2 * imgH);
    final p3 = Offset(imgL + _x3 * imgW, imgT + _y3 * imgH);
    final p4 = Offset(imgL + _x4 * imgW, imgT + _y4 * imgH);

    return [
      Positioned(
        left: imgL,
        top: imgT,
        width: imgW,
        height: imgH,
        child: Image.memory(
          _displayBytes,
          fit: BoxFit.fill,
          gaplessPlayback: true,
        ),
      ),
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
    ];
  }

  Widget _buildEdgeMidHandle(double ax, double ay, double bx, double by, double il, double it, double iw, double ih, void Function(double dnx, double dny) onDelta) {
    final mx = (ax + bx) / 2, my = (ay + by) / 2;
    final centerX = il + mx * iw, centerY = it + my * ih;
    final isHorizontal = (bx - ax).abs() >= (by - ay).abs();

    return Positioned(
      left: centerX - 14, top: centerY - 14,
      child: GestureDetector(
        onPanStart: (_) => setState(() => _dragFocalPoint = Offset(centerX, centerY)),
        onPanUpdate: (details) {
          onDelta(details.delta.dx / iw, details.delta.dy / ih);
          setState(() => _dragFocalPoint = (_dragFocalPoint ?? Offset(centerX, centerY)) + details.delta);
        },
        onPanEnd: (_) => setState(() => _dragFocalPoint = null),
        child: Container(
          width: 28, height: 28, alignment: Alignment.center,
          child: Container(
            width: isHorizontal ? 24 : 10, height: isHorizontal ? 10 : 24,
            decoration: BoxDecoration(
              color: Colors.white, borderRadius: BorderRadius.circular(4),
              border: Border.all(color: const Color(0xFF0284C7), width: 1.5),
              boxShadow: const [BoxShadow(color: Colors.black38, blurRadius: 3)],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildMagnifier(double cw, double ch, double il, double it, double iw, double ih) {
    if (_dragFocalPoint == null) return const SizedBox.shrink();
    const double lensSize = 110; const double zoom = 2.5;
    final localX = _dragFocalPoint!.dx - il, localY = _dragFocalPoint!.dy - it;
    double left = (_dragFocalPoint!.dx - lensSize / 2).clamp(0.0, math.max(0.0, cw - lensSize));
    double top = _dragFocalPoint!.dy - lensSize - 40;
    if (top < 0) top = math.min(_dragFocalPoint!.dy + 40, math.max(0.0, ch - lensSize));

    return Positioned(
      left: left, top: top,
      child: IgnorePointer(
        child: Container(
          width: lensSize, height: lensSize,
          decoration: BoxDecoration(shape: BoxShape.circle, border: Border.all(color: Colors.white, width: 3), boxShadow: const [BoxShadow(color: Colors.black54, blurRadius: 8)]),
          child: ClipOval(
            child: Stack(
              children: [
                Positioned(
                  left: lensSize / 2 - localX * zoom, top: lensSize / 2 - localY * zoom,
                  width: iw * zoom, height: ih * zoom,
                  child: Image.memory(_displayBytes, fit: BoxFit.fill),
                ),
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
          onMove(((currentX + details.delta.dx - il) / iw).clamp(0.0, 1.0), ((currentY + details.delta.dy - it) / ih).clamp(0.0, 1.0));
          setState(() => _dragFocalPoint = (_dragFocalPoint ?? Offset(currentX, currentY)) + details.delta);
        },
        onPanEnd: (_) => setState(() => _dragFocalPoint = null),
        child: Container(
          width: 36, height: 36,
          decoration: BoxDecoration(color: const Color(0xFF0284C7), shape: BoxShape.circle, border: Border.all(color: Colors.white, width: 2), boxShadow: const [BoxShadow(color: Colors.black45, blurRadius: 4)]),
          child: const Icon(Icons.control_camera, size: 16, color: Colors.white),
        ),
      ),
    );
  }
}
