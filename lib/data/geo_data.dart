import 'dart:convert';
import 'dart:math' as math;
import 'dart:ui';

import 'package:flutter/services.dart' show rootBundle;

import 'shape.dart';

/// 国内省 / 地级市
class Region {
  const Region({
    required this.id,
    required this.name,
    required this.fullName,
    required this.shape,
    this.parentId = 0,
  });

  /// 行政区划代码（省 2 位、市 4 位，与参考站数据一致）
  final int id;
  final String name;
  final String fullName;
  final int parentId;
  final Shape shape;

  String get label => name;
}

/// 某个国家内部的一级行政区（省 / 州 / 县…）
class SubRegion {
  const SubRegion({
    required this.index,
    required this.name,
    required this.fullName,
    required this.shape,
  });

  /// 在该国列表中的序号，用于持久化与命中判断
  final int index;
  final String name;
  final String fullName;
  final Shape shape;

  String get key => '$index';
}

/// 世界国家 / 地区
class Country {
  const Country({
    required this.code,
    required this.name,
    required this.shape,
    this.regions = const <SubRegion>[],
  });

  /// ISO 3166-1 alpha-3
  final String code;
  final String name;
  final Shape shape;

  /// 内部一级行政区，部分小国没有数据
  final List<SubRegion> regions;

  bool get hasRegions => regions.isNotEmpty;

  String get label => name;
}

/// 全部地图数据，进程内只加载一次
class GeoData {
  GeoData({
    required this.provinces,
    required this.cities,
    required this.countries,
  });

  final List<Region> provinces;
  final List<Region> cities;
  final List<Country> countries;

  late final Map<int, Region> provinceById = {
    for (final province in provinces) province.id: province,
  };

  late final Map<int, Region> cityById = {
    for (final city in cities) city.id: city,
  };

  late final Map<String, Country> countryByCode = {
    for (final country in countries) country.code: country,
  };

  late final Map<int, List<Region>> citiesByProvince = _groupCities();

  late final List<Region> citiesByExtent = _sortedByExtent(cities);

  late final List<Country> countriesByExtent = _sortedCountriesByExtent(countries);

  late final Rect chinaBounds = _unionBounds(provinces.map((p) => p.shape.bounds));

  /// 加上南海诸岛（三沙市那一串岛礁）后的完整范围。
  ///
  /// 初始取景仍然用 [chinaBounds]（只看大陆主体），但**能拖到的范围**用这个，
  /// 否则缩放到一定程度后往下拖会被卡住，看不到南海全貌（需求 4）。
  late final Rect chinaFullBounds = _unionBounds([
    ...provinces.map((p) => p.shape.bounds),
    ...cities.map((c) => c.shape.bounds),
  ]);

  late final Rect worldBounds = _unionBounds(countries.map((c) => c.shape.bounds));

  Map<int, List<Region>> _groupCities() {
    final grouped = <int, List<Region>>{};
    for (final city in cities) {
      grouped.putIfAbsent(city.parentId, () => <Region>[]).add(city);
    }
    return grouped;
  }

  static List<Region> _sortedByExtent(List<Region> regions) {
    final sorted = [...regions]..sort((a, b) => b.shape.extent.compareTo(a.shape.extent));
    return sorted;
  }

  static List<Country> _sortedCountriesByExtent(List<Country> countries) {
    final sorted = [...countries]..sort((a, b) => b.shape.extent.compareTo(a.shape.extent));
    return sorted;
  }

  static Rect _unionBounds(Iterable<Rect> bounds) {
    Rect? union;
    for (final rect in bounds) {
      union = union == null ? rect : union.expandToInclude(rect);
    }
    return union ?? Rect.zero;
  }

  /// 找出落点所在的省份（点击地图时用）
  ///
  /// 优先返回"包含落点的最小图形"，避免南海诸岛这种细碎区域被大块多边形抢走；
  /// 没点中时允许在 [tolerance] 范围内吸附到最近的图形，这样小岛、城区也能点。
  Region? provinceAt(Offset point, {double tolerance = 0}) {
    final best = _smallestContaining(provinces, point);
    return best ?? _nearest(provinces, point, tolerance);
  }

  /// 找出落点所在的地级市
  Region? cityAt(Offset point, {double tolerance = 0}) {
    final best = _smallestContaining(cities, point);
    return best ?? _nearest(cities, point, tolerance);
  }

