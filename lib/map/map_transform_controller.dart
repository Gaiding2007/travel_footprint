import 'dart:math' as math;
import 'dart:ui';

import 'package:flutter/foundation.dart';

/// 地图的缩放/平移状态（纯数学，便于单独测试）。
///
/// 屏幕坐标 = 地图坐标 * scale + offset
class MapTransformController extends ChangeNotifier {
  double _scale = 1;
  Offset _offset = Offset.zero;
  Size _viewport = Size.zero;
  Rect _content = Rect.zero;

  /// 初始取景用的范围（通常是"主体部分"，比 [content] 小）
  Rect _frame = Rect.zero;
  double _fitScale = 1;
  double _minScale = 0.5;
  double _maxScale = 20;
  double _minFactor = 0.85;
  double _maxFactor = 45;

  double get scale => _scale;
  Offset get offset => _offset;
  Size get viewport => _viewport;

  /// 允许拖到的范围
  Rect get content => _content;

  /// 初始适配的范围
  Rect get frame => _frame;
  double get fitScale => _fitScale;
  double get minScale => _minScale;
  double get maxScale => _maxScale;

  bool get isReady => _viewport.width > 0 && _content.width > 0;

  Offset screenToMap(Offset point) => (point - _offset) / _scale;

  Offset mapToScreen(Offset point) => point * _scale + _offset;

  /// 当前可见的地图范围
  Rect get visibleMapRect => Rect.fromLTWH(
        -_offset.dx / _scale,
        -_offset.dy / _scale,
        _viewport.width / _scale,
        _viewport.height / _scale,
      );

  /// 交给外部布局调用：视口尺寸或内容包围盒变化时重新适配。
  ///
  /// - [content]：允许拖动的总范围（比如中国要包含南海诸岛）；
  /// - [frame]：初始取景范围，不传就和 [content] 一样。
  ///
  /// 布局阶段调用时传 [notify] = false，避免在 build 过程中触发重建。
  void attach({
    required Size viewport,
    required Rect content,
    Rect? frame,
    double minFactor = 0.85,
    double maxFactor = 45,
    bool notify = true,
  }) {
    final nextFrame = frame ?? content;
    final changed = viewport != _viewport ||
        content != _content ||
        nextFrame != _frame ||
        minFactor != _minFactor ||
        maxFactor != _maxFactor;
    if (!changed) return;
    _viewport = viewport;
    _content = content;
    _frame = nextFrame;
    _minFactor = minFactor;
    _maxFactor = maxFactor;
    _fitScale = _computeFit();
    _minScale = _fitScale * _minFactor;
    _maxScale = _fitScale * _maxFactor;
    _scale = _fitScale;
    _centerFrame();
    if (notify) notifyListeners();
  }

  double _computeFit() {
    if (_viewport.width <= 0 || _viewport.height <= 0) return 1;
    if (_frame.width <= 0 || _frame.height <= 0) return 1;
    final padding = math.min(_viewport.width, _viewport.height) * 0.06;
    final width = _viewport.width - padding * 2;
    final height = _viewport.height - padding * 2;
    return math.min(width / _frame.width, height / _frame.height);
  }

  /// 让 [frame] 居中（初始视角）
  void _centerFrame() {
    _offset = Offset(
      (_viewport.width - _frame.width * _scale) / 2 - _frame.left * _scale,
      (_viewport.height - _frame.height * _scale) / 2 - _frame.top * _scale,
    );
    _clampOffset();
  }

  void reset() {
    if (!isReady) return;
    _scale = _fitScale;
    _centerFrame();
    notifyListeners();
  }

  void zoomBy(double factor, Offset focal) {
    if (!isReady) return;
    final next = (_scale * factor).clamp(_minScale, _maxScale);
    if ((next - _scale).abs() < 1e-9) return;
    final mapFocal = screenToMap(focal);
    _scale = next;
    _offset = focal - mapFocal * next;
    _clampOffset();
    notifyListeners();
  }

  void panBy(Offset delta) {
    if (!isReady) return;
    _offset += delta;
    _clampOffset();
    notifyListeners();
  }

  /// 手指拖动/双指缩放：以 [focal]（屏幕坐标）为锚点缩放到 [scale]
  void transformTo({required double scale, required Offset focal}) {
    if (!isReady) return;
    final next = scale.clamp(_minScale, _maxScale);
    final mapFocal = screenToMap(focal);
    _scale = next;
    _offset = focal - mapFocal * next;
    _clampOffset();
    notifyListeners();
  }

  void _clampOffset() {
    final contentWidth = _content.width * _scale;
    final contentHeight = _content.height * _scale;
    double dx = _offset.dx;
    double dy = _offset.dy;

    if (contentWidth <= _viewport.width) {
      dx = (_viewport.width - contentWidth) / 2 - _content.left * _scale;
    } else {
      final minDx = _viewport.width - _content.right * _scale;
      final maxDx = -_content.left * _scale;
      dx = dx.clamp(minDx, maxDx);
    }

    if (contentHeight <= _viewport.height) {
      dy = (_viewport.height - contentHeight) / 2 - _content.top * _scale;
    } else {
      final minDy = _viewport.height - _content.bottom * _scale;
      final maxDy = -_content.top * _scale;
      dy = dy.clamp(minDy, maxDy);
    }

    _offset = Offset(dx, dy);
  }
}
