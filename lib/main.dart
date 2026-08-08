import 'dart:io';
import 'dart:math';
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:image/image.dart' as img;
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';
import 'crop_engine.dart';

void main() => runApp(const MosulScannerApp());

class MosulScannerApp extends StatelessWidget {
  const MosulScannerApp({super.key});
  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'مكتب علاء الحديدي - الماسح والطباعة',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(primarySwatch: Colors.blue, useMaterial3: true),
      home: const MainScreen(),
    );
  }
}

class DocItem {
  String id;
  img.Image image;
  Uint8List bytes;
  double wMm, hMm, xMm, yMm;
  int rot;
  bool photo;
  DocItem({required this.id, required this.image, required this.bytes, required this.wMm, required this.hMm, required this.xMm, required this.yMm, this.rot = 0, this.photo = false});

  img.Image get rotated {
    if (rot % 360 == 0) return image;
    final r = (rot % 360 + 360) % 360;
    if (r == 90) return img.copyRotate(image, angle: 90);
    if (r == 180) return img.copyRotate(image, angle: 180);
    if (r == 270) return img.copyRotate(image, angle: 270);
    return image;
  }
  void applyRot() {
    if (rot % 360 == 0) return;
    image = rotated;
    bytes = Uint8List.fromList(ImageUtils.encodeJpg(image));
    final t = wMm; wMm = hMm; hMm = t; rot = 0;
  }
  void replaceImage(img.Image newImg) {
    image = newImg; bytes = Uint8List.fromList(ImageUtils.encodeJpg(newImg));
    rot = 0; hMm = newImg.height / newImg.width * wMm;
  }
}

class MainScreen extends StatefulWidget {
  const MainScreen({super.key});
  @override State<MainScreen> createState() => _MainScreenState();
}

class _MainScreenState extends State<MainScreen> {
  final List<DocItem> _items = [];
  DocItem? _sel;
  final ImagePicker _picker = ImagePicker();
  String _mode = 'docs';
  bool _busy = false;
  static const pwM = 210.0, phM = 297.0, mM = 10.0;

  void _addImgs(ImageSource src) async {
    final List<XFile> files = [];
    if (src == ImageSource.gallery) { files.addAll(await _picker.pickMultiImage()); }
    else { final f = await _picker.pickImage(source: src, imageQuality: 95); if (f != null) files.add(f); }
    for (int i = 0; i < files.length; i++) {
      final raw = await File(files[i].path).readAsBytes();
      final dec = ImageUtils.decodeJpg(raw); if (dec == null) continue;
      final enc = Uint8List.fromList(ImageUtils.encodeJpg(dec));
      setState(() {
        final item = DocItem(id: '${DateTime.now().millisecondsSinceEpoch}$i', image: dec, bytes: enc,
          wMm: _mode == 'photos' ? 36 : 85, hMm: _mode == 'photos' ? 45 : (dec.height / dec.width * 85),
          xMm: mM + _items.length * 4, yMm: mM + _items.length * 4, photo: _mode == 'photos');
        _items.add(item); _sel = item;
      });
    }
  }

  void _resz(double w, double h, {bool p = false}) { if (_sel != null) setState(() { _sel!.wMm = w; _sel!.hMm = h; _sel!.photo = p; }); }
  void _rot() { if (_sel != null) setState(() => _sel!.applyRot()); }
  void _dup() { if (_sel == null) return; final s = _sel!;
    setState(() { _items.add(DocItem(id: '${DateTime.now().millisecondsSinceEpoch}', image: img.copyResize(s.image, width: s.image.width),
      bytes: Uint8List.fromList(s.bytes), wMm: s.wMm, hMm: s.hMm, xMm: s.xMm + 5, yMm: s.yMm + 5, rot: s.rot, photo: s.photo)); _sel = _items.last; }); }
  void _aln() { setState(() { double cx = mM, cy = mM, mh = 0;
    for (var i in _items) { if (cx + i.wMm > pwM - mM) { cx = mM; cy += mh + 5; mh = 0; }
      i.xMm = cx; i.yMm = cy; cx += i.wMm + 5; if (i.hMm > mh) mh = i.hMm; } }); }

