import 'dart:typed_data';
import 'dart:ui';

import 'package:flutter/foundation.dart';
import 'package:image/image.dart' as img;
import 'package:tflite_flutter/tflite_flutter.dart';

class AIDocumentDetector {
  static Interpreter? _interpreter;
  static List<int>? _inputShape;
  static List<int>? _outputShape;
  static bool _isMaskOutput = false;

  static Future<void> _ensureLoaded() async {
    if (_interpreter != null) return;

    _interpreter = await Interpreter.fromAsset('assets/border_detect_224.tflite');

    final inputTensor = _interpreter!.getInputTensor(0);
    final outputTensor = _interpreter!.getOutputTensor(0);

    _inputShape = inputTensor.shape;
    _outputShape = outputTensor.shape;

    final outputElements = _outputShape!.fold<int>(1, (a, b) => a * b);
    // لو الموديل بيرجع 8 أرقام فقط => يعني 4 زوايا (x,y) مباشرة
    // غير هيك => نعتبره "قناع" (mask) وناخذ الزوايا القصوى منه
    _isMaskOutput = outputElements != 8;

    debugPrint('==================================================');
    debugPrint('✅ تم تحميل موديل كشف الحواف');
    debugPrint('➡️ Input shape: $_inputShape');
    debugPrint('⬅️ Output shape: $_outputShape (${_isMaskOutput ? "mask mode" : "corners mode"})');
    debugPrint('==================================================');
  }

  /// دالة تشخيصية (اختيارية) لفحص شكل الموديل من الـ console
  static Future<void> inspectModel() async {
    try {
      await _ensureLoaded();
    } catch (e) {
      debugPrint('❌ حدث خطأ أثناء تحميل الموديل: $e');
    }
  }

  /// الدالة الأساسية: تاخذ بايتات صورة، وترجع 4 زوايا بترتيب
  /// [أعلى-يسار, أعلى-يمين, أسفل-يمين, أسفل-يسار] بمقاييس بكسل الصورة الأصلية.
  /// ترجع null لو فشل الكشف.
  static Future<List<Offset>?> detect(Uint8List imageBytes) async {
    try {
      await _ensureLoaded();
      final interpreter = _interpreter;
      final inputShape = _inputShape;
      if (interpreter == null || inputShape == null || inputShape.length < 3) {
        return null;
      }

      final original = img.decodeImage(imageBytes);
      if (original == null) return null;

      final inH = inputShape[1];
      final inW = inputShape[2];

      final resized = img.copyResize(original, width: inW, height: inH);

      final input = [
        List.generate(
          inH,
          (y) => List.generate(inW, (x) {
            final p = resized.getPixel(x, y);
            return [p.r / 255.0, p.g / 255.0, p.b / 255.0];
          }),
        ),
      ];

      if (!_isMaskOutput) {
        final output = [List.filled(8, 0.0)];
        interpreter.run(input, output);
        final flat = output[0];

        return [
          Offset(flat[0] * original.width, flat[1] * original.height),
          Offset(flat[2] * original.width, flat[3] * original.height),
          Offset(flat[4] * original.width, flat[5] * original.height),
          Offset(flat[6] * original.width, flat[7] * original.height),
        ];
      } else {
        final outShape = _outputShape!;
        final outH = outShape.length >= 3 ? outShape[1] : inH;
        final outW = outShape.length >= 3 ? outShape[2] : inW;

        final output = [
          List.generate(outH, (_) => List.generate(outW, (_) => [0.0])),
        ];
        interpreter.run(input, output);

        return _cornersFromMask(output[0], outW, outH, original.width, original.height);
      }
    } catch (e) {
      debugPrint('❌ خطأ أثناء تشغيل كشف الحواف: $e');
      return null;
    }
  }

  /// يستخرج 4 زوايا من قناع (mask) عن طريق إيجاد النقاط القصوى
  /// بأربع اتجاهات هندسية (x+y, x-y).
  static List<Offset>? _cornersFromMask(
    List<dynamic> mask, int maskW, int maskH, int origW, int origH,
  ) {
    const threshold = 0.5;

    double minSum = double.infinity, maxSum = -double.infinity;
    double maxDiff = -double.infinity, minDiff = double.infinity;

    int? tlX, tlY, brX, brY, trX, trY, blX, blY;

    for (int y = 0; y < maskH; y++) {
      for (int x = 0; x < maskW; x++) {
        final v = (mask[y][x][0] as num).toDouble();
        if (v < threshold) continue;

        final sum = (x + y).toDouble();
        final diff = (x - y).toDouble();

        if (sum < minSum) { minSum = sum; tlX = x; tlY = y; }
        if (sum > maxSum) { maxSum = sum; brX = x; brY = y; }
        if (diff > maxDiff) { maxDiff = diff; trX = x; trY = y; }
        if (diff < minDiff) { minDiff = diff; blX = x; blY = y; }
      }
    }

    if (tlX == null || trX == null || brX == null || blX == null) return null;

    final sx = origW / maskW;
    final sy = origH / maskH;

    return [
      Offset(tlX * sx, tlY! * sy),
      Offset(trX * sx, trY! * sy),
      Offset(brX * sx, brY! * sy),
      Offset(blX * sx, blY! * sy),
    ];
  }
}
