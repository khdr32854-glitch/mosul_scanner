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

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(const MosulScannerApp());
}

// ═══════════════════════════════════════════════════════════════
// التطبيق
// ═══════════════════════════════════════════════════════════════

class MosulScannerApp extends StatelessWidget {
  const MosulScannerApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'مكتب علاء الحديدي - الماسح والطباعة',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        useMaterial3: true,
        colorSchemeSeed: const Color(0xFF0284C7),
        scaffoldBackgroundColor: const Color(0xFF1E293B),
      ),
      home: const MainScreen(),
    );
  }
}

// ═══════════════════════════════════════════════════════════════
// عنصر المستند
// ═══════════════════════════════════════════════════════════════

class DocItem {
  final String id;

  img.Image image;
  Uint8List bytes;

  double wMm;
  double hMm;

  double xMm;
  double yMm;

  int rot;

  bool photo;
  bool curvedCorners;

  DocItem({
    required this.id,
    required this.image,
    required this.bytes,
    required this.wMm,
    required this.hMm,
    required this.xMm,
    required this.yMm,
    this.rot = 0,
    this.photo = false,
    this.curvedCorners = false,
  });

  img.Image get rotated {
    final r = ((rot % 360) + 360) % 360;

    if (r == 0) {
      return image;
    }

    if (r == 90) {
      return img.copyRotate(image, angle: 90);
    }

    if (r == 180) {
      return img.copyRotate(image, angle: 180);
    }

    if (r == 270) {
      return img.copyRotate(image, angle: 270);
    }

    return image;
  }

  void applyRot() {
    final r = ((rot % 360) + 360) % 360;

    if (r == 0) {
      return;
    }

    image = rotated;

    bytes = Uint8List.fromList(
      ImageUtils.encodeJpg(
        image,
        quality: 94,
      ),
    );

    if (r == 90 || r == 270) {
      final oldW = wMm;
      wMm = hMm;
      hMm = oldW;
    }

    rot = 0;
  }

  /// استبدال الصورة بعد القص.
  ///
  /// هذه الدالة مهمة جدًا:
  /// بعد القص يتم تحديث:
  /// - image
  /// - bytes
  /// - الأبعاد
  /// - الدوران
  void replaceImage(img.Image newImage) {
    if (newImage.width < 2 || newImage.height < 2) {
      return;
    }

    image = newImage;

    bytes = Uint8List.fromList(
      ImageUtils.encodeJpg(
        newImage,
        quality: 95,
      ),
    );

    rot = 0;

    final aspect =
        newImage.height / max(1, newImage.width);

    hMm = wMm * aspect;
  }

  DocItem duplicate() {
    final copied = img.Image.from(image);

    return DocItem(
      id: '${DateTime.now().microsecondsSinceEpoch}',
      image: copied,
      bytes: Uint8List.fromList(bytes),
      wMm: wMm,
      hMm: hMm,
      xMm: xMm + 5,
      yMm: yMm + 5,
      rot: rot,
      photo: photo,
      curvedCorners: curvedCorners,
    );
  }
}

// ═══════════════════════════════════════════════════════════════
// الشاشة الرئيسية
// ═══════════════════════════════════════════════════════════════

class MainScreen extends StatefulWidget {
  const MainScreen({super.key});

  @override
  State<MainScreen> createState() => _MainScreenState();
}

class _MainScreenState extends State<MainScreen> {
  final List<DocItem> _items = [];

  DocItem? _sel;

  final ImagePicker _picker = ImagePicker();

  String _mode = 'docs';

  static const double pageW = 210.0;
  static const double pageH = 297.0;
  static const double margin = 10.0;

  // ═══════════════════════════════════════════════════════════
  // Google Scanner
  // ═══════════════════════════════════════════════════════════

  Future<void> _googleScan() async {
    try {
      final paths = await GoogleScanner.scan();

      if (!mounted) {
        return;
      }

      if (paths == null || paths.isEmpty) {
        _message(
          'تم إلغاء المسح',
          Colors.grey,
        );
        return;
      }

      for (int i = 0; i < paths.length; i++) {
        final file = File(paths[i]);

        if (!await file.exists()) {
          continue;
        }

        final raw = await file.readAsBytes();

        final decoded = ImageUtils.decodeBytes(raw);

        if (decoded == null) {
          continue;
        }

        _addDecodedImage(
          decoded,
          prefix: 'google_$i',
        );
      }
    } catch (e) {
      if (!mounted) {
        return;
      }

      _message(
        'تعذر تشغيل الماسح — سيتم استخدام الكاميرا',
        Colors.blue,
      );

      await _addImages(ImageSource.camera);
    }
  }

  // ═══════════════════════════════════════════════════════════
  // إضافة صورة
  // ═══════════════════════════════════════════════════════════

