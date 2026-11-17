import 'dart:convert';
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
  Region? provinceAt(Offset point) {
    for (final province in provinces) {
      if (province.shape.contains(point)) return province;
    }
    return null;
  }

  /// 找出落点所在的地级市
  Region? cityAt(Offset point) {
    for (final city in cities) {
      if (city.shape.contains(point)) return city;
    }
    return null;
  }

  Country? countryAt(Offset point) {
    for (final country in countriesByExtent) {
      if (country.shape.contains(point)) return country;
    }
    return null;
  }

  /// 找出落点在该国内的哪个一级行政区
  SubRegion? subRegionAt(Country country, Offset point) {
    for (final region in country.regions) {
      if (region.shape.contains(point)) return region;
    }
    return null;
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