  void _autoCrop() { if (_sel == null) return; setState(() => _busy = true);
    Future(() { if (!mounted) return;
      var r = SmartCrop.adaptiveThreshold(_sel!.rotated);
      if (!r.changed) r = SmartCrop.sobelEdges(_sel!.rotated);
      if (mounted) { if (r.changed) { setState(() { _sel!.replaceImage(r.image); _busy = false; }); }
        else { setState(() => _busy = false); ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          content: Text('لم يتم اكتشاف مستند واضح'), backgroundColor: Colors.orange, duration: Duration(seconds: 2))); } } }); }

  void _manualCrop() async { if (_sel == null) return;
    final ri = _sel!.rotated; final res = await Navigator.push<img.Image>(context, MaterialPageRoute(builder: (_) => CropScreen(image: ri)));
    if (res != null && mounted) setState(() => _sel!.replaceImage(res)); }

  void _prnt() async { final doc = pw.Document();
    doc.addPage(pw.Page(pageFormat: PdfPageFormat.a4, margin: pw.EdgeInsets.zero, build: (_) { final ws = <pw.Widget>[];
      for (final i in _items) { final pi = i.rotated; ws.add(pw.Positioned(left: i.xMm * PdfPageFormat.mm, top: i.yMm * PdfPageFormat.mm,
        child: pw.SizedBox(width: i.wMm * PdfPageFormat.mm, height: i.hMm * PdfPageFormat.mm,
          child: pw.Image(pw.MemoryImage(Uint8List.fromList(ImageUtils.encodeJpg(pi, quality: 95))), fit: pw.BoxFit.fill)))); }
      return pw.Stack(children: List<pw.Widget>.from(ws)); }));
    await Printing.layoutPdf(onLayout: (_) async => doc.save()); }

  @override Widget build(BuildContext c) {
    return Scaffold(appBar: AppBar(
      title: const Text('مكتب علاء الحديدي - الماسح الذكي', style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold)),
      backgroundColor: const Color(0xFF0284C7), foregroundColor: Colors.white,
      actions: [IconButton(icon: const Icon(Icons.print, size: 18), tooltip: 'طباعة', onPressed: _prnt),
        IconButton(icon: const Icon(Icons.add_a_photo, size: 18), onPressed: () => _addImgs(ImageSource.camera)),
        IconButton(icon: const Icon(Icons.photo_library, size: 18), onPressed: () => _addImgs(ImageSource.gallery))]),
      body: LayoutBuilder(builder: (_, cc) {
        final sw = cc.maxWidth * 0.19, cw = cc.maxWidth - sw, tbh = 48.0;
        final sc = min((cw - 20) / pwM, (cc.maxHeight - tbh - 20) / phM);
        return Column(children: [
          Container(height: tbh, padding: const EdgeInsets.symmetric(horizontal: 4),
            decoration: const BoxDecoration(color: Color(0xFF1E293B)),
            child: Row(children: [const SizedBox(width: 4),
              _tb('مستمسكات', _mode=='docs', Colors.blueGrey, ()=>setState(()=>_mode='docs')),
              _tb('صور', _mode=='photos', Colors.blueGrey, ()=>setState(()=>_mode='photos')), const Spacer(),
              _tb('قص تلقائي', false, const Color(0xFFF59E0B), _autoCrop),
              _tb('قص يدوي', false, const Color(0xFF06B6D4), _manualCrop),
              _tb('ترتيب', false, const Color(0xFF10B981), _aln),
              _tb('تدوير', false, const Color(0xFF94A3B8), _rot),
              _tb('نسخ', false, const Color(0xFFA78BFA), _dup)])),
          Expanded(child: Row(children: [
            SizedBox(width: sw, child: Container(color: const Color(0xFFF1F5F9),
              child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                Container(margin: const EdgeInsets.all(4), padding: const EdgeInsets.all(6),
                  decoration: BoxDecoration(color: const Color(0xFF0369A1), borderRadius: BorderRadius.circular(4)),
                  child: const Text('القياسات (سم)', textAlign: TextAlign.center,
                    style: TextStyle(fontWeight: FontWeight.bold, fontSize: 10, color: Colors.white))),
                if (_mode == 'docs') ...[
                  _sz('بطاقة موحدة', '8.5 × 5.4', ()=>_resz(85,54)), _sz('بطاقة سكن', '8.8 × 5.8', ()=>_resz(88,58)),
                  _sz('ورقة كاملة A4', '21 × 29.7', ()=>_resz(210,297), clr: const Color(0xFF0F766E)) ] else ...[
                  _sz('معاملة', '3.6 × 4.5', ()=>_resz(36,45,p:true)), _sz('مصغر', '2.5 × 3.4', ()=>_resz(25,34,p:true)) ],
                const Spacer(),
                if (_sel!=null) Padding(padding: const EdgeInsets.all(4), child: SizedBox(height: 30, child: ElevatedButton.icon(
                  style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFFDC2626), foregroundColor: Colors.white,
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(6)), padding: const EdgeInsets.symmetric(horizontal: 6)),
                  onPressed: ()=>setState((){_items.remove(_sel);_sel=null;}),
                  icon: const Icon(Icons.delete_outline, size: 14), label: const Text('حذف', style: TextStyle(fontSize: 10, fontWeight: FontWeight.bold))))),
              ]))),
            Expanded(child: Container(color: const Color(0xFF1E293B),
              child: Center(child: Container(width: pwM * sc, height: phM * sc,
                decoration: BoxDecoration(color: Colors.white, boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.4), blurRadius: 12)]),
                child: ClipRect(child: Stack(children: List.generate(_items.length, (i){ final it=_items[i]; final act=_sel?.id==it.id;
                  return Positioned(left: it.xMm*sc, top: it.yMm*sc, width: it.wMm*sc, height: it.hMm*sc,
                    child: GestureDetector(onTap:()=>setState(()=>_sel=it),
                      onPanUpdate:(d)=>setState((){ it.xMm+=d.delta.dx/sc; it.yMm+=d.delta.dy/sc; }),
                      child: Container(decoration: BoxDecoration(
                        border: Border.all(color: act?Colors.blue:(it.photo?Colors.red.withOpacity(0.4):Colors.transparent), width: act?3:1),
                        boxShadow: act?[BoxShadow(color: Colors.blue.withOpacity(0.4), blurRadius: 8)]:null),
                        child: Transform.rotate(angle: it.rot*pi/180, child: Image.memory(it.bytes, fit: BoxFit.fill))))); }))))),
              ))),
          ]))
        ]);
      }));
  }

  Widget _tb(String l, bool sel, Color clr, VoidCallback fn) => Padding(padding: const EdgeInsets.symmetric(horizontal:2),
    child: Material(color: Colors.transparent, child: InkWell(onTap:_busy?null:fn, borderRadius: BorderRadius.circular(6),
      child: Container(padding: const EdgeInsets.symmetric(horizontal:8,vertical:6),
        decoration: BoxDecoration(color: sel?clr.withOpacity(0.25):Colors.transparent, borderRadius: BorderRadius.circular(6),
          border: Border.all(color: sel?clr:Colors.white24, width:1)),
        child: Text(l, style: TextStyle(fontSize:10,fontWeight:FontWeight.w700,color:sel?clr:Colors.white))))));

  Widget _sz(String t, String sub, VoidCallback fn, {Color clr = const Color(0xFF0369A1)}) => Padding(
    padding: const EdgeInsets.symmetric(horizontal:4,vertical:2), child: SizedBox(height:38, child: ElevatedButton(
      style: ElevatedButton.styleFrom(padding:EdgeInsets.zero,minimumSize:Size.zero,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(6)),
        backgroundColor: clr.withOpacity(0.06), foregroundColor: clr, side: BorderSide(color: clr.withOpacity(0.35)), elevation:0),
      onPressed:fn, child: Column(mainAxisAlignment:MainAxisAlignment.center, children:[
        Text(t, style: TextStyle(fontSize:9,fontWeight:FontWeight.w700,color:clr)),
        Text(sub, style: TextStyle(fontSize:7,fontWeight:FontWeight.w500,color:clr.withOpacity(0.7)))]))));
}

