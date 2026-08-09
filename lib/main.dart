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

  DocumentItem({
    required this.id,
    required this.image,
    required this.cachedBytes,
    required this.widthMm,
    required this.heightMm,
    required this.xMm,
    required this.yMm,
  });
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

  static const double pageWidthMm = 210.0;
  static const double pageHeightMm = 297.0;

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
        final CropResult cropRes = HybridEngine.autoCrop(decodedImg);
        final finalImg = ImageEnhancer.apply(cropRes.image, EnhanceMode.soft);
        final finalBytes = Uint8List.fromList(ImageUtils.encodeJpg(finalImg, quality: 92));

        setState(() {
          final newItem = DocumentItem(
            id: DateTime.now().millisecondsSinceEpoch.toString() + i.toString(),
            image: finalImg,
            cachedBytes: finalBytes,
            widthMm: 85.0,
            heightMm: (finalImg.height.toDouble() / finalImg.width.toDouble() * 85.0),
            xMm: 10.0 + (_items.length * 4.0),
            yMm: 10.0 + (_items.length * 4.0),
          );
          _items.add(newItem);
          _activeItem = newItem;
        });
      }
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
              return pw.Positioned(
                left: item.xMm * PdfPageFormat.mm,
                top: item.yMm * PdfPageFormat.mm,
                child: pw.SizedBox(
                  width: item.widthMm * PdfPageFormat.mm,
                  height: item.heightMm * PdfPageFormat.mm,
                  child: pw.Image(pw.MemoryImage(item.cachedBytes), fit: pw.BoxFit.fill),
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
      backgroundColor: const Color(0xFF1E293B),
      appBar: AppBar(
        title: const Text('مكتب علاء الحديدي - الماسح والطباعة الذكية', style: TextStyle(fontSize: 14, fontWeight: FontWeight.bold)),
        backgroundColor: const Color(0xFF0284C7),
        foregroundColor: Colors.white,
        actions: [
          IconButton(icon: const Icon(Icons.print), onPressed: _exportAndPrint),
          IconButton(icon: const Icon(Icons.add_a_photo), onPressed: () => _addNewImages(ImageSource.camera)),
          IconButton(icon: const Icon(Icons.photo_library), onPressed: () => _addNewImages(ImageSource.gallery)),
        ],
      ),
      body: Stack(
        children: [
          Center(
            child: LayoutBuilder(
              builder: (context, constraints) {
                final scaleX = (constraints.maxWidth - 20.0) / pageWidthMm;
                final scaleY = (constraints.maxHeight - 20.0) / pageHeightMm;
                final scale = min(scaleX, scaleY);

                return Container(
                  width: pageWidthMm * scale,
                  height: pageHeightMm * scale,
                  color: Colors.white,
                  child: Stack(
                    children: _items.map((item) {
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
                              border: Border.all(color: isActive ? Colors.blue : Colors.transparent, width: 2.0),
                            ),
                            child: Image.memory(item.cachedBytes, fit: BoxFit.fill),
                          ),
                        ),
                      );
                    }).toList(),
                  ),
                );
              },
            ),
          ),
          if (_activeItem != null)
            Positioned(
              bottom: 20.0,
              left: 20.0,
              right: 20.0,
              child: Card(
                color: Colors.black87,
                child: Padding(
                  padding: const EdgeInsets.all(8.0),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                    children: [
                      ElevatedButton(
                        onPressed: () => setState(() {
                          _activeItem!.widthMm = 85.0;
                          _activeItem!.heightMm = 54.0;
                        }),
                        child: const Text('بطاقة (8.5×5.4 سم)'),
                      ),
                      IconButton(
                        icon: const Icon(Icons.delete, color: Colors.red),
                        onPressed: () => setState(() {
                          _items.remove(_activeItem);
                          _activeItem = null;
                        }),
                      )
                    ],
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}
