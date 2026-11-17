import 'dart:ui';

/// 地图坐标系（等距圆柱投影，和参考站 ECharts 的绘制方式一致）：
///   x = (经度 + 180) * [kUnitsPerDegree]
///   y = (90 - 纬度) * [kUnitsPerDegree]
/// 因此中国大致落在 x∈[253000, 315000]、y∈[36000, 87000] 的范围内。
const double kUnitsPerDegree = 1000.0;

Offset projectLonLat(double lon, double lat) =>
    Offset((lon + 180.0) * kUnitsPerDegree, (90.0 - lat) * kUnitsPerDegree);

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

  /// 从数据文件里的一条记录构建，坐标是“经纬度 × 10000”的整数
  static Shape fromJson(Map<String, dynamic> json) {
    final rings = <List<Offset>>[];
    var minX = double.infinity;
    var minY = double.infinity;
    var maxX = -double.infinity;
    var maxY = -double.infinity;

    for (final rawRing in (json['r'] as List).cast<List<dynamic>>()) {
      final ring = <Offset>[];
      for (final rawPoint in rawRing.cast<List<dynamic>>()) {
        final point = Offset(
          (rawPoint[0] as num).toDouble() / 10.0 + 180000.0,
          90000.0 - (rawPoint[1] as num).toDouble() / 10.0,
        );
        ring.add(point);
        if (point.dx < minX) minX = point.dx;
        if (point.dy < minY) minY = point.dy;
        if (point.dx > maxX) maxX = point.dx;
        if (point.dy > maxY) maxY = point.dy;
      }
      if (ring.length >= 3) rings.add(ring);
    }

    final anchor = Offset(
      (json['x'] as num).toDouble() / 10.0 + 180000.0,
      90000.0 - (json['y'] as num).toDouble() / 10.0,
    );

    return Shape(
      anchor: anchor,
      rings: rings,
      bounds: Rect.fromLTRB(minX, minY, maxX, maxY),
    );
  }
}
