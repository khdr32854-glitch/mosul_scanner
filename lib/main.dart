import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:google_mlkit_document_scanner/google_mlkit_document_scanner.dart';
import 'package:image/image.dart' as img;
import 'package:image_picker/image_picker.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';

/// ===============================================================
/// MOSUL SCANNER - PROFESSIONAL EDITION
/// GOOGLE ML KIT DOCUMENT SCANNER
/// ===============================================================

class GoogleScanner {
  static Future<List<String>?> scan() async {
    // إعدادات Google Document Scanner:
    //
    // Gallery       = ممنوع
    // Page Limit    = صفحتان
    // JPEG + PDF    = مفعّلان
    // Scanner Mode  = FULL
    //
    // هذه هي المعادلة المقابلة تقريباً لـ:
    //
    // setGalleryImportAllowed(false)
    // setPageLimit(2)
    // setResultFormats(RESULT_FORMAT_JPEG, RESULT_FORMAT_PDF)
    // setScannerMode(SCANNER_MODE_FULL)

    const options = DocumentScannerOptions(
      documentFormats: {
        DocumentFormat.jpeg,
        DocumentFormat.pdf,
      },
      mode: ScannerMode.full,
      pageLimit: 2,
      isGalleryImport: false,
    );

    final scanner = DocumentScanner(options: options);

    try {
      final result = await scanner.scanDocument();

      // نستخدم صور JPEG داخل التطبيق.
      //
      // PDF يبقى متاحاً من Google Scanner في result.pdf،
      // لكن نظام الطباعة الموجود في التطبيق يبني PDF الخاص به
      // حتى نحافظ على المقاسات والترتيب الحالي.

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

/// ===============================================================
/// IMAGE UTILS
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

  static Uint8List encodeJpg(
    img.Image image, {
    int quality = 92,
  }) {
    try {
      return Uint8List.fromList(
        img.encodeJpg(
          image,
          quality: quality,
        ),
      );
    } catch (e) {
      debugPrint('JPEG encode error: $e');
      return Uint8List(0);
    }
  }

  static bool isValid(img.Image? image) {
    return image != null &&
        image.width >= 10 &&
        image.height >= 10;
  }
}

/// ===============================================================
/// ENHANCE
/// ===============================================================

enum EnhanceMode {
  none,
  magic,
  bw,
}

class ImageEnhancer {
  static img.Image apply(
    img.Image source,
    EnhanceMode mode,
    double intensity,
  ) {
    final image = img.Image.from(source);

    switch (mode) {
      case EnhanceMode.none:
        return image;

      case EnhanceMode.magic:
        try {
          final normalized = img.normalize(
            image,
            min: 0,
            max: 255,
          );

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

          final normalized = img.normalize(
            gray,
            min: 0,
            max: 255,
          );

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

/// ===============================================================
/// MANUAL CROP
/// ===============================================================

class ManualCrop {
  static img.Image cropPerspective(
    img.Image source,
    double x1,
    double y1,
    double x2,
    double y2,
    double x3,
    double y3,
    double x4,
    double y4,
  ) {
    if (!ImageUtils.isValid(source)) {
      return img.Image.from(source);
    }

    final w = source.width.toDouble();
    final h = source.height.toDouble();

    final valuesX = <double>[
      x1,
      x2,
      x3,
      x4,
    ];

    final valuesY = <double>[
      y1,
      y2,
      y3,
      y4,
    ];

    final minNormalizedX =
        valuesX.reduce(math.min).clamp(0.0, 1.0);

    final maxNormalizedX =
        valuesX.reduce(math.max).clamp(0.0, 1.0);

    final minNormalizedY =
        valuesY.reduce(math.min).clamp(0.0, 1.0);

    final maxNormalizedY =
        valuesY.reduce(math.max).clamp(0.0, 1.0);

    final minX = (minNormalizedX * w)
        .round()
        .clamp(0, source.width - 1);

    final minY = (minNormalizedY * h)
        .round()
        .clamp(0, source.height - 1);

    final maxX = (maxNormalizedX * w)
        .round()
        .clamp(minX + 1, source.width);

    final maxY = (maxNormalizedY * h)
        .round()
        .clamp(minY + 1, source.height);

    return img.copyCrop(
      source,
      x: minX,
      y: minY,
      width: math.max(10, maxX - minX),
      height: math.max(10, maxY - minY),
    );
  }
}

/// ===============================================================
/// MAIN
/// ===============================================================

void main() {
  WidgetsFlutterBinding.ensureInitialized();

  runApp(
    const MosulScannerApp(),
  );
}

/// ===============================================================
/// APP
/// ===============================================================

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
    final angle =
        ((rotationAngle % 360) + 360) % 360;

    if (angle == 90 ||
        angle == 180 ||
        angle == 270) {
      return img.copyRotate(
        image,
        angle: angle,
      );
    }

    return image;
  }

  void applyRotation() {
    final angle =
        ((rotationAngle % 360) + 360) % 360;

    if (angle == 0) {
      return;
    }

    image = rotatedImage;

    cachedBytes = Uint8List.fromList(
      img.encodeJpg(
        image,
        quality: 95,
      ),
    );

    if (angle == 90 || angle == 270) {
      final temp = widthMm;
      widthMm = heightMm;
      heightMm = temp;
    }

    rotationAngle = 0;
  }

  void replaceImage(img.Image newImage) {
    image = newImage;

    cachedBytes = Uint8List.fromList(
      img.encodeJpg(
        newImage,
        quality: 95,
      ),
    );

    rotationAngle = 0;

    if (newImage.width > 0) {
      heightMm =
          (newImage.height / newImage.width) *
              widthMm;
    }
  }
}

/// ===============================================================
/// MAIN SCANNER SCREEN
/// ===============================================================

class MainScannerScreen extends StatefulWidget {
  const MainScannerScreen({super.key});

  @override
  State<MainScannerScreen> createState() =>
      _MainScannerScreenState();
}

class _MainScannerScreenState
    extends State<MainScannerScreen> {
  final List<DocumentItem> _items = [];

  DocumentItem? _activeItem;

  final ImagePicker _picker =
      ImagePicker();

  String _activeTabMode = 'docs';

  bool _isScanning = false;

  static const double pageWidthMm = 210.0;
  static const double pageHeightMm = 297.0;
  static const double pageMarginMm = 10.0;

  /// =============================================================
  /// GOOGLE DOCUMENT SCANNER
  /// =============================================================

  Future<void> _openGoogleScanner() async {
    if (_isScanning) {
      return;
    }

    setState(() {
      _isScanning = true;
    });

    try {
      final paths =
          await GoogleScanner.scan();

      if (!mounted) {
        return;
      }

      if (paths != null && paths.isNotEmpty) {
        int added = 0;

        for (final path in paths) {
          try {
            final file = File(path);

            if (!await file.exists()) {
              continue;
            }

            final bytes =
                await file.readAsBytes();

            final decoded =
                ImageUtils.decodeBytes(bytes);

            if (decoded == null) {
              continue;
            }

            _addDecodedImage(
              decoded,
              isPhoto: false,
              curved: false,
            );

            added++;
          } catch (e) {
            debugPrint(
              'Google image processing error: $e',
            );
          }
        }

        if (added > 0) {
          _showMessage(
            'تم المسح بواسطة Google Scanner بنجاح',
          );
        } else {
          _showMessage(
            'لم يتم العثور على صور صالحة',
            error: true,
          );
        }
      }
    } catch (e) {
      debugPrint(
        'Google Scanner execution error: $e',
      );

      if (mounted) {
        _showMessage(
          'تعذر تشغيل ماسح Google',
          error: true,
        );
      }
    } finally {
      if (mounted) {
        setState(() {
          _isScanning = false;
        });
      }
    }
  }

  /// =============================================================
  /// MANUAL CAMERA / GALLERY
  /// =============================================================

  Future<void> _addManualImages(
    ImageSource source,
  ) async {
    try {
      if (source == ImageSource.camera) {
        final photo =
            await _picker.pickImage(
          source: ImageSource.camera,
          imageQuality: 95,
        );

        if (photo == null) {
          return;
        }

        final bytes =
            await File(photo.path).readAsBytes();

        final decoded =
            ImageUtils.decodeBytes(bytes);

        if (decoded != null) {
          await _processImageWithCropScreen(
            decoded,
            isPhoto:
                _activeTabMode == 'photos',
          );
        }

        return;
      }

      final files =
          await _picker.pickMultiImage(
        imageQuality: 95,
      );

      for (final file in files) {
        final bytes =
            await File(file.path).readAsBytes();

        final decoded =
            ImageUtils.decodeBytes(bytes);

        if (decoded != null) {
          await _processImageWithCropScreen(
            decoded,
            isPhoto:
                _activeTabMode == 'photos',
          );
        }
      }
    } catch (e) {
      if (mounted) {
        _showMessage(
          'خطأ في جلب الصور: $e',
          error: true,
        );
      }
    }
  }

  /// =============================================================
  /// CROP SCREEN
  /// =============================================================

  Future<void> _processImageWithCropScreen(
    img.Image decoded, {
    bool isPhoto = false,
  }) async {
    if (!mounted) {
      return;
    }

    if (isPhoto) {
      _addDecodedImage(
        decoded,
        isPhoto: true,
        curved: false,
      );

      return;
    }

    final result =
        await Navigator.push<img.Image>(
      context,
      MaterialPageRoute(
        builder: (_) => CropScreen(
          image: decoded,
        ),
      ),
    );

    if (result != null && mounted) {
      _addDecodedImage(
        result,
        isPhoto: false,
        curved: true,
      );
    }
  }

  /// =============================================================
  /// ADD IMAGE
  /// =============================================================

  void _addDecodedImage(
    img.Image decodedImage, {
    bool isPhoto = false,
    bool curved = false,
  }) {
    if (!ImageUtils.isValid(decodedImage)) {
      _showMessage(
        'الصورة غير صالحة',
        error: true,
      );

      return;
    }

    final encodedBytes =
        ImageUtils.encodeJpg(
      decodedImage,
      quality: 95,
    );

    if (!mounted) {
      return;
    }

    setState(() {
      final photoMode =
          isPhoto ||
          _activeTabMode == 'photos';

      final width =
          photoMode ? 36.0 : 85.0;

      final ratio =
          decodedImage.height /
              decodedImage.width;

      final height =
          photoMode
              ? 45.0
              : width * ratio;

      final offset =
          _items.length * 4.0;

      final item = DocumentItem(
        id: DateTime.now()
            .microsecondsSinceEpoch
            .toString(),
        image: decodedImage,
        cachedBytes: encodedBytes,
        widthMm: width,
        heightMm: height,
        xMm:
            pageMarginMm + offset,
        yMm:
            pageMarginMm + offset,
        isPhotoMode: photoMode,
        hasCurvedCorners: curved,
      );

      _items.add(item);

      _activeItem = item;
    });
  }

  /// =============================================================
  /// RESIZE
  /// =============================================================

  void _resizeActiveItem(
    double width,
    double height, {
    bool isPhoto = false,
    bool curved = false,
  }) {
    if (_activeItem == null) {
      return;
    }

    setState(() {
      _activeItem!.widthMm = width;
      _activeItem!.heightMm = height;
      _activeItem!.isPhotoMode = isPhoto;
      _activeItem!.hasCurvedCorners = curved;
    });
  }

  /// =============================================================
  /// ROTATE
  /// =============================================================

  void _rotateActiveItem() {
    if (_activeItem == null) {
      return;
    }

    setState(() {
      _activeItem!.rotationAngle =
          (_activeItem!.rotationAngle + 90) %
              360;

      _activeItem!.applyRotation();
    });
  }

  /// =============================================================
  /// DUPLICATE
  /// =============================================================

  void _duplicateActiveItem() {
    final source = _activeItem;

    if (source == null) {
      return;
    }

    setState(() {
      final duplicate =
          DocumentItem(
        id: DateTime.now()
            .microsecondsSinceEpoch
            .toString(),
        image:
            img.Image.from(source.image),
        cachedBytes:
            Uint8List.fromList(
          source.cachedBytes,
        ),
        widthMm:
            source.widthMm,
        heightMm:
            source.heightMm,
        xMm:
            source.xMm + 5,
        yMm:
            source.yMm + 5,
        rotationAngle:
            source.rotationAngle,
        isPhotoMode:
            source.isPhotoMode,
        hasCurvedCorners:
            source.hasCurvedCorners,
      );

      _items.add(duplicate);

      _activeItem = duplicate;
    });
  }

  /// =============================================================
  /// AUTO ALIGN
  /// =============================================================

  void _autoAlignItems() {
    if (_items.isEmpty) {
      return;
    }

    setState(() {
      double currentX =
          pageMarginMm;

      double currentY =
          pageMarginMm;

      double rowHeight = 0;

      for (final item in _items) {
        if (currentX +
                item.widthMm >
            pageWidthMm -
                pageMarginMm) {
          currentX =
              pageMarginMm;

          currentY +=
              rowHeight + 5;

          rowHeight = 0;
        }

        item.xMm = currentX;
        item.yMm = currentY;

        currentX +=
            item.widthMm + 5;

        rowHeight =
            math.max(
          rowHeight,
          item.heightMm,
        );
      }
    });
  }

  /// =============================================================
  /// MANUAL CROP
  /// =============================================================

  Future<void> _manualCropActiveItem() async {
    final active = _activeItem;

    if (active == null) {
      return;
    }

    final result =
        await Navigator.push<img.Image>(
      context,
      MaterialPageRoute(
        builder: (_) => CropScreen(
          image: active.rotatedImage,
        ),
      ),
    );

    if (result != null && mounted) {
      setState(() {
        active.replaceImage(result);
      });
    }
  }

  /// =============================================================
  /// DELETE
  /// =============================================================

  void _deleteActiveItem() {
    if (_activeItem == null) {
      return;
    }

    setState(() {
      _items.remove(_activeItem);

      _activeItem =
          _items.isEmpty
              ? null
              : _items.last;
    });
  }

  /// =============================================================
  /// PRINT / PDF
  /// =============================================================

  Future<void> _exportAndPrint() async {
    if (_items.isEmpty) {
      _showMessage(
        'لا توجد مستندات للطباعة',
        error: true,
      );

      return;
    }

    try {
      final pdf = pw.Document();

      pdf.addPage(
        pw.Page(
          pageFormat:
              PdfPageFormat.a4,
          margin:
              pw.EdgeInsets.zero,
          build: (context) {
            return pw.Stack(
              children:
                  _items.map((item) {
                final rotated =
                    item.rotatedImage;

                final bytes =
                    ImageUtils.encodeJpg(
                  rotated,
                  quality: 95,
                );

                return pw.Positioned(
                  left:
                      item.xMm *
                          PdfPageFormat.mm,
                  top:
                      item.yMm *
                          PdfPageFormat.mm,
                  child: pw.ClipRRect(
                    horizontalRadius:
                        item.hasCurvedCorners
                            ? 3.5 *
                                PdfPageFormat.mm
                            : 0,
                    verticalRadius:
                        item.hasCurvedCorners
                            ? 3.5 *
                                PdfPageFormat.mm
                            : 0,
                    child: pw.SizedBox(
                      width:
                          item.widthMm *
                              PdfPageFormat.mm,
                      height:
                          item.heightMm *
                              PdfPageFormat.mm,
                      child: pw.Image(
                        pw.MemoryImage(
                          bytes,
                        ),
                        fit:
                            pw.BoxFit.fill,
                      ),
                    ),
                  ),
                );
              }).toList(),
            );
          },
        ),
      );

      await Printing.layoutPdf(
        onLayout:
            (format) async =>
                pdf.save(),
      );
    } catch (e) {
      if (mounted) {
        _showMessage(
          'خطأ أثناء تجهيز الطباعة: $e',
          error: true,
        );
      }
    }
  }

  /// =============================================================
  /// MESSAGE
  /// =============================================================

  void _showMessage(
    String message, {
    bool error = false,
  }) {
    if (!mounted) {
      return;
    }

    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(
          content: Text(
            message,
            textDirection:
                TextDirection.rtl,
          ),
          backgroundColor:
              error
                  ? Colors.red.shade800
                  : null,
        ),
      );
  }

  /// =============================================================
  /// BUILD
  /// =============================================================

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor:
          const Color(0xFF0F172A),

      appBar: AppBar(
        title: const Text(
          'مكتب علاء الحديدي - نظام الطباعة الاحترافي',
          style: TextStyle(
            fontSize: 13,
            fontWeight: FontWeight.bold,
          ),
        ),

        backgroundColor:
            const Color(0xFF1E293B),

        foregroundColor:
            Colors.white,

        elevation: 0,

        actions: [
          IconButton(
            tooltip:
                'طباعة المستندات',
            icon:
                const Icon(
              Icons.print_outlined,
            ),
            onPressed:
                _exportAndPrint,
          ),

          /// ======================================================
          /// GOOGLE SCANNER
          /// ======================================================

          IconButton(
            tooltip:
                'ماسح Google الذكي',
            icon: _isScanning
                ? const SizedBox(
                    width: 18,
                    height: 18,
                    child:
                        CircularProgressIndicator(
                      strokeWidth: 2,
                      color: Colors.white,
                    ),
                  )
                : const Icon(
                    Icons.document_scanner,
                  ),
            onPressed:
                _isScanning
                    ? null
                    : _openGoogleScanner,
          ),

          IconButton(
            tooltip:
                'استيراد من المعرض',
            icon:
                const Icon(
              Icons.photo_library_outlined,
            ),
            onPressed: () =>
                _addManualImages(
              ImageSource.gallery,
            ),
          ),
        ],
      ),

      body: Column(
        children: [
          /// ======================================================
          /// TOP TOOLS
          /// ======================================================

          Container(
            height: 48,
            color:
                const Color(0xFF111827),

            child: ListView(
              scrollDirection:
                  Axis.horizontal,

              padding:
                  const EdgeInsets.symmetric(
                horizontal: 8,
                vertical: 6,
              ),

              children: [
                _buildToolBtn(
                  'المستمسكات',
                  Icons.badge_outlined,
                  _activeTabMode ==
                      'docs',
                  () => setState(
                    () =>
                        _activeTabMode =
                            'docs',
                  ),
                ),

                _buildToolBtn(
                  'الصور الشخصية',
                  Icons.person_outline,
                  _activeTabMode ==
                      'photos',
                  () => setState(
                    () =>
                        _activeTabMode =
                            'photos',
                  ),
                ),

                const VerticalDivider(
                  color:
                      Colors.white24,
                  indent: 4,
                  endIndent: 4,
                ),

                _buildActionBtn(
                  'قص وتوضيح سحري',
                  Icons.crop,
                  _manualCropActiveItem,
                  const Color(
                    0xFF0EA5E9,
                  ),
                ),

                _buildActionBtn(
                  'تنسيق تلقائي',
                  Icons.grid_view,
                  _autoAlignItems,
                  const Color(
                    0xFF10B981,
                  ),
                ),

                _buildActionBtn(
                  'تدوير',
                  Icons.rotate_right,
                  _rotateActiveItem,
                  const Color(
                    0xFF64748B,
                  ),
                ),

                _buildActionBtn(
                  'نسخ',
                  Icons.copy_all,
                  _duplicateActiveItem,
                  const Color(
                    0xFF8B5CF6,
                  ),
                ),
              ],
            ),
          ),

          /// ======================================================
          /// CONTENT
          /// ======================================================

          Expanded(
            child: Row(
              children: [
                /// =================================================
                /// LEFT PANEL
                /// =================================================

                Container(
                  width: 110,
                  color:
                      const Color(
                    0xFF1E293B,
                  ),

                  child: Column(
                    children: [
                      Container(
                        padding:
                            const EdgeInsets.symmetric(
                          vertical: 8,
                        ),

                        width:
                            double.infinity,

                        color:
                            const Color(
                          0xFF0F172A,
                        ),

                        child:
                            const Text(
                          'المقاسات القياسية',
                          textAlign:
                              TextAlign.center,
                          style:
                              TextStyle(
                            color:
                                Colors.white70,
                            fontSize: 10,
                            fontWeight:
                                FontWeight.bold,
                          ),
                        ),
                      ),

                      Expanded(
                        child:
                            ListView(
                          padding:
                              const EdgeInsets.all(
                            6,
                          ),

                          children:
                              _activeTabMode ==
                                      'docs'
                                  ? [
                                      _buildSizeBtn(
                                        'بطاقة موحدة',
                                        '8.5 × 5.4 سم',
                                        () =>
                                            _resizeActiveItem(
                                          85,
                                          54,
                                          curved:
                                              true,
                                        ),
                                      ),

                                      _buildSizeBtn(
                                        'بطاقة سكن',
                                        '8.8 × 5.8 سم',
                                        () =>
                                            _resizeActiveItem(
                                          88,
                                          58,
                                          curved:
                                              true,
                                        ),
                                      ),

                                      _buildSizeBtn(
                                        'ورقة A4',
                                        '21 × 29.7 سم',
                                        () =>
                                            _resizeActiveItem(
                                          210,
                                          297,
                                          curved:
                                              false,
                                        ),
                                        clr:
                                            const Color(
                                          0xFF0D9488,
                                        ),
                                      ),
                                    ]
                                  : [
                                      _buildSizeBtn(
                                        'صورة معاملة',
                                        '3.6 × 4.5 سم',
                                        () =>
                                            _resizeActiveItem(
                                          36,
                                          45,
                                          isPhoto:
                                              true,
                                        ),
                                      ),

                                      _buildSizeBtn(
                                        'صورة مصغرة',
                                        '2.5 × 3.4 سم',
                                        () =>
                                            _resizeActiveItem(
                                          25,
                                          34,
                                          isPhoto:
                                              true,
                                        ),
                                      ),
                                    ],
                        ),
                      ),

                      if (_activeItem != null)
                        Padding(
                          padding:
                              const EdgeInsets.all(
                            6,
                          ),

                          child:
                              SizedBox(
                            width:
                                double.infinity,

                            child:
                                ElevatedButton.icon(
                              style:
                                  ElevatedButton.styleFrom(
                                backgroundColor:
                                    const Color(
                                  0xFFDC2626,
                                ),
                                foregroundColor:
                                    Colors.white,
                                elevation: 0,
                                padding:
                                    const EdgeInsets.symmetric(
                                  vertical: 8,
                                ),
                                shape:
                                    RoundedRectangleBorder(
                                  borderRadius:
                                      BorderRadius.circular(
                                    6,
                                  ),
                                ),
                              ),

                              onPressed:
                                  _deleteActiveItem,

                              icon:
                                  const Icon(
                                Icons
                                    .delete_sweep_outlined,
                                size: 16,
                              ),

                              label:
                                  const Text(
                                'حذف العنصر',
                                style:
                                    TextStyle(
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

                /// =================================================
                /// A4 WORKSPACE
                /// =================================================

                Expanded(
                  child:
                      Container(
                    color:
                        const Color(
                      0xFF090D16,
                    ),

                    child:
                        Center(
                      child:
                          LayoutBuilder(
                        builder:
                            (
                          context,
                          constraints,
                        ) {
                          final scaleX =
                              (constraints
                                          .maxWidth -
                                      30) /
                                  pageWidthMm;

                          final scaleY =
                              (constraints
                                          .maxHeight -
                                      30) /
                                  pageHeightMm;

                          final scale =
                              math.min(
                            scaleX,
                            scaleY,
                          );

                          return Container(
                            width:
                                pageWidthMm *
                                    scale,

                            height:
                                pageHeightMm *
                                    scale,

                            decoration:
                                BoxDecoration(
                              color:
                                  Colors.white,

                              boxShadow: [
                                BoxShadow(
                                  color: Colors
                                      .black
                                      .withAlpha(
                                    153,
                                  ),
                                  blurRadius:
                                      16,
                                  offset:
                                      const Offset(
                                    0,
                                    4,
                                  ),
                                ),
                              ],
                            ),

                            child:
                                Stack(
                              children:
                                  _items.map(
                                (item) {
                                  final active =
                                      _activeItem
                                              ?.id ==
                                          item.id;

                                  final radius =
                                      item.hasCurvedCorners
                                          ? BorderRadius
                                              .circular(
                                              3.5 *
                                                  scale,
                                            )
                                          : BorderRadius
                                              .zero;

                                  return Positioned(
                                    left:
                                        item.xMm *
                                            scale,

                                    top:
                                        item.yMm *
                                            scale,

                                    width:
                                        item.widthMm *
                                            scale,

                                    height:
                                        item.heightMm *
                                            scale,

                                    child:
                                        GestureDetector(
                                      onTap:
                                          () =>
                                              setState(
                                        () =>
                                            _activeItem =
                                                item,
                                      ),

                                      onPanUpdate:
                                          (details) {
                                        setState(
                                          () {
                                            item.xMm +=
                                                details
                                                        .delta
                                                        .dx /
                                                    scale;

                                            item.yMm +=
                                                details
                                                        .delta
                                                        .dy /
                                                    scale;
                                          },
                                        );
                                      },

                                      child:
                                          Container(
                                        decoration:
                                            BoxDecoration(
                                          borderRadius:
                                              radius,

                                          border:
                                              Border.all(
                                            color:
                                                active
                                                    ? const Color(
                                                        0xFF0284C7,
                                                      )
                                                    : Colors
                                                        .transparent,

                                            width:
                                                active
                                                    ? 2
                                                    : 1,
                                          ),
                                        ),

                                        child:
                                            ClipRRect(
                                          borderRadius:
                                              radius,

                                          child:
                                              Image.memory(
                                            item.cachedBytes,
                                            fit:
                                                BoxFit.fill,
                                          ),
                                        ),
                                      ),
                                    ),
                                  );
                                },
                              ).toList(),
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

  /// =============================================================
  /// TOOL BUTTON
  /// =============================================================

  Widget _buildToolBtn(
    String label,
    IconData icon,
    bool selected,
    VoidCallback onTap,
  ) {
    return Padding(
      padding:
          const EdgeInsets.symmetric(
        horizontal: 3,
      ),

      child:
          InkWell(
        onTap: onTap,
        borderRadius:
            BorderRadius.circular(
          6,
        ),

        child:
            Container(
          padding:
              const EdgeInsets.symmetric(
            horizontal: 10,
            vertical: 4,
          ),

          decoration:
              BoxDecoration(
            color:
                selected
                    ? const Color(
                        0xFF0284C7,
                      ).withAlpha(51)
                    : Colors.transparent,

            borderRadius:
                BorderRadius.circular(
              6,
            ),

            border:
                Border.all(
              color:
                  selected
                      ? const Color(
                          0xFF0284C7,
                        )
                      : Colors.white24,
            ),
          ),

          child:
              Row(
            children: [
              Icon(
                icon,
                size: 14,
                color:
                    selected
                        ? const Color(
                            0xFF38BDF8,
                          )
                        : Colors.white70,
              ),

              const SizedBox(
                width: 5,
              ),

              Text(
                label,
                style:
                    TextStyle(
                  fontSize: 11,
                  fontWeight:
                      FontWeight.bold,
                  color:
                      selected
                          ? const Color(
                              0xFF38BDF8,
                            )
                          : Colors.white70,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  /// =============================================================
  /// ACTION BUTTON
  /// =============================================================

  Widget _buildActionBtn(
    String label,
    IconData icon,
    VoidCallback onTap,
    Color color,
  ) {
    return Padding(
      padding:
          const EdgeInsets.symmetric(
        horizontal: 3,
      ),

      child:
          InkWell(
        onTap: onTap,
        borderRadius:
            BorderRadius.circular(
          6,
        ),

        child:
            Container(
          padding:
              const EdgeInsets.symmetric(
            horizontal: 8,
            vertical: 4,
          ),

          decoration:
              BoxDecoration(
            color:
                color.withAlpha(38),

            borderRadius:
                BorderRadius.circular(
              6,
            ),

            border:
                Border.all(
              color:
                  color.withAlpha(102),
            ),
          ),

          child:
              Row(
            children: [
              Icon(
                icon,
                size: 14,
                color: color,
              ),

              const SizedBox(
                width: 4,
              ),

              Text(
                label,
                style:
                    TextStyle(
                  fontSize: 10,
                  fontWeight:
                      FontWeight.bold,
                  color: color,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  /// =============================================================
  /// SIZE BUTTON
  /// =============================================================

  Widget _buildSizeBtn(
    String title,
    String subtitle,
    VoidCallback onTap, {
    Color clr =
        const Color(0xFF0284C7),
  }) {
    return Padding(
      padding:
          const EdgeInsets.symmetric(
        vertical: 3,
      ),

      child:
          ElevatedButton(
        style:
            ElevatedButton.styleFrom(
          padding:
              const EdgeInsets.symmetric(
            vertical: 6,
            horizontal: 4,
          ),

          backgroundColor:
              clr.withAlpha(30),

          foregroundColor:
              clr,

          side:
              BorderSide(
            color:
                clr.withAlpha(76),
          ),

          shape:
              RoundedRectangleBorder(
            borderRadius:
                BorderRadius.circular(
              6,
            ),
          ),

          elevation: 0,
        ),

        onPressed: onTap,

        child:
            Column(
          children: [
            Text(
              title,
              style:
                  TextStyle(
                fontSize: 10,
                fontWeight:
                    FontWeight.bold,
                color: clr,
              ),
            ),

            const SizedBox(
              height: 2,
            ),

            Text(
              subtitle,
              style:
                  TextStyle(
                fontSize: 8,
                color:
                    clr.withAlpha(204),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// ===============================================================
/// CROP PAINTER
/// ===============================================================

class CropBoxPainter
    extends CustomPainter {
  final Offset p1;
  final Offset p2;
  final Offset p3;
  final Offset p4;

  CropBoxPainter(
    this.p1,
    this.p2,
    this.p3,
    this.p4,
  );

  @override
  void paint(
    Canvas canvas,
    Size size,
  ) {
    final paint = Paint()
      ..color =
          const Color(
        0xFF0284C7,
      ).withAlpha(220)
      ..strokeWidth = 2.5
      ..style =
          PaintingStyle.stroke
      ..strokeJoin =
          StrokeJoin.round;

    final path =
        Path()
          ..moveTo(
            p1.dx,
            p1.dy,
          )
          ..lineTo(
            p2.dx,
            p2.dy,
          )
          ..lineTo(
            p3.dx,
            p3.dy,
          )
          ..lineTo(
            p4.dx,
            p4.dy,
          )
          ..close();

    canvas.drawPath(
      path,
      paint,
    );
  }

  @override
  bool shouldRepaint(
    covariant CustomPainter oldDelegate,
  ) {
    return true;
  }
}

/// ===============================================================
/// CROP SCREEN
/// ===============================================================

class CropScreen
    extends StatefulWidget {
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
  double _x1 = 0.05;
  double _y1 = 0.05;

  double _x2 = 0.95;
  double _y2 = 0.05;

  double _x3 = 0.95;
  double _y3 = 0.95;

  double _x4 = 0.05;
  double _y4 = 0.95;

  EnhanceMode _filter =
      EnhanceMode.none;

  double _filterIntensity =
      0.8;

  late Uint8List _displayBytes;

  @override
  void initState() {
    super.initState();

    _updateDisplayBytes();
  }

  void _updateDisplayBytes() {
    final processed =
        ImageEnhancer.apply(
      widget.image,
      _filter,
      _filterIntensity,
    );

    _displayBytes =
        ImageUtils.encodeJpg(
      processed,
      quality: 92,
    );
  }

  void _autoCrop() {
    setState(() {
      _x1 = 0.05;
      _y1 = 0.05;

      _x2 = 0.95;
      _y2 = 0.05;

      _x3 = 0.95;
      _y3 = 0.95;

      _x4 = 0.05;
      _y4 = 0.95;
    });
  }

  void _applyCrop() {
    var cropped =
        ManualCrop.cropPerspective(
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

    cropped =
        ImageEnhancer.apply(
      cropped,
      _filter,
      _filterIntensity,
    );

    Navigator.pop(
      context,
      cropped,
    );
  }

  @override
  Widget build(
    BuildContext context,
  ) {
    return Scaffold(
      backgroundColor:
          Colors.black,

      appBar: AppBar(
        backgroundColor:
            const Color(
          0xFF1E293B,
        ),

        leading:
            IconButton(
          icon:
              const Icon(
            Icons.close,
            color:
                Colors.white,
          ),
          onPressed:
              () =>
                  Navigator.pop(
            context,
          ),
        ),

        title:
            SingleChildScrollView(
          scrollDirection:
              Axis.horizontal,

          child:
              Row(
            children: [
              _filterChip(
                'أصلي',
                _filter ==
                    EnhanceMode.none,
                () {
                  setState(() {
                    _filter =
                        EnhanceMode.none;
                    _updateDisplayBytes();
                  });
                },
              ),

              const SizedBox(
                width: 4,
              ),

              _filterChip(
                'تحسين سحري ✨',
                _filter ==
                    EnhanceMode.magic,
                () {
                  setState(() {
                    _filter =
                        EnhanceMode.magic;
                    _updateDisplayBytes();
                  });
                },
              ),

              const SizedBox(
                width: 4,
              ),

              _filterChip(
                'أبيض وأسود رسمي',
                _filter ==
                    EnhanceMode.bw,
                () {
                  setState(() {
                    _filter =
                        EnhanceMode.bw;
                    _updateDisplayBytes();
                  });
                },
              ),
            ],
          ),
        ),

        actions: [
          IconButton(
            tooltip:
                'تحديد تقريبي',
            icon:
                const Icon(
              Icons
                  .auto_awesome_mosaic,
              color:
                  Colors.amber,
            ),
            onPressed:
                _autoCrop,
          ),

          IconButton(
            tooltip:
                'تم والتصدير',
            icon:
                const Icon(
              Icons.check,
              color:
                  Colors.greenAccent,
            ),
            onPressed:
                _applyCrop,
          ),
        ],
      ),

      body:
          Column(
        children: [
          Expanded(
            child:
                LayoutBuilder(
              builder:
                  (
                context,
                constraints,
              ) {
                final cw =
                    constraints
                        .maxWidth;

                final ch =
                    constraints
                        .maxHeight;

                final iw =
                    widget.image.width
                        .toDouble();

                final ih =
                    widget.image.height
                        .toDouble();

                final scale =
                    math.min(
                  cw / iw,
                  ch / ih,
                );

                final imgW =
                    iw * scale;

                final imgH =
                    ih * scale;

                final imgL =
                    (cw - imgW) / 2;

                final imgT =
                    (ch - imgH) / 2;

                final p1 =
                    Offset(
                  imgL +
                      _x1 *
                          imgW,
                  imgT +
                      _y1 *
                          imgH,
                );

                final p2 =
                    Offset(
                  imgL +
                      _x2 *
                          imgW,
                  imgT +
                      _y2 *
                          imgH,
                );

                final p3 =
                    Offset(
                  imgL +
                      _x3 *
                          imgW,
                  imgT +
                      _y3 *
                          imgH,
                );

                final p4 =
                    Offset(
                  imgL +
                      _x4 *
                          imgW,
                  imgT +
                      _y4 *
                          imgH,
                );

                return Stack(
                  children: [
                    Positioned(
                      left: imgL,
                      top: imgT,
                      width: imgW,
                      height: imgH,
                      child:
                          Image.memory(
                        _displayBytes,
                        fit:
                            BoxFit.fill,
                      ),
                    ),

                    Positioned.fill(
                      child:
                          CustomPaint(
                        painter:
                            CropBoxPainter(
                          p1,
                          p2,
                          p3,
                          p4,
                        ),
                      ),
                    ),

                    _buildCornerDot(
                      _x1,
                      _y1,
                      imgL,
                      imgT,
                      imgW,
                      imgH,
                      (
                        nx,
                        ny,
                      ) {
                        setState(() {
                          _x1 = nx;
                          _y1 = ny;
                        });
                      },
                    ),

                    _buildCornerDot(
                      _x2,
                      _y2,
                      imgL,
                      imgT,
                      imgW,
                      imgH,
                      (
                        nx,
                        ny,
                      ) {
                        setState(() {
                          _x2 = nx;
                          _y2 = ny;
                        });
                      },
                    ),

                    _buildCornerDot(
                      _x3,
                      _y3,
                      imgL,
                      imgT,
                      imgW,
                      imgH,
                      (
                        nx,
                        ny,
                      ) {
                        setState(() {
                          _x3 = nx;
                          _y3 = ny;
                        });
                      },
                    ),

                    _buildCornerDot(
                      _x4,
                      _y4,
                      imgL,
                      imgT,
                      imgW,
                      imgH,
                      (
                        nx,
                        ny,
                      ) {
                        setState(() {
                          _x4 = nx;
                          _y4 = ny;
                        });
                      },
                    ),
                  ],
                );
              },
            ),
          ),

          if (_filter !=
              EnhanceMode.none)
            Container(
              color:
                  const Color(
                0xFF1E293B,
              ),

              padding:
                  const EdgeInsets.symmetric(
                horizontal: 16,
                vertical: 8,
              ),

              child:
                  Row(
                children: [
                  const Icon(
                    Icons.contrast,
                    color:
                        Colors.white70,
                    size: 18,
                  ),

                  const SizedBox(
                    width: 8,
                  ),

                  Expanded(
                    child:
                        Slider(
                      value:
                          _filterIntensity,
                      min: 0.0,
                      max: 2.0,
                      activeColor:
                          const Color(
                        0xFF38BDF8,
                      ),
                      inactiveColor:
                          Colors.white24,
                      onChanged:
                          (val) {
                        setState(() {
                          _filterIntensity =
                              val;
                          _updateDisplayBytes();
                        });
                      },
                    ),
                  ),

                  Text(
                    '${(_filterIntensity * 50).toInt()}%',
                    style:
                        const TextStyle(
                      color:
                          Colors.white,
                      fontSize: 12,
                    ),
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildCornerDot(
    double rx,
    double ry,
    double il,
    double it,
    double iw,
    double ih,
    void Function(
      double,
      double,
    ) onMove,
  ) {
    return Positioned(
      left:
          il +
              rx * iw -
              18,

      top:
          it +
              ry * ih -
              18,

      child:
          GestureDetector(
        onPanUpdate:
            (details) {
          final currentX =
              il +
                  rx * iw;

          final currentY =
              it +
                  ry * ih;

          final newX =
              ((currentX +
                          details
                              .delta
                              .dx -
                      il) /
                  iw)
              .clamp(
            0.0,
            1.0,
          );

          final newY =
              ((currentY +
                          details
                              .delta
                              .dy -
                      it) /
                  ih)
              .clamp(
            0.0,
            1.0,
          );

          onMove(
            newX,
            newY,
          );
        },

        child:
            Container(
          width: 36,
          height: 36,

          decoration:
              BoxDecoration(
            color:
                const Color(
              0xFF0284C7,
            ).withAlpha(230),

            shape:
                BoxShape.circle,

            border:
                Border.all(
              color:
                  Colors.white,
              width: 2,
            ),

            boxShadow:
                const [
              BoxShadow(
                color:
                    Colors.black45,
                blurRadius:
                    4,
              ),
            ],
          ),

          child:
              const Icon(
            Icons.control_camera,
            size: 16,
            color:
                Colors.white,
          ),
        ),
      ),
    );
  }

  Widget _filterChip(
    String label,
    bool selected,
    VoidCallback onTap,
  ) {
    return GestureDetector(
      onTap: onTap,

      child:
          Container(
        padding:
            const EdgeInsets.symmetric(
          horizontal: 10,
          vertical: 5,
        ),

        decoration:
            BoxDecoration(
          color:
              selected
                  ? const Color(
                      0xFF0284C7,
                    )
                  : Colors.white12,

          borderRadius:
              BorderRadius.circular(
            6,
          ),
        ),

        child:
            Text(
          label,
          style:
              TextStyle(
            color:
                selected
                    ? Colors.white
                    : Colors.white70,
            fontSize: 10,
            fontWeight:
                FontWeight.bold,
          ),
        ),
      ),
    );
  }
}
