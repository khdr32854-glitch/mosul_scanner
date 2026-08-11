class CropScreen extends StatefulWidget {
  final Uint8List imageBytes;

  const CropScreen({
    super.key,
    required this.imageBytes,
  });

  @override
  State<CropScreen> createState() => _CropScreenState();
}

class _CropScreenState extends State<CropScreen> {
  double _x1 = 0.05;
  double _y1 = 0.05;

  double _x2 = 0.95;
  double _y2 = 0.05;

  double _x3 = 0.95;
  double _y3 = 0.95;

  double _x4 = 0.05;
  double _y4 = 0.95;

  EnhanceMode _filter = EnhanceMode.none;

  late Uint8List _displayBytes;

  int _imgWidth = 100;
  int _imgHeight = 100;

  Offset? _dragFocalPoint;

  bool _isDetecting = false;
  bool _isProcessing = false;

  @override
  void initState() {
    super.initState();

    // مهم جداً:
    // نعرض الصورة الأصلية مباشرة بدون إعادة ترميزها.
    _displayBytes = widget.imageBytes;

    _initializeDimensions();
  }

  void _initializeDimensions() {
    final mat = ImageUtils.decodeBytes(widget.imageBytes);

    if (mat == null || mat.isEmpty) {
      return;
    }

    if (!mounted) return;

    setState(() {
      _imgWidth = mat.cols;
      _imgHeight = mat.rows;
    });
  }

  // ============================================================
  // الفلاتر
  // ============================================================

  Future<void> _applyFilter(EnhanceMode mode) async {
    if (_isProcessing) return;

    setState(() {
      _filter = mode;
    });

    // الأصلي = نرجع للصورة الأصلية بدون OpenCV
    if (mode == EnhanceMode.none) {
      if (!mounted) return;

      setState(() {
        _displayBytes = widget.imageBytes;
      });

      return;
    }

    setState(() {
      _isProcessing = true;
    });

    try {
      final mat = ImageUtils.decodeBytes(widget.imageBytes);

      if (mat == null || mat.isEmpty) {
        throw Exception('تعذر قراءة الصورة');
      }

      final processed = ImageEnhancer.apply(
        mat,
        mode,
      );

      final bytes = ImageUtils.encodeJpg(
        processed,
        quality: 95,
      );

      // إذا فشل OpenCV، لا نخلي الشاشة سوداء
      if (bytes.isEmpty) {
        throw Exception('فشل تحويل الصورة');
      }

      if (!mounted) return;

      setState(() {
        _displayBytes = bytes;
      });
    } catch (e) {
      debugPrint('Filter error: $e');

      if (!mounted) return;

      // نرجع للصورة الأصلية
      setState(() {
        _displayBytes = widget.imageBytes;
        _filter = EnhanceMode.none;
      });

      _showSnack('تعذر تطبيق التحسين');
    } finally {
      if (mounted) {
        setState(() {
          _isProcessing = false;
        });
      }
    }
  }

  // ============================================================
  // تحديد كامل الصورة
  // ============================================================

  void _selectAll() {
    setState(() {
      _x1 = 0.0;
      _y1 = 0.0;

      _x2 = 1.0;
      _y2 = 0.0;

      _x3 = 1.0;
      _y3 = 1.0;

      _x4 = 0.0;
      _y4 = 1.0;
    });
  }

  // ============================================================
  // القص التلقائي
  // ============================================================

  Future<void> _runAutoDetect() async {
    if (_isDetecting || _isProcessing) return;

    setState(() {
      _isDetecting = true;
    });

    try {
      final mat = ImageUtils.decodeBytes(
        widget.imageBytes,
      );

      if (mat == null || mat.isEmpty) {
        throw Exception('الصورة غير صالحة');
      }

      final corners = SmartCrop.detectCorners(mat);

      if (corners != null && corners.length == 8) {
        if (!mounted) return;

        setState(() {
          _x1 = corners[
