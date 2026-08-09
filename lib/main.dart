import 'dart:io';
import 'dart:math';
import 'dart:typed_data';
import 'package:image/image.dart' as img;
import 'package:google_mlkit_document_scanner/google_mlkit_document_scanner.dart';

/// crop_engine.dart v10 — مع Perspective Warp كامل
/// سير العمل: كشف حواف ← تصحيح منظور ← تبييض موضعي

class CropResult {
  final img.Image image;
  final bool changed;
  const CropResult({required this.image, required this.changed});
}

enum EnhanceMode { none, soft, bw }

/// ═══════════════════════════════════════
/// Perspective Warp — تصحيح المنظور (قلب المحرك)
/// ═══════════════════════════════════════
class PerspectiveWarp {
  static img.Image warp(img.Image src, double x1, double y1, double x2, double y2, double x3, double y3, double x4, double y4) {
    final pts = _orderPoints(x1, y1, x2, y2, x3, y3, x4, y4);
    final w1 = sqrt(pow(pts[2]-pts[0],2)+pow(pts[3]-pts[1],2));
    final w2 = sqrt(pow(pts[6]-pts[4],2)+pow(pts[7]-pts[5],2));
    final h1 = sqrt(pow(pts[4]-pts[0],2)+pow(pts[5]-pts[1],2));
    final h2 = sqrt(pow(pts[6]-pts[2],2)+pow(pts[7]-pts[3],2));
    final maxW = max(w1, w2).round(), maxH = max(h1, h2).round();
    if (maxW < 10 || maxH < 10) return src;

    final result = img.Image(width: maxW, height: maxH);
    final srcPts = [pts[0],pts[1],pts[2],pts[3],pts[4],pts[5],pts[6],pts[7]];
    final dstPts = [0.0,0.0,maxW-1.0,0.0,maxW-1.0,maxH-1.0,0.0,maxH-1.0];
    final M = _getPerspectiveTransform(srcPts, dstPts);
    if (M == null) return src;
    final invM = _invert3x3(M);
    if (invM == null) return src;

    for (int y = 0; y < maxH; y++) {
      for (int x = 0; x < maxW; x++) {
        final w = invM[0][0]*x + invM[0][1]*y + invM[0][2];
        final v = invM[1][0]*x + invM[1][1]*y + invM[1][2];
        final q = invM[2][0]*x + invM[2][1]*y + invM[2][2];
        if (q.abs() < 0.000001) continue;
        final sx = (w/q).round(), sy = (v/q).round();
        if (sx >= 0 && sx < src.width && sy >= 0 && sy < src.height) {
          final p = src.getPixel(sx, sy);
          result.setPixelRgba(x, y, p.r.toInt(), p.g.toInt(), p.b.toInt(), p.a.toInt());
        }
      }
    }
    return result;
  }

  static List<double> _orderPoints(double x1,double y1,double x2,double y2,double x3,double y3,double x4,double y4) {
    final pts = [[x1,y1],[x2,y2],[x3,y3],[x4,y4]];
    pts.sort((a,b) => a[1].compareTo(b[1]));
    final top = [pts[0],pts[1]]; top.sort((a,b) => a[0].compareTo(b[0]));
    final bottom = [pts[2],pts[3]]; bottom.sort((a,b) => b[0].compareTo(a[0]));
    return [top[0][0],top[0][1],top[1][0],top[1][1],bottom[0][0],bottom[0][1],bottom[1][0],bottom[1][1]];
  }

  static List<List<double>>? _getPerspectiveTransform(List<double> src, List<double> dst) {
    final A = List.generate(8,(_)=>List.filled(8,0.0));
    final b = List.filled(8,0.0);
    for (int i=0;i<4;i++) {
      final sx=src[i*2],sy=src[i*2+1],dx=dst[i*2],dy=dst[i*2+1];
      A[i*2][0]=sx;A[i*2][1]=sy;A[i*2][2]=1;A[i*2][6]=-dx*sx;A[i*2][7]=-dx*sy;b[i*2]=dx;
      A[i*2+1][3]=sx;A[i*2+1][4]=sy;A[i*2+1][5]=1;A[i*2+1][6]=-dy*sx;A[i*2+1][7]=-dy*sy;b[i*2+1]=dy;
    }
    final h=_solveLinear(A,b);
    if(h==null)return null;
    return [[h[0],h[1],h[2]],[h[3],h[4],h[5]],[h[6],h[7],1.0]];
  }

