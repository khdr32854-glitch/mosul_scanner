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
      title: 'مكتب علاء الحديدي - الماسح والطباعة الذكية',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(primarySwatch: Colors.blue, useMaterial3: true),
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
    if (rotationAngle % 360 == 0) return image;
    final normalized = (rotationAngle % 360 + 360) % 360;
    if (normalized == 90) return img.copyRotate(image, angle: 90);
    if (normalized == 180) return img.copyRotate(image, angle: 180);
    if (normalized == 270) return img.copyRotate(image, angle: 270);
    return image;
  }

  void applyRotation() {
    if (rotationAngle % 360 == 0) return;
    image = rotatedImage;
    cachedBytes = Uint8List.fromList(ImageUtils.encodeJpg(image));
    final temp = widthMm;
    widthMm = heightMm;
    heightMm = temp;
    rotationAngle = 0;
  }

  void replaceImage(img.Image newImg) {
    image = newImg;
    cachedBytes = Uint8List.fromList(ImageUtils.encodeJpg(newImg));
    rotationAngle = 0;
    heightMm = (newImg.height.toDouble() / newImg.width.toDouble()) * widthMm;
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

  static const double pageWidthMm = 210.0;
  static const double pageHeightMm = 297.0;
  static const double pageMarginMm = 10.0;

  /// فتح ماسح Google ML Kit الرسمي (كاميرا وقص تلقائي واستوديو)
  void _googleScan() async {
    try {
      final paths = await GoogleScanner.scan();
      if (paths == null || paths.isEmpty) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('تم إلغاء المسح'), backgroundColor: Colors.grey, duration: Duration(seconds: 1)),
          );
        }
        return;
      }
      for (int i = 0; i < paths.length; i++) {
        final raw = await File(paths[i]).readAsBytes();
        final decoded = ImageUtils.decodeBytes(raw);
        if (decoded == null) continue;
        final encoded = Uint8List.fromList(ImageUtils.encodeJpg(decoded));
        if (!mounted) return;
        setState(() {
          final item = DocumentItem(
            id: 'gs_${DateTime.now().millisecondsSinceEpoch}_$i',
            image: decoded,
            cachedBytes: encoded,
            widthMm: _activeTabMode == 'photos' ? 36.0 : 85.0,
            heightMm: _activeTabMode == 'photos' ? 45.0 : (decoded.height.toDouble() / decoded.width.toDouble() * 85.0),
            xMm: pageMarginMm + (_items.length * 4.0),
            yMm: pageMarginMm + (_items.length * 4.0),
            isPhotoMode: _activeTabMode == 'photos',
            hasCurvedCorners: _activeTabMode == 'docs',
          );
          _items.add(item);
          _activeItem = item;
        });
      }
    } catch (_) {
      if (mounted) {
        _addNewImages(ImageSource.camera);
      }
    }
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
      final decodedImg = ImageUtils.decodeBytes(bytes);

      if (decodedImg != null) {
        final encodedBytes = Uint8List.fromList(ImageUtils.encodeJpg(decodedImg));
        if (!mounted) return;
        setState(() {
          final newItem = DocumentItem(
            id: '${DateTime.now().millisecondsSinceEpoch}_$i',
            image: decodedImg,
            cachedBytes: encodedBytes,
            widthMm: _activeTabMode == 'photos' ? 36.0 : 85.0,
            heightMm: _activeTabMode == 'photos' ? 45.0 : (decodedImg.height.toDouble() / decodedImg.width.toDouble() * 85.0),
            xMm: pageMarginMm + (_items.length * 4.0),
            yMm: pageMarginMm + (_items.length * 4.0),
            isPhotoMode: _activeTabMode == 'photos',
            hasCurvedCorners: _activeTabMode == 'docs',
          );
          _items.add(newItem);
          _activeItem = newItem;
        });
      }
    }
  }

  void _resizeActiveItem(double w, double h, {bool isPhoto = false, bool curved = false}) {
    if (_activeItem != null) {
      setState(() {
        _activeItem!.widthMm = w;
        _activeItem!.heightMm = h;
        _activeItem!.isPhotoMode = isPhoto;
        _activeItem!.hasCurvedCorners = curved;
      });
    }
  }

  void _rotateActiveItem() {
    if (_activeItem != null) {
      setState(() => _activeItem!.applyRotation());
    }
  }

  void _duplicateActiveItem() {
    if (_activeItem == null) return;
    final src = _activeItem!;
    setState(() {
      final dup = DocumentItem(
        id: '${DateTime.now().millisecondsSinceEpoch}',
        image: img.copyResize(src.image, width: src.image.width),
        cachedBytes: Uint8List.fromList(src.cachedBytes),
        widthMm: src.widthMm,
        heightMm: src.heightMm,
        xMm: src.xMm + 5.0,
        yMm: src.yMm + 5.0,
        rotationAngle: src.rotationAngle,
        isPhotoMode: src.isPhotoMode,
        hasCurvedCorners: src.hasCurvedCorners,
      );
      _items.add(dup);
      _activeItem = dup;
    });
  }

  void _autoAlignItems() {
    setState(() {
      double currentX = pageMarginMm;
      double currentY = pageMarginMm;
      double maxHeightInRow = 0;
      for (var item in _items) {
        if (currentX + item.widthMm > pageWidthMm - pageMarginMm) {
          currentX = pageMarginMm;
          currentY += maxHeightInRow + 5.0;
          maxHeightInRow = 0;
        }
        item.xMm = currentX;
        item.yMm = currentY;
        currentX += item.widthMm + 5.0;
        if (item.heightMm > maxHeightInRow) maxHeightInRow = item.heightMm;
      }
    });
  }

  void _autoCropActiveItem() {
    if (_activeItem == null) return;
    final result = HybridEngine.autoCrop(_activeItem!.rotatedImage);
    if (result.changed) {
      setState(() => _activeItem!.replaceImage(result.image));
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('تم القص والتحديد'), backgroundColor: Colors.teal, duration: Duration(seconds: 1)),
      );
    }
  }

  void _manualCropActiveItem() async {
    if (_activeItem == null) return;
    final result = await Navigator.push<img.Image>(
      context,
      MaterialPageRoute(builder: (_) => CropScreen(image: _activeItem!.rotatedImage)),
    );
    if (result != null && mounted) {
      setState(() => _activeItem!.replaceImage(result));
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
              final rotated = item.rotatedImage;
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
                      pw.MemoryImage(Uint8List.fromList(ImageUtils.encodeJpg(rotated, quality: 95))),
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
      backgroundColor: const Color(0xFF0F172A),
      appBar: AppBar(
        title: const Text('مكتب علاء الحديدي - الماسح الذكي والطباعة', style: TextStyle(fontSize: 13, fontWeight: FontWeight.bold)),
        backgroundColor: const Color(0xFF0284C7),
        foregroundColor: Colors.white,
        actions: [
          IconButton(icon: const Icon(Icons.print, size: 20), tooltip: 'طباعة PDF', onPressed: _exportAndPrint),
          IconButton(icon: const Icon(Icons.document_scanner, size: 22, color: Color(0xFF4ADE80)), tooltip: 'مسح Google الذكي', onPressed: _googleScan),
          IconButton(icon: const Icon(Icons.add_a_photo, size: 20), tooltip: 'كاميرا', onPressed: () => _addNewImages(ImageSource.camera)),
          IconButton(icon: const Icon(Icons.photo_library, size: 20), tooltip: 'معرض', onPressed: () => _addNewImages(ImageSource.gallery)),
        ],
      ),
      body: Column(
        children: [
          Container(
            height: 48,
            color: const Color(0xFF1E293B),
            child: ListView(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 6),
              children: [
                _buildToolBtn('مستمسكات', _activeTabMode == 'docs', () => setState(() => _activeTabMode = 'docs')),
                _buildToolBtn('صور', _activeTabMode == 'photos', () => setState(() => _activeTabMode = 'photos')),
                const VerticalDivider(color: Colors.white24, indent: 6, endIndent: 6),
                _buildToolBtn('قص تلقائي ✨', false, _autoCropActiveItem, const Color(0xFFF59E0B)),
                _buildToolBtn('قص يدوي ✂️', false, _manualCropActiveItem, const Color(0xFF06B6D4)),
                _buildToolBtn('ترتيب 📐', false, _autoAlignItems, const Color(0xFF10B981)),
                _buildToolBtn('تدوير 🔄', false, _rotateActiveItem, const Color(0xFF94A3B8)),
                _buildToolBtn('نسخ 📋', false, _duplicateActiveItem, const Color(0xFFA78BFA)),
              ],
            ),
          ),
          Expanded(
            child: Row(
              children: [
                Container(
                  width: 100,
                  color: const Color(0xFFF8FAFC),
                  child: Column(
                    children: [
                      Container(
                        padding: const EdgeInsets.all(6),
                        color: const Color(0xFF0369A1),
                        width: double.infinity,
                        child: const Text('القياسات', textAlign: TextAlign.center, style: TextStyle(color: Colors.white, fontSize: 11, fontWeight: FontWeight.bold)),
                      ),
                      Expanded(
                        child: ListView(
                          padding: const EdgeInsets.all(4),
                          children: _activeTabMode == 'docs'
                              ? [
                                  _buildSizeBtn('بطاقة موحدة', '8.5×5.4 سم', () => _resizeActiveItem(85, 54, curved: true)),
                                  _buildSizeBtn('بطاقة سكن', '8.8×5.8 سم', () => _resizeActiveItem(88, 58, curved: true)),
                                  _buildSizeBtn('ورقة A4', '21×29.7 سم', () => _resizeActiveItem(210, 297, curved: false), clr: const Color(0xFF0F766E)),
                                ]
                              : [
                                  _buildSizeBtn('معاملة', '3.6×4.5 سم', () => _resizeActiveItem(36, 45, isPhoto: true)),
                                  _buildSizeBtn('مصغر', '2.5×3.4 سم', () => _resizeActiveItem(25, 34, isPhoto: true)),
                                ],
                        ),
                      ),
                      if (_activeItem != null)
                        Padding(
                          padding: const EdgeInsets.all(4.0),
                          child: ElevatedButton.icon(
                            style: ElevatedButton.styleFrom(backgroundColor: Colors.red, foregroundColor: Colors.white, padding: const EdgeInsets.all(4)),
                            onPressed: () => setState(() {
                              _items.remove(_activeItem);
                              _activeItem = null;
                            }),
                            icon: const Icon(Icons.delete, size: 14),
                            label: const Text('حذف', style: TextStyle(fontSize: 10)),
                          ),
                        ),
                    ],
                  ),
                ),
                Expanded(
                  child: Container(
                    color: const Color(0xFF0F172A),
                    child: Center(
                      child: LayoutBuilder(
                        builder: (context, constraints) {
                          final scaleX = (constraints.maxWidth - 20) / pageWidthMm;
                          final scaleY = (constraints.maxHeight - 20) / pageHeightMm;
                          final scale = min(scaleX, scaleY);

                          return Container(
                            width: pageWidthMm * scale,
                            height: pageHeightMm * scale,
                            decoration: BoxDecoration(color: Colors.white, boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.5), blurRadius: 10)]),
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
                                    onPanUpdate: (details) {
                                      setState(() {
                                        item.xMm += details.delta.dx / scale;
                                        item.yMm += details.delta.dy / scale;
                                      });
                                    },
                                    child: Container(
                                      decoration: BoxDecoration(
                                        borderRadius: radius,
                                        border: Border.all(color: isActive ? Colors.blue : Colors.transparent, width: isActive ? 2.5 : 1.0),
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

  Widget _buildToolBtn(String label, bool isSelected, VoidCallback onTap, [Color? color]) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 2.0),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(6),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
          decoration: BoxDecoration(
            color: isSelected ? (color ?? Colors.blue).withOpacity(0.3) : Colors.transparent,
            borderRadius: BorderRadius.circular(6),
            border: Border.all(color: isSelected ? (color ?? Colors.blue) : Colors.white30),
          ),
          child: Text(label, style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: isSelected ? (color ?? Colors.lightBlueAccent) : Colors.white)),
        ),
      ),
    );
  }

  Widget _buildSizeBtn(String title, String subtitle, VoidCallback onTap, {Color clr = const Color(0xFF0369A1)}) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3.0),
      child: ElevatedButton(
        style: ElevatedButton.styleFrom(
          padding: const EdgeInsets.symmetric(vertical: 8),
          backgroundColor: clr.withOpacity(0.1),
          foregroundColor: clr,
          side: BorderSide(color: clr.withOpacity(0.4)),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(6)),
          elevation: 0,
        ),
        onPressed: onTap,
        child: Column(
          children: [
            Text(title, style: TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: clr)),
            Text(subtitle, style: TextStyle(fontSize: 8, color: clr.withOpacity(0.8))),
          ],
        ),
      ),
    );
  }
}

