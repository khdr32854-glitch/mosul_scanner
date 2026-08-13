import 'dart:typed_data';
import 'dart:ui';
import 'package:flutter/foundation.dart';
import 'package:image/image.dart' as img;
import 'package:tflite_flutter/tflite_flutter.dart';

class AIDocumentDetector {
  static Interpreter? _interpreter;
  static const int _inputSize = 256; 

  // تحميل ملف الذكاء الاصطناعي في الذاكرة
  static Future<void> loadModel() async {
    try {
      if (_interpreter == null) {
        _interpreter = await Interpreter.fromAsset('assets/models/document_scanner.tflite');
        debugPrint('AI Model Loaded Successfully!');
      }
    } catch (e) {
      debugPrint('Failed to load AI model: $e');
    }
  }

  // الدالة الرئيسية لاكتشاف الزوايا باستخدام الذكاء الاصطناعي
  static Future<List<Offset>?> detect(Uint8List imageBytes) async {
    if (_interpreter == null) await loadModel();
    if (_interpreter == null) return null;

    try {
      final originalImage = img.decodeImage(imageBytes);
      if (originalImage == null) return null;

      final w = originalImage.width.toDouble();
      final h = originalImage.height.toDouble();

      // تصغير الصورة لتناسب مدخلات النموذج
      final resizedImage = img.copyResize(originalImage, width: _inputSize, height: _inputSize);

      var input = List.generate(
        1,
        (i) => List.generate(
          _inputSize,
          (y) => List.generate(
            _inputSize,
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

      var output = List.generate(1, (i) => List.filled(8, 0.0));

      _interpreter!.run(input, output);

      final points = output[0];

      return [
        Offset((points[0] * w).clamp(0, w), (points[1] * h).clamp(0, h)), // أعلى اليسار
        Offset((points[2] * w).clamp(0, w), (points[3] * h).clamp(0, h)), // أعلى اليمين
        Offset((points[4] * w).clamp(0, w), (points[5] * h).clamp(0, h)), // أسفل اليمين
        Offset((points[6] * w).clamp(0, w), (points[7] * h).clamp(0, h)), // أسفل اليسار
      ];
    } catch (e) {
      debugPrint('AI Detection Error: $e');
      return null;
    }
  }
}