  static List<double>? _solveLinear(List<List<double>> A,List<double> b) {
    final n=A.length;
    final aug=List.generate(n,(i)=>[...A[i],b[i]]);
    for(int col=0;col<n;col++){
      int maxRow=col;
      for(int row=col+1;row<n;row++) if(aug[row][col].abs()>aug[maxRow][col].abs()) maxRow=row;
      if(aug[maxRow][col].abs()<1e-12) return null;
      final tmp=aug[col];aug[col]=aug[maxRow];aug[maxRow]=tmp;
      for(int row=col+1;row<n;row++){
        final factor=aug[row][col]/aug[col][col];
        for(int j=col;j<=n;j++) aug[row][j]-=factor*aug[col][j];
      }
    }
    final x=List.filled(n,0.0);
    for(int i=n-1;i>=0;i--){x[i]=aug[i][n];for(int j=i+1;j<n;j++)x[i]-=aug[i][j]*x[j];x[i]/=aug[i][i];}
    return x;
  }

  static List<List<double>>? _invert3x3(List<List<double>> M){
    final det=M[0][0]*(M[1][1]*M[2][2]-M[1][2]*M[2][1])-M[0][1]*(M[1][0]*M[2][2]-M[1][2]*M[2][0])+M[0][2]*(M[1][0]*M[2][1]-M[1][1]*M[2][0]);
    if(det.abs()<1e-12)return null;
    final id=1.0/det;
    return [
      [(M[1][1]*M[2][2]-M[1][2]*M[2][1])*id,(M[0][2]*M[2][1]-M[0][1]*M[2][2])*id,(M[0][1]*M[1][2]-M[0][2]*M[1][1])*id],
      [(M[1][2]*M[2][0]-M[1][0]*M[2][2])*id,(M[0][0]*M[2][2]-M[0][2]*M[2][0])*id,(M[0][2]*M[1][0]-M[0][0]*M[1][2])*id],
      [(M[1][0]*M[2][1]-M[1][1]*M[2][0])*id,(M[0][1]*M[2][0]-M[0][0]*M[2][1])*id,(M[0][0]*M[1][1]-M[0][1]*M[1][0])*id],
    ];
  }
}


/// ═══════════════════════════════════════
/// القص الذكي متعدد الأشكال — v11
///
/// المبدأ:
/// 1) لا نفترض أن المستند مستطيل محاذٍ للصورة.
/// 2) نبحث عن أكبر مجموعة حواف مترابطة، وليس أقوى مستطيل فقط.
/// 3) نعطي الأولوية للمستند الكبير حتى لا نختار بطاقة/إطارًا داخل
///    المستند بالخطأ.
/// 4) نستخرج أربع زوايا تقريبية من شكل الحواف.
/// 5) إذا كانت الزوايا صالحة نستخدم Perspective Warp لتصحيح الميلان.
/// 6) إذا لم تكن الثقة كافية نرجع للصورة الأصلية بدل قص خاطئ.
///
/// هذا مهم لأن الصور الواقعية قد تحتوي على:
/// - A4/A5 وإيصالات وبطاقات بأحجام مختلفة.
/// - دوران وميلان ومنظور متفاوت.
/// - حدود داخلية وبطاقات أو صور داخل الورقة.
/// - خلفيات وإضاءة وظلال مختلفة.
/// ═══════════════════════════════════════
class SmartCrop {
  static CropResult detect(img.Image src) {
    if (src.width < 100 || src.height < 100) {
      return CropResult(image: src, changed: false);
    }

    final corners = detectCorners(src);
    if (corners == null) {
      return CropResult(image: src, changed: false);
    }

    final px = <double>[
      corners[0] * src.width,
      corners[1] * src.height,
      corners[2] * src.width,
      corners[3] * src.height,
      corners[4] * src.width,
      corners[5] * src.height,
      corners[6] * src.width,
      corners[7] * src.height,
    ];

    final area = _quadArea(
      px[0], px[1], px[2], px[3], px[4], px[5], px[6], px[7],
    );
    final imageArea = src.width * src.height;
    final ratio = area / imageArea;

    // منع قصات صغيرة جدًا أو نتيجة شبه مساوية للصورة كلها بسبب الضوضاء.
    if (ratio < 0.08) {
      return CropResult(image: src, changed: false);
    }

    // إذا كان الكشف يغطي تقريبًا كل الصورة، لا نعيد قصها بلا داعٍ.
    if (ratio > 0.94) {
      return CropResult(image: src, changed: false);
    }

    final warped = PerspectiveWarp.warp(
      src,
      px[0], px[1], px[2], px[3],
      px[4], px[5], px[6], px[7],
    );

    if (warped.width < 30 || warped.height < 30) {
      return CropResult(image: src, changed: false);
    }

    return CropResult(image: warped, changed: true);
  }