class CropScreen extends StatefulWidget {
  final img.Image image;
  const CropScreen({super.key, required this.image});

  @override
  State<CropScreen> createState() => _CropScreenState();
}

class _CropScreenState extends State<CropScreen> {
  double _x1 = 0.05, _y1 = 0.05;
  double _x2 = 0.95, _y2 = 0.05;
  double _x3 = 0.95, _y3 = 0.95;
  double _x4 = 0.05, _y4 = 0.95;
  EnhanceMode _filter = EnhanceMode.soft;
  late Uint8List _displayBytes;

  @override
  void initState() {
    super.initState();
    _displayBytes = Uint8List.fromList(ImageUtils.encodeJpg(widget.image, quality: 92));
  }

  void _applyCrop() {
    var cropped = ManualCrop.cropPerspective(widget.image, _x1, _y1, _x2, _y2, _x3, _y3, _x4, _y4);
    cropped = ImageEnhancer.apply(cropped, _filter);
    Navigator.pop(context, cropped);
  }

  void _autoDetectCorners() {
    final corners = HybridEngine.detectCorners(widget.image);
    if (corners != null && corners.length == 8) {
      setState(() {
        _x1 = corners[0]; _y1 = corners[1];
        _x2 = corners[2]; _y2 = corners[3];
        _x3 = corners[4]; _y3 = corners[5];
        _x4 = corners[6]; _y4 = corners[7];
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: const Color(0xFF1E293B),
        leading: IconButton(icon: const Icon(Icons.close, color: Colors.white), onPressed: () => Navigator.pop(context)),
        title: Row(
          children: [
            _filterChip('أصلي', _filter == EnhanceMode.none, () => setState(() => _filter = EnhanceMode.none)),
            const SizedBox(width: 4),
            _filterChip('تحسين ✨', _filter == EnhanceMode.soft, () => setState(() => _filter = EnhanceMode.soft)),
            const SizedBox(width: 4),
            _filterChip('أبيض وأسود', _filter == EnhanceMode.bw, () => setState(() => _filter = EnhanceMode.bw)),
          ],
        ),
        actions: [
          IconButton(icon: const Icon(Icons.auto_fix_high, color: Color(0xFF4ADE80)), onPressed: _autoDetectCorners),
          IconButton(icon: const Icon(Icons.check, color: Colors.green), onPressed: _applyCrop),
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
              Positioned(left: imgL, top: imgT, width: imgW, height: imgH, child: Image.memory(_displayBytes, fit: BoxFit.fill)),
              _buildCornerDot(_x1, _y1, imgL, imgT, imgW, imgH, (nx, ny) => setState(() { _x1 = nx; _y1 = ny; })),
              _buildCornerDot(_x2, _y2, imgL, imgT, imgW, imgH, (nx, ny) => setState(() { _x2 = nx; _y2 = ny; })),
              _buildCornerDot(_x3, _y3, imgL, imgT, imgW, imgH, (nx, ny) => setState(() { _x3 = nx; _y3 = ny; })),
              _buildCornerDot(_x4, _y4, imgL, imgT, imgW, imgH, (nx, ny) => setState(() { _x4 = nx; _y4 = ny; })),
            ],
          );
        },
      ),
    );
  }

  Widget _buildCornerDot(double rx, double ry, double il, double it, double iw, double ih, void Function(double, double) onMove) {
    return Positioned(
      left: il + rx * iw - 20,
      top: it + ry * ih - 20,
      child: GestureDetector(
        onPanUpdate: (d) => onMove(
          ((il + rx * iw + d.delta.dx - il) / iw).clamp(0.0, 1.0),
          ((it + ry * ih + d.delta.dy - it) / ih).clamp(0.0, 1.0),
        ),
        child: Container(
          width: 40,
          height: 40,
          decoration: BoxDecoration(color: Colors.blue.withOpacity(0.8), shape: BoxShape.circle, border: Border.all(color: Colors.white, width: 2)),
          child: const Icon(Icons.crop, size: 18, color: Colors.white),
        ),
      ),
    );
  }

  Widget _filterChip(String label, bool isSelected, VoidCallback onTap) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
        decoration: BoxDecoration(color: isSelected ? Colors.blue : Colors.black45, borderRadius: BorderRadius.circular(12)),
        child: Text(label, style: const TextStyle(color: Colors.white, fontSize: 10)),
      ),
    );
  }
}
