import 'dart:math' as math;
import 'dart:typed_data';

import 'package:image/image.dart' as img;
import 'package:google_mlkit_document_scanner/google_mlkit_document_scanner.dart';

class GoogleScanner {
  static Future<List<String>> scan() async {
    final s=DocumentScanner(options:DocumentScannerOptions(documentFormats:const{DocumentFormat.jpeg},pageLimit:20,mode:ScannerMode.full,isGalleryImport:true));
    try{final r=await s.scanDocument();return List<String>.from(r.images??const[]);}finally{await s.close();}
  }
}

class ImageUtils {
  static img.Image? decodeBytes(dynamic bytes){try{if(bytes is Uint8List)return img.decodeImage(bytes);if(bytes is List<int>)return img.decodeImage(Uint8List.fromList(bytes));return null;}catch(_){return null;}}
  static List<int> encodeJpg(img.Image src,{int quality=92})=>img.encodeJpg(src,quality:quality.clamp(1,100));
  static Uint8List encodeJpgBytes(img.Image src,{int quality=92})=>Uint8List.fromList(encodeJpg(src,quality:quality));
  static bool isValid(img.Image? i)=>i!=null&&i.width>=10&&i.height>=10;
}

class CropResult{final img.Image image;final bool changed;final double confidence;const CropResult({required this.image,required this.changed,required this.confidence});}
enum EnhanceMode{none,soft,bw}

class ImageEnhancer{
  static img.Image apply(img.Image s,EnhanceMode m){switch(m){case EnhanceMode.none:return s.clone();case EnhanceMode.soft:return _soft(s);case EnhanceMode.bw:return _bw(s);}}
  static img.Image _soft(img.Image i){try{return img.adjustColor(i,contrast:1.12,brightness:1.04,saturation:1.03);}catch(_){return i;}}
  static img.Image _bw(img.Image i){try{final g=img.grayscale(i);return img.adjustColor(g,contrast:1.22,brightness:1.03);}catch(_){return i;}}
}

class _Pt{final double x,y;const _Pt(this.x,this.y);}
class _Ln{final double a,b;const _Ln(this.a,this.b);double y(double x)=>a*x+b;}
class _Rgb{final double r,g,b;const _Rgb(this.r,this.g,this.b);}
class _Cand{final List<double> c;final double s;final String t;const _Cand({required this.c,required this.s,required this.t});}

class SmartCrop{
  static const _as=760;static const _ma=0.12;
  static CropResult detect(img.Image src){
    if(!ImageUtils.isValid(src))return CropResult(image:src.clone(),changed:false,confidence:0);
    final cs=<_Cand>[];
    final d=detectCorners(src);
    if(d!=null&&_vn(d))cs.add(_Cand(c:d,s:0.95,t:'edge'));
    final f=_fb(src);if(f!=null)cs.add(_Cand(c:f,s:0.82,t:'fg'));
    final p=_pb(src);if(p!=null)cs.add(_Cand(c:p,s:0.76,t:'proj'));
    if(cs.isNotEmpty){cs.sort((a,b)=>b.s.compareTo(a.s));final b=cs.first;final r=ManualCrop.cropPerspective(src,b.c[0],b.c[1],b.c[2],b.c[3],b.c[4],b.c[5],b.c[6],b.c[7]);return CropResult(image:r,changed:r.width!=src.width||r.height!=src.height,confidence:b.s);}
    final fb=_fs(src);final r=ManualCrop.cropPerspective(src,fb[0],fb[1],fb[2],fb[3],fb[4],fb[5],fb[6],fb[7]);return CropResult(image:r,changed:r.width!=src.width||r.height!=src.height,confidence:0.25);
  }

