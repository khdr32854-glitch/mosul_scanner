import 'package:permission_handler/permission_handler.dart';

class PermissionService {
  PermissionService._();

  static Future<bool> requestCameraPermission() async {
    final status = await Permission.camera.request();

    return status.isGranted;
  }

  static Future<bool> requestPhotosPermission() async {
    final status = await Permission.photos.request();

    return status.isGranted;
  }

  static Future<bool> requestScannerPermissions() async {
    final cameraStatus = await Permission.camera.request();

    if (!cameraStatus.isGranted) {
      return false;
    }

    final photosStatus = await Permission.photos.request();

    return photosStatus.isGranted;
  }

  static Future<bool> isCameraGranted() async {
    return await Permission.camera.isGranted;
  }

  static Future<bool> isPhotosGranted() async {
    return await Permission.photos.isGranted;
  }

  static Future<void> openSettings() async {
    await openAppSettings();
  }
}
