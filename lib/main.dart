import 'dart:io';
import 'dart:math';
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:image/image.dart' as img;
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';

// استدعينا ملف محرك القص والماكينة الذكية
import 'crop_engine.dart';

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

  static const double pageWidthMm = 210;
  static const double pageHeightMm = 297;

  // ✅ استخدام Google ML Kit المباشر والسرعة 100% لكل الصور
  Future<void> _scanDocumentNative() async {
    try {
      final List<String> paths = await GoogleScanner.scan();

      for (int i = 0; i < paths.length; i++) {
        final bytes = await File(paths[i]).readAsBytes();
        final decodedImg = ImageUtils.decodeBytes(bytes);

        if (decodedImg != null) {
          // تطبيق فلتر ناعم مريح يحافظ على البيانات
          final enhancedImg = ImageEnhancer.apply(decodedImg, EnhanceMode.soft);
          final Uint8List finalBytes = ImageUtils.encodeJpgBytes(enhancedImg);

          setState(() {
            final newItem = DocumentItem(
              id: DateTime.now().millisecondsSinceEpoch.toString() + i.toString(),
              image: enhancedImg,
              cachedBytes: finalBytes,
              widthMm: 85,
              heightMm: (enhancedImg.height / enhancedImg.width * 85),
              xMm: 10 + (_items.length * 4),
              yMm: 10 + (_items.length * 4),
            );
            _items.add(newItem);
            _activeItem = newItem;
          });
        }
      }
    } catch (e) {
      debugPrint("خطأ في المسح: $e");
    }
  }

  // ✅ معالجة الحواف والقص الذكي الخالص في حال كانت الصورة موجودة مسبقاً
  void _runAutoSmartCrop() {
    if (_activeItem == null) return;
    final item = _activeItem!;

    // تشغيل SmartCrop المطور الذي يحتوي على 4 طرق كشف بديلة + Fallback آمن
    final CropResult result = SmartCrop.detect(item.image);

    setState(() {
      item.image = result.image;
      item.cachedBytes = ImageUtils.encodeJpgBytes(result.image);
      item.heightMm = (result.image.height / result.image.width * item.widthMm);
    });

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(result.changed ? 'تم الاقتطاع والتعديل بنجاح ✨' : 'تم الحفاظ على أبعاد المستند بنجاح 👍'),
        duration: const Duration(seconds: 2),
      ),
    );
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
        title: const Text('مكتب علاء الحديدي - الماسح والطباعة الذكية', style: TextStyle(fontSize: 14)),
        backgroundColor: const Color(0xFF0284C7),
        foregroundColor: Colors.white,
        actions: [
          IconButton(icon: const Icon(Icons.print), onPressed: _exportAndPrint),
          ElevatedButton.icon(
            style: ElevatedButton.styleFrom(backgroundColor: Colors.white, foregroundColor: const Color(0xFF0284C7)),
            onPressed: _scanDocumentNative,
            icon: const Icon(Icons.document_scanner, size: 18),
            label: const Text('مسح ضوئي محترِف', style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold)),
          ),
          const SizedBox(width: 8),
        ],
      ),
      body: Stack(
        children: [
          Center(
            child: LayoutBuilder(
              builder: (context, constraints) {
                final scaleX = (constraints.maxWidth - 20) / pageWidthMm;
                final scaleY = (constraints.maxHeight - 20) / pageHeightMm;
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
                              item.yMm += details.delta.deltaY / scale;
                            });
                          },
                          child: Container(
                            decoration: BoxDecoration(
                              border: Border.all(color: isActive ? Colors.blue : Colors.transparent, width: 2),
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
              bottom: 20,
              left: 20,
              right: 20,
              child: Card(
                color: Colors.black87,
                child: Padding(
                  padding: const EdgeInsets.all(8.0),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                    children: [
                      ElevatedButton.icon(
                        style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFFD97706), foregroundColor: Colors.white),
                        onPressed: _runAutoSmartCrop,
                        icon: const Icon(Icons.auto_fix_high, size: 16),
                        label: const Text('إعادة تعديل وتأكيد الحواف'),
                      ),
                      ElevatedButton(
                        onPressed: () => setState(() {
                          _activeItem!.widthMm = 85;
                          _activeItem!.heightMm = 54;
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
