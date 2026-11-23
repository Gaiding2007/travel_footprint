import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/rendering.dart';
import 'package:flutter/widgets.dart';

import 'media_service.dart';

/// 把 RepaintBoundary 里的地图截成 PNG，再交给原生存进相册
class ExportService {
  /// 截图（logical 尺寸的 [pixelRatio] 倍）
  static Future<Uint8List?> capturePng(GlobalKey boundaryKey, {double pixelRatio = 3}) async {
    final renderObject = boundaryKey.currentContext?.findRenderObject();
    if (renderObject is! RenderRepaintBoundary) return null;
    final image = await renderObject.toImage(pixelRatio: pixelRatio);
    try {
      final data = await image.toByteData(format: ui.ImageByteFormat.png);
      return data?.buffer.asUint8List();
    } finally {
      image.dispose();
    }
  }

  static String buildFileName(String prefix) {
    final now = DateTime.now();
    String two(int value) => value.toString().padLeft(2, '0');
    return '$prefix-${now.year}${two(now.month)}${two(now.day)}-'
        '${two(now.hour)}${two(now.minute)}${two(now.second)}.png';
  }

  /// 截图 + 保存到相册，返回 content uri
  static Future<String?> saveToGallery(GlobalKey boundaryKey, {String prefix = 'travel-footprint'}) async {
    final bytes = await capturePng(boundaryKey);
    if (bytes == null) return null;
    return MediaService.saveImage(bytes, buildFileName(prefix));
  }

  /// 把已经截好的图存进相册（预览对话框确认后走这里）
  static Future<String?> saveBytes(Uint8List bytes, {String prefix = 'travel-footprint'}) {
    return MediaService.saveImage(bytes, buildFileName(prefix));
  }

  static Future<void> share(String? uri) => MediaService.shareImage(uri);
}