  Future<void> _addImages(ImageSource source) async {
    try {
      List<XFile> files = [];

      if (source == ImageSource.gallery) {
        files = await _picker.pickMultiImage(
          imageQuality: 95,
        );
      } else {
        final file = await _picker.pickImage(
          source: source,
          imageQuality: 95,
        );

        if (file != null) {
          files = [file];
        }
      }

      if (files.isEmpty) {
        return;
      }

      for (int i = 0; i < files.length; i++) {
        final raw = await File(files[i].path).readAsBytes();

        final decoded = ImageUtils.decodeBytes(raw);

        if (decoded == null) {
          continue;
        }

        _addDecodedImage(
          decoded,
          prefix: 'image_$i',
        );
      }
    } catch (e) {
      if (!mounted) {
        return;
      }

      _message(
        'تعذر فتح الصورة',
        Colors.red,
      );
    }
  }

  void _addDecodedImage(
    img.Image decoded, {
    String prefix = 'img',
  }) {
    final isPhoto = _mode == 'photos';

    final w = isPhoto ? 36.0 : 85.0;

    final h = isPhoto
        ? 45.0
        : w * decoded.height / max(1, decoded.width);

    final item = DocItem(
      id: '${prefix}_${DateTime.now().microsecondsSinceEpoch}',
      image: decoded,
      bytes: Uint8List.fromList(
        ImageUtils.encodeJpg(
          decoded,
          quality: 95,
        ),
      ),
      wMm: w,
      hMm: h,
      xMm: margin + (_items.length % 4) * 5,
      yMm: margin + (_items.length ~/ 4) * 5,
      photo: isPhoto,
    );

    setState(() {
      _items.add(item);
      _sel = item;
    });
  }

  // ═══════════════════════════════════════════════════════════
  // القياسات
  // ═══════════════════════════════════════════════════════════

  void _resize(
    double w,
    double h, {
    bool photo = false,
    bool curved = false,
  }) {
    if (_sel == null) {
      return;
    }

    setState(() {
      _sel!.wMm = w;
      _sel!.hMm = h;
      _sel!.photo = photo;
      _sel!.curvedCorners = curved;
    });
  }

  // ═══════════════════════════════════════════════════════════
  // تدوير
  // ═══════════════════════════════════════════════════════════

  void _rotate() {
    final item = _sel;

    if (item == null) {
      return;
    }

    setState(() {
      item.rot = (item.rot + 90) % 360;
    });
  }

  // ═══════════════════════════════════════════════════════════
  // نسخ
  // ═══════════════════════════════════════════════════════════

  void _duplicate() {
    final item = _sel;

    if (item == null) {
      return;
    }

    final copy = item.duplicate();

    setState(() {
      _items.add(copy);
      _sel = copy;
    });
  }

  // ═══════════════════════════════════════════════════════════
  // حذف
  // ═══════════════════════════════════════════════════════════

  void _deleteSelected() {
    final item = _sel;

    if (item == null) {
      return;
    }

    setState(() {
      _items.removeWhere(
        (element) => element.id == item.id,
      );

      _sel = _items.isEmpty ? null : _items.last;
    });
  }

  // ═══════════════════════════════════════════════════════════
  // ترتيب
  // ═══════════════════════════════════════════════════════════

  void _align() {
    if (_items.isEmpty) {
      return;
    }

    setState(() {
      double x = margin;
      double y = margin;
      double rowHeight = 0;

      for (final item in _items) {
        if (x + item.wMm > pageW - margin) {
          x = margin;
          y += rowHeight + 5;
          rowHeight = 0;
        }

        item.xMm = x;
        item.yMm = y;

        x += item.wMm + 5;

        rowHeight = max(
          rowHeight,
          item.hMm,
        );
      }
    });
  }

  // ═══════════════════════════════════════════════════════════
  // القص التلقائي
  // ═══════════════════════════════════════════════════════════

  Future<void> _autoCrop() async {
    final item = _sel;

    if (item == null) {
      _message(
        'حدد صورة أولاً',
        Colors.orange,
      );
      return;
    }

    final source = item.rotated;

    await Future<void>.delayed(
      Duration.zero,
    );

    final result = SmartCrop.detect(source);

    if (!mounted) {
      return;
    }

    if (!result.changed) {
      _message(
        'لم يتم اكتشاف حدود واضحة — استخدم القص اليدوي',
        Colors.orange,
      );
      return;
    }

    setState(() {
      item.replaceImage(result.image);
    });

    _message(
      'تم القص التلقائي وتصحيح الميلان',
      Colors.green,
    );
  }

  // ═══════════════════════════════════════════════════════════
  // القص اليدوي
  // ═══════════════════════════════════════════════════════════

