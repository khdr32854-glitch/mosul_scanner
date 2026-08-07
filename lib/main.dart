import 'dart:io';
import 'dart:math';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:image/image.dart' as img;

void main() {
  runApp(const MosulScannerApp());
}

class MosulScannerApp extends StatelessWidget {
  const MosulScannerApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'مكتب علاء الحديدي - الماسح الذكي',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        primarySwatch: Colors.sky,
        useMaterial3: true,
        fontFamily: 'sans-serif',
      ),
      home: const MainScannerScreen(),
    );
  }
}

enum PaperMode { docs, photos, photosSelphy }

class MainScannerScreen extends StatefulWidget {
  const MainScannerScreen({super.key});

  @override
  State<MainScannerScreen> createState() => _MainScannerScreenState();
}

class _MainScannerScreenState extends State<MainScannerScreen> {
  PaperMode currentMode = PaperMode.docs;
  final List<DocumentItem> _items = [];
  DocumentItem? _activeItem;
  final ImagePicker _picker = ImagePicker();

  void _addNewImage(ImageSource source) async {
    final XFile? pickedFile = await _picker.pickImage(source: source);
    if (pickedFile != null) {
      final File file = File(pickedFile.path);
      final bytes = await file.readAsBytes();
      final decodedImg = img.decodeImage(bytes);

      if (decodedImg != null) {
        setState(() {
          final newItem = DocumentItem(
            id: DateTime.now().millisecondsSinceEpoch.toString(),
            image: decodedImg,
            widthMm: 85,
            heightMm: (decodedImg.height / decodedImg.width * 85),
            xMm: 10.0 + (_items.length * 5),
            yMm: 10.0 + (_items.length * 5),
          );
          _items.add(newItem);
          _activeItem = newItem;
        });
      }
    }
  }

  void _resizeActive(double w, double h) {
    if (_activeItem == null) return;
    setState(() {
      _activeItem!.widthMm = w;
      _activeItem!.heightMm = h;
    });
  }

  void _rotateActive() {
    if (_activeItem == null) return;
    setState(() {
      _activeItem!.rotation = (_activeItem!.rotation + 90) % 360;
    });
  }

