import 'dart:math';
import 'package:tflite_flutter/tflite_flutter.dart';

class DocumentScannerAI {
  late Interpreter _interpreter;

  /// 1. تهيئة وتحميل النموذج من المسار الخاص بك
  Future<void> loadModel() async {
    try {
      _interpreter = await Interpreter.fromAsset('assets/ClearScanner/border_detect_224.tflite');
      print("تم تحميل نموذج الذكاء الاصطناعي بنجاح.");
    } catch (e) {
      print("خطأ في تحميل النموذج: $e");
    }
  }

  /// 2. دالة تحليل الصورة واستخراج الزوايا الأربع
  /// ملاحظة: تأكد أن inputImage أبعادها [1, 224, 224, 3] وقيم البكسل مقسومة على 255.0
  Future<List<Point<double>>> detectCorners(List<List<List<List<double>>>> inputImage) async {
    
    // الحصول على جميع مخرجات النموذج
    var outputTensors = _interpreter.getOutputTensors();
    
    int cornersIndex = -1;
    Map<int, Object> outputs = {};

    // أ. تجهيز خريطة المخرجات (Map) والبحث التلقائي عن مخرج الزوايا
    for (var tensor in outputTensors) {
      // بناء مصفوفة فارغة لكل مخرج حسب أبعاده لاستقبال البيانات
      outputs[tensor.index] = _createEmptyBuffer(tensor.shape);

      // إذا كانت أبعاد المصفوفة هي [1, 1, 4, 2] فهذا هو مخرج الزوايا!
      if (tensor.shape.length == 4 && 
          tensor.shape[2] == 4 && 
          tensor.shape[3] == 2) {
        cornersIndex = tensor.index;
      }
    }

    if (cornersIndex == -1) {
      throw Exception("فشل: لم يتم العثور على المخرج الخاص بالزوايا في هذا النموذج.");
    }

    // ب. تشغيل النموذج بإرسال الإدخال واستقبال المخرجات المتعددة
    _interpreter.runForMultipleInputsOutputs([inputImage], outputs);

    // ج. استخلاص البيانات من المخرج الصحيح
    // البيانات ستكون متداخلة بهذا الشكل: outputs[cornersIndex][0][0][رقم الزاوية][x أو y]
    var cornersData = outputs[cornersIndex] as List;
    var pointsArray = cornersData[0][0] as List;

    List<Point<double>> documentCorners = [];
    
    for (int i = 0; i < 4; i++) {
      // إحداثيات النموذج عادة ما تكون قياسية (Normalized) بين 0.0 و 1.0
      double x = pointsArray[i][0];
      double y = pointsArray[i][1];
      documentCorners.add(Point(x, y));
    }

    return documentCorners;
  }

  /// 3. دالة مساعدة لإنشاء مصفوفات فارغة ديناميكياً لتجنب أخطاء TFLite
  dynamic _createEmptyBuffer(List<int> shape) {
    if (shape.isEmpty) return 0.0;
    if (shape.length == 1) return List.filled(shape[0], 0.0);
    if (shape.length == 2) return List.generate(shape[0], (_) => List.filled(shape[1], 0.0));
    if (shape.length == 3) return List.generate(shape[0], (_) => List.generate(shape[1], (_) => List.filled(shape[2], 0.0)));
    if (shape.length == 4) return List.generate(shape[0], (_) => List.generate(shape[1], (_) => List.generate(shape[2], (_) => List.filled(shape[3], 0.0))));
    return [];
  }
}
