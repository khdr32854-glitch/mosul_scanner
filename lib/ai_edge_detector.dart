import 'dart:math' as math;
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
      debugPrint('❌ حدث خطأ: $e');
    }
  }

  static Future<List<Offset>?> detect(Uint8List imageBytes) async {
    try {
      await _ensureLoaded();
      if (_interpreter == null) return null;

      final original = img.decodeImage(imageBytes);
      if (original == null) return null;

      final int origW = original.width;
      final int origH = original.height;

      // 1. نظام الـ Letterbox الإلزامي لنجاح الموديل
      final double scale = math.min(_inputW / origW, _inputH / origH);
      final int newW = (origW * scale).round().clamp(1, _inputW);
      final int newH = (origH * scale).round().clamp(1, _inputH);
      
      final int padX = ((_inputW - newW) / 2).round();
      final int padY = ((_inputH - newH) / 2).round();

      final resizedContent = img.copyResize(original, width: newW, height: newH);
      final canvas = img.Image(width: _inputW, height: _inputH);
      img.fill(canvas, color: img.ColorRgb8(0, 0, 0)); // الحشوة السوداء
      img.compositeImage(canvas, resizedContent, dstX: padX, dstY: padY);

      // 2. تحضير المصفوفة
      final input = [
        List.generate(
          _inputH,
          (y) => List.generate(_inputW, (x) {
            final p = canvas.getPixel(x, y);
            return [p.r / 255.0, p.g / 255.0, p.b / 255.0];
          }),
        ),
      ];

      final outputs = <int, Object>{};
      for (int i = 0; i < _outputCount; i++) {
        outputs[i] = _buildNestedZeros(_interpreter!.getOutputTensor(i).shape);
      }

      _interpreter!.runForMultipleInputs([input], outputs);

      for (int i = 0; i < _outputCount; i++) {
        final shape = _interpreter!.getOutputTensor(i).shape;
        // البحث عن مخرج النقاط الأربع
        if (shape.length == 4 && shape[2] == 4 && shape[3] == 2) {
          final result = _extractCorners(outputs[i], origW, origH, scale, padX, padY);
          lastDebugInfo = 'تم الكشف بنجاح.\nالنقاط:\n$result';
          return result;
        }
      }
      return null;
    } catch (e) {
      lastDebugInfo = 'خطأ: $e';
      return null;
    }
  }

  static Object _buildNestedZeros(List<int> shape) {
    if (shape.isEmpty) return 0.0;
    if (shape.length == 1) return List.filled(shape[0], 0.0);
    return List.generate(shape[0], (_) => _buildNestedZeros(shape.sublist(1)));
  }

  static List<Offset>? _extractCorners(
    dynamic raw, int origW, int origH, double scale, int padX, int padY
  ) {
    dynamic level = raw;
    while (level is List && level.isNotEmpty && level[0] is List && 
           (level[0] as List).isNotEmpty && (level[0] as List)[0] is List) {
      level = level[0];
    }
    if (level is! List || level.length != 4) return null;

    final points = <Offset>[];
    for (final kp in level) {
      // إحداثيات نسبية من الموديل
      double yNorm = (kp[0] as num).toDouble().clamp(0.0, 1.0);
      double xNorm = (kp[1] as num).toDouble().clamp(0.0, 1.0);

      // 1. ضرب النسبة في حجم الإدخال الكامل (224)
      double px = xNorm * _inputW;
      double py = yNorm * _inputH;

      // 2. إزالة الحشوة السوداء (Padding) رياضياً
      double unpaddedX = px - padX;
      double unpaddedY = py - padY;

      // 3. إعادة التكبير ليتطابق مع الصورة الأصلية
      double xOrig = unpaddedX / scale;
      double yOrig = unpaddedY / scale;

      points.add(Offset(
        xOrig.clamp(0.0, origW.toDouble()), 
        yOrig.clamp(0.0, origH.toDouble())
      ));
    }

    // الترتيب الهندسي للزوايا لضمان عدم تقاطع الخطوط (TL, TR, BR, BL)
    Offset topLeft = points[0], topRight = points[0];
    Offset bottomRight = points[0], bottomLeft = points[0];
    double minSum = double.infinity, maxSum = -double.infinity;
    double minDiff = double.infinity, maxDiff = -double.infinity;

    for (final p in points) {
      final sum = p.dx + p.dy;
      final diff = p.dx - p.dy;
      if (sum < minSum) { minSum = sum; topLeft = p; }
      if (sum > maxSum) { maxSum = sum; bottomRight = p; }
      if (diff > maxDiff) { maxDiff = diff; topRight = p; }
      if (diff < minDiff) { minDiff = diff; bottomLeft = p; }
    }

    return [topLeft, topRight, bottomRight, bottomLeft];
  }
}
