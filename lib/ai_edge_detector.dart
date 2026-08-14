import 'dart:ui';

import 'package:flutter/foundation.dart';
import 'package:image/image.dart' as img;
import 'package:tflite_flutter/tflite_flutter.dart';

/// كاشف زوايا المستند باستخدام border_detect_224.tflite.
///
/// تمت مطابقة التجهيز مع ClearScanner الأصلي:
/// - تغيير مباشر للصورة إلى 224x224.
/// - Bilinear resize.
/// - RGB بصيغة FLOAT32 بقيم خام من 0 إلى 255.
/// - لا يوجد Letterbox ولا حشوة سوداء.
/// - النقاط تُقرأ بترتيب النموذج: TL, TR, BR, BL.
/// - لا يُقبل الكشف إلا إذا كان متوسط ثقة النقاط أكبر من 0.75.
class AIDocumentDetector {
  static Interpreter? _interpreter;
  static const String _modelAsset = 'assets/border_detect_224.tflite';
  static const int _inputWidth = 224;
  static const int _inputHeight = 224;
  static const int _outputCount = 6;
  static const double _minimumConfidence = 0.75;

  static String lastDebugInfo = '';

  static Future<void> _ensureLoaded() async {
    if (_interpreter != null) return;

    // ClearScanner الأصلي يستخدم أربعة خيوط للمعالجة.
    final options = InterpreterOptions()..threads = 4;
    final interpreter = await Interpreter.fromAsset(
      _modelAsset,
      options: options,
    );
    _interpreter = interpreter;
  }

  static Future<void> inspectModel() async {
    try {
      await _ensureLoaded();
      final interpreter = _interpreter!;

      final input = interpreter.getInputTensor(0);
      final outputInfo = <String>[];

      for (int i = 0; i < interpreter.getOutputTensors().length; i++) {
        final tensor = interpreter.getOutputTensor(i);
        outputInfo.add(
          '$i: name=${tensor.name}, shape=${tensor.shape}, type=${tensor.type}',
        );
      }

      lastDebugInfo = [
        'Input: shape=${input.shape}, type=${input.type}',
        ...outputInfo,
      ].join('\n');

      debugPrint(lastDebugInfo);
    } catch (e, stackTrace) {
      lastDebugInfo = 'خطأ في تحميل النموذج: $e';
      debugPrint('$lastDebugInfo\n$stackTrace');
    }
  }

