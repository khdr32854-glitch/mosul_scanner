# Mosul Scanner for Flutlab.io

## طريقة الاستخدام على Flutlab

1. افتح https://flutlab.io
2. اسحب مجلد `mosul_scanner` بالكامل أو ارفع الملفات
3. تأكد من أن `pubspec.yaml` يحتوي على:
   - `sdk: '>=2.18.0 <3.0.0'`
   - `image_picker: ^0.8.7`
   - `image: ^4.0.17`
4. اضغط Run

## الملفات
- `pubspec.yaml` - تبعيات المشروع (Dart فقط - لا NDK ولا C++)
- `lib/main.dart` - كود التطبيق بالكامل (كاميرا + كشف + قص + تحسين)