// ════════════════════════════════════
// شاشة القص اليدوي
// ════════════════════════════════════
class CropScreen extends StatefulWidget {
  final img.Image image;
  const CropScreen({super.key, required this.image});
  @override State<CropScreen> createState() => _CropScreenState();
}

class _CropScreenState extends State<CropScreen> {
  double _x1=0.05,_y1=0.05,_x2=0.95,_y2=0.05,_x3=0.95,_y3=0.95,_x4=0.05,_y4=0.95;
  EnhanceMode _filt=EnhanceMode.none;
  late Uint8List _disp;
  @override void initState(){super.initState();_disp=Uint8List.fromList(ImageUtils.encodeJpg(widget.image,quality:90));}

  void _done(){
    var res=ManualCrop.cropFromPoints(widget.image,_x1,_y1,_x2,_y2,_x3,_y3,_x4,_y4);
    res=ImageEnhancer.apply(res,_filt);
    Navigator.pop(context,res);
  }
  void _reset()=>setState((){_x1=_y1=0.05;_x2=0.95;_y2=0.05;_x3=0.95;_y3=0.95;_x4=0.05;_y4=0.95;});

  @override Widget build(BuildContext c)=>Scaffold(backgroundColor:Colors.black,
    body:SafeArea(child:Column(children:[
      Container(height:48,padding:const EdgeInsets.symmetric(horizontal:12),color:const Color(0xFF111827),
        child:Row(children:[
          IconButton(icon:const Icon(Icons.close,color:Colors.white70,size:20),onPressed:()=>Navigator.pop(context)),
          const Spacer(),
          _cBtn('أصلي',_filt==EnhanceMode.none,()=>setState(()=>_filt=EnhanceMode.none)),
          const SizedBox(width:6),_cBtn('تحسين',_filt==EnhanceMode.soft,()=>setState(()=>_filt=EnhanceMode.soft)),
          const SizedBox(width:6),_cBtn('أبيض وأسود',_filt==EnhanceMode.bw,()=>setState(()=>_filt=EnhanceMode.bw)),
          const SizedBox(width:16),
          TextButton.icon(onPressed:_reset,icon:const Icon(Icons.refresh,size:16,color:Colors.orange),label:const Text('إعادة',style:TextStyle(fontSize:11,color:Colors.orange))),
          const Spacer(),
          FilledButton.icon(style:FilledButton.styleFrom(backgroundColor:const Color(0xFF10B981),padding:const EdgeInsets.symmetric(horizontal:16,vertical:8)),
            onPressed:_done,icon:const Icon(Icons.check,size:18),label:const Text('تطبيق',style:TextStyle(fontSize:12,fontWeight:FontWeight.bold)))]))),
      Expanded(child:LayoutBuilder(builder:(_,cc){final w=cc.maxWidth,h=cc.maxHeight;
        return Stack(children:[
          Center(child:Image.memory(_disp,fit:BoxFit.contain)),
          IgnorePointer(child:CustomPaint(size:Size(w,h),painter:_Ovr(_x1*w,_y1*h,_x2*w,_y2*h,_x3*w,_y3*h,_x4*w,_y4*h))),
          CustomPaint(size:Size(w,h),painter:_Ln([Offset(_x1*w,_y1*h),Offset(_x2*w,_y2*h),Offset(_x3*w,_y3*h),Offset(_x4*w,_y4*h)])),
          _dot('↖',_x1,_y1,w,h,(dx,dy)=>setState((){_x1=dx;_y1=dy;})),
          _dot('↗',_x2,_y2,w,h,(dx,dy)=>setState((){_x2=dx;_y2=dy;})),
          _dot('↘',_x3,_y3,w,h,(dx,dy)=>setState((){_x3=dx;_y3=dy;})),
          _dot('↙',_x4,_y4,w,h,(dx,dy)=>setState((){_x4=dx;_y4=dy;})),
        ]);})),
      Container(height:36,color:const Color(0xFF111827),
        child:const Center(child:Text('اسحب الدوائر الزرقاء لتحديد منطقة القص',style:TextStyle(color:Colors.white54,fontSize:11))))])));

  Widget _dot(String lbl,double x,double y,double w,double h,void Function(double,double) s)=>Positioned(left:x*w-26,top:y*h-26,
    child:GestureDetector(behavior:HitTestBehavior.opaque,
      onPanUpdate:(d)=>s((x+d.delta.dx/w).clamp(0.0,1.0),(y+d.delta.dy/h).clamp(0.0,1.0)),
      child:Container(width:52,height:52,
        decoration:BoxDecoration(color:const Color(0xFF2563EB),shape:BoxShape.circle,
          border:Border.all(color:Colors.white,width:3.5),boxShadow:const [BoxShadow(color:Colors.black54,blurRadius:8,offset:Offset(0,2))]),
        child:Center(child:Text(lbl,style:const TextStyle(color:Colors.white,fontSize:14,fontWeight:FontWeight.bold))))));

  Widget _cBtn(String t,bool sel,VoidCallback fn)=>GestureDetector(onTap:fn,
    child:Container(padding:const EdgeInsets.symmetric(horizontal:10,vertical:6),
      decoration:BoxDecoration(color:sel?const Color(0xFF2563EB):const Color(0xFF1E293B),
        borderRadius:BorderRadius.circular(20),border:Border.all(color:sel?Colors.transparent:Colors.white24)),
      child:Text(t,style:TextStyle(color:Colors.white,fontSize:11,fontWeight:sel?FontWeight.bold:FontWeight.w500))));
}