  /// كشف الزوايا الأربع كنسب 0..1.
  /// النقاط بالترتيب: أعلى-يسار، أعلى-يمين، أسفل-يمين، أسفل-يسار.
  static List<double>? detectCorners(img.Image src) {
    if (src.width < 100 || src.height < 100) return null;

    final data = _detectCandidate(src);
    if (data == null) return null;

    final r = data;
    final pts = <double>[
      r.tlX / data.sw, r.tlY / data.sh,
      r.trX / data.sw, r.trY / data.sh,
      r.brX / data.sw, r.brY / data.sh,
      r.blX / data.sw, r.blY / data.sh,
    ];

    // هامش صغير جدًا حتى لا نخسر الحواف بسبب التوسيع.
    const pad = 0.008;
    for (int i = 0; i < pts.length; i += 2) {
      pts[i] = (pts[i] + (pts[i] < 0.5 ? -pad : pad)).clamp(0.0, 1.0);
      pts[i + 1] =
          (pts[i + 1] + (pts[i + 1] < 0.5 ? -pad : pad)).clamp(0.0, 1.0);
    }
    return pts;
  }

  static _Candidate? _detectCandidate(img.Image src) {
    // حجم صغير نسبيًا حتى يبقى القص التلقائي سريعًا على الهاتف.
    const target = 320;
    final ratio = max(src.width, src.height) / target;
    final sw = max(80, (src.width / ratio).round());
    final sh = max(80, (src.height / ratio).round());

    var gray = img.grayscale(img.copyResize(src, width: sw, height: sh));
    gray = img.gaussianBlur(gray, radius: 2);

    final edges = _makeEdges(gray);
    final connected = _connectEdgesWithSize(edges, sw, sh);

    final candidates = <_Candidate>[];
    final visited = List<bool>.filled(sw * sh, false);
    final queue = <int>[];

    for (int y = 1; y < sh - 1; y++) {
      for (int x = 1; x < sw - 1; x++) {
        final start = y * sw + x;
        if (visited[start] || !connected[start]) continue;

        queue.clear();
        queue.add(start);
        visited[start] = true;

        int head = 0;
        int count = 0;
        int minX = x, maxX = x, minY = y, maxY = y;

        double minSum = double.infinity;
        double maxSum = -double.infinity;
        double minDiff = double.infinity;
        double maxDiff = -double.infinity;

        int tlX = x, tlY = y;
        int trX = x, trY = y;
        int brX = x, brY = y;
        int blX = x, blY = y;

        while (head < queue.length) {
          final idx = queue[head++];
          final py = idx ~/ sw;
          final px = idx - py * sw;
          count++;

          if (px < minX) minX = px;
          if (px > maxX) maxX = px;
          if (py < minY) minY = py;
          if (py > maxY) maxY = py;

          final sum = (px + py).toDouble();
          final diff = (px - py).toDouble();

          if (sum < minSum) {
            minSum = sum; tlX = px; tlY = py;
          }
          if (sum > maxSum) {
            maxSum = sum; brX = px; brY = py;
          }
          if (diff < minDiff) {
            minDiff = diff; blX = px; blY = py;
          }
          if (diff > maxDiff) {
            maxDiff = diff; trX = px; trY = py;
          }

          for (int dy = -1; dy <= 1; dy++) {
            for (int dx = -1; dx <= 1; dx++) {
              if (dx == 0 && dy == 0) continue;
              final nx = px + dx;
              final ny = py + dy;
              if (nx < 1 || nx >= sw - 1 || ny < 1 || ny >= sh - 1) {
                continue;
              }
              final ni = ny * sw + nx;
              if (!visited[ni] && connected[ni]) {
                visited[ni] = true;
                queue.add(ni);
              }
            }
          }
        }

        final bw = maxX - minX + 1;
        final bh = maxY - minY + 1;
        final bboxArea = bw * bh;
        final imageArea = sw * sh;

        // نرفض الضوضاء الصغيرة جدًا.
        if (count < max(30, imageArea ~/ 5000)) continue;
        if (bw < sw * 0.12 || bh < sh * 0.08) continue;
        if (bboxArea < imageArea * 0.07) continue;

        // نستخرج زوايا من أقصى نقاط الشكل.
        final qArea = _quadArea(
          tlX, tlY, trX, trY,
          brX, brY, blX, blY,
        );
        if (qArea < imageArea * 0.06) continue;

        final coverage = (qArea / imageArea).clamp(0.0, 1.0);
        final componentDensity = (count / bboxArea).clamp(0.0, 1.0);

        // العامل الأهم هو المساحة. هذا يمنع اختيار بطاقة صغيرة داخل ورقة.
        // الكثافة تستخدم فقط لكسر التعادل بين مرشحين متقاربين.
        final score = coverage * 0.82 + componentDensity * 0.18;

        candidates.add(_Candidate(
          sw: sw, sh: sh,
          tlX: tlX, tlY: tlY,
          trX: trX, trY: trY,
          brX: brX, brY: brY,
          blX: blX, blY: blY,
          score: score,
          areaRatio: coverage,
        ));
      }
    }

    if (candidates.isEmpty) {
      // fallback: مستطيل خارجي فقط عندما لا نستطيع بناء شكل موثوق.
      final rect = _fallbackRect(edges, sw, sh);
      if (rect == null) return null;

      final areaRatio =
          ((rect[2] - rect[0]) * (rect[3] - rect[1])) / (sw * sh);
      if (areaRatio < 0.08 || areaRatio > 0.94) return null;

      return _Candidate(
        sw: sw, sh: sh,
        tlX: rect[0], tlY: rect[1],
        trX: rect[2], trY: rect[1],
        brX: rect[2], brY: rect[3],
        blX: rect[0], blY: rect[3],
        score: areaRatio,
        areaRatio: areaRatio,
      );
    }

    candidates.sort((a, b) => b.score.compareTo(a.score));
    final best = candidates.first;

    // تحويل إحداثيات الصورة المصغرة إلى إحداثيات الصورة الأصلية.
    final sx = src.width / sw;
    final sy = src.height / sh;

    return _Candidate(
      sw: src.width, sh: src.height,
      tlX: best.tlX * sx, tlY: best.tlY * sy,
      trX: best.trX * sx, trY: best.trY * sy,
      brX: best.brX * sx, brY: best.brY * sy,
      blX: best.blX * sx, blY: best.blY * sy,
      score: best.score,
      areaRatio: best.areaRatio,
    );
  }