  Country? countryAt(Offset point, {double tolerance = 0}) {
    final best = _smallestContaining(countries, point);
    return best ?? _nearest(countries, point, tolerance);
  }

  /// 找出落点在该国内的哪个一级行政区
  SubRegion? subRegionAt(Country country, Offset point, {double tolerance = 0}) {
    final best = _smallestContaining(country.regions, point);
    return best ?? _nearest(country.regions, point, tolerance);
  }

  /// 包含落点的图形里面积最小的那个
  static T? _smallestContaining<T>(List<T> items, Offset point) {
    T? best;
    double bestExtent = double.infinity;
    for (final item in items) {
      final shape = _shapeOf(item);
      if (!shape.contains(point)) continue;
      if (shape.extent < bestExtent) {
        bestExtent = shape.extent;
        best = item;
      }
    }
    return best;
  }

  /// 距离落点最近的图形（只在 [tolerance] 以内才返回）
  static T? _nearest<T>(List<T> items, Offset point, double tolerance) {
    if (tolerance <= 0) return null;
    T? best;
    var bestDistance = tolerance;
    for (final item in items) {
      final distance = _boundsDistance(_shapeOf(item).bounds, point);
      if (distance < bestDistance) {
        bestDistance = distance;
        best = item;
      }
    }
    return best;
  }

  static Shape _shapeOf(Object? item) {
    if (item is Region) return item.shape;
    if (item is SubRegion) return item.shape;
    if (item is Country) return item.shape;
    throw ArgumentError('不支持的类型：$item');
  }

  static double _boundsDistance(Rect rect, Offset point) {
    final dx = point.dx < rect.left
        ? rect.left - point.dx
        : (point.dx > rect.right ? point.dx - rect.right : 0.0);
    final dy = point.dy < rect.top
        ? rect.top - point.dy
        : (point.dy > rect.bottom ? point.dy - rect.bottom : 0.0);
    return math.sqrt(dx * dx + dy * dy);
  }

  static Future<GeoData> load() async {
    final loaded = await Future.wait([
      rootBundle.loadString('assets/geo/cn.json'),
      rootBundle.loadString('assets/geo/world.json'),
      rootBundle.loadString('assets/geo/admin1.json'),
    ]);
    return parse(loaded[0], loaded[1], loaded[2]);
  }

  static GeoData parse(String cnJson, String worldJson, [String? admin1Json]) {
    final cn = jsonDecode(cnJson) as Map<String, dynamic>;
    final world = jsonDecode(worldJson) as Map<String, dynamic>;
    final admin = admin1Json == null
        ? const <String, dynamic>{}
        : (jsonDecode(admin1Json) as Map<String, dynamic>)['countries'] as Map<String, dynamic>? ??
            const <String, dynamic>{};

    final provinces = <Region>[
      for (final raw in (cn['provinces'] as List).cast<Map<String, dynamic>>())
        Region(
          id: (raw['i'] as num).toInt(),
          name: raw['n'] as String,
          fullName: raw['e'] as String? ?? raw['n'] as String,
          shape: Shape.fromJson(raw),
        ),
    ];

    final cities = <Region>[
      for (final raw in (cn['cities'] as List).cast<Map<String, dynamic>>())
        Region(
          id: (raw['i'] as num).toInt(),
          name: raw['n'] as String,
          fullName: raw['e'] as String? ?? raw['n'] as String,
          parentId: (raw['p'] as num).toInt(),
          shape: Shape.fromJson(raw),
        ),
    ];

    final countries = <Country>[
      for (final raw in (world['countries'] as List).cast<Map<String, dynamic>>())
        Country(
          code: raw['i'] as String,
          name: raw['n'] as String,
          shape: Shape.fromJson(raw),
          regions: _parseRegions(admin[raw['i']]),
        ),
    ];

    return GeoData(provinces: provinces, cities: cities, countries: countries);
  }

  static List<SubRegion> _parseRegions(Object? raw) {
    if (raw is! List) return const <SubRegion>[];
    final regions = <SubRegion>[];
    for (var index = 0; index < raw.length; index++) {
      final item = raw[index] as Map<String, dynamic>;
      regions.add(
        SubRegion(
          index: index,
          name: item['n'] as String,
          fullName: item['e'] as String? ?? item['n'] as String,
          shape: Shape.fromJson(item),
        ),
      );
    }
    return regions;
  }
}
