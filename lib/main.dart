import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:image/image.dart' as img;
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';

import 'crop_engine.dart';

/// ===============================================================
/// APP START
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
      title: 'Mosul Scanner',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        useMaterial3: true,
        colorSchemeSeed: Colors.blue,
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

    if (angle == 0) {
      return image;
    }

    if (angle == 90) {
      return img.copyRotate(
        image,
        angle: 90,
      );
    }

    if (angle == 180) {
      return img.copyRotate(
        image,
        angle: 180,
      );
    }

    if (angle == 270) {
      return img.copyRotate(
        image,
        angle: 270,
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

  void replaceImage(
    img.Image newImage,
  ) {
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
/// MAIN SCREEN
/// ===============================================================

class MainScannerScreen extends StatefulWidget {
  const MainScannerScreen({
    super.key,
  });

  @override
  State<MainScannerScreen> createState() =>
      _MainScannerScreenState();
}

class _MainScannerScreenState
    extends State<MainScannerScreen> {
  /// -------------------------------------------------------------
  /// DATA
  /// -------------------------------------------------------------

  final List<DocumentItem> _items = [];

  DocumentItem? _activeItem;

  final ImagePicker _picker =
      ImagePicker();

  String _activeTabMode = 'docs';

  bool _isScanning = false;

  /// A4
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
      debugPrint(
        '==========================================',
      );
      debugPrint(
        'MOSUL SCANNER',
      );
      debugPrint(
        'Starting Google ML Kit Document Scanner',
      );
      debugPrint(
        '==========================================',
      );

      final List<String>? paths =
          await GoogleScanner.scan(
        pageLimit: 10,
        allowGallery: false,
      );

      if (!mounted) {
        return;
      }

      if (paths == null ||
          paths.isEmpty) {
        _showMessage(
          'لم يتم إرجاع أي مستند',
          error: true,
        );
        return;
      }

      int added = 0;

      for (final path in paths) {
        try {
          final file = File(path);

          if (!await file.exists()) {
            debugPrint(
              'Scanner file does not exist: $path',
            );
            continue;
          }

          final bytes =
              await file.readAsBytes();

          if (bytes.isEmpty) {
            debugPrint(
              'Scanner returned empty file: $path',
            );
            continue;
          }

          final decoded =
              img.decodeImage(bytes);

          if (decoded == null) {
            debugPrint(
              'Could not decode scanner image: $path',
            );
            continue;
          }

          _addDecodedImage(
            decoded,
            isPhoto: false,
            curved: true,
          );

          added++;
        } catch (e) {
          debugPrint(
            'Error processing scanner image: $e',
          );
        }
      }

      if (!mounted) {
        return;
      }

      if (added > 0) {
        _showMessage(
          'تم مسح $added مستند بنجاح بواسطة Google',
        );
      } else {
        _showMessage(
          'تعذر قراءة الصور الناتجة من Google',
          error: true,
        );
      }
    } catch (e, stackTrace) {
      debugPrint(
        '==========================================',
      );
      debugPrint(
        'GOOGLE SCANNER ERROR',
      );
      debugPrint('$e');
      debugPrint('$stackTrace');
      debugPrint(
        '==========================================',
      );

      if (mounted) {
        _showMessage(
          'تعذر تشغيل ماسح Google: $e',
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
  /// CAMERA / GALLERY
  /// =============================================================

  Future<void> _addNewImages(
    ImageSource source,
  ) async {
    /// -----------------------------------------------------------
    /// المستمسكات
    /// -----------------------------------------------------------

    if (source == ImageSource.camera &&
        _activeTabMode == 'docs') {
      await _openGoogleScanner();
      return;
    }

    /// -----------------------------------------------------------
    /// الصور
    /// -----------------------------------------------------------

    try {
      if (source == ImageSource.camera) {
        final XFile? photo =
            await _picker.pickImage(
          source: ImageSource.camera,
          imageQuality: 95,
        );

        if (photo == null) {
          return;
        }

        final bytes =
            await File(photo.path).readAsBytes();

        _processAndAddImage(
          bytes,
          isPhoto: true,
        );

        return;
      }

      final List<XFile> files =
          await _picker.pickMultiImage(
        imageQuality: 95,
      );

      for (final file in files) {
        final bytes =
            await File(file.path).readAsBytes();

        _processAndAddImage(
          bytes,
          isPhoto:
              _activeTabMode == 'photos',
        );
      }
    } catch (e) {
      if (!mounted) {
        return;
      }

      _showMessage(
        'خطأ في فتح الصورة: $e',
        error: true,
      );
    }
  }

  /// =============================================================
  /// PROCESS IMAGE
  /// =============================================================

  void _processAndAddImage(
    Uint8List bytes, {
    bool isPhoto = false,
  }) {
    final decoded =
        img.decodeImage(bytes);

    if (decoded == null) {
      _showMessage(
        'تعذر قراءة الصورة',
        error: true,
      );
      return;
    }

    _addDecodedImage(
      decoded,
      isPhoto: isPhoto,
      curved: !isPhoto,
    );
  }

  /// =============================================================
  /// ADD IMAGE
  /// =============================================================

  void _addDecodedImage(
    img.Image decodedImage, {
    bool isPhoto = false,
    bool curved = false,
  }) {
    if (!ImageUtils.isValid(
      decodedImage,
    )) {
      _showMessage(
        'الصورة غير صالحة',
        error: true,
      );
      return;
    }

    final encodedBytes =
        Uint8List.fromList(
      img.encodeJpg(
        decodedImage,
        quality: 95,
      ),
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

      final item =
          DocumentItem(
        id: DateTime.now()
            .microsecondsSinceEpoch
            .toString(),
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
        widthMm: source.widthMm,
        heightMm: source.heightMm,
        xMm: source.xMm + 5,
        yMm: source.yMm + 5,
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

  Future<void>
      _manualCropActiveItem() async {
    final active = _activeItem;

    if (active == null) {
      return;
    }

    final result =
        await Navigator.push<img.Image>(
      context,
      MaterialPageRoute(
        builder: (_) =>
            CropScreen(
          image: active.rotatedImage,
        ),
      ),
    );

    if (result != null &&
        mounted) {
      setState(() {
        active.replaceImage(
          result,
        );
      });
    }
  }

  /// =============================================================
  /// DELETE
  /// =============================================================

  void _deleteActiveItem() {
    final active = _activeItem;

    if (active == null) {
      return;
    }

    setState(() {
      _items.remove(active);

      if (_items.isEmpty) {
        _activeItem = null;
      } else {
        _activeItem =
            _items.last;
      }
    });
  }

  /// =============================================================
  /// PRINT / PDF
  /// =============================================================

  Future<void>
      _exportAndPrint() async {
    if (_items.isEmpty) {
      _showMessage(
        'لا توجد صور للطباعة',
        error: true,
      );
      return;
    }

    try {
      final pdf =
          pw.Document();

      pdf.addPage(
        pw.Page(
          pageFormat:
              PdfPageFormat.a4,
          margin:
              pw.EdgeInsets.zero,
          build: (context) {
            return pw.Stack(
              children:
                  _items.map(
                (item) {
                  final rotated =
                      item.rotatedImage;

                  final bytes =
                      Uint8List.fromList(
                    img.encodeJpg(
                      rotated,
                      quality: 95,
                    ),
                  );

                  return pw.Positioned(
                    left:
                        item.xMm *
                            PdfPageFormat.mm,
                    top:
                        item.yMm *
                            PdfPageFormat.mm,
                    child:
                        pw.ClipRRect(
                      horizontalRadius:
                          item.hasCurvedCorners
                              ? 3.5 *
                                  PdfPageFormat
                                      .mm
                              : 0,
                      verticalRadius:
                          item.hasCurvedCorners
                              ? 3.5 *
                                  PdfPageFormat
                                      .mm
                              : 0,
                      child:
                          pw.SizedBox(
                        width:
                            item.widthMm *
                                PdfPageFormat
                                    .mm,
                        height:
                            item.heightMm *
                                PdfPageFormat
                                    .mm,
                        child:
                            pw.Image(
                          pw.MemoryImage(
                            bytes,
                          ),
                          fit:
                              pw.BoxFit.fill,
                        ),
                      ),
                    ),
                  );
                },
              ).toList(),
            );
          },
        ),
      );

      await Printing.layoutPdf(
        onLayout:
            (format) async {
          return pdf.save();
        },
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
                  ? Colors.red
                  : null,
        ),
      );
  }

  /// =============================================================
  /// BUILD
  /// =============================================================

  @override
  Widget build(
    BuildContext context,
  ) {
    return Scaffold(
      backgroundColor:
          const Color(0xFF0F172A),

      appBar: AppBar(
        title: const Text(
          'مكتب علاء الحديدي - الماسح والطباعة',
          style: TextStyle(
            fontSize: 13,
            fontWeight:
                FontWeight.bold,
          ),
        ),
        backgroundColor:
            const Color(0xFF0284C7),
        foregroundColor:
            Colors.white,
        actions: [
          IconButton(
            tooltip: 'طباعة PDF',
            icon: const Icon(
              Icons.print,
            ),
            onPressed:
                _exportAndPrint,
          ),

          IconButton(
            tooltip:
                'ماسح Google',
            icon: _isScanning
                ? const SizedBox(
                    width: 20,
                    height: 20,
                    child:
                        CircularProgressIndicator(
                      strokeWidth: 2,
                      color:
                          Colors.white,
                    ),
                  )
                : const Icon(
                    Icons
                        .document_scanner,
                  ),
            onPressed:
                _isScanning
                    ? null
                    : () {
                        _addNewImages(
                          ImageSource
                              .camera,
                        );
                      },
          ),

          IconButton(
            tooltip:
                'المعرض',
            icon: const Icon(
              Icons
                  .photo_library,
            ),
            onPressed: () {
              _addNewImages(
                ImageSource
                    .gallery,
              );
            },
          ),
        ],
      ),

      body: Column(
        children: [
          /// =====================================================
          /// TOP TOOLS
          /// =====================================================

          Container(
            height: 50,
            color:
                const Color(
              0xFF1E293B,
            ),
            child:
                ListView(
              scrollDirection:
                  Axis.horizontal,
              padding:
                  const EdgeInsets
                      .symmetric(
                horizontal: 6,
                vertical: 6,
              ),
              children: [
                _buildToolBtn(
                  'مستمسكات',
                  _activeTabMode ==
                      'docs',
                  () {
                    setState(() {
                      _activeTabMode =
                          'docs';
                    });
                  },
                ),

                _buildToolBtn(
                  'صور',
                  _activeTabMode ==
                      'photos',
                  () {
                    setState(() {
                      _activeTabMode =
                          'photos';
                    });
                  },
                ),

                const SizedBox(
                  width: 5,
                ),

                _buildToolBtn(
                  'قص يدوي ✂️',
                  false,
                  _manualCropActiveItem,
                  const Color(
                    0xFF06B6D4,
                  ),
                ),

                _buildToolBtn(
                  'ترتيب 📐',
                  false,
                  _autoAlignItems,
                  const Color(
                    0xFF10B981,
                  ),
                ),

                _buildToolBtn(
                  'تدوير 🔄',
                  false,
                  _rotateActiveItem,
                  const Color(
                    0xFF94A3B8,
                  ),
                ),

                _buildToolBtn(
                  'نسخ 📋',
                  false,
                  _duplicateActiveItem,
                  const Color(
                    0xFFA78BFA,
                  ),
                ),
              ],
            ),
          ),

          /// =====================================================
          /// WORK AREA
          /// =====================================================

          Expanded(
            child: Row(
              children: [
                /// =================================================
                /// LEFT PANEL
                /// =================================================

                Container(
                  width: 105,
                  color:
                      const Color(
                    0xFFF8FAFC,
                  ),
                  child:
                      Column(
                    children: [
                      Container(
                        padding:
                            const EdgeInsets
                                .all(
                          6,
                        ),
                        width:
                            double.infinity,
                        color:
                            const Color(
                          0xFF0369A1,
                        ),
                        child:
                            const Text(
                          'القياسات',
                          textAlign:
                              TextAlign
                                  .center,
                          style:
                              TextStyle(
                            color:
                                Colors.white,
                            fontSize:
                                11,
                            fontWeight:
                                FontWeight
                                    .bold,
                          ),
                        ),
                      ),

                      Expanded(
                        child:
                            ListView(
                          padding:
                              const EdgeInsets
                                  .all(
                            4,
                          ),
                          children:
                              _activeTabMode ==
                                      'docs'
                                  ? [
                                      _buildSizeBtn(
                                        'بطاقة موحدة',
                                        '8.5×5.4 سم',
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
                                        '8.8×5.8 سم',
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
                                        '21×29.7 سم',
                                        () =>
                                            _resizeActiveItem(
                                          210,
                                          297,
                                          curved:
                                              false,
                                        ),
                                        clr:
                                            const Color(
                                          0xFF0F766E,
                                        ),
                                      ),
                                    ]
                                  : [
                                      _buildSizeBtn(
                                        'معاملة',
                                        '3.6×4.5 سم',
                                        () =>
                                            _resizeActiveItem(
                                          36,
                                          45,
                                          isPhoto:
                                              true,
                                        ),
                                      ),

                                      _buildSizeBtn(
                                        'مصغر',
                                        '2.5×3.4 سم',
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

                      if (_activeItem !=
                          null)
                        Padding(
                          padding:
                              const EdgeInsets
                                  .all(
                            4,
                          ),
                          child:
                              ElevatedButton.icon(
                            style:
                                ElevatedButton
                                    .styleFrom(
                              backgroundColor:
                                  Colors.red,
                              foregroundColor:
                                  Colors.white,
                              padding:
                                  const EdgeInsets
                                      .all(
                                4,
                              ),
                            ),
                            onPressed:
                                _deleteActiveItem,
                            icon:
                                const Icon(
                              Icons.delete,
                              size: 14,
                            ),
                            label:
                                const Text(
                              'حذف',
                              style:
                                  TextStyle(
                                fontSize:
                                    10,
                              ),
                            ),
                          ),
                        ),
                    ],
                  ),
                ),

                /// =================================================
                /// A4 CANVAS
                /// =================================================

                Expanded(
                  child:
                      Container(
                    color:
                        const Color(
                      0xFF0F172A,
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
                                      20) /
                                  pageWidthMm;

                          final scaleY =
                              (constraints
                                          .maxHeight -
                                      20) /
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
                                  color:
                                      Colors.black.withValues(
                                    alpha:
                                        0.5,
                                  ),
                                  blurRadius:
                                      10,
                                ),
                              ],
                            ),
                            child:
                                Stack(
                              children:
                                  _items
                                      .map(
                                (
                                  item,
                                ) {
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
                                          () {
                                        setState(
                                          () {
                                            _activeItem =
                                                item;
                                          },
                                        );
                                      },
                                      onPanUpdate:
                                          (details) {
                                        setState(
                                          () {
                                            item.xMm +=
                                                details.delta.dx /
                                                    scale;

                                            item.yMm +=
                                                details.delta.dy /
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
                                                    ? Colors.blue
                                                    : Colors.transparent,
                                            width:
                                                active
                                                    ? 2.5
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
    bool selected,
    VoidCallback onTap, [
    Color? color,
  ]) {
    final selectedColor =
        color ?? Colors.blue;

    return Padding(
      padding:
          const EdgeInsets
              .symmetric(
        horizontal: 2,
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
              const EdgeInsets
                  .symmetric(
            horizontal: 10,
            vertical: 6,
          ),
          decoration:
              BoxDecoration(
            color: selected
                ? selectedColor
                    .withValues(
                    alpha: 0.3,
                  )
                : Colors
                    .transparent,
            borderRadius:
                BorderRadius.circular(
              6,
            ),
            border:
                Border.all(
              color: selected
                  ? selectedColor
                  : Colors.white30,
            ),
          ),
          child:
              Text(
            label,
            style:
                TextStyle(
              fontSize: 11,
              fontWeight:
                  FontWeight
                      .bold,
              color: selected
                  ? selectedColor
                  : Colors.white,
            ),
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
        const Color(
      0xFF0369A1,
    ),
  }) {
    return Padding(
      padding:
          const EdgeInsets
              .symmetric(
        vertical: 3,
      ),
      child:
          ElevatedButton(
        style:
            ElevatedButton
                .styleFrom(
          padding:
              const EdgeInsets
                  .symmetric(
            vertical: 8,
          ),
          backgroundColor:
              clr.withValues(
            alpha: 0.1,
          ),
          foregroundColor:
              clr,
          side:
              BorderSide(
            color:
                clr.withValues(
              alpha: 0.4,
            ),
          ),
          shape:
              RoundedRectangleBorder(
            borderRadius:
                BorderRadius
                    .circular(
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
                    FontWeight
                        .bold,
                color: clr,
              ),
            ),
            Text(
              subtitle,
              style:
                  TextStyle(
                fontSize: 8,
                color:
                    clr.withValues(
                  alpha: 0.8,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// ===============================================================
/// MANUAL CROP SCREEN
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
      EnhanceMode.soft;

  late Uint8List
      _displayBytes;

  @override
  void initState() {
    super.initState();

    _displayBytes =
        Uint8List.fromList(
      img.encodeJpg(
        widget.image,
        quality: 92,
      ),
    );
  }

  /// =============================================================
  /// APPLY CROP
  /// =============================================================

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
    );

    Navigator.pop(
      context,
      cropped,
    );
  }

  /// =============================================================
  /// BUILD
  /// =============================================================

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
                    EnhanceMode
                        .none,
                () {
                  setState(() {
                    _filter =
                        EnhanceMode
                            .none;
                  });
                },
              ),
              const SizedBox(
                width: 4,
              ),
              _filterChip(
                'تحسين ✨',
                _filter ==
                    EnhanceMode
                        .soft,
                () {
                  setState(() {
                    _filter =
                        EnhanceMode
                            .soft;
                  });
                },
              ),
              const SizedBox(
                width: 4,
              ),
              _filterChip(
                'أبيض وأسود',
                _filter ==
                    EnhanceMode
                        .bw,
                () {
                  setState(() {
                    _filter =
                        EnhanceMode
                            .bw;
                  });
                },
              ),
            ],
          ),
        ),
        actions: [
          IconButton(
            icon:
                const Icon(
              Icons.check,
              color:
                  Colors.green,
            ),
            onPressed:
                _applyCrop,
          ),
        ],
      ),

      body:
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
                  fit: BoxFit.fill,
                ),
              ),

              _buildCornerDot(
                _x1,
                _y1,
                imgL,
                imgT,
                imgW,
                imgH,
                (nx, ny) {
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
                (nx, ny) {
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
                (nx, ny) {
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
                (nx, ny) {
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
    );
  }

  /// =============================================================
  /// CORNER DOT
  /// =============================================================

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
          20,
      top:
          it +
          ry * ih -
          20,
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
          width: 40,
          height: 40,
          decoration:
              BoxDecoration(
            color:
                Colors.blue
                    .withValues(
              alpha: 0.8,
            ),
            shape:
                BoxShape.circle,
            border:
                Border.all(
              color:
                  Colors.white,
              width: 2,
            ),
          ),
          child:
              const Icon(
            Icons.crop,
            size: 18,
            color:
                Colors.white,
          ),
        ),
      ),
    );
  }

  /// =============================================================
  /// FILTER CHIP
  /// =============================================================

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
            const EdgeInsets
                .symmetric(
          horizontal: 8,
          vertical: 4,
        ),
        decoration:
            BoxDecoration(
          color: selected
              ? Colors.blue
              : Colors.black45,
          borderRadius:
              BorderRadius
                  .circular(
            12,
          ),
        ),
        child:
            Text(
          label,
          style:
              const TextStyle(
            color:
                Colors.white,
            fontSize: 10,
          ),
        ),
      ),
    );
  }
}