  Future<void> _manualCrop() async {
    final item = _sel;

    if (item == null) {
      _message(
        'حدد صورة أولاً',
        Colors.orange,
      );
      return;
    }

    final source = item.rotated;

    final result = await Navigator.of(context).push<img.Image>(
      MaterialPageRoute(
        builder: (_) => CropScreen(
          image: source,
        ),
      ),
    );

    if (!mounted || result == null) {
      return;
    }

    if (result.width < 20 || result.height < 20) {
      _message(
        'منطقة القص صغيرة جدًا',
        Colors.orange,
      );
      return;
    }

    // أهم نقطة:
    // يتم استبدال الصورة الأصلية فعليًا بالصورة المقصوصة.
    setState(() {
      item.replaceImage(result);
      _sel = item;
    });

    _message(
      'تم تطبيق القص بنجاح',
      Colors.green,
    );
  }

  // ═══════════════════════════════════════════════════════════
  // الطباعة
  // ═══════════════════════════════════════════════════════════

  Future<void> _print() async {
    if (_items.isEmpty) {
      _message(
        'لا توجد صور للطباعة',
        Colors.orange,
      );
      return;
    }

    final document = pw.Document();

    document.addPage(
      pw.Page(
        pageFormat: PdfPageFormat.a4,
        margin: pw.EdgeInsets.zero,
        build: (_) {
          final widgets = <pw.Widget>[];

          for (final item in _items) {
            final image = item.rotated;

            final bytes = Uint8List.fromList(
              ImageUtils.encodeJpg(
                image,
                quality: 95,
              ),
            );

            widgets.add(
              pw.Positioned(
                left: item.xMm * PdfPageFormat.mm,
                top: item.yMm * PdfPageFormat.mm,
                child: pw.SizedBox(
                  width: item.wMm * PdfPageFormat.mm,
                  height: item.hMm * PdfPageFormat.mm,
                  child: pw.Image(
                    pw.MemoryImage(bytes),
                    fit: pw.BoxFit.fill,
                  ),
                ),
              ),
            );
          }

          return pw.Stack(
            children: widgets,
          );
        },
      ),
    );

    await Printing.layoutPdf(
      onLayout: (_) async {
        return document.save();
      },
    );
  }

  // ═══════════════════════════════════════════════════════════
  // رسالة
  // ═══════════════════════════════════════════════════════════

