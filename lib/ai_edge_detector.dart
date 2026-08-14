import 'dart:typed_data';
import 'dart:ui';
import 'package:flutter/foundation.dart';
import 'package:tflite_flutter/tflite_flutter.dart';
import 'package:image/image.dart' as img;

class AIDocumentDetector {
  static Interpreter? _interpreter;
  static bool _isLoaded = false;

  static Future<void> inspectModel() async {
    await loadModel();
  }

  static Future<void> loadModel() async {
    if (_isLoaded) return;
    try {
      _interpreter = await Interpreter.fromAsset('assets/border_detect_224.tflite');
      _isLoaded = true;
    } catch (e) {
      debugPrint("خطأ في تحميل النموذج: $e");
    }
  }

  static Future<List<Offset>> detect(Uint8List imageBytes) async {
    if (!_isLoaded || _interpreter == null) {
      await loadModel();
    }

    img.Image? originalImage = img.decodeImage(imageBytes);
    if (originalImage == null) {
      throw Exception("فشل في فك تشفير الصورة.");
    }

    final double origWidth = originalImage.width.toDouble();
    final double origHeight = originalImage.height.toDouble();

    var inputImage = await _prepareImage(originalImage);
    
    var outputTensors = _interpreter!.getOutputTensors();
    int cornersIndex = -1;
    Map<int, Object> outputs = {};

    for (int i = 0; i < outputTensors.length; i++) {
      var tensor = outputTensors[i];
      outputs[i] = _createEmptyBuffer(tensor.shape);
      
      if (tensor.shape.length == 4 && 
          tensor.shape[2] == 4 && 
          tensor.shape[3] == 2) {
        cornersIndex = i;
      }
    }

    if (cornersIndex == -1) {
      // قيمة افتراضية آمنة تحيط بوسط البطاقة في حال لم يتعرف النموذج على المخرج بدقة
      return [
        const Offset(0.1, 0.1),
        const Offset(0.9, 0.1),
        const Offset(0.9, 0.9),
        const Offset(0.1, 0.9),
      ];
    }

    _interpreter!.runForMultipleInputs([inputImage], outputs);

    var cornersData = outputs[cornersIndex] as List;
    var pointsArray = cornersData[0][0] as List;

    List<Offset> rawPoints = [];
    for (int i = 0; i < 4; i++) {
      double x = (pointsArray[i][0] as num).toDouble();
      double y = (pointsArray[i][1] as num).toDouble();

      // إذا كانت الإحداثيات مطلقة وليست نسبية، نحولها إلى نطاق نسبي
      if (x > 1.0 || y > 1.0) {
        x = x / 224.0;
        y = y / 224.0;
      }

      rawPoints.add(Offset(
        x.clamp(0.05, 0.95),
        y.clamp(0.05, 0.95),
      ));
    }

    return rawPoints;
  }

  static Future<List<List<List<List<double>>>>> _prepareImage(img.Image originalImage) async {
    img.Image resizedImage = img.copyResize(originalImage, width: 224, height: 224);

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

  static dynamic _createEmptyBuffer(List<int> shape) {
    if (shape.isEmpty) return 0.0;
    if (shape.length == 1) return List.filled(shape[0], 0.0);
    if (shape.length == 2) return List.generate(shape[0], (_) => List.filled(shape[1], 0.0));
    if (shape.length == 3) return List.generate(shape[0], (_) => List.generate(shape[1], (_) => List.filled(shape[2], 0.0)));
    if (shape.length == 4) return List.generate(shape[0], (_) => List.generate(shape[1], (_) => List.generate(shape[2], (_) => List.filled(shape[3], 0.0))));
    return [];
  }
}
