Future<void> _openGoogleScanner() async {
  if (_isScanning) return;

  setState(() {
    _isScanning = true;
  });

  try {
    debugPrint('==========================================');
    debugPrint('MOSUL SCANNER');
    debugPrint('Starting Google ML Kit Document Scanner');
    debugPrint('==========================================');

    final List<String>? paths = await GoogleScanner.scan(
      pageLimit: 10,
      allowGallery: false,
    );

    if (!mounted) return;

    // -----------------------------------------------------------
    // Google رجع نتيجة صحيحة
    // -----------------------------------------------------------

    if (paths != null && paths.isNotEmpty) {
      int added = 0;

      for (final path in paths) {
        try {
          debugPrint(
            'Processing Google image: $path',
          );

          final file = File(path);

          final exists = await file.exists();

          if (!exists) {
            debugPrint(
              'Google image does not exist: $path',
            );
            continue;
          }

          final bytes = await file.readAsBytes();

          if (bytes.isEmpty) {
            debugPrint(
              'Google image is empty: $path',
            );
            continue;
          }

          final decoded = img.decodeImage(bytes);

          if (decoded == null) {
            debugPrint(
              'Could not decode Google image: $path',
            );
            continue;
          }

          debugPrint(
            'Google image decoded: '
            '${decoded.width}x${decoded.height}',
          );

          _addDecodedImage(
            decoded,
            isPhoto: false,
            curved: true,
          );

          added++;
        } catch (e, stackTrace) {
          debugPrint(
            'Error processing Google image: $e',
          );
          debugPrint('$stackTrace');
        }
      }

      if (!mounted) return;

      if (added > 0) {
        _showMessage(
          'تم مسح $added مستند بنجاح بواسطة Google',
        );
      } else {
        _showMessage(
          'Google أرجع الصور لكن تعذر قراءتها',
          error: true,
        );
      }

      return;
    }

    // -----------------------------------------------------------
    // Google لم يرجع صور
    // -----------------------------------------------------------

    debugPrint(
      'Google returned no document images.',
    );

    if (!mounted) return;

    // نفتح الكاميرا العادية كحل احتياطي
    _showMessage(
      'لم يُرجع Google صورة. سيتم فتح الكاميرا الاحتياطية.',
    );

    await Future.delayed(
      const Duration(milliseconds: 500),
    );

    if (!mounted) return;

    final XFile? photo =
        await _picker.pickImage(
      source: ImageSource.camera,
      imageQuality: 95,
    );

    if (photo == null) {
      return;
    }

    final bytes =
        await File(photo.path).readAsBytes();

    final decoded =
        img.decodeImage(bytes);

    if (decoded == null) {
      _showMessage(
        'تعذر قراءة الصورة',
        error: true,
      );
      return;
    }

    _addDecodedImage(
      decoded,
      isPhoto: false,
      curved: true,
    );

    if (mounted) {
      _showMessage(
        'تمت إضافة المستند بالكاميرا الاحتياطية',
      );
    }
  } catch (e, stackTrace) {
    debugPrint('==========================================');
    debugPrint('GOOGLE SCANNER ERROR');
    debugPrint('$e');
    debugPrint('$stackTrace');
    debugPrint('==========================================');

    if (!mounted) return;

    _showMessage(
      'تعذر تشغيل ماسح Google',
      error: true,
    );
  } finally {
    if (mounted) {
      setState(() {
        _isScanning = false;
      });
    }
  }
}