  static List<double>? detectCorners(img.Image src){
    if(!ImageUtils.isValid(src))return null;
    final sc=math.min(1.0,_as/math.max(src.width,src.height));
    final sm=sc<1.0?img.copyResize(src,width:math.max(1,(src.width*sc).round()),height:math.max(1,(src.height*sc).round())):src.clone();
    final w=sm.width,h=sm.height;if(w<80||h<80)return null;
    final tp=<_Pt>[],bp=<_Pt>[],lp=<_Pt>[],rp=<_Pt>[];const ns=100;final th=_et(sm);
    for(int i=0;i<ns;i++){final x=((i+0.5)*w/ns).round().clamp(3,w-4);
      double bs=0;int by=(h*0.04).round();for(int y=(h*0.015).round();y<=(h*0.48).round();y++){final e=_ve(sm,x,y);final pw=1.0+((h*0.48-y)/(h*0.48))*0.35;final s=e*pw;if(s>bs){bs=s;by=y;}}if(bs>=th)tp.add(_Pt(x.toDouble(),by.toDouble()));
      bs=0;by=(h*0.96).round();for(int y=(h*0.52).round();y<=(h*0.985).round();y++){final e=_ve(sm,x,y);final pw=1.0+((y-h*0.52)/math.max(1,h*0.985-h*0.52))*0.35;final s=e*pw;if(s>bs){bs=s;by=y;}}if(bs>=th)bp.add(_Pt(x.toDouble(),by.toDouble()));
    }
    for(int i=0;i<ns;i++){final y=((i+0.5)*h/ns).round().clamp(3,h-4);
      double bs=0;int bx=(w*0.04).round();for(int x=(w*0.015).round();x<=(w*0.48).round();x++){final e=_he(sm,x,y);final pw=1.0+((w*0.48-x)/(w*0.48))*0.35;final s=e*pw;if(s>bs){bs=s;bx=x;}}if(bs>=th)lp.add(_Pt(bx.toDouble(),y.toDouble()));
      bs=0;bx=(w*0.96).round();for(int x=(w*0.52).round();x<=(w*0.985).round();x++){final e=_he(sm,x,y);final pw=1.0+((x-w*0.52)/math.max(1,w*0.985-w*0.52))*0.35;final s=e*pw;if(s>bs){bs=s;bx=x;}}if(bs>=th)rp.add(_Pt(bx.toDouble(),y.toDouble()));
    }
    if(tp.length<12||bp.length<12||lp.length<12||rp.length<12)return null;
    final t=_fh(tp,w,h,upper:true),b=_fh(bp,w,h,upper:false),l=_fv(lp,w,h,ls:true),r=_fv(rp,w,h,ls:false);
    if(t==null||b==null||l==null||r==null)return null;
    final tl=_ix(t,l),tr=_ix(t,r),br=_ix(b,r),bl=_ix(b,l);
    if(tl==null||tr==null||br==null||bl==null)return null;
    final n=[tl.x/w,tl.y/h,tr.x/w,tr.y/h,br.x/w,br.y/h,bl.x/w,bl.y/h];
    return _vn(n)?n:null;
  }

  static double _et(img.Image im){final vs=<double>[];final sx=math.max(1,im.width~/36),sy=math.max(1,im.height~/36);for(int y=3;y<im.height-3;y+=sy)for(int x=3;x<im.width-3;x+=sx){vs.add(_ve(im,x,y));vs.add(_he(im,x,y));}if(vs.isEmpty)return 8;vs.sort();return math.max(6.0,math.min(42.0,math.max(vs[vs.length~/2]*1.45,vs[((vs.length-1)*0.75).round()]*0.48)));}
  static double _ve(img.Image im,int x,int y){final a=_lu(im.getPixel(x,y-2)),b=_lu(im.getPixel(x,y+2)),c=_lu(im.getPixel(x,y-1)),d=_lu(im.getPixel(x,y+1));return(a-b).abs()*0.65+(c-d).abs()*0.35;}
  static double _he(img.Image im,int x,int y){final a=_lu(im.getPixel(x-2,y)),b=_lu(im.getPixel(x+2,y)),c=_lu(im.getPixel(x-1,y)),d=_lu(im.getPixel(x+1,y));return(a-b).abs()*0.65+(c-d).abs()*0.35;}
  static double _lu(img.Pixel p)=>0.2126*p.r+0.7152*p.g+0.0722*p.b;