  void _message(
    String text,
    Color color,
  ) {
    if (!mounted) {
      return;
    }

    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(
          content: Text(
            text,
            textAlign: TextAlign.center,
          ),
          backgroundColor: color,
          duration: const Duration(
            seconds: 2,
          ),
        ),
      );
  }

  // ═══════════════════════════════════════════════════════════
  // Build
  // ═══════════════════════════════════════════════════════════

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        backgroundColor: const Color(0xFF0284C7),
        foregroundColor: Colors.white,
        title: const Text(
          'مكتب علاء الحديدي - الماسح الذكي',
          style: TextStyle(
            fontSize: 13,
            fontWeight: FontWeight.bold,
          ),
        ),
        actions: [
          IconButton(
            tooltip: 'طباعة',
            icon: const Icon(
              Icons.print,
              size: 19,
            ),
            onPressed: _print,
          ),
          IconButton(
            tooltip: 'ماسح المستندات',
            icon: const Icon(
              Icons.document_scanner,
              size: 21,
            ),
            onPressed: _googleScan,
          ),
          IconButton(
            tooltip: 'الكاميرا',
            icon: const Icon(
              Icons.add_a_photo,
              size: 19,
            ),
            onPressed: () {
              _addImages(
                ImageSource.camera,
              );
            },
          ),
          IconButton(
            tooltip: 'المعرض',
            icon: const Icon(
              Icons.photo_library,
              size: 19,
            ),
            onPressed: () {
              _addImages(
                ImageSource.gallery,
              );
            },
          ),
        ],
      ),
      body: LayoutBuilder(
        builder: (
          context,
          constraints,
        ) {
          final sidebarWidth =
              constraints.maxWidth * 0.19;

          final canvasWidth =
              constraints.maxWidth -
                  sidebarWidth;

          const toolbarHeight = 50.0;

          final scale = min(
            (canvasWidth - 20) / pageW,
            (constraints.maxHeight -
                    toolbarHeight -
                    20) /
                pageH,
          ).clamp(0.1, 10.0);

          return Column(
            children: [
              _buildToolbar(),
              Expanded(
                child: Row(
                  children: [
                    _buildSidebar(
                      sidebarWidth,
                    ),
                    Expanded(
                      child: _buildCanvas(
                        scale,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          );
        },
      ),
    );
  }

  // ═══════════════════════════════════════════════════════════
  // Toolbar
  // ═══════════════════════════════════════════════════════════

  Widget _buildToolbar() {
    return Container(
      height: 50,
      padding: const EdgeInsets.symmetric(
        horizontal: 4,
      ),
      decoration: const BoxDecoration(
        color: Color(0xFF0F172A),
      ),
      child: Row(
        children: [
          _toolButton(
            'مستمسكات',
            _mode == 'docs',
            () {
              setState(() {
                _mode = 'docs';
              });
            },
          ),
          _toolButton(
            'صور',
            _mode == 'photos',
            () {
              setState(() {
                _mode = 'photos';
              });
            },
          ),
          const Spacer(),
          _toolButton(
            'قص تلقائي',
            false,
            _autoCrop,
            color: const Color(0xFFF59E0B),
          ),
          _toolButton(
            'قص يدوي',
            false,
            _manualCrop,
            color: const Color(0xFF06B6D4),
          ),
          _toolButton(
            'ترتيب',
            false,
            _align,
            color: const Color(0xFF10B981),
          ),
          _toolButton(
            'تدوير',
            false,
            _rotate,
            color: const Color(0xFF94A3B8),
          ),
          _toolButton(
            'نسخ',
            false,
            _duplicate,
            color: const Color(0xFFA78BFA),
          ),
        ],
      ),
    );
  }

  // ═══════════════════════════════════════════════════════════
  // Sidebar
  // ═══════════════════════════════════════════════════════════

  Widget _buildSidebar(
    double width,
  ) {
    return SizedBox(
      width: width,
      child: Container(
        color: const Color(0xFFF1F5F9),
        child: Column(
          crossAxisAlignment:
              CrossAxisAlignment.stretch,
          children: [
            Container(
              margin: const EdgeInsets.all(5),
              padding: const EdgeInsets.all(7),
              decoration: BoxDecoration(
                color: const Color(0xFF0369A1),
                borderRadius:
                    BorderRadius.circular(6),
              ),
              child: const Text(
                'القياسات (مم)',
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontWeight: FontWeight.bold,
                  fontSize: 10,
                  color: Colors.white,
                ),
              ),
            ),
            if (_mode == 'docs') ...[
              _sizeButton(
                'بطاقة موحدة',
                '85 × 54',
                () => _resize(
                  85,
                  54,
                  curved: true,
                ),
              ),
              _sizeButton(
                'بطاقة سكن',
                '88 × 58',
                () => _resize(
                  88,
                  58,
                  curved: true,
                ),
              ),
              _sizeButton(
                'ورقة A4',
                '210 × 297',
                () => _resize(
                  210,
                  297,
                ),
                color: const Color(0xFF0F766E),
              ),
            ] else ...[
              _sizeButton(
                'صورة 3.6 × 4.5',
                '36 × 45',
                () => _resize(
                  36,
                  45,
                  photo: true,
                ),
              ),
              _sizeButton(
                'صورة 2.5 × 3.4',
                '25 × 34',
                () => _resize(
                  25,
                  34,
                  photo: true,
                ),
              ),
            ],
            const Spacer(),
            if (_sel != null)
              Padding(
                padding:
                    const EdgeInsets.all(5),
                child: SizedBox(
                  height: 34,
                  child: ElevatedButton.icon(
                    style:
                        ElevatedButton.styleFrom(
                      backgroundColor:
                          const Color(
                        0xFFDC2626,
                      ),
                      foregroundColor:
                          Colors.white,
                      padding:
                          const EdgeInsets.symmetric(
                        horizontal: 5,
                      ),
                    ),
                    onPressed:
                        _deleteSelected,
                    icon: const Icon(
                      Icons.delete_outline,
                      size: 15,
                    ),
                    label: const Text(
                      'حذف',
                      style: TextStyle(
                        fontSize: 10,
                        fontWeight:
                            FontWeight.bold,
                      ),
                    ),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }

  // ═══════════════════════════════════════════════════════════
  // Canvas
  // ═══════════════════════════════════════════════════════════

  Widget _buildCanvas(
    double scale,
  ) {
    return RepaintBoundary(
      child: Container(
        color: const Color(0xFF1E293B),
        child: Center(
          child: Container(
            width: pageW * scale,
            height: pageH * scale,
            decoration: BoxDecoration(
              color: Colors.white,
              boxShadow: [
                BoxShadow(
                  color:
                      Colors.black.withOpacity(
                    0.45,
                  ),
                  blurRadius: 14,
                ),
              ],
            ),
            child: ClipRect(
              child: Stack(
                children: [
                  for (final item in _items)
                    _buildItem(
                      item,
                      scale,
                    ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  // ═══════════════════════════════════════════════════════════
  // عنصر داخل الورقة
  // ═══════════════════════════════════════════════════════════

  Widget _buildItem(
    DocItem item,
    double scale,
  ) {
    final selected =
        _sel?.id == item.id;

    final radius = item.curvedCorners
        ? BorderRadius.circular(
            4 * scale,
          )
        : BorderRadius.zero;

    return Positioned(
      left: item.xMm * scale,
      top: item.yMm * scale,
      width: item.wMm * scale,
      height: item.hMm * scale,
      child: GestureDetector(
        behavior:
            HitTestBehavior.opaque,
        onTap: () {
          setState(() {
            _sel = item;
          });
        },
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
            borderRadius: radius,
            border: Border.all(
              color: selected
                  ? const Color(
                      0xFF2563EB,
                    )
                  : Colors.transparent,
              width: selected ? 2.5 : 1,
            ),
          ),
          child: ClipRRect(
            borderRadius: radius,
            child: Transform.rotate(
              angle:
                  item.rot * pi / 180,
              child: Image.memory(
                item.bytes,
                fit: BoxFit.fill,
                gaplessPlayback: true,
                filterQuality:
                    FilterQuality.medium,
              ),
            ),
          ),
        ),
      ),
    );
  }

  // ═══════════════════════════════════════════════════════════
  // أدوات
  // ═══════════════════════════════════════════════════════════

  Widget _toolButton(
    String text,
    bool selected,
    VoidCallback onTap, {
    Color? color,
  }) {
    final c = color ?? const Color(0xFF0284C7);

    return Padding(
      padding:
          const EdgeInsets.symmetric(
        horizontal: 2,
      ),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: onTap,
          borderRadius:
              BorderRadius.circular(6),
          child: Container(
            padding:
                const EdgeInsets.symmetric(
              horizontal: 8,
              vertical: 7,
            ),
            decoration: BoxDecoration(
              color: selected
                  ? c.withOpacity(0.22)
                  : Colors.transparent,
              borderRadius:
                  BorderRadius.circular(6),
              border: Border.all(
                color: selected
                    ? c
                    : Colors.white24,
              ),
            ),
            child: Text(
              text,
              style: TextStyle(
                fontSize: 10,
                fontWeight:
                    FontWeight.w700,
                color: selected
                    ? c
                    : Colors.white70,
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _sizeButton(
    String title,
    String subtitle,
    VoidCallback onTap, {
    Color color =
        const Color(0xFF0369A1),
  }) {
    return Padding(
      padding:
          const EdgeInsets.symmetric(
        horizontal: 5,
        vertical: 2,
      ),
      child: SizedBox(
        height: 42,
        child: ElevatedButton(
          style:
              ElevatedButton.styleFrom(
            padding: EdgeInsets.zero,
            minimumSize: Size.zero,
            backgroundColor:
                color.withOpacity(0.06),
            foregroundColor: color,
            elevation: 0,
            side: BorderSide(
              color:
                  color.withOpacity(0.3),
            ),
            shape:
                RoundedRectangleBorder(
              borderRadius:
                  BorderRadius.circular(
                6,
              ),
            ),
          ),
          onPressed: onTap,
          child: Column(
            mainAxisAlignment:
                MainAxisAlignment.center,
            children: [
              Text(
                title,
                style: TextStyle(
                  fontSize: 9,
                  fontWeight:
                      FontWeight.w700,
                  color: color,
                ),
              ),
              Text(
                subtitle,
                style: TextStyle(
                  fontSize: 7,
                  color:
                      color.withOpacity(
                    0.7,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ═══════════════════════════════════════════════════════════════
// شاشة القص اليدوي
// ═══════════════════════════════════════════════════════════════

class CropScreen extends StatefulWidget {
  final img.Image image;

  const CropScreen({
    super.key,
    required this.image,
  });

  @override
  State<CropScreen> createState() =>
      _CropScreenState();
}

class _CropScreenState
    extends State<CropScreen> {
  double _x1 = 0.04;
  double _y1 = 0.04;

  double _x2 = 0.96;
  double _y2 = 0.04;

  double _x3 = 0.96;
  double _y3 = 0.96;

  double _x4 = 0.04;
  double _y4 = 0.96;

  EnhanceMode _filter =
      EnhanceMode.soft;

  late Uint8List _displayBytes;

  double _imageLeft = 0;
  double _imageTop = 0;
  double _imageWidth = 1;
  double _imageHeight = 1;

  @override
  void initState() {
    super.initState();

    _displayBytes =
        Uint8List.fromList(
      ImageUtils.encodeJpg(
        widget.image,
        quality: 92,
      ),
    );
  }

  // ═══════════════════════════════════════════════════════════
  // تطبيق القص
  // ═══════════════════════════════════════════════════════════

  void _apply() {
    final valid = _validCorners();

    if (!valid) {
      _showMessage(
        'رتب نقاط القص بشكل صحيح',
        Colors.orange,
      );
      return;
    }

    img.Image result;

    try {
      result = ManualCrop.cropPerspective(
        widget.image,
        _x1,
        _y1,
        _x2,
        _y2,
        _x3,
        _y3,
        _x4,
        _y4,
      );
    } catch (_) {
      _showMessage(
        'تعذر تنفيذ القص',
        Colors.red,
      );
      return;
    }

    if (result.width < 20 ||
        result.height < 20) {
      _showMessage(
        'منطقة القص صغيرة جدًا',
        Colors.orange,
      );
      return;
    }

    // الفلتر يطبق على الناتج النهائي فقط.
    result = _applyEnhancement(
      result,
      _filter,
    );

    // نرجع الصورة الجديدة فعليًا إلى MainScreen.
    Navigator.of(context).pop(result);
  }

  // ═══════════════════════════════════════════════════════════
  // كشف تلقائي داخل شاشة القص
  // ═══════════════════════════════════════════════════════════

  void _autoDetect() {
    try {
      final corners =
          SmartCrop.detectCorners(
        widget.image,
      );

      if (corners == null ||
          corners.length < 8) {
        _showMessage(
          'لم يتم العثور على حدود واضحة',
          Colors.orange,
        );
        return;
      }

      setState(() {
        _x1 = corners[0];
        _y1 = corners[1];

        _x2 = corners[2];
        _y2 = corners[3];

        _x3 = corners[4];
        _y3 = corners[5];

        _x4 = corners[6];
        _y4 = corners[7];
      });
    } catch (_) {
      _showMessage(
        'تعذر الكشف التلقائي',
        Colors.orange,
      );
    }
  }

  // ═══════════════════════════════════════════════════════════
  // إعادة
  // ═══════════════════════════════════════════════════════════

  void _reset() {
    setState(() {
      _x1 = 0.04;
      _y1 = 0.04;

      _x2 = 0.96;
      _y2 = 0.04;

      _x3 = 0.96;
      _y3 = 0.96;

      _x4 = 0.04;
      _y4 = 0.96;
    });
  }

  // ═══════════════════════════════════════════════════════════
  // التحقق من النقاط
  // ═══════════════════════════════════════════════════════════

  bool _validCorners() {
    final points = <Offset>[
      Offset(_x1, _y1),
      Offset(_x2, _y2),
      Offset(_x3, _y3),
      Offset(_x4, _y4),
    ];

    final area =
        _polygonArea(points);

    return area > 0.01;
  }

  double _polygonArea(
    List<Offset> points,
  ) {
    double sum = 0;

    for (int i = 0;
        i < points.length;
        i++) {
      final a = points[i];

      final b =
          points[(i + 1) % points.length];

      sum +=
          a.dx * b.dy -
          a.dy * b.dx;
    }

    return sum.abs() / 2;
  }

  // ═══════════════════════════════════════════════════════════
  // تحسين الصورة
  // ═══════════════════════════════════════════════════════════

  img.Image _applyEnhancement(
    img.Image source,
    EnhanceMode mode,
  ) {
    if (mode == EnhanceMode.none) {
      return source;
    }

    final result =
        img.Image.from(source);

    for (int y = 0;
        y < result.height;
        y++) {
      for (int x = 0;
          x < result.width;
          x++) {
        final p =
            result.getPixel(x, y);

        double r = p.r.toDouble();
        double g = p.g.toDouble();
        double b = p.b.toDouble();

        if (mode == EnhanceMode.bw) {
          final gray =
              0.299 * r +
              0.587 * g +
              0.114 * b;

          final v =
              gray > 150 ? 255 : 0;

          result.setPixelRgba(
            x,
            y,
            v,
            v,
            v,
            p.a.toInt(),
          );
        } else {
          // تحسين خفيف:
          // رفع التباين والإضاءة بدون تدمير التفاصيل.
          r = ((r - 128) * 1.08) + 134;
          g = ((g - 128) * 1.08) + 134;
          b = ((b - 128) * 1.08) + 134;

          r = r.clamp(0, 255);
          g = g.clamp(0, 255);
          b = b.clamp(0, 255);

          result.setPixelRgba(
            x,
            y,
            r.round(),
            g.round(),
            b.round(),
            p.a.toInt(),
          );
        }
      }
    }

    return result;
  }

  // ═══════════════════════════════════════════════════════════
  // نقطة التحكم
  // ═══════════════════════════════════════════════════════════

  Widget _handle(
    double x,
    double y,
    void Function(
      double,
      double,
    ) update,
  ) {
    return Positioned(
      left:
          _imageLeft +
          x * _imageWidth -
          29,
      top:
          _imageTop +
          y * _imageHeight -
          29,
      child: GestureDetector(
        behavior:
            HitTestBehavior.opaque,
        onPanUpdate: (details) {
          final nx =
              x +
              details.delta.dx /
                  _imageWidth;

          final ny =
              y +
              details.delta.dy /
                  _imageHeight;

          update(
            nx.clamp(0.0, 1.0),
            ny.clamp(0.0, 1.0),
          );
        },
        child: Container(
          width: 58,
          height: 58,
          decoration:
              const BoxDecoration(
            color: Color(0xDD2563EB),
            shape: BoxShape.circle,
          ),
          foregroundDecoration:
              BoxDecoration(
            shape: BoxShape.circle,
            border: Border.all(
              color: Colors.white,
              width: 3,
            ),
            boxShadow: const [
              BoxShadow(
                color: Colors.black54,
                blurRadius: 7,
                offset: Offset(0, 2),
              ),
            ],
          ),
          child: const Center(
            child: Icon(
              Icons.open_with,
              color: Colors.white,
              size: 23,
            ),
          ),
        ),
      ),
    );
  }

  // ═══════════════════════════════════════════════════════════
  // Build شاشة القص
  // ═══════════════════════════════════════════════════════════

  @override
  Widget build(
    BuildContext context,
  ) {
    return Scaffold(
      backgroundColor:
          Colors.black,
      appBar: AppBar(
        backgroundColor:
            const Color(0xFF111827),
        foregroundColor:
            Colors.white,
        leading: IconButton(
          tooltip: 'إلغاء',
          icon: const Icon(
            Icons.close,
          ),
          onPressed: () {
            Navigator.of(
              context,
            ).pop();
          },
        ),
        title: SingleChildScrollView(
          scrollDirection:
              Axis.horizontal,
          child: Row(
            children: [
              _filterButton(
                'أصلي',
                EnhanceMode.none,
              ),
              const SizedBox(width: 5),
              _filterButton(
                'تحسين',
                EnhanceMode.soft,
              ),
              const SizedBox(width: 5),
              _filterButton(
                'أبيض وأسود',
                EnhanceMode.bw,
              ),
            ],
          ),
        ),
        actions: [
          TextButton.icon(
            onPressed:
                _autoDetect,
            icon: const Icon(
              Icons.auto_fix_high,
              size: 17,
              color: Color(
                0xFF4ADE80,
              ),
            ),
            label: const Text(
              'تلقائي',
              style: TextStyle(
                fontSize: 11,
                color: Color(
                  0xFF4ADE80,
                ),
              ),
            ),
          ),
          TextButton.icon(
            onPressed: _reset,
            icon: const Icon(
              Icons.refresh,
              size: 17,
              color: Colors.orange,
            ),
            label: const Text(
              'إعادة',
              style: TextStyle(
                fontSize: 11,
                color: Colors.orange,
              ),
            ),
          ),
          const SizedBox(width: 3),
          FilledButton.icon(
            onPressed: _apply,
            style:
                FilledButton.styleFrom(
              backgroundColor:
                  const Color(
                0xFF10B981,
              ),
              foregroundColor:
                  Colors.white,
              padding:
                  const EdgeInsets.symmetric(
                horizontal: 13,
              ),
            ),
            icon: const Icon(
              Icons.check,
              size: 18,
            ),
            label: const Text(
              'تطبيق',
              style: TextStyle(
                fontSize: 12,
                fontWeight:
                    FontWeight.bold,
              ),
            ),
          ),
          const SizedBox(width: 5),
        ],
      ),
      body: LayoutBuilder(
        builder: (
          context,
          constraints,
        ) {
          final cw =
              constraints.maxWidth;

          final ch =
              constraints.maxHeight;

          final iw =
              widget.image.width
                  .toDouble();

          final ih =
              widget.image.height
                  .toDouble();

          final scale = min(
            cw / iw,
            ch / ih,
          );

          _imageWidth =
              iw * scale;

          _imageHeight =
              ih * scale;

          _imageLeft =
              (cw - _imageWidth) / 2;

          _imageTop =
              (ch - _imageHeight) / 2;

          return Stack(
            children: [
              // الصورة
              Positioned(
                left: _imageLeft,
                top: _imageTop,
                width: _imageWidth,
                height: _imageHeight,
                child: Image.memory(
                  _displayBytes,
                  fit: BoxFit.fill,
                  filterQuality:
                      FilterQuality.high,
                ),
              ),

              // التعتيم والخطوط
              Positioned.fill(
                child: IgnorePointer(
                  child: CustomPaint(
                    painter:
                        _CropOverlayPainter(
                      x1: _imageLeft +
                          _x1 *
                              _imageWidth,
                      y1: _imageTop +
                          _y1 *
                              _imageHeight,
                      x2: _imageLeft +
                          _x2 *
                              _imageWidth,
                      y2: _imageTop +
                          _y2 *
                              _imageHeight,
                      x3: _imageLeft +
                          _x3 *
                              _imageWidth,
                      y3: _imageTop +
                          _y3 *
                              _imageHeight,
                      x4: _imageLeft +
                          _x4 *
                              _imageWidth,
                      y4: _imageTop +
                          _y4 *
                              _imageHeight,
                    ),
                  ),
                ),
              ),

              // نقاط التحكم
              _handle(
                _x1,
                _y1,
                (x, y) {
                  setState(() {
                    _x1 = x;
                    _y1 = y;
                  });
                },
              ),

              _handle(
                _x2,
                _y2,
                (x, y) {
                  setState(() {
                    _x2 = x;
                    _y2 = y;
                  });
                },
              ),

              _handle(
                _x3,
                _y3,
                (x, y) {
                  setState(() {
                    _x3 = x;
                    _y3 = y;
                  });
                },
              ),

              _handle(
                _x4,
                _y4,
                (x, y) {
                  setState(() {
                    _x4 = x;
                    _y4 = y;
                  });
                },
              ),
            ],
          );
        },
      ),
    );
  }

  // ═══════════════════════════════════════════════════════════
  // زر الفلتر
  // ═══════════════════════════════════════════════════════════

  Widget _filterButton(
    String title,
    EnhanceMode mode,
  ) {
    final selected =
        _filter == mode;

    return GestureDetector(
      onTap: () {
        setState(() {
          _filter = mode;
        });
      },
      child: Container(
        padding:
            const EdgeInsets.symmetric(
          horizontal: 10,
          vertical: 5,
        ),
        decoration:
            BoxDecoration(
          color: selected
              ? const Color(
                  0xFF2563EB,
                )
              : const Color(
                  0xFF1E293B,
                ),
          borderRadius:
              BorderRadius.circular(
            20,
          ),
          border: Border.all(
            color: selected
                ? Colors.transparent
                : Colors.white24,
          ),
        ),
        child: Text(
          title,
          style: const TextStyle(
            color: Colors.white,
            fontSize: 10,
            fontWeight:
                FontWeight.w600,
          ),
        ),
      ),
    );
  }

  void _showMessage(
    String text,
    Color color,
  ) {
    if (!mounted) {
      return;
    }

    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(
          content: Text(
            text,
            textAlign: TextAlign.center,
          ),
          backgroundColor: color,
          duration:
              const Duration(
            seconds: 2,
          ),
        ),
      );
  }
}

// ═══════════════════════════════════════════════════════════════
// رسام القص
// ═══════════════════════════════════════════════════════════════

class _CropOverlayPainter
    extends CustomPainter {
  final double x1;
  final double y1;

  final double x2;
  final double y2;

  final double x3;
  final double y3;

  final double x4;
  final double y4;

  const _CropOverlayPainter({
    required this.x1,
    required this.y1,
    required this.x2,
    required this.y2,
    required this.x3,
    required this.y3,
    required this.x4,
    required this.y4,
  });

  @override
  void paint(
    Canvas canvas,
    Size size,
  ) {
    final cropPath = Path()
      ..moveTo(x1, y1)
      ..lineTo(x2, y2)
      ..lineTo(x3, y3)
      ..lineTo(x4, y4)
      ..close();

    // التعتيم الخارجي.
    final overlayPath =
        Path.combine(
      PathOperation.difference,
      Path()..addRect(
        Rect.fromLTWH(
          0,
          0,
          size.width,
          size.height,
        ),
      ),
      cropPath,
    );

    final darkPaint = Paint()
      ..color =
          Colors.black.withOpacity(
        0.55,
      );

    canvas.drawPath(
      overlayPath,
      darkPaint,
    );

    // حدود القص.
    final borderPaint = Paint()
      ..color =
          const Color(0xFF22D3EE)
      ..strokeWidth = 2.5
      ..style =
          PaintingStyle.stroke;

    canvas.drawPath(
      cropPath,
      borderPaint,
    );

    // شبكة خفيفة داخل المستند.
    final gridPaint = Paint()
      ..color = Colors.white38
      ..strokeWidth = 0.8;

    final topX =
        x1 + (x2 - x1) / 3;

    final topY =
        y1 + (y2 - y1) / 3;

    final topX2 =
        x1 + (x2 - x1) * 2 / 3;

    final topY2 =
        y1 + (y2 - y1) * 2 / 3;

    final bottomX =
        x4 + (x3 - x4) / 3;

    final bottomY =
        y4 + (y3 - y4) / 3;

    final bottomX2 =
        x4 + (x3 - x4) * 2 / 3;

    final bottomY2 =
        y4 + (y3 - y4) * 2 / 3;

    canvas.drawLine(
      Offset(topX, topY),
      Offset(bottomX, bottomY),
      gridPaint,
    );

    canvas.drawLine(
      Offset(topX2, topY2),
      Offset(bottomX2, bottomY2),
      gridPaint,
    );

    final leftX =
        x1 + (x4 - x1) / 3;

    final leftY =
        y1 + (y4 - y1) / 3;

    final leftX2 =
        x1 + (x4 - x1) * 2 / 3;

    final leftY2 =
        y1 + (y4 - y1) * 2 / 3;

    final rightX =
        x2 + (x3 - x2) / 3;

    final rightY =
        y2 + (y3 - y2) / 3;

    final rightX2 =
        x2 + (x3 - x2) * 2 / 3;

    final rightY2 =
        y2 + (y3 - y2) * 2 / 3;

    canvas.drawLine(
      Offset(leftX, leftY),
      Offset(rightX, rightY),
      gridPaint,
    );

    canvas.drawLine(
      Offset(leftX2, leftY2),
      Offset(rightX2, rightY2),
      gridPaint,
    );
  }

  @override
  bool shouldRepaint(
    _CropOverlayPainter oldDelegate,
  ) {
    return oldDelegate.x1 != x1 ||
        oldDelegate.y1 != y1 ||
        oldDelegate.x2 != x2 ||
        oldDelegate.y2 != y2 ||
        oldDelegate.x3 != x3 ||
        oldDelegate.y3 != y3 ||
        oldDelegate.x4 != x4 ||
        oldDelegate.y4 != y4;
  }
}