  /// يكتشف زوايا المستند ويرجعها بالبكسل داخل الصورة الأصلية.
  ///
  /// ترتيب النتيجة:
  /// [topLeft, topRight, bottomRight, bottomLeft]
  static Future<List<Offset>?> detect(Uint8List imageBytes) async {
    try {
      await _ensureLoaded();
      final interpreter = _interpreter;
      if (interpreter == null) return null;

      final original = img.decodeImage(imageBytes);
      if (original == null || original.width < 10 || original.height < 10) {
        lastDebugInfo = 'الصورة غير صالحة';
        return null;
      }

      final originalWidth = original.width.toDouble();
      final originalHeight = original.height.toDouble();

      // مهم جدًا: ClearScanner يستخدم Resize مباشر إلى 224x224.
      // لا تستخدم Letterbox ولا تضف حشوة سوداء.
      final resized = img.copyResize(
        original,
        width: _inputWidth,
        height: _inputHeight,
        interpolation: img.Interpolation.linear,
      );

      // مهم جدًا: ClearScanner يرسل RGB الخام 0..255 إلى FLOAT32.
      // لا تقسم القيم على 255.
      final input = <List<List<List<double>>>>[
        List.generate(
          _inputHeight,
          (y) => List.generate(
            _inputWidth,
            (x) {
              final pixel = resized.getPixel(x, y);
              return <double>[
                pixel.r.toDouble(),
                pixel.g.toDouble(),
                pixel.b.toDouble(),
              ];
            },
          ),
        ),
      ];

      final outputs = <int, Object>{};
      for (int i = 0; i < _outputCount; i++) {
        outputs[i] = _buildNestedZeros(
          interpreter.getOutputTensor(i).shape,
        );
      }

      interpreter.runForMultipleInputs([input], outputs);

      // في هذا النموذج تحديدًا:
      // :1 = keypoints [1,1,4,2]
      // :0 = درجات الثقة الأربع [1,1,4]
      // ملاحظة: المخرج :5 موجود لكنه ليس meanConfidenceScore
      final keypointOutputIndex = _findOutputIndex(
        interpreter,
        namePart: ':1',
        requiredShape: (shape) =>
            shape.length == 4 && shape[2] == 4 && shape[3] == 2,
        fallback: _findShapeIndex(
          interpreter,
          (shape) =>
              shape.length == 4 && shape[2] == 4 && shape[3] == 2,
        ),
      );

      if (keypointOutputIndex == null) {
        lastDebugInfo = 'لم يتم العثور على مخرج النقاط الأربع';
        return null;
      }

      final scoreOutputIndex = _findOutputIndex(
        interpreter,
        namePart: ':0',
        requiredShape: (shape) =>
            shape.length == 3 && shape[1] == 1 && shape[2] == 4,
        fallback: _findShapeIndex(
          interpreter,
          (shape) =>
              shape.length == 3 && shape[1] == 1 && shape[2] == 4,
        ),
      );

      if (scoreOutputIndex == null) {
        lastDebugInfo = 'لم يتم العثور على درجات ثقة الزوايا الأربع';
        return null;
      }

      final keypointValues = _flattenNumbers(outputs[keypointOutputIndex]!);
      final scoreValues = _flattenNumbers(outputs[scoreOutputIndex]!);

      if (keypointValues.length < 8 || scoreValues.length < 4) {
        lastDebugInfo = [
          'مخرجات غير مكتملة',
          'keypoints=${keypointValues.length}',
          'scores=${scoreValues.length}',
        ].join('\n');
        return null;
      }

      final scores = scoreValues.take(4).toList();
      final meanConfidence =
          scores.reduce((a, b) => a + b) / scores.length;

      // ClearScanner يرفض النتيجة عندما تكون الثقة <= 0.75.
      if (meanConfidence <= _minimumConfidence) {
        lastDebugInfo =
            'تم رفض الكشف: متوسط الثقة ${meanConfidence.toStringAsFixed(4)}';
        return null;
      }

      // المخرج الأصلي هو أزواج [y, x]، وليس [x, y].
      // ClearScanner يحولها إلى PointF(x, y) هكذا:
      // topLeft     = (values[1], values[0])
      // topRight    = (values[3], values[2])
      // bottomRight = (values[5], values[4])
      // bottomLeft  = (values[7], values[6])
      final normalizedCorners = <Offset>[
        Offset(
          _clamp01(keypointValues[1]),
          _clamp01(keypointValues[0]),
        ),
        Offset(
          _clamp01(keypointValues[3]),
          _clamp01(keypointValues[2]),
        ),
        Offset(
          _clamp01(keypointValues[5]),
          _clamp01(keypointValues[4]),
        ),
        Offset(
          _clamp01(keypointValues[7]),
          _clamp01(keypointValues[6]),
        ),
      ];

      // إرجاع بكسلات الصورة الأصلية حتى يبقى باقي مشروعك متوافقًا.
      final corners = normalizedCorners
          .map(
            (point) => Offset(
              point.dx * originalWidth,
              point.dy * originalHeight,
            ),
          )
          .toList(growable: false);

      lastDebugInfo = [
        'تم الكشف بنجاح',
        'meanConfidence=${meanConfidence.toStringAsFixed(4)}',
        ...corners.asMap().entries.map(
              (entry) =>
                  '${_cornerName(entry.key)}: '
                  'x=${entry.value.dx.toStringAsFixed(1)}, '
                  'y=${entry.value.dy.toStringAsFixed(1)}',
            ),
      ].join('\n');

      return corners;
    } catch (e, stackTrace) {
      lastDebugInfo = 'خطأ أثناء الكشف: $e';
      debugPrint('$lastDebugInfo\n$stackTrace');
      return null;
    }
  }

  static int? _findOutputIndex(
    Interpreter interpreter, {
    required String namePart,
    required bool Function(List<int> shape) requiredShape,
    required int? fallback,
  }) {
    for (int i = 0; i < interpreter.getOutputTensors().length; i++) {
      final tensor = interpreter.getOutputTensor(i);
      if (tensor.name.contains(namePart) && requiredShape(tensor.shape)) {
        return i;
      }
    }
    return fallback;
  }

  static int? _findShapeIndex(
    Interpreter interpreter,
    bool Function(List<int> shape) predicate,
  ) {
    for (int i = 0; i < interpreter.getOutputTensors().length; i++) {
      if (predicate(interpreter.getOutputTensor(i).shape)) return i;
    }
    return null;
  }

  static List<double> _flattenNumbers(dynamic value) {
    final result = <double>[];

    void visit(dynamic item) {
      if (item is List) {
        for (final child in item) {
          visit(child);
        }
      } else if (item is num) {
        result.add(item.toDouble());
      }
    }

    visit(value);
    return result;
  }

  static Object _buildNestedZeros(List<int> shape) {
    if (shape.isEmpty) return 0.0;
    if (shape.length == 1) return List<double>.filled(shape[0], 0.0);
    return List<Object>.generate(
      shape[0],
      (_) => _buildNestedZeros(shape.sublist(1)),
    );
  }

  static double _clamp01(double value) {
    if (value.isNaN || value.isInfinite) return 0.0;
    return value.clamp(0.0, 1.0).toDouble();
  }

  static String _cornerName(int index) {
    switch (index) {
      case 0:
        return 'topLeft';
      case 1:
        return 'topRight';
      case 2:
        return 'bottomRight';
      case 3:
        return 'bottomLeft';
      default:
        return 'corner$index';
    }
  }
}