  static _Ln? _fh(List<_Pt> pts,int w,int h,{required bool upper}){if(pts.length<8)return null;_Ln? b;int bi=0;double be=double.infinity;final mx=math.min(220,pts.length*4);for(int i=0;i<mx;i++){final p1=pts[(i*7)%pts.length],p2=pts[(i*19+3)%pts.length];if((p1.x-p2.x).abs()<w*0.10)continue;final a=(p2.y-p1.y)/(p2.x-p1.x);if(a.abs()>0.75)continue;final bb=p1.y-a*p1.x;int inl=0;double er=0;for(final p in pts){final d=(a*p.x+bb-p.y).abs();if(d<=math.max(3.0,h*0.014)){inl++;er+=d;}}if(inl>bi||(inl==bi&&er<be)){bi=inl;be=er;b=_Ln(a,bb);}}if(b==null||bi<math.max(8,(pts.length*0.20).round()))return null;final yc=b.y(w/2);if(upper&&yc>h*0.58)return null;if(!upper&&yc<h*0.42)return null;return b;}
  static _Ln? _fv(List<_Pt> pts,int w,int h,{required bool ls}){if(pts.length<8)return null;_Ln? b;int bi=0;double be=double.infinity;final mx=math.min(220,pts.length*4);for(int i=0;i<mx;i++){final p1=pts[(i*7)%pts.length],p2=pts[(i*17+5)%pts.length];if((p1.y-p2.y).abs()<h*0.10)continue;final a=(p2.x-p1.x)/(p2.y-p1.y);if(a.abs()>0.75)continue;final bb=p1.x-a*p1.y;int inl=0;double er=0;for(final p in pts){final d=(a*p.y+bb-p.x).abs();if(d<=math.max(3.0,w*0.014)){inl++;er+=d;}}if(inl>bi||(inl==bi&&er<be)){bi=inl;be=er;b=_Ln(a,bb);}}if(b==null||bi<math.max(8,(pts.length*0.20).round()))return null;final xc=b.y(h/2);if(ls&&xc>w*0.58)return null;if(!ls&&xc<w*0.42)return null;return b;}
  static _Pt? _ix(_Ln h,_Ln v){final d=1.0-v.a*h.a;if(d.abs()<0.000001)return null;final x=(v.a*h.b+v.b)/d,y=h.a*x+h.b;return(x.isFinite&&y.isFinite)?_Pt(x,y):null;}
  static bool _vn(List<double> p){if(p.length!=8)return false;for(final v in p){if(!v.isFinite||v<-0.12||v>1.12)return false;}final tl=_Pt(p[0],p[1]),tr=_Pt(p[2],p[3]),br=_Pt(p[4],p[5]),bl=_Pt(p[6],p[7]);if(_pa([tl,tr,br,bl])<_ma)return false;final tw=_di(tl,tr),bw=_di(bl,br),lh=_di(tl,bl),rh=_di(tr,br);if(tw<0.10||bw<0.10||lh<0.10||rh<0.10)return false;final r1=tw/math.max(0.001,lh),r2=bw/math.max(0.001,rh);return!(r1<0.12||r1>9.0||r2<0.12||r2>9.0);}

  static List<double>? _fb(img.Image src){final sc=math.min(1.0,720/math.max(src.width,src.height));final im=sc<1.0?img.copyResize(src,width:math.max(1,(src.width*sc).round()),height:math.max(1,(src.height*sc).round())):src.clone();final w=im.width,h=im.height;if(w<50||h<50)return null;final bg=_eb(im);List<double>? b;double bs=-double.infinity;for(final th in[10.0,15,20,25,32,40]){final bx=_fbt(im,bg,th);if(bx==null)continue;final c=_bn(bx,w,h);if(!_vn(c))continue;double sc2=_pa([_Pt(c[0],c[1]),_Pt(c[2],c[3]),_Pt(c[4],c[5]),_Pt(c[6],c[7])]);if(sc2>0.96)sc2-=0.25;if(sc2>0.90)sc2-=0.08;if(sc2>bs){bs=sc2;b=c;}}return b;}
  static _Rgb _eb(img.Image im){final w=im.width,h=im.height,st=math.max(1,math.min(w,h)~/25);final vs=<_Rgb>[];for(int x=0;x<w;x+=st){vs.add(_pr(im.getPixel(x,1)));vs.add(_pr(im.getPixel(x,h-2)));}for(int y=0;y<h;y+=st){vs.add(_pr(im.getPixel(1,y)));vs.add(_pr(im.getPixel(w-2,y)));}if(vs.isEmpty)return const _Rgb(128,128,128);final rs=vs.map((e)=>e.r).toList()..sort(),gs=vs.map((e)=>e.g).toList()..sort(),bs2=vs.map((e)=>e.b).toList()..sort();return _Rgb(rs[rs.length~/2],gs[gs.length~/2],bs2[bs2.length~/2]);}
  static List<int>? _fbt(img.Image im,_Rgb bg,double th){final w=im.width,h=im.height,st=math.max(1,math.min(w,h)~/220);int mx=-1,my=-1,mnx=w,mny=h;for(int y=2;y<h-2;y+=st)for(int x=2;x<w-2;x+=st)if(_cd(_pr(im.getPixel(x,y)),bg)>th){if(x<mnx)mnx=x;if(y<mny)mny=y;if(x>mx)mx=x;if(y>my)my=y;}if(mx<=mnx||my<=mny)return null;final px=math.max(2,((mx-mnx)*0.018).round()),py=math.max(2,((my-mny)*0.018).round());mnx=math.max(1,mnx-px);mny=math.max(1,mny-py);mx=math.min(w-2,mx+px);my=math.min(h-2,my+py);if(((mx-mnx)*(my-mny))/(w*h)<0.10)return null;return[mnx,mny,mx,my];}