  static List<bool> _makeEdges(img.Image gray) {
    final w = gray.width, h = gray.height;
    final out = List<bool>.filled(w * h, false);

    for (int y = 1; y < h - 1; y++) {
      for (int x = 1; x < w - 1; x++) {
        final tl = gray.getPixel(x - 1, y - 1).r.toInt();
        final tc = gray.getPixel(x, y - 1).r.toInt();
        final tr = gray.getPixel(x + 1, y - 1).r.toInt();
        final ml = gray.getPixel(x - 1, y).r.toInt();
        final mr = gray.getPixel(x + 1, y).r.toInt();
        final bl = gray.getPixel(x - 1, y + 1).r.toInt();
        final bc = gray.getPixel(x, y + 1).r.toInt();
        final br = gray.getPixel(x + 1, y + 1).r.toInt();

        final gx = (tr + 2 * mr + br) - (tl + 2 * ml + bl);
        final gy = (bl + 2 * bc + br) - (tl + 2 * tc + tr);
        final mag = sqrt((gx * gx + gy * gy).toDouble());

        // Threshold متوازن: لا نريد التقاط كل تفاصيل النص.
        if (mag > 52) out[y * w + x] = true;
      }
    }
    return out;
  }

  static List<bool> _dilate(List<bool> src, int w, int h, int radius) {
    final out = List<bool>.filled(src.length, false);
    for (int y = 0; y < h; y++) {
      for (int x = 0; x < w; x++) {
        bool hit = false;
        for (int dy = -radius; dy <= radius && !hit; dy++) {
          final ny = y + dy;
          if (ny < 0 || ny >= h) continue;
          for (int dx = -radius; dx <= radius; dx++) {
            final nx = x + dx;
            if (nx < 0 || nx >= w) continue;
            if (src[ny * w + nx]) {
              hit = true;
              break;
            }
          }
        }
        out[y * w + x] = hit;
      }
    }
    return out;
  }

