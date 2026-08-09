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
/// تحسين — CLAHE + Light Sharpen
/// ═══════════════════════════════════════
class ImageEnhancer {
  static img.Image enhance(img.Image src) {
    try {
      var r = _clahe(src);
      r = _lightSharpen(r);
      return r;
    } catch (_) { return img.adjustColor(src, brightness: 1.03, contrast: 1.08); }
  }

  static img.Image _clahe(img.Image src) {
    final w=src.width,h=src.height;
    final result=img.Image(width:w,height:h);
    const tile=32,blend=0.65;
    for(int ty=0;ty<h;ty+=tile)for(int tx=0;tx<w;tx+=tile){
      final ex=min(tx+tile,w),ey=min(ty+tile,h);
      final hr=List.filled(256,0),hg=List.filled(256,0),hb=List.filled(256,0);int cnt=0;
      for(int y=ty;y<ey;y++)for(int x=tx;x<ex;x++){final p=src.getPixel(x,y);hr[p.r.toInt()]++;hg[p.g.toInt()]++;hb[p.b.toInt()]++;cnt++;}
      final cr=_buildCdf(hr,cnt),cg=_buildCdf(hg,cnt),cb=_buildCdf(hb,cnt);
      for(int y=ty;y<ey;y++)for(int x=tx;x<ex;x++){
        final p=src.getPixel(x,y);
        final r=(cr[p.r.toInt()]*blend+p.r.toInt()*(1-blend)).round().clamp(0,255);
        final g=(cg[p.g.toInt()]*blend+p.g.toInt()*(1-blend)).round().clamp(0,255);
        final b=(cb[p.b.toInt()]*blend+p.b.toInt()*(1-blend)).round().clamp(0,255);
        result.setPixelRgba(x,y,r,g,b,p.a.toInt());
      }
    }
    return result;
  }

  static List<int> _buildCdf(List<int> hist,int cnt){
    final clip=(cnt/256*2.5).round();
    final c=List<int>.from(hist);int excess=0;
    for(int i=0;i<256;i++){if(c[i]>clip){excess+=c[i]-clip;c[i]=clip;}}
    double add=excess/256,sum=0;
    final cdf=List.filled(256,0);
    for(int i=0;i<256;i++){sum+=c[i]+add;cdf[i]=(sum*255/cnt).round().clamp(0,255);}
    return cdf;
  }

  static img.Image _lightSharpen(img.Image src){
    final w=src.width,h=src.height,result=img.Image(width:w,height:h);
    for(int y=0;y<h;y++)for(int x=0;x<w;x++){final p=src.getPixel(x,y);result.setPixelRgba(x,y,p.r.toInt(),p.g.toInt(),p.b.toInt(),255);}
    for(int y=1;y<h-1;y++)for(int x=1;x<w-1;x++){
      final c=src.getPixel(x,y),u=src.getPixel(x,y-1),d=src.getPixel(x,y+1),lf=src.getPixel(x-1,y),rt=src.getPixel(x+1,y);
      result.setPixelRgba(x,y,
        (c.r.toInt()*4.8-u.r.toInt()*.8-d.r.toInt()*.8-lf.r.toInt()*.8-rt.r.toInt()*.8).round().clamp(0,255),
        (c.g.toInt()*4.8-u.g.toInt()*.8-d.g.toInt()*.8-lf.g.toInt()*.8-rt.g.toInt()*.8).round().clamp(0,255),
        (c.b.toInt()*4.8-u.b.toInt()*.8-d.b.toInt()*.8-lf.b.toInt()*.8-rt.b.toInt()*.8).round().clamp(0,255),
        c.a.toInt());
    }
    return result;
  }

  static img.Image blackWhite(img.Image src){
    var gray=img.grayscale(src);
    gray=img.gaussianBlur(gray,radius:1);
    return _adaptiveThreshold(gray,31,8);
  }

  static img.Image _adaptiveThreshold(img.Image gray,int blockSize,int C){
    final w=gray.width,h=gray.height,half=blockSize~/2,result=img.Image(width:w,height:h);
    for(int y=0;y<h;y++)for(int x=0;x<w;x++){
      int sum=0,cnt=0;
      for(int dy=-half;dy<=half;dy++)for(int dx=-half;dx<=half;dx++){
        final nx=(x+dx).clamp(0,w-1),ny=(y+dy).clamp(0,h-1);
        sum+=gray.getPixel(nx,ny).r.toInt();cnt++;
      }
      final bw=gray.getPixel(x,y).r.toInt()>sum~/cnt-C?255:0;
      result.setPixelRgba(x,y,bw,bw,bw,255);
    }
    return result;
  }

  static img.Image apply(img.Image src,EnhanceMode mode){
    switch(mode){case EnhanceMode.soft:return enhance(src);case EnhanceMode.bw:return blackWhite(src);case EnhanceMode.none:return src;}
  }
}

