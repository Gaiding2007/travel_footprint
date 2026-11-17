import 'dart:math' as math;
import 'dart:ui';

/// 地图坐标系（Web 墨卡托投影，和手机地图上的形状一致）：
///   x = (经度 + 180) * [kUnitsPerDegree]
///   y = (90 - 墨卡托纬度) * [kUnitsPerDegree]
///
/// 用墨卡托是为了让"形状不变形"：等距圆柱投影下，中国地图会被横向拉宽约 25%。
/// 高纬度（南极、北极圈外）墨卡托会趋于无穷，这里用线性方式接一段，保证有界。
const double kUnitsPerDegree = 1000.0;

const double _mercatorLatMin = -60.0;
const double _mercatorLatMax = 84.0;
const double _polarStretch = 0.6;

/// 把纬度换成"墨卡托纬度"（单位仍是度）
double mercatorLat(double lat) {
  final clamped = lat.clamp(_mercatorLatMin, _mercatorLatMax).toDouble();
  final rad = clamped * math.pi / 180.0;
  final base = math.log(math.tan(math.pi / 4 + rad / 2)) * 180.0 / math.pi;
  if (lat == clamped) return base;
  return base + (lat - clamped) * _polarStretch;
}

Offset projectLonLat(double lon, double lat) => Offset(
  (lon + 180.0) * kUnitsPerDegree,
  (90.0 - mercatorLat(lat)) * kUnitsPerDegree,
);

/// 一块地图图形的几何：外环 + 洞（偶奇填充规则）。
class Shape {
  Shape({required this.anchor, required this.rings, required this.bounds});

  /// 名称标注的位置（数据里给的行政中心点）
  final Offset anchor;

  /// 组成该图形所有环（第一个通常是外环，其余是洞）
  final List<List<Offset>> rings;

  /// 经纬度包围盒（地图坐标）
  final Rect bounds;

  /// 包围盒面积，用于标注去重时优先照顾大区域
  double get extent => bounds.width * bounds.height;

  late final Path path = _buildPath();

  Path _buildPath() {
    final path = Path()..fillType = PathFillType.evenOdd;
    for (final ring in rings) {
      if (ring.length < 3) continue;
      path.addPolygon(ring, true);
    }
    return path;
  }

  /// 偶奇规则判断某点是否落在图形内
  bool contains(Offset point) {
    if (!bounds.contains(point)) return false;
    var inside = false;
    for (final ring in rings) {
      if (_ringCrossings(ring, point)) inside = !inside;
    }
    return inside;
  }

  static bool _ringCrossings(List<Offset> ring, Offset point) {
    var inside = false;
    for (var i = 0, j = ring.length - 1; i < ring.length; j = i++) {
      final a = ring[i];
      final b = ring[j];
      if ((a.dy > point.dy) != (b.dy > point.dy) &&
          point.dx < (b.dx - a.dx) * (point.dy - a.dy) / (b.dy - a.dy) + a.dx) {
        inside = !inside;
      }
    }
    return inside;
  }

  /// 从数据文件里的一条记录构建，坐标是"经度/纬度 × 10000"的整数
  static Shape fromJson(Map<String, dynamic> json) {
    final rings = <List<Offset>>[];
    var minX = double.infinity;
    var minY = double.infinity;
    var maxX = -double.infinity;
    var maxY = -double.infinity;

    for (final rawRing in (json['r'] as List).cast<List<dynamic>>()) {
      final ring = <Offset>[];
      for (final rawPoint in rawRing.cast<List<dynamic>>()) {
        // 数据里存的是 经度*10000、纬度*10000
        final lon = (rawPoint[0] as num).toDouble() / 10000.0;
        final lat = (rawPoint[1] as num).toDouble() / 10000.0;
        final point = projectLonLat(lon, lat);
        ring.add(point);
        if (point.dx < minX) minX = point.dx;
        if (point.dy < minY) minY = point.dy;
        if (point.dx > maxX) maxX = point.dx;
        if (point.dy > maxY) maxY = point.dy;
      }
      if (ring.length >= 3) rings.add(ring);
    }

    final anchor = projectLonLat(
      (json['x'] as num).toDouble() / 10000.0,
      (json['y'] as num).toDouble() / 10000.0,
    );

    return Shape(
      anchor: anchor,
      rings: rings,
      bounds: Rect.fromLTRB(minX, minY, maxX, maxY),
    );
  }
}
