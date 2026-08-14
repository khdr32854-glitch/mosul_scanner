import 'dart:typed_data';
import 'dart:ui'; // تمت الإضافة من أجل استخدام Offset
import 'package:flutter/foundation.dart';
import 'package:tflite_flutter/tflite_flutter.dart';
import 'package:image/image.dart' as img;

class AIDocumentDetector {
  // تحويل المتغيرات إلى static لتتوافق مع الاستدعاء المباشر
  static Interpreter? _interpreter;
  static bool _isLoaded = false;

  /// دالة التهيئة والفحص (static)
  static Future<void> inspectModel() async {
    await loadModel();
    if (_isLoaded) {
      debugPrint("تم فحص النموذج بنجاح.");
    }
  }

  /// تحميل النموذج (static)
  static Future<void> loadModel() async {
    if (_isLoaded) return; // منع التحميل المزدوج
    try {
      _interpreter = await Interpreter.fromAsset('assets/border_detect_224.tflite');
      _isLoaded = true;
      debugPrint("تم تحميل نموذج الذكاء الاصطناعي بنجاح.");
    } catch (e) {
      debugPrint("خطأ في تحميل النموذج: $e");
    }
  }

  /// الدالة الرئيسية (static): تستقبل Uint8List وترجع List<Offset>
  static Future<List<Offset>> detect(Uint8List imageBytes) async {
    if (!_isLoaded || _interpreter == null) {
      await loadModel();
    }

    // أ. تجهيز الصورة (Pre-processing)
    var inputImage = await _prepareImage(imageBytes);
    
    // ب. الحصول على مخرجات النموذج
    var outputTensors = _interpreter!.getOutputTensors();
    int cornersIndex = -1;
    Map<int, Object> outputs = {};

    for (int i = 0; i < outputTensors.length; i++) {
      var tensor = outputTensors[i];
      outputs[i] = _createEmptyBuffer(tensor.shape);
      
      // البحث عن المخرج الصحيح
      if (tensor.shape.length == 4 && 
          tensor.shape[2] == 4 && 
          tensor.shape[3] == 2) {
        cornersIndex = i;
      }
    }

    if (cornersIndex == -1) {
      throw Exception("فشل: لم يتم العثور على المخرج الخاص بالزوايا.");
    }

    // ج. تشغيل النموذج
    _interpreter!.runForMultipleInputs([inputImage], outputs);

    // د. استخلاص الإحداثيات وتحويلها إلى Offset بدلاً من Point
    var cornersData = outputs[cornersIndex] as List;
    var pointsArray = cornersData[0][0] as List;

    List<Offset> documentCorners = [];
    for (int i = 0; i < 4; i++) {
      double x = pointsArray[i][0];
      double y = pointsArray[i][1];
      documentCorners.add(Offset(x, y)); // استخدام Offset لتوفير dx و dy
    }

    return documentCorners;
  }

  /// دالة لمعالجة الصورة مباشرة من الذاكرة (Uint8List)
  static Future<List<List<List<List<double>>>>> _prepareImage(Uint8List imageBytes) async {
    // فك التشفير مباشرة من البايتات دون الحاجة لقراءة ملف
    img.Image? originalImage = img.decodeImage(imageBytes);

    if (originalImage == null) {
      throw Exception("فشل في فك تشفير الصورة.");
    }

    // تغيير الحجم
    img.Image resizedImage = img.copyResize(originalImage, width: 224, height: 224);

    // بناء المصفوفة
    List<List<List<List<double>>>> inputMatrix = List.generate(
      1,
      (b) => List.generate(
        224,
        (y) => List.generate(
          224,
          (x) {
            final pixel = resizedImage.getPixel(x, y);
            return [
              pixel.r / 255.0,
              pixel.g / 255.0,
              pixel.b / 255.0
            ];
          },
        ),
      ),
    );

    return inputMatrix;
  }

  /// دالة مساعدة لإنشاء مصفوفات فارغة ديناميكياً
  static dynamic _createEmptyBuffer(List<int> shape) {
    if (shape.isEmpty) return 0.0;
    if (shape.length == 1) return List.filled(shape[0], 0.0);
    if (shape.length == 2) return List.generate(shape[0], (_) => List.filled(shape[1], 0.0));
    if (shape.length == 3) return List.generate(shape[0], (_) => List.generate(shape[1], (_) => List.filled(shape[2], 0.0)));
    if (shape.length == 4) return List.generate(shape[0], (_) => List.generate(shape[1], (_) => List.generate(shape[2], (_) => List.filled(shape[3], 0.0))));
    return [];
  }
  
  /// إغلاق النموذج (static)
  static void close() {
    if (_isLoaded && _interpreter != null) {
      _interpreter!.close();
      _isLoaded = false;
    }
  }
}
