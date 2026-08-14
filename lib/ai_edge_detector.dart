import 'dart:typed_data';
import 'dart:ui';

import 'package:flutter/foundation.dart';
import 'package:image/image.dart' as img;
import 'package:tflite_flutter/tflite_flutter.dart';

/// كاشف زوايا المستند باستخدام موديل border_detect_224.tflite
class AIDocumentDetector {
  static Interpreter? _interpreter;
  static int _inputH = 224;
  static int _inputW = 224;

  static String lastDebugInfo = '';
  static const int _outputCount = 6;

  static Future<void> _ensureLoaded() async {
    if (_interpreter != null) return;

    final interpreter = await Interpreter.fromAsset('assets/border_detect_224.tflite');
    _interpreter = interpreter;

    final inputTensor = interpreter.getInputTensor(0);
    _inputH = inputTensor.shape[1];
    _inputW = inputTensor.shape[2];
  }

  static Future<void> inspectModel() async {
    try {
      await _ensureLoaded();
    } catch (e) {
      debugPrint('❌ حدث خطأ أثناء تحميل الموديل: $e');
    }
  }

  static Future<List<Offset>?> detect(Uint8List imageBytes) async {
    try {
      await _ensureLoaded();
      final interpreter = _interpreter;
      if (interpreter == null) return null;

      final original = img.decodeImage(imageBytes);
      if (original == null) return null;

      // 1. استخدام التمدد المباشر (Stretch) بدلاً من الـ Letterbox 
      // هذا يتوافق 100% مع الطريقة التي تدرب بها الموديل
      final resizedContent = img.copyResize(original, width: _inputW, height: _inputH);

      final input = [
        List.generate(
          _inputH,
          (y) => List.generate(_inputW, (x) {
            final p = resizedContent.getPixel(x, y);
            return [p.r / 255.0, p.g / 255.0, p.b / 255.0];
          }),
        ),
      ];

      final outputs = <int, Object>{};
      for (int i = 0; i < _outputCount; i++) {
        final shape = interpreter.getOutputTensor(i).shape;
        outputs[i] = _buildNestedZeros(shape);
      }

      interpreter.runForMultipleInputs([input], outputs);

      for (int i = 0; i < _outputCount; i++) {
        final shape = interpreter.getOutputTensor(i).shape;
        // البحث عن مخرج الإحداثيات المكون من 4 نقاط
        if (shape.length == 4 && shape[2] == 4 && shape[3] == 2) {
          final result = _extractCorners(outputs[i], original.width, original.height);

          lastDebugInfo = 'تم الكشف بنجاح!\nالنقاط المكتشفة:\n$result';
          return result;
        }
      }

      lastDebugInfo = 'لم يتم العثور على مخرج الزوايا.';
      return null;
    } catch (e) {
      debugPrint('❌ خطأ أثناء تشغيل كشف الحواف: $e');
      return null;
    }
  }

  static Object _buildNestedZeros(List<int> shape) {
    if (shape.isEmpty) return 0.0;
    if (shape.length == 1) return List.filled(shape[0], 0.0);
    return List.generate(shape[0], (_) => _buildNestedZeros(shape.sublist(1)));
  }

  static List<Offset>? _extractCorners(dynamic raw, int origW, int origH) {
    dynamic level = raw;
    while (level is List &&
        level.isNotEmpty &&
        level[0] is List &&
        (level[0] as List).isNotEmpty &&
        (level[0] as List)[0] is List) {
      level = level[0];
    }
    if (level is! List || level.length != 4) return null;

    final points = <Offset>[];
    for (final kp in level) {
      if (kp is! List || kp.length < 2) return null;

      // النموذج يُخرج الإحداثيات بتنسيق [y, x] كنسبة مئوية بين 0 و 1
      double yNorm = (kp[0] as num).toDouble().clamp(0.0, 1.0);
      double xNorm = (kp[1] as num).toDouble().clamp(0.0, 1.0);

      // نظرًا لأننا استخدمنا Stretch Resize، يمكننا ضرب النسبة مباشرة في أبعاد الصورة الأصلية
      double xOrig = xNorm * origW;
      double yOrig = yNorm * origH;

      points.add(Offset(xOrig, yOrig));
    }

    // الترتيب الهندسي للزوايا (TL, TR, BR, BL) باستخدام الإحداثيات النسبية لمنع أي خلل
    Offset topLeft = points[0];
    Offset topRight = points[0];
    Offset bottomRight = points[0];
    Offset bottomLeft = points[0];
    
    double minSum = double.infinity;
    double maxSum = -double.infinity;
    double minDiff = double.infinity;
    double maxDiff = -double.infinity;

    for (final p in points) {
      // استخدام النسبة المئوية للترتيب حتى لا يؤثر عرض وطول الصورة على دقة الترتيب
      final nx = p.dx / origW;
      final ny = p.dy / origH;
      
      final sum = nx + ny;
      final diff = nx - ny;
      
      if (sum < minSum) {
        minSum = sum;
        topLeft = p;
      }
      if (sum > maxSum) {
        maxSum = sum;
        bottomRight = p;
      }
      if (diff > maxDiff) {
        maxDiff = diff;
        topRight = p;
      }
      if (diff < minDiff) {
        minDiff = diff;
        bottomLeft = p;
      }
    }

    return [topLeft, topRight, bottomRight, bottomLeft];
  }
}
