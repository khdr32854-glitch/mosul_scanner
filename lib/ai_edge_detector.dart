      final rawOutputsText = StringBuffer();
      for (int i = 0; i < _outputCount; i++) {
        rawOutputsText.writeln('Output[$i] shape=${interpreter.getOutputTensor(i).shape}');
      }

      // طباعة تشخيصية لكل المخرجات الستة بشكلها الخام (بدون أي تصحيح)
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

          lastDebugInfo =
              'الشكل: $rawOutputsText'
              'مخرج الزوايا [$i] الخام (y,x) 0-1:\n${outputs[i]}\n\n'
              'letterbox:\nscale=$scale\npadX=$padX padY=$padY\n'
              'origW=${original.width} origH=${original.height}\n\n'
              'النقاط بعد التصحيح (TL,TR,BR,BL):\n$result';

          return result;
        }
      }

      lastDebugInfo = 'لم يتم العثور على مخرج بالشكل [.., .., 4, 2]\n$rawOutputsText';

      debugPrint('⚠️ لم يتم العثور على مخرج الزوايا بالشكل المتوقع [.., .., 4, 2]');
      return null;
    } catch (e) {
      debugPrint('❌ خطأ أثناء تشغيل كشف الحواف: $e');
