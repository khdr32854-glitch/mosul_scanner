import 'dart:typed_data';
import 'dart:ui';

import 'package:flutter/foundation.dart';
import 'package:image/image.dart' as img;
import 'package:tflite_flutter/tflite_flutter.dart';

/// كاشف زوايا المستند باستخدام موديل border_detect_224.tflite
/// (موديل CenterNet keypoints — 4 نقاط، كل نقطة إحداثيتين y,x بمقياس 0-1)
class AIDocumentDetector {
  static Interpreter? _interpreter;
  static int _inputH = 224;
  static int _inputW = 224;

  // عدد مخرجات هذا الموديل بالتحديد (مؤكد من فحص الملف): 6
  static const int _outputCount = 6;

  static Future<void> _ensureLoaded() async {
    if (_interpreter != null) return;

    final interpreter = await Interpreter.fromAsset('assets/border_detect_224.tflite');
    _interpreter = interpreter;

    final inputTensor = interpreter.getInputTensor(0);
    _inputH = inputTensor.shape[1];
    _inputW = inputTensor.shape[2];

    debugPrint('==================================================');
    debugPrint('✅ تم تحميل موديل كشف الحواف');
    debugPrint('➡️ Input shape: ${inputTensor.shape}');
    for (int i = 0; i < _outputCount; i++) {
      final t = interpreter.getOutputTensor(i);
      debugPrint('⬅️ Output[$i]: ${t.shape}');
    }
    debugPrint('==================================================');
  }

  /// دالة تشخيصية اختيارية لفحص شكل الموديل من الـ console عند إقلاع التطبيق
  static Future<void> inspectModel() async {
    try {
      await _ensureLoaded();
    } catch (e) {
      debugPrint('❌ حدث خطأ أثناء تحميل الموديل: $e');
    }
  }

  /// الدالة الأساسية: تاخذ بايتات صورة، وترجع 4 زوايا بترتيب
  /// [أعلى-يسار, أعلى-يمين, أسفل-يمين, أسفل-يسار] بمقاييس بكسل الصورة الأصلية.
  /// ترجع null لو فشل الكشف أو حصل خطأ.
  static Future<List<Offset>?> detect(Uint8List imageBytes) async {
    try {
      await _ensureLoaded();
      final interpreter = _interpreter;
      if (interpreter == null) return null;

      final original = img.decodeImage(imageBytes);
      if (original == null) return null;

      final resized = img.copyResize(original, width: _inputW, height: _inputH);

      final input = [
        List.generate(
          _inputH,
          (y) => List.generate(_inputW, (x) {
            final p = resized.getPixel(x, y);
            return [p.r / 255.0, p.g / 255.0, p.b / 255.0];
          }),
        ),
      ];

      // تجهيز مخازن استقبال لكل المخرجات الستة حسب شكل كل واحد منها فعليًا
      final outputs = <int, Object>{};
      for (int i = 0; i < _outputCount; i++) {
        final shape = interpreter.getOutputTensor(i).shape;
        outputs[i] = _buildNestedZeros(shape);
      }

      interpreter.runForMultipleInputs([input], outputs);

      // إيجاد مخرج الزوايا: الشكل الوحيد المميز بين كل المخرجات هو [.., .., 4, 2]
      for (int i = 0; i < _outputCount; i++) {
        final shape = interpreter.getOutputTensor(i).shape;
        if (shape.length == 4 && shape[2] == 4 && shape[3] == 2) {
          return _extractCorners(outputs[i], original.width, original.height);
        }
      }

      debugPrint('⚠️ لم يتم العثور على مخرج الزوايا بالشكل المتوقع [.., .., 4, 2]');
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

  /// يقرأ مصفوفة الـ keypoints (شكلها [1,1,4,2]) ويرجع 4 نقاط
  /// مرتبة هندسيًا: أعلى-يسار, أعلى-يمين, أسفل-يمين, أسفل-يسار.
  static List<Offset>? _extractCorners(dynamic raw, int origW, int origH) {
    // ننزل بالمصفوفة حتى نوصل لآخر بعدين (4 نقاط × 2 إحداثية)
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

      // ترتيب الإحداثيات في TensorFlow Object Detection API القياسي هو (y, x)
      double y = (kp[0] as num).toDouble();
      double x = (kp[1] as num).toDouble();

      if (x < 0) x = 0;
      if (x > 1) x = 1;
      if (y < 0) y = 0;
      if (y > 1) y = 1;

      points.add(Offset(x * origW, y * origH));
    }

    // ترتيب هندسي مستقل عن ترتيب الموديل الداخلي:
    // أعلى-يسار (أصغر x+y) / أسفل-يمين (أكبر x+y)
    // أعلى-يمين (أكبر x-y) / أسفل-يسار (أصغر x-y)
    Offset topLeft = points[0];
    Offset topRight = points[0];
    Offset bottomRight = points[0];
    Offset bottomLeft = points[0];
    double minSum = double.infinity;
    double maxSum = -double.infinity;
    double minDiff = double.infinity;
    double maxDiff = -double.infinity;

    for (final p in points) {
      final sum = p.dx + p.dy;
      final diff = p.dx - p.dy;
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