  static List<bool> _connectEdgesWithSize(List<bool> src, int w, int h) {
    var a = _dilate(src, w, h, 2);
    // تكرار صغير يساعد على ربط أضلاع الورقة، لكنه لا يحول الصورة كلها إلى حافة.
    a = _dilate(a, w, h, 1);
    return a;
  }

  static List<int>? _fallbackRect(List<bool> edges, int w, int h) {
    int? top, bottom, left, right;

    for (int y = 0; y < h; y++) {
      int c = 0;
      for (int x = 0; x < w; x++) {
        if (edges[y * w + x]) c++;
      }
      if (c > w * 0.10) { top = y; break; }
    }
    for (int y = h - 1; y >= 0; y--) {
      int c = 0;
      for (int x = 0; x < w; x++) {
        if (edges[y * w + x]) c++;
      }
      if (c > w * 0.10) { bottom = y; break; }
    }
    for (int x = 0; x < w; x++) {
      int c = 0;
      for (int y = 0; y < h; y++) {
        if (edges[y * w + x]) c++;
      }
      if (c > h * 0.10) { left = x; break; }
    }
    for (int x = w - 1; x >= 0; x--) {
      int c = 0;
      for (int y = 0; y < h; y++) {
        if (edges[y * w + x]) c++;
      }
      if (c > h * 0.10) { right = x; break; }
    }

    if (top == null || bottom == null || left == null || right == null) {
      return null;
    }
    if (right - left < w * 0.12 || bottom - top < h * 0.08) return null;
    return [left, top, right, bottom];
  }

  static double _quadArea(
    double x1, double y1, double x2, double y2,
    double x3, double y3, double x4, double y4,
  ) {
    return ((x1 * y2 + x2 * y3 + x3 * y4 + x4 * y1) -
            (y1 * x2 + y2 * x3 + y3 * x4 + y4 * x1))
        .abs() / 2.0;
  }
}

/// بيانات مرشح واحد.
class _Candidate {
  final double sw, sh;
  final double tlX, tlY, trX, trY, brX, brY, blX, blY;
  final double score, areaRatio;

  const _Candidate({
    required this.sw, required this.sh,
    required this.tlX, required this.tlY,
    required this.trX, required this.trY,
    required this.brX, required this.brY,
    required this.blX, required this.blY,
    required this.score, required this.areaRatio,
  });
}

/// ═══════════════════════════════════════
/// قص يدوي
/// ═══════════════════════════════════════
class ManualCrop {
  static img.Image cropPerspective(img.Image src,double x1,double y1,double x2,double y2,double x3,double y3,double x4,double y4){
    return PerspectiveWarp.warp(src,x1,y1,x2,y2,x3,y3,x4,y4);
  }
  static img.Image cropRect(img.Image src,double x1,double y1,double x2,double y2,double x3,double y3,double x4,double y4){
    final ax=[x1*src.width,x2*src.width,x3*src.width,x4*src.width],ay=[y1*src.height,y2*src.height,y3*src.height,y4*src.height];
    final l=ax.reduce(min).round().clamp(0,src.width-1),r=ax.reduce(max).round().clamp(1,src.width);
    final t=ay.reduce(min).round().clamp(0,src.height-1),b=ay.reduce(max).round().clamp(1,src.height);
    return img.copyCrop(src,x:l,y:t,width:max(10,r-l),height:max(10,b-t));
  }
}

/// ═══════════════════════════════════════
/// Google ML Kit
/// ═══════════════════════════════════════
class GoogleScanner {
  static Future<List<String>?> scan() async {
    try{
      final s=DocumentScanner(options:DocumentScannerOptions(documentFormats:{DocumentFormat.jpeg},mode:ScannerMode.filter,pageLimit:10,isGalleryImport:true));
      final r=await s.scanDocument();s.close();
      if(r.images==null||r.images!.isEmpty)return null;
      return r.images;
    }catch(_){return null;}
  }
}

/// ═══════════════════════════════════════
/// أدوات
/// ═══════════════════════════════════════
class ImageUtils {
  static List<int> encodeJpg(img.Image src,{int quality=92})=>img.encodeJpg(src,quality:quality);
  static img.Image? decodeBytes(dynamic bytes)=>bytes is Uint8List?img.decodeImage(bytes):bytes is List<int>?img.decodeImage(Uint8List.fromList(bytes)):null;
}
