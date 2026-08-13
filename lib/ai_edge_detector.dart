import 'package:flutter/foundation.dart';
import 'package:tflite_flutter/tflite_flutter.dart';

class AIDocumentDetector {
  static Interpreter? _interpreter;

  /// هذه الدالة ستقوم بتحميل ملف ClearScanner وكشف أسراره
  static Future<void> inspectModel() async {
    try {
      // 1. تحميل الملف الثنائي من المسار الجديد
      _interpreter = await Interpreter.fromAsset('assets/border_detect_224.tflite');
      
      debugPrint('==================================================');
      debugPrint('✅ تم تحميل عقل الذكاء الاصطناعي بنجاح!');

      // 2. سؤال الموديل: ما هو شكل الصورة التي تريدها؟
      final inputTensor = _interpreter!.getInputTensor(0);
      debugPrint('➡️ الموديل يستقبل بيانات بشكل: ${inputTensor.shape} ونوعها: ${inputTensor.type}');

      // 3. سؤال الموديل: ماذا ستعطينا بعد أن نعطيك الصورة؟
      final outputTensor = _interpreter!.getOutputTensor(0);
      debugPrint('⬅️ الموديل يخرج بيانات بشكل: ${outputTensor.shape} ونوعها: ${outputTensor.type}');
      debugPrint('==================================================');

    } catch (e) {
      debugPrint('❌ حدث خطأ أثناء تحميل الموديل: $e');
    }
  }
}