  static List<double>? _pb(img.Image src){final sc=math.min(1.0,680/math.max(src.width,src.height));final im=sc<1.0?img.copyResize(src,width:math.max(1,(src.width*sc).round()),height:math.max(1,(src.height*sc).round())):src.clone();final w=im.width,h=im.height,bg=_eb(im);final col=List.filled(w,0.0),row=List.filled(h,0.0);final ss=math.max(1,math.min(w,h)~/100);for(int y=0;y<h;y+=ss)for(int x=0;x<w;x+=ss){final d=_cd(_pr(im.getPixel(x,y)),bg);row[y]+=d;col[x]+=d;}final sr=_sm(row,math.max(2,h~/70)),sc2=_sm(col,math.max(2,w~/70));final t=_fp(sr,fs:true),b=_fp(sr,fs:false),l=_fp(sc2,fs:true),r=_fp(sc2,fs:false);if(t==null||b==null||l==null||r==null||r<=l||b<=t)return null;final c=[l/w,t/h,r/w,t/h,r/w,b/h,l/w,b/h];return _vn(c)?c:null;}
  static int? _fp(List<double> vs,{required bool fs}){if(vs.length<10)return null;final st=List.from(vs)..sort();final th=math.max(st[((st.length-1)*0.35).round()]*1.20,st[((st.length-1)*0.35).round()]+4);if(fs){for(int i=3;i<vs.length*0.60;i++)if(vs[i]>th)return i;}else{for(int i=vs.length-4;i>vs.length*0.40;i--)if(vs[i]>th)return i;}return null;}
  static List<double> _sm(List<double> vs,int r){if(vs.isEmpty)return[];final rs=List.filled(vs.length,0.0);for(int i=0;i<vs.length;i++){final s=math.max(0,i-r),e=math.min(vs.length-1,i+r);double sum=0;for(int j=s;j<=e;j++)sum+=vs[j];rs[i]=sum/(e-s+1);}return rs;}
  static List<double> _bn(List<int> bx,int w,int h)=>[bx[0]/w,bx[1]/h,bx[2]/w,bx[1]/h,bx[2]/w,bx[3]/h,bx[0]/w,bx[3]/h];
  static List<double> _fs(img.Image src)=>const[0.008,0.008,0.992,0.008,0.992,0.992,0.008,0.992];
  static _Rgb _pr(img.Pixel p)=>_Rgb(p.r.toDouble(),p.g.toDouble(),p.b.toDouble());
  static double _cd(_Rgb a,_Rgb b){final dr=a.r-b.r,dg=a.g-b.g,db=a.b-b.b;return math.sqrt(dr*dr+dg*dg+db*db);}
  static double _pa(List<_Pt> ps){double s=0;for(int i=0;i<ps.length;i++){final j=(i+1)%ps.length;s+=ps[i].x*ps[j].y-ps[j].x*ps[i].y;}return s.abs()/2;}
  static double _di(_Pt a,_Pt b){final dx=a.x-b.x,dy=a.y-b.y;return math.sqrt(dx*dx+dy*dy);}
}

