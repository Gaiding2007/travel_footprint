import 'package:flutter/services.dart';

/// 与原生侧（Kotlin）通讯：把图片存进系统相册 / 分享出去
class MediaService {
  static const MethodChannel _channel = MethodChannel('com.gaiding.travel_footprint/media');

  /// 返回保存后的 content uri
  static Future<String?> saveImage(Uint8List bytes, String fileName) async {
    return _channel.invokeMethod<String>('saveImage', {
      'bytes': bytes,
      'name': fileName,
    });
  }

  /// 用系统分享面板分享刚保存的图片，传 null 时分享最后一次保存的图片
  static Future<void> shareImage(String? uri) async {
    await _channel.invokeMethod<void>('shareImage', {'uri': uri});
  }
}
