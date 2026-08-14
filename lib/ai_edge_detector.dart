import 'dart:math' as math;
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

      // letterbox resize: نحافظ على نسبة الصورة الأصلية ونضيف حشوة سوداء
      // متوسطة لنوصل لمقاس الإدخال المربّع (نفس أسلوب تدريب الموديل غالبًا)
      final scale = math.min(_inputW / original.width, _inputH / original.height);
      final newW = (original.width * scale).round().clamp(1, _inputW);
      final newH = (original.height * scale).round().clamp(1, _inputH);
      final padX = ((_inputW - newW) / 2).round();
      final padY = ((_inputH - newH) / 2).round();

      final resizedContent = img.copyResize(original, width: newW, height: newH);
      final canvas = img.Image(width: _inputW, height: _inputH);
      img.fill(canvas, color: img.ColorRgb8(0, 0, 0));
      img.compositeImage(canvas, resizedContent, dstX: padX, dstY: padY);

      final input = [
        List.generate(
          _inputH,
          (y) => List.generate(_inputW, (x) {
            final p = canvas.getPixel(x, y);
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

      // طباعة تشخيصية لكل المخرجات الستة بشكلها الخام (بدون أي تصحيح)
      // لنتأكد فعليًا من ترتيب النقاط وقيمها الحقيقية قبل أي افتراض
      debugPrint('==================================================');
      debugPrint('🔍 RAW OUTPUTS (قبل أي تصحيح):');
      for (int i = 0; i < _outputCount; i++) {
        debugPrint('Output[$i] shape=${interpreter.getOutputTensor(i).shape} => ${outputs[i]}');
      }
      debugPrint('==================================================');

      // إيجاد مخرج الزوايا: الشكل الوحيد المميز بين كل المخرجات هو [.., .., 4, 2]
      for (int i = 0; i < _outputCount; i++) {
        final shape = interpreter.getOutputTensor(i).shape;
        if (shape.length == 4 && shape[2] == 4 && shape[3] == 2) {
          debugPrint('🎯 مخرج النقاط (raw normalized, y,x): ${outputs[i]}');
          debugPrint('🎯 letterbox params: scale=$scale padX=$padX padY=$padY origW=${original.width} origH=${original.height}');
          final result = _extractCorners(
            outputs[i],
            original.width,
            original.height,
            scale,
            padX,
            padY,
          );
          debugPrint('🎯 النقاط بعد التصحيح والترتيب (TL,TR,BR,BL): $result');
          return result;
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
  /// [scale], [padX], [padY]: نفس قيم letterbox المستخدمة عند التحضير،
  /// لعكس التحويل ورجوع الإحداثيات لمقاس الصورة الأصلية.
  static List<Offset>? _extractCorners(
    dynamic raw,
    int origW,
    int origH,
    double scale,
    int padX,
    int padY,
  ) {
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
      // وهي منسوبة لمساحة الـ 224×224 كاملة (بما فيها الحشوة السوداء)
      double yNorm = (kp[0] as num).toDouble();
      double xNorm = (kp[1] as num).toDouble();

      if (xNorm < 0) xNorm = 0;
      if (xNorm > 1) xNorm = 1;
      if (yNorm < 0) yNorm = 0;
      if (yNorm > 1) yNorm = 1;

      // إزالة الحشوة والتحجيم، رجوع لمقاس الصورة الأصلية
      double xOrig = (xNorm * _inputW - padX) / scale;
      double yOrig = (yNorm * _inputH - padY) / scale;

      if (xOrig < 0) xOrig = 0;
      if (xOrig > origW) xOrig = origW.toDouble();
      if (yOrig < 0) yOrig = 0;
      if (yOrig > origH) yOrig = origH.toDouble();

      points.add(Offset(xOrig, yOrig));
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