class ManualCrop{
  static img.Image cropPerspective(img.Image s,double x1,double y1,double x2,double y2,double x3,double y3,double x4,double y4){
    if(!ImageUtils.isValid(s))return s.clone();
    final ps=[_Pt(x1.clamp(0,1),y1.clamp(0,1)),_Pt(x2.clamp(0,1),y2.clamp(0,1)),_Pt(x3.clamp(0,1),y3.clamp(0,1)),_Pt(x4.clamp(0,1),y4.clamp(0,1))];
    final q=[for(final p in ps)_Pt(p.x*s.width,p.y*s.height)];if(!_vq(q))return s.clone();
    final tw=_di(q[0],q[1]),bw=_di(q[3],q[2]),lh=_di(q[0],q[3]),rh=_di(q[1],q[2]);
    int ow=math.max(1,((tw+bw)/2).round()),oh=math.max(1,((lh+rh)/2).round());
    final lng=math.max(ow,oh);if(lng>3200){final f=3200/lng;ow=math.max(1,(ow*f).round());oh=math.max(1,(oh*f).round());}
    final h=_ch(q,[_Pt(0,0),_Pt(ow-1.0,0),_Pt(ow-1.0,oh-1.0),_Pt(0,oh-1.0)]);if(h==null)return s.clone();
    final inv=_ih(h);if(inv==null)return s.clone();
    final o=img.Image(width:ow,height:oh,numChannels:3);
    for(int y=0;y<oh;y++)for(int x=0;x<ow;x++){final m=_mp(inv,x.toDouble(),y.toDouble());if(m==null||m.x<0||m.y<0||m.x>s.width-1||m.y>s.height-1){o.setPixelRgb(x,y,255,255,255);continue;}final p=s.getPixelCubic(m.x,m.y);o.setPixelRgb(x,y,p.r,p.g,p.b);}
    return o;
  }
  static img.Image cropRect(img.Image s,double x1,double y1,double x2,double y2,double x3,double y3,double x4,double y4){final ax=[x1*s.width,x2*s.width,x3*s.width,x4*s.width],ay=[y1*s.height,y2*s.height,y3*s.height,y4*s.height];final l=ax.reduce(math.min).round().clamp(0,s.width-1),r=ax.reduce(math.max).round().clamp(1,s.width),t=ay.reduce(math.min).round().clamp(0,s.height-1),b=ay.reduce(math.max).round().clamp(1,s.height);return img.copyCrop(s,x:l,y:t,width:math.max(10,r-l),height:math.max(10,b-t));}
  static bool _vq(List<_Pt> p){if(_ar(p)<1.0)return false;final sn=<double>[];for(int i=0;i<4;i++){final a=p[i],b=p[(i+1)%4],c=p[(i+2)%4];sn.add((b.x-a.x)*(c.y-b.y)-(b.y-a.y)*(c.x-b.x));}return!(sn.any((v)=>v>0)&&sn.any((v)=>v<0));}
  static double _ar(List<_Pt> p){double v=0;for(int i=0;i<p.length;i++){final j=(i+1)%p.length;v+=p[i].x*p[j].y-p[j].x*p[i].y;}return v.abs()/2;}
  static List<double>? _ch(List<_Pt> s,List<_Pt> d){final m=List.generate(8,(_)=>List.filled(9,0.0));for(int i=0;i<4;i++){final x=s[i].x,y=s[i].y,u=d[i].x,v=d[i].y,r=i*2;m[r][0]=x;m[r][1]=y;m[r][2]=1;m[r][6]=-u*x;m[r][7]=-u*y;m[r][8]=u;m[r+1][3]=x;m[r+1][4]=y;m[r+1][5]=1;m[r+1][6]=-v*x;m[r+1][7]=-v*y;m[r+1][8]=v;}for(int c=0;c<8;c++){int pv=c;for(int r=c+1;r<8;r++)if(m[r][c].abs()>m[pv][c].abs())pv=r;if(m[pv][c].abs()<1e-10)return null;if(pv!=c){final t=m[pv];m[pv]=m[c];m[c]=t;}final dv=m[c][c];for(int j=c;j<=8;j++)m[c][j]/=dv;for(int r=0;r<8;r++){if(r==c)continue;final f=m[r][c];if(f.abs()<1e-12)continue;for(int j=c;j<=8;j++)m[r][j]-=f*m[c][j];}}return[m[0][8],m[1][8],m[2][8],m[3][8],m[4][8],m[5][8],m[6][8],m[7][8],1];}
  static List<double>? _ih(List<double> h){final a=h[0],b=h[1],c=h[2],d=h[3],e=h[4],f=h[5],g=h[6],i=h[7],j=h[8];final A=e*j-f*i,B=-(d*j-f*g),C=d*i-e*g,D=-(b*j-c*i),E=a*j-c*g,F=-(a*i-b*g),G=b*f-c*e,H=-(a*f-c*d),I=a*e-b*d;final det=a*A+b*B+c*C;if(det.abs()<1e-12)return null;return[A/det,D/det,G/det,B/det,E/det,H/det,C/det,F/det,I/det];}
  static _Pt? _mp(List<double> h,double x,double y){final d=h[6]*x+h[7]*y+h[8];if(d.abs()<1e-10)return null;final nx=h[0]*x+h[1]*y+h[2],ny=h[3]*x+h[4]*y+h[5];final rx=nx/d,ry=ny/d;return(rx.isFinite&&ry.isFinite)?_Pt(rx,ry):null;}
  static double _di(_Pt a,_Pt b){final dx=a.x-b.x,dy=a.y-b.y;return math.sqrt(dx*dx+dy*dy);}
}
