import 'dart:io';
import 'dart:math';
import 'package:flutter/foundation.dart';
import 'package:tflite_flutter/tflite_flutter.dart';
import 'package:image/image.dart' as img;

class AIDocumentDetector {
  late Interpreter _interpreter;
  bool _isLoaded = false;

  /// دالة التهيئة والفحص (تمت إضافتها لتتوافق مع main.dart)
  Future<void> inspectModel() async {
    await loadModel();
    if (_isLoaded) {
      debugPrint("تم فحص النموذج بنجاح.");
      // يمكنك تفعيل السطرين التاليين إذا أردت طباعة أبعاد النموذج في الكونسول
      // debugPrint("المدخلات: ${_interpreter.getInputTensors().map((t) => t.shape)}");
      // debugPrint("المخرجات: ${_interpreter.getOutputTensors().map((t) => t.shape)}");
    }
  }

  /// تحميل النموذج
  Future<void> loadModel() async {
    try {
      _interpreter = await Interpreter.fromAsset('assets/border_detect_224.tflite');
      _isLoaded = true;
      debugPrint("تم تحميل نموذج الذكاء الاصطناعي بنجاح.");
    } catch (e) {
      debugPrint("خطأ في تحميل النموذج: $e");
    }
  }

  /// الدالة الرئيسية: (تم تغيير الاسم من processImage إلى detect لتتوافق مع main.dart)
  Future<List<Point<double>>> detect(String imagePath) async {
    if (!_isLoaded) {
      await loadModel();
    }

    // أ. تجهيز الصورة (Pre-processing)
    var inputImage = await _prepareImage(imagePath);
    
    // ب. الحصول على مخرجات النموذج وبناء خريطة الاستقبال
    var outputTensors = _interpreter.getOutputTensors();
    int cornersIndex = -1;
    Map<int, Object> outputs = {};

    for (int i = 0; i < outputTensors.length; i++) {
      var tensor = outputTensors[i];
      outputs[i] = _createEmptyBuffer(tensor.shape);
      
      // البحث عن المخرج الصحيح للزوايا بأبعاد [1, 1, 4, 2]
      if (tensor.shape.length == 4 && 
          tensor.shape[2] == 4 && 
          tensor.shape[3] == 2) {
        cornersIndex = i;
      }
    }

    if (cornersIndex == -1) {
      throw Exception("فشل: لم يتم العثور على المخرج الخاص بالزوايا في هذا النموذج.");
    }

    // ج. تشغيل النموذج
    _interpreter.runForMultipleInputs([inputImage], outputs);

    // د. استخلاص الإحداثيات (Normalized coordinates 0.0 - 1.0)
    var cornersData = outputs[cornersIndex] as List;
    var pointsArray = cornersData[0][0] as List;

    List<Point<double>> documentCorners = [];
    for (int i = 0; i < 4; i++) {
      double x = pointsArray[i][0];
      double y = pointsArray[i][1];
      documentCorners.add(Point(x, y));
    }

    return documentCorners;
  }

  /// دالة داخلية لمعالجة الصورة قبل إرسالها للنموذج
  Future<List<List<List<List<double>>>>> _prepareImage(String imagePath) async {
    final fileBytes = await File(imagePath).readAsBytes();
    img.Image? originalImage = img.decodeImage(fileBytes);

    if (originalImage == null) {
      throw Exception("فشل في فك تشفير الصورة.");
    }

    // تغيير الحجم إلى 224x224
    img.Image resizedImage = img.copyResize(originalImage, width: 224, height: 224);

    // بناء المصفوفة وتحويل الألوان إلى قيم عشرية
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
  dynamic _createEmptyBuffer(List<int> shape) {
    if (shape.isEmpty) return 0.0;
    if (shape.length == 1) return List.filled(shape[0], 0.0);
    if (shape.length == 2) return List.generate(shape[0], (_) => List.filled(shape[1], 0.0));
    if (shape.length == 3) return List.generate(shape[0], (_) => List.generate(shape[1], (_) => List.filled(shape[2], 0.0)));
    if (shape.length == 4) return List.generate(shape[0], (_) => List.generate(shape[1], (_) => List.generate(shape[2], (_) => List.filled(shape[3], 0.0))));
    return [];
  }
  
  /// إغلاق النموذج لتحرير الذاكرة عند الانتهاء
  void close() {
    if (_isLoaded) {
      _interpreter.close();
      _isLoaded = false;
    }
  }
}
