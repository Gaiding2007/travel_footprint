import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'dart:convert';
import 'package:flutter/services.dart';
import 'dart:async';

class MapScreen extends StatefulWidget {
  const MapScreen({Key? key}) : super(key: key);

  @override
  MapScreenState createState() => MapScreenState();
}

class MapScreenState extends State<MapScreen> {
  List<dynamic> _provinceFeatures = [];
  Map<String, bool> _litCities = {};
  bool _isLoading = true;
  late MapController _mapController;
  String _appVersion = '0.3.17';

  OverlayEntry? _overlayEntry;
  Timer? _hideTimer;

  // 存储所有多边形及其所属城市
  List<_RenderPolygon> _polygons = [];

  @override
  void initState() {
    super.initState();
    _mapController = MapController();
    _loadLitState();
    _loadProvinceGeoJson();
    _loadCityGeoJson();
  }

  @override
  void dispose() {
    _hideOverlay();
    _mapController.dispose();
    super.dispose();
  }

  void _hideOverlay() {
    _hideTimer?.cancel();
    _overlayEntry?.remove();
    _overlayEntry = null;
    _hideTimer = null;
  }

  void _showCityNamePopup(String cityName, TapPosition tapPosition) {
    _hideOverlay();

    final RenderBox? renderBox = context.findRenderObject() as RenderBox?;
    if (renderBox == null) return;

    final Offset position = renderBox.globalToLocal(tapPosition.global);
    final OverlayState? overlayState = Overlay.of(context);
    if (overlayState == null) return;

    _overlayEntry = OverlayEntry(
      builder: (context) => Positioned(
        left: position.dx + 15,
        top: position.dy + 10,
        child: Material(
          color: Colors.transparent,
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(6),
              boxShadow: const [
                BoxShadow(
                    color: Colors.black26, blurRadius: 4, offset: Offset(1, 1)),
              ],
            ),
            child: Text(cityName,
                style: const TextStyle(color: Colors.black87, fontSize: 14)),
          ),
        ),
      ),
    );

    overlayState.insert(_overlayEntry!);
    _hideTimer = Timer(const Duration(milliseconds: 1500), _hideOverlay);
  }

  Future<void> _loadLitState() async {
    final prefs = await SharedPreferences.getInstance();
    final keys = prefs.getKeys();
    Map<String, bool> loaded = {};
    for (String key in keys) {
      if (key.startsWith('city_')) {
        final cityName = key.substring(5);
        loaded[cityName] = prefs.getBool(key) ?? false;
      }
    }
    setState(() {
      _litCities = loaded;
    });
  }

  Future<void> _saveCityState(String cityName, bool lit) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('city_$cityName', lit);
  }

  Future<void> _loadProvinceGeoJson() async {
    try {
      final string =
          await rootBundle.loadString('assets/data/china_provinces.geojson');
      final jsonData = json.decode(string) as Map<String, dynamic>;
      if (jsonData['type'] == 'FeatureCollection') {
        setState(() {
          _provinceFeatures = jsonData['features'] as List<dynamic>;
        });
        print('省级边界加载成功');
      }
    } catch (e) {
      print('加载省级 GeoJSON 失败: $e');
    }
  }

  Future<void> _loadCityGeoJson() async {
    try {
      final string = await rootBundle.loadString('assets/data/cities.geojson');
      final jsonData = json.decode(string) as Map<String, dynamic>;
      if (jsonData['type'] != 'FeatureCollection') {
        setState(() => _isLoading = false);
        return;
      }
      final features = jsonData['features'] as List<dynamic>;

      // 1. 解析所有多边形
      List<_RawPolygon> allPolygons = [];
      for (var feature in features) {
        final cityName = _getCityName(feature);
        if (cityName.isEmpty) continue;

        final adcode = _getAdcode(feature);
        final level = _getAdminLevel(feature);

        final polygons = _extractPolygons(feature);
        for (var poly in polygons) {
          final area = _calculateArea(poly);
          allPolygons.add(_RawPolygon(
            points: poly,
            cityName: cityName,
            adcode: adcode,
            level: level,
            area: area,
            feature: feature,
          ));
        }
      }

      // 2. 按面积从小到大排序（小面积优先，用于去重时优先保留小面积的飞地）
      allPolygons.sort((a, b) => a.area.compareTo(b.area));

      // 3. 核心：去重 - 当一个多边形完全被另一个多边形包含时，保留面积小的（飞地）
      // 使用一个列表记录哪些多边形被标记为"移除"
      Set<int> indicesToRemove = {};

      for (int i = 0; i < allPolygons.length; i++) {
        if (indicesToRemove.contains(i)) continue;

        final polyA = allPolygons[i];

        for (int j = i + 1; j < allPolygons.length; j++) {
          if (indicesToRemove.contains(j)) continue;

          final polyB = allPolygons[j];

          // 检查包含关系
          final isAContainsB = _isPolygonContains(polyA, polyB);
          final isBContainsA = _isPolygonContains(polyB, polyA);

          if (isAContainsB && !isBContainsA) {
            // A 包含 B，且 A 面积更大，移除 A 中的这个多边形区域
            // 但不同城市不能简单移除，因为 A 和 B 可能属于不同城市
            // 我们需要记录"B 是 A 的飞地"
            print(
                '${polyA.cityName} (面积:${polyA.area}) 包含 ${polyB.cityName} (面积:${polyB.area})');
          }

          if (isBContainsA && !isAContainsB) {
            print(
                '${polyB.cityName} (面积:${polyB.area}) 包含 ${polyA.cityName} (面积:${polyA.area})');
          }
        }
      }

      // 4. 构建最终渲染列表：保留所有多边形，但点击时按优先级处理
      // 不删除任何多边形，因为渲染需要显示边界，点击时由优先级规则决定
      _polygons.clear();
      for (var poly in allPolygons) {
        _polygons.add(_RenderPolygon(
          points: poly.points,
          cityName: poly.cityName,
          feature: poly.feature,
          area: poly.area,
          adcode: poly.adcode,
          level: poly.level,
        ));
      }

      setState(() {
        _isLoading = false;
      });
      print('加载完成，共 ${_polygons.length} 个多边形');
    } catch (e) {
      print('加载市级 GeoJSON 失败: $e');
      setState(() => _isLoading = false);
    }
  }

  // 检查多边形 A 是否完全包含多边形 B
  bool _isPolygonContains(_RawPolygon a, _RawPolygon b) {
    if (a.area <= b.area) return false;

    // 检查 B 的边界框是否在 A 内
    final bboxA = _getBoundingBox(a.points);
    final bboxB = _getBoundingBox(b.points);

    if (bboxB.minLng < bboxA.minLng ||
        bboxB.maxLng > bboxA.maxLng ||
        bboxB.minLat < bboxA.minLat ||
        bboxB.maxLat > bboxA.maxLat) {
      return false;
    }

    // 检查 B 的多个点是否在 A 内
    int pointsInside = 0;
    final totalPoints = b.points.length > 10 ? 10 : b.points.length;
    for (int i = 0; i < totalPoints; i++) {
      if (_pointInPolygon(b.points[i], a.points)) {
        pointsInside++;
      }
    }

    return pointsInside > totalPoints * 0.8;
  }

  _BoundingBox _getBoundingBox(List<LatLng> points) {
    double minLng = points[0].longitude;
    double maxLng = points[0].longitude;
    double minLat = points[0].latitude;
    double maxLat = points[0].latitude;

    for (var p in points) {
      minLng = minLng < p.longitude ? minLng : p.longitude;
      maxLng = maxLng > p.longitude ? maxLng : p.longitude;
      minLat = minLat < p.latitude ? minLat : p.latitude;
      maxLat = maxLat > p.latitude ? maxLat : p.latitude;
    }

    return _BoundingBox(
        minLng: minLng, maxLng: maxLng, minLat: minLat, maxLat: maxLat);
  }

  int _getAdcode(Map<String, dynamic> feature) {
    final props = feature['properties'] as Map<String, dynamic>?;
    if (props == null) return 0;
    return props['adcode'] ?? 0;
  }

  int _getAdminLevel(Map<String, dynamic> feature) {
    final adcode = _getAdcode(feature);
    final props = feature['properties'] as Map<String, dynamic>?;
    final level = props?['level'] as String?;

    if (level == 'district') return 0;
    if (level == 'city') return 1;
    if (level == 'province') return 2;

    if (adcode % 100 != 0) return 0;
    return 1;
  }

  List<List<LatLng>> _extractPolygons(Map<String, dynamic> feature) {
    List<List<LatLng>> polygons = [];
    final geometry = feature['geometry'];
    if (geometry == null) return polygons;
    final type = geometry['type'];
    final coordinates = geometry['coordinates'] as List<dynamic>;

    if (type == 'Polygon') {
      final points = _toLatLngList(coordinates[0] as List);
      if (points.isNotEmpty) polygons.add(points);
    } else if (type == 'MultiPolygon') {
      for (var poly in coordinates) {
        final points = _toLatLngList(poly[0] as List);
        if (points.isNotEmpty) polygons.add(points);
      }
    }
    return polygons;
  }

  String _getCityName(Map<String, dynamic> feature) {
    final props = feature['properties'] as Map<String, dynamic>?;
    if (props == null) return '';
    return props['name'] ?? props['city'] ?? props['市'] ?? props['NAME'] ?? '';
  }

  Color _getCityFillColor(String cityName) {
    if (_litCities[cityName] == true) {
      return Colors.lightBlue.withValues(alpha: 0.5);
    }
    return Colors.transparent;
  }

  List<LatLng> _toLatLngList(List coords) {
    return coords.map<LatLng>((point) {
      return LatLng(point[1] as double, point[0] as double);
    }).toList();
  }

  List<Polyline> _buildProvinceBorders() {
    List<Polyline> polylines = [];
    for (var feature in _provinceFeatures) {
      final geometry = feature['geometry'];
      if (geometry == null) continue;
      final type = geometry['type'];
      final coordinates = geometry['coordinates'] as List<dynamic>;

      if (type == 'Polygon') {
        final ring = _toLatLngList(coordinates[0] as List);
        if (ring.isNotEmpty) {
          final closedRing = List<LatLng>.from(ring);
          if (closedRing.first != closedRing.last)
            closedRing.add(closedRing.first);
          polylines.add(Polyline(
              points: closedRing, color: Colors.black, strokeWidth: 1.5));
        }
      } else if (type == 'MultiPolygon') {
        for (var poly in coordinates) {
          final ring = _toLatLngList(poly[0] as List);
          if (ring.isNotEmpty) {
            final closedRing = List<LatLng>.from(ring);
            if (closedRing.first != closedRing.last)
              closedRing.add(closedRing.first);
            polylines.add(Polyline(
                points: closedRing, color: Colors.black, strokeWidth: 1.5));
          }
        }
      }
    }
    return polylines;
  }

  List<Polygon> _buildCityPolygons() {
    List<Polygon> polygons = [];
    for (var poly in _polygons) {
      polygons.add(Polygon(
        points: poly.points,
        color: _getCityFillColor(poly.cityName),
        borderStrokeWidth: 0.8,
        borderColor: Colors.grey.shade400,
        isFilled: true,
      ));
    }
    return polygons;
  }

  bool _pointInPolygon(LatLng point, List<LatLng> polygon) {
    int intersectCount = 0;
    for (int i = 0; i < polygon.length; i++) {
      final p1 = polygon[i];
      final p2 = polygon[(i + 1) % polygon.length];
      if (((p1.latitude > point.latitude) != (p2.latitude > point.latitude)) &&
          (point.longitude <
              (p2.longitude - p1.longitude) *
                      (point.latitude - p1.latitude) /
                      (p2.latitude - p1.latitude) +
                  p1.longitude)) {
        intersectCount++;
      }
    }
    return intersectCount % 2 == 1;
  }

  double _calculateArea(List<LatLng> points) {
    if (points.length < 3) return 0;
    double area = 0;
    for (int i = 0; i < points.length; i++) {
      final j = (i + 1) % points.length;
      area += points[i].longitude * points[j].latitude;
      area -= points[i].latitude * points[j].longitude;
    }
    return area.abs() / 2;
  }

  void _handleTap(TapPosition tapPosition, LatLng latlng) {
    // 找出点击点所在的所有多边形
    List<_RenderPolygon> hitPolygons = [];
    for (var poly in _polygons) {
      if (_pointInPolygon(latlng, poly.points)) {
        hitPolygons.add(poly);
      }
    }

    if (hitPolygons.isEmpty) return;

    // 只有一个多边形时直接使用
    if (hitPolygons.length == 1) {
      final cityName = hitPolygons.first.cityName;
      _showCityNamePopup(cityName, tapPosition);
      setState(() {
        _litCities[cityName] = !(_litCities[cityName] ?? false);
      });
      _saveCityState(cityName, _litCities[cityName]!);
      return;
    }

    // 多个多边形重叠时的优先级规则
    // 规则1: adcode 后两位不为 00 的（区县级）优先于地级市
    // 规则2: 名称中包含"地区"的优先（如大兴安岭地区）
    // 规则3: 面积小的优先
    hitPolygons.sort((a, b) {
      final isDistrictA = a.adcode % 100 != 0;
      final isDistrictB = b.adcode % 100 != 0;
      if (isDistrictA && !isDistrictB) return -1;
      if (!isDistrictA && isDistrictB) return 1;

      final hasAreaA = a.cityName.contains('地区');
      final hasAreaB = b.cityName.contains('地区');
      if (hasAreaA && !hasAreaB) return -1;
      if (!hasAreaA && hasAreaB) return 1;

      return a.area.compareTo(b.area);
    });

    final selected = hitPolygons.first;
    final cityName = selected.cityName;

    print('点击位置: (${latlng.latitude}, ${latlng.longitude})');
    print('匹配到的多边形: ${hitPolygons.map((p) => p.cityName).join(', ')}');
    print('选择: $cityName');

    _showCityNamePopup(cityName, tapPosition);
    setState(() {
      _litCities[cityName] = !(_litCities[cityName] ?? false);
    });
    _saveCityState(cityName, _litCities[cityName]!);
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }

    return Scaffold(
      appBar: AppBar(
        title: const Text('旅行足迹地图'),
        centerTitle: true,
        elevation: 2,
        backgroundColor: Colors.blue,
        actions: [
          Padding(
            padding: const EdgeInsets.only(right: 16.0),
            child: Center(
                child: Text('v$_appVersion',
                    style: const TextStyle(fontSize: 14))),
          ),
        ],
      ),
      body: FlutterMap(
        mapController: _mapController,
        options: MapOptions(
          initialCenter: const LatLng(35.0, 105.0),
          initialZoom: 5.0,
          minZoom: 4.0,
          maxZoom: 12.0,
          onTap: _handleTap,
          backgroundColor: Colors.white,
        ),
        children: [
          TileLayer(
            urlTemplate: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
            userAgentPackageName: 'com.example.city_footprint',
          ),
          PolygonLayer(polygons: _buildCityPolygons()),
          PolylineLayer(polylines: _buildProvinceBorders()),
        ],
      ),
    );
  }
}

class _RawPolygon {
  final List<LatLng> points;
  final String cityName;
  final int adcode;
  final int level;
  final double area;
  final Map<String, dynamic> feature;

  _RawPolygon({
    required this.points,
    required this.cityName,
    required this.adcode,
    required this.level,
    required this.area,
    required this.feature,
  });
}

class _RenderPolygon {
  final List<LatLng> points;
  final String cityName;
  final Map<String, dynamic> feature;
  final double area;
  final int adcode;
  final int level;

  _RenderPolygon({
    required this.points,
    required this.cityName,
    required this.feature,
    required this.area,
    required this.adcode,
    required this.level,
  });
}

class _BoundingBox {
  final double minLng;
  final double maxLng;
  final double minLat;
  final double maxLat;

  _BoundingBox({
    required this.minLng,
    required this.maxLng,
    required this.minLat,
    required this.maxLat,
  });
}