class _Ovr extends CustomPainter{
  final double x1,y1,x2,y2,x3,y3,x4,y4;
  _Ovr(this.x1,this.y1,this.x2,this.y2,this.x3,this.y3,this.x4,this.y4);
  @override void paint(Canvas c,Size s){
    final o=Path()..addRect(Rect.fromLTWH(0,0,s.width,s.height));
    final i=Path()..moveTo(x1,y1)..lineTo(x2,y2)..lineTo(x3,y3)..lineTo(x4,y4)..close();
    c.drawPath(Path.combine(PathOperation.difference,o,i),Paint()..color=Colors.black.withOpacity(0.6));
    c.drawPath(i,Paint()..color=const Color(0xFF22D3EE).withOpacity(0.3)..style=PaintingStyle.stroke..strokeWidth=3);
  }
  @override bool shouldRepaint(_)=>true;
}

class _Ln extends CustomPainter{
  final List<Offset> p;
  _Ln(this.p);
  @override void paint(Canvas c,Size s){
    final w=Paint()..color=Colors.white..strokeWidth=1.5..style=PaintingStyle.stroke;
    final cy=Paint()..color=const Color(0xFF22D3EE)..strokeWidth=2.0..style=PaintingStyle.stroke;
    for(int i=0;i<4;i++){final a=p[i],b=p[(i+1)%4];c.drawLine(a,b,w);c.drawLine(a,b,cy);}
  }
  @override bool shouldRepaint(_)=>true;
}