  void _openCropOverlay() async {
    if (_activeItem == null) return;

    final img.Image? cropped = await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => SmartCropScreen(image: _activeItem!.image),
      ),
    );

    if (cropped != null) {
      setState(() {
        _activeItem!.image = cropped;
        _activeItem!.heightMm = (cropped.height / cropped.width * _activeItem!.widthMm);
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('مكتب علاء الحديدي - الطباعة والقص الذكي', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
        backgroundColor: const Color(0xFF0284C7),
        foregroundColor: Colors.white,
        actions: [
          IconButton(
            icon: const Icon(Icons.add_a_photo),
            onPressed: () => _addNewImage(ImageSource.camera),
          ),
          IconButton(
            icon: const Icon(Icons.photo_library),
            onPressed: () => _addNewImage(ImageSource.gallery),
          ),
        ],
      ),
      body: Row(
        children: [
          // لوحة التحكم الجانبية
          Container(
            width: 220,
            color: Colors.white,
            padding: const EdgeInsets.all(8.0),
            child: SingleChildScrollView(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  const Text('التحكم الرئيسي', style: TextStyle(fontWeight: FontWeight.bold, color: Color(0xFF0369A1))),
                  const SizedBox(height: 8),
                  ElevatedButton.icon(
                    style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFFD97706), foregroundColor: Colors.white),
                    onPressed: _openCropOverlay,
                    icon: const Icon(Icons.crop_rotate),
                    label: const Text('القص الذكي والتحسين'),
                  ),
                  const SizedBox(height: 4),
                  ElevatedButton.icon(
                    style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFF475569), foregroundColor: Colors.white),
                    onPressed: _rotateActive,
                    icon: const Icon(Icons.rotate_right),
                    label: const Text('تدوير 90°'),
                  ),
                  const Divider(),
                  const Text('قياسات سريعة (ملم)', style: TextStyle(fontWeight: FontWeight.bold, color: Color(0xFF0369A1))),
                  const SizedBox(height: 6),
                  ElevatedButton(
                    onPressed: () => _resizeActive(85, 54),
                    child: const Text('بطاقة موحدة (8.5×5.4 سم)'),
                  ),
                  ElevatedButton(
                    onPressed: () => _resizeActive(88, 58),
                    child: const Text('بطاقة سكن (8.8×5.8 سم)'),
                  ),
                  ElevatedButton(
                    onPressed: () => _resizeActive(36, 45),
                    child: const Text('صورة معاملة (3.6×4.5 سم)'),
                  ),
                  const Divider(),
                  if (_activeItem != null)
                    ElevatedButton.icon(
                      style: ElevatedButton.styleFrom(backgroundColor: Colors.red, foregroundColor: Colors.white),
                      onPressed: () {
                        setState(() {
                          _items.remove(_activeItem);
                          _activeItem = null;
                        });
                      },
                      icon: const Icon(Icons.delete),
                      label: const Text('حذف العنصر'),
                    ),
                ],
              ),
            ),
          ),
          // منطقة ورقة العمل A4
          Expanded(
            child: Container(
              color: const Color(0xFF475569),
              child: Center(
                child: AspectRatio(
                  aspectRatio: 210 / 297, // أبعاد ورقة A4
                  child: Container(
                    decoration: BoxDecoration(
                      color: Colors.white,
                      boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.3), blurRadius: 10)],
                    ),
                    child: Stack(
                      children: _items.map((item) {
                        final isActive = _activeItem?.id == item.id;
                        return Positioned(
                          left: item.xMm * 2, // تحويل بسيط للتناسب على الشاشة
                          top: item.yMm * 2,
                          width: item.widthMm * 2,
                          height: item.heightMm * 2,
                          child: GestureDetector(
                            onTap: () => setState(() => _activeItem = item),
                            onPanUpdate: (details) {
                              setState(() {
                                item.xMm += details.delta.dx / 2;
                                item.yMm += details.delta.dy / 2;
                              });
                            },
                            child: Container(
                              decoration: BoxDecoration(
                                border: Border.all(
                                  color: isActive ? Colors.blue : Colors.transparent,
                                  width: 2,
                                ),
                              ),
                              child: Transform.rotate(
                                angle: item.rotation * pi / 180,
                                child: Image.memory(
                                  img.encodeJpg(item.image),
                                  fit: BoxFit.fill,
                                ),
                              ),
                            ),
                          ),
                        );
                      }).toList(),
                    ),
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class DocumentItem {
  String id;
  img.Image image;
  double widthMm;
  double heightMm;
  double xMm;
  double yMm;
  double rotation;

  DocumentItem({
    required this.id,
    required this.image,
    required this.widthMm,
    required this.heightMm,
    required this.xMm,
    required this.yMm,
    this.rotation = 0,
  });
}

// ==========================================
// شاشة القص الذكي الحر والتحسين المتقدم
// ==========================================
class SmartCropScreen extends StatefulWidget {
  final img.Image image;
  const SmartCropScreen({super.key, required this.image});

  @override
  State<SmartCropScreen> createState() => _SmartCropScreenState();
}

class _SmartCropScreenState extends State<SmartCropScreen> {
  late List<Offset> points;
  bool isMagicFilter = true;

  @override
  void initState() {
    super.initState();
    // تحديد زوايا تلقائية للقص الحر (10% هامش من الأطراف)
    points = [
      const Offset(0.1, 0.1),
      const Offset(0.9, 0.1),
      const Offset(0.9, 0.9),
      const Offset(0.1, 0.9),
    ];
  }

  void _applySmartMagicFilter(img.Image image) {
    // خوارزمية التبييض والتوضيح السحرية للمستمسكات
    for (int y = 0; y < image.height; y++) {
      for (int x = 0; x < image.width; x++) {
        final pixel = image.getPixel(x, y);
        int r = pixel.r.toInt();
        int g = pixel.g.toInt();
        int b = pixel.b.toInt();

        // تباين وتبييض ذكي للورقة
        r = ((r - 128) * 1.3 + 135).clamp(0, 255).toInt();
        g = ((g - 128) * 1.3 + 135).clamp(0, 255).toInt();
        b = ((b - 128) * 1.3 + 135).clamp(0, 255).toInt();

        image.setPixelRgb(x, y, r, g, b);
      }
    }
  }

  void _processCrop() {
    final src = widget.image;
    
    // استخراج المنطقة المحددة بالقص العادي أو المائل
    int minX = (points.map((p) => p.dx).reduce(min) * src.width).toInt().clamp(0, src.width - 1);
    int maxX = (points.map((p) => p.dx).reduce(max) * src.width).toInt().clamp(1, src.width);
    int minY = (points.map((p) => p.dy).reduce(min) * src.height).toInt().clamp(0, src.height - 1);
    int maxY = (points.map((p) => p.dy).reduce(max) * src.height).toInt().clamp(1, src.height);

    int cropW = max(10, maxX - minX);
    int cropH = max(10, maxY - minY);

    img.Image cropped = img.copyCrop(src, x: minX, y: minY, width: cropW, height: cropH);

    if (isMagicFilter) {
      _applySmartMagicFilter(cropped);
    }

    Navigator.pop(context, cropped);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF0F172A),
      appBar: AppBar(
        title: const Text('القص الحر والتبييض الذكي'),
        backgroundColor: Colors.black,
        foregroundColor: Colors.white,
        actions: [
          IconButton(
            icon: const Icon(Icons.check, color: Colors.greenAccent, size: 28),
            onPressed: _processCrop,
          ),
        ],
      ),
      body: Column(
        children: [
          // شريط أدوات الفلاتر والقص الذكي
          Container(
            color: Colors.black54,
            padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 16),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceEvenly,
              children: [
                FilterChip(
                  label: const Text('✨ تبييض سحري'),
                  selected: isMagicFilter,
                  onSelected: (val) => setState(() => isMagicFilter = val),
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
                  icon: const Icon(Icons.center_focus_strong),
                  label: const Text('إعادة الضبط'),
                ),
              ],
            ),
          ),
          // منطقة معاينة الصورة وسحب نقاط القص بحرية
          Expanded(
            child: LayoutBuilder(
              builder: (context, constraints) {
                final w = constraints.maxWidth;
                final h = constraints.maxHeight;

                return Stack(
                  children: [
                    Center(
                      child: Image.memory(
                        img.encodeJpg(widget.image),
                        fit: BoxFit.contain,
                      ),
                    ),
                    // رسم خطوط اتصال نقاط القص الأربعة
                    CustomPaint(
                      size: Size(w, h),
                      painter: CropLinesPainter(points: points),
                    ),
                    // مقابض سحب الزوايا الأربعة باللمس
                    ...List.generate(4, (index) {
                      return Positioned(
                        left: points[index].dx * w - 18,
                        top: points[index].dy * h - 18,
                        child: GestureDetector(
                          onPanUpdate: (details) {
                            setState(() {
                              double newX = (points[index].dx + details.delta.dx / w).clamp(0.0, 1.0);
                              double newY = (points[index].dy + details.delta.dy / h).clamp(0.0, 1.0);
                              points[index] = Offset(newX, newY);
                            });
                          },
                          child: Container(
                            width: 36,
                            height: 36,
                            decoration: BoxDecoration(
                              color: const Color(0xFF0284C7),
                              shape: BoxShape.circle,
                              border: Border.all(color: Colors.white, width: 3),
                              boxShadow: const [BoxShadow(color: Colors.black48, blurRadius: 4)],
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

// رسام الخطوط بين نقاط القص
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