/// ═══════════════════════════════════════
/// قص تلقائي
/// ═══════════════════════════════════════
class SmartCrop {
  /// قص تلقائي — يرجع الصورة المقصوصة
  static CropResult detect(img.Image src){
    if(src.width<100||src.height<100)return CropResult(image:src,changed:false);
    final rect=_detectRectOnImage(src);
    if(rect==null)return CropResult(image:src,changed:false);
    final pad=8.0,ox=(rect[0]-pad).clamp(0,src.width-1),oy=(rect[1]-pad).clamp(0,src.height-1);
    final ow=(rect[2]-rect[0]+pad*2).clamp(20,src.width-ox).round(),oh=(rect[3]-rect[1]+pad*2).clamp(20,src.height-oy).round();
    return CropResult(image:img.copyCrop(src,x:ox,y:oy,width:ow,height:oh),changed:true);
  }

  /// كشف الزوايا الأربع (كنسب 0-1) — لاستخدامها في أداة القص اليدوي
  static List<double>? detectCorners(img.Image src){
    if(src.width<100||src.height<100)return null;
    final rect=_detectRectOnImage(src);
    if(rect==null)return null;
    final pad=6.0;
    return[
      ((rect[0]-pad)/src.width).clamp(0.0,1.0),((rect[1]-pad)/src.height).clamp(0.0,1.0),
      ((rect[2]+pad)/src.width).clamp(0.0,1.0),((rect[1]-pad)/src.height).clamp(0.0,1.0),
      ((rect[2]+pad)/src.width).clamp(0.0,1.0),((rect[3]+pad)/src.height).clamp(0.0,1.0),
      ((rect[0]-pad)/src.width).clamp(0.0,1.0),((rect[3]+pad)/src.height).clamp(0.0,1.0),
    ];
  }

  static List<int>? _detectRectOnImage(img.Image src){
    const target=256;
    final ratio=max(src.width,src.height)/target;
    final sw=(src.width/ratio).round(),sh=(src.height/ratio).round();
    var gray=img.grayscale(img.copyResize(src,width:sw,height:sh));
    gray=img.gaussianBlur(gray,radius:3);
    final rect=_detectRect(gray);
    if(rect==null)return null;
    return[
      (rect[0]*ratio).round(),(rect[1]*ratio).round(),
      (rect[2]*ratio).round(),(rect[3]*ratio).round(),
    ];
  }

  static List<int>? _detectRect(img.Image gray){
    final w=gray.width,h=gray.height;
    var edges=img.Image(width:w,height:h);
    for(int y=1;y<h-1;y++)for(int x=1;x<w-1;x++){
      final tl=gray.getPixel(x-1,y-1).r.toInt(),tc=gray.getPixel(x,y-1).r.toInt(),tr=gray.getPixel(x+1,y-1).r.toInt();
      final ml=gray.getPixel(x-1,y).r.toInt(),mr=gray.getPixel(x+1,y).r.toInt();
      final bl=gray.getPixel(x-1,y+1).r.toInt(),bc=gray.getPixel(x,y+1).r.toInt(),br=gray.getPixel(x+1,y+1).r.toInt();
      final mag=sqrt(((tr+2*mr+br)-(tl+2*ml+bl)).toDouble().pow(2)+((bl+2*bc+br)-(tl+2*tc+tr)).toDouble().pow(2)).toInt().clamp(0,255);
      final v=mag>40?255:0;edges.setPixelRgba(x,y,v,v,v,255);
    }
    for(int p=0;p<3;p++){final d=img.Image(width:w,height:h);
      for(int y=0;y<h;y++)for(int x=0;x<w;x++){int mx=0;for(int dy=-2;dy<=2;dy++)for(int dx=-2;dx<=2;dx++)mx=max(mx,edges.getPixel((x+dx).clamp(0,w-1),(y+dy).clamp(0,h-1)).r.toInt());d.setPixelRgba(x,y,mx,mx,mx,255);}
      edges=d;
    }
    final th=64;int? t,b,l,r;
    for(int y=0;y<h;y++){int ec=0;for(int x=0;x<w;x++)if(edges.getPixel(x,y).r.toInt()>th)ec++;if(ec>w*0.03){t=y;break;}}
    for(int y=h-1;y>=0;y--){int ec=0;for(int x=0;x<w;x++)if(edges.getPixel(x,y).r.toInt()>th)ec++;if(ec>w*0.03){b=y;break;}}
    for(int x=0;x<w;x++){int ec=0;for(int y=0;y<h;y++)if(edges.getPixel(x,y).r.toInt()>th)ec++;if(ec>h*0.03){l=x;break;}}
    for(int x=w-1;x>=0;x--){int ec=0;for(int y=0;y<h;y++)if(edges.getPixel(x,y).r.toInt()>th)ec++;if(ec>h*0.03){r=x;break;}}
    if(t==null||b==null||l==null||r==null||r-l<12||b-t<12)return null;
    return[l,t,r,b];
  }
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
