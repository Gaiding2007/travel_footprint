import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../data/geo_data.dart';

/// 一条记录的状态：没去过 / 去了一部分 / 整个都去过
enum ProvinceStatus { none, partial, lit }

/// 旅行足迹的业务状态：点亮了哪些省 / 市 / 省州 / 国家，以及界面偏好。
///
/// 0.3.0 起的关键规则（对应需求 1、2、9）：
/// - 点地图上的省，只点亮这个省本身，**不连带**点亮它下面的所有市；
/// - 地图上只有"亮"和"不亮"两种颜色，不再有"部分点亮"的淡蓝色；
/// - 一个国家只要点亮过任意一个省/州，就算去过这个国家；
/// - 全球地图可以在"粗略"（亮整个国家）和"详细"（只亮去过的省/州）之间切换。
class FootprintStore extends ChangeNotifier {
  FootprintStore(this.geo);

  final GeoData geo;

  static const String _keyCities = 'lit_cities';
  static const String _keyProvinces = 'lit_provinces';
  static const String _keyCountries = 'lit_countries';
  static const String _keyRegions = 'lit_regions';
  static const String _keyDetail = 'detail_display';
  static const String _keySelectedOnly = 'show_selected_only';

  /// 点亮的国内地级市
  final Set<int> _litCities = <int>{};

  /// 整体点亮的国内省份（不要求每个市都点亮）
  final Set<int> _litProvinces = <int>{};

  /// 整体点亮、或者没有下级省州的国家
  final Set<String> _litCountries = <String>{};

  /// 国家内部点亮的省/州，键是 `国家代码#序号`
  final Set<String> _litRegions = <String>{};

  bool _detailDisplay = false;
  bool _showSelectedOnly = false;

  Timer? _saveTimer;
  SharedPreferences? _prefs;
  bool _loaded = false;

  bool get isLoaded => _loaded;
  bool get showSelectedOnly => _showSelectedOnly;

  /// true = 详细（只亮去过的省/州），false = 粗略（亮整个国家）
  bool get detailDisplay => _detailDisplay;

  // ---------------------------------------------------------------- 国内

  bool isCityLit(int id) => _litCities.contains(id);

  /// 省级行政区是否被整体点亮（不要求下辖市都点亮）
  bool isProvinceLit(int provinceId) => _litProvinces.contains(provinceId);

  /// 这个省有没有留下过足迹（整体点亮，或者其中某个市点亮）
  bool provinceVisited(int provinceId) =>
      _litProvinces.contains(provinceId) ||
      (geo.citiesByProvince[provinceId] ?? const <Region>[])
          .any((city) => _litCities.contains(city.id));

  ProvinceStatus provinceStatus(int provinceId) {
    if (_litProvinces.contains(provinceId)) return ProvinceStatus.lit;
    final cities = geo.citiesByProvince[provinceId] ?? const <Region>[];
    if (cities.isEmpty) return ProvinceStatus.none;
    var lit = 0;
    for (final city in cities) {
      if (_litCities.contains(city.id)) lit++;
    }
    if (lit == 0) return ProvinceStatus.none;
    return lit == cities.length ? ProvinceStatus.lit : ProvinceStatus.partial;
  }

  int get litCityCount => _litCities.length;

  /// 有过足迹的省级行政区数量
  int get litProvinceCount {
    var count = 0;
    for (final province in geo.provinces) {
      if (provinceVisited(province.id)) count++;
    }
    return count;
  }

  int litCityCountInProvince(int provinceId) {
    var count = 0;
    for (final city in geo.citiesByProvince[provinceId] ?? const <Region>[]) {
      if (_litCities.contains(city.id)) count++;
    }
    return count;
  }

  Set<int> get litProvinceIds => {
        for (final province in geo.provinces)
          if (provinceVisited(province.id)) province.id,
      };

  Set<int> get litCityIds => _litCities;

  void toggleCity(int id) {
    if (!_litCities.remove(id)) _litCities.add(id);
    _changed();
  }

  void setCity(int id, bool lit) {
    final changed = lit ? _litCities.add(id) : _litCities.remove(id);
    if (changed) _changed();
  }

  /// 点一个国家内部的地级市：只动这个市
  void toggleProvince(int provinceId) {
    if (_litProvinces.remove(provinceId)) {
      // 取消整省时，把这个省下面的市一起清掉，避免"亮了却点不掉"
      for (final city in geo.citiesByProvince[provinceId] ?? const <Region>[]) {
        _litCities.remove(city.id);
      }
    } else {
      _litProvinces.add(provinceId);
    }
    _changed();
  }

  void setProvince(int provinceId, bool lit) {
    if (lit) {
      _litProvinces.add(provinceId);
    } else {
      _litProvinces.remove(provinceId);
      for (final city in geo.citiesByProvince[provinceId] ?? const <Region>[]) {
        _litCities.remove(city.id);
      }
    }
    _changed();
  }

  // ---------------------------------------------------------------- 世界

  /// 走遍了这个国家：整国点亮，或者它下面所有省/州都点亮了
  bool isWholeCountryLit(String code) {
    if (_litCountries.contains(code)) return true;
    final regions = geo.countryByCode[code]?.regions ?? const <SubRegion>[];
    if (regions.isEmpty) return false;
    return litRegionCount(code) == regions.length;
  }

  bool isRegionLit(String code, int index) => _litRegions.contains('$code#$index');

  /// 去过这个国家（整体点亮，或者点亮过任意一个省/州）
  bool isCountryLit(String code) =>
      _litCountries.contains(code) || _litRegions.any((key) => key.startsWith('$code#'));

  int get litCountryCount {
    var count = 0;
    for (final country in geo.countries) {
      if (isCountryLit(country.code)) count++;
    }
    return count;
  }

  ProvinceStatus countryStatus(String code) {
    if (_litCountries.contains(code)) return ProvinceStatus.lit;
    final regions = geo.countryByCode[code]?.regions ?? const <SubRegion>[];
    var lit = 0;
    for (final region in regions) {
      if (isRegionLit(code, region.index)) lit++;
    }
    if (lit == 0) return ProvinceStatus.none;
    return lit == regions.length ? ProvinceStatus.lit : ProvinceStatus.partial;
  }

  int regionCount(String code) => geo.countryByCode[code]?.regions.length ?? 0;

  int litRegionCount(String code) {
    var count = 0;
    for (final region in geo.countryByCode[code]?.regions ?? const <SubRegion>[]) {
      if (isRegionLit(code, region.index)) count++;
    }
    return count;
  }

  /// 所有国家里已点亮的省/州总数
  int get litRegionTotal => _litRegions.length;

  Set<int> litRegionIndexes(String code) {
    final regions = geo.countryByCode[code]?.regions ?? const <SubRegion>[];
    return {
      for (final region in regions)
        if (isRegionLit(code, region.index)) region.index,
    };
  }

  /// 单独标了"整块"的国家/地区（南极洲这种没有真实省州划分的用它）
  bool isCountryMarkedWhole(String code) => _litCountries.contains(code);

  void setWholeCountry(String code, bool lit) {
    if (lit) {
      _litCountries.add(code);
      _litRegions.removeWhere((key) => key.startsWith('$code#'));
    } else {
      _litCountries.remove(code);
    }
    _changed();
  }

  /// 点一下地图上的国家：整体点亮 / 整体取消
  void toggleCountry(String code) {
    if (isCountryLit(code)) {
      _litCountries.remove(code);
      _litRegions.removeWhere((key) => key.startsWith('$code#'));
    } else {
      _litCountries.add(code);
    }
    _changed();
  }

  void setCountry(String code, bool lit) {
    if (lit) {
      _litCountries.add(code);
    } else {
      _litCountries.remove(code);
      _litRegions.removeWhere((key) => key.startsWith('$code#'));
    }
    _changed();
  }

  void toggleRegion(String code, int index) {
    final key = '$code#$index';
    if (!_litRegions.remove(key)) {
      _litRegions.add(key);
      _litCountries.remove(code);
    }
    _changed();
  }

  void setRegion(String code, int index, bool lit) {
    final key = '$code#$index';
    final changed = lit ? _litRegions.add(key) : _litRegions.remove(key);
    if (lit) _litCountries.remove(code);
    if (changed) _changed();
  }

  void setAllRegions(String code, bool lit) {
    final regions = geo.countryByCode[code]?.regions ?? const <SubRegion>[];
    if (lit) {
      _litCountries.remove(code);
      for (final region in regions) {
        _litRegions.add('$code#${region.index}');
      }
    } else {
      _litRegions.removeWhere((key) => key.startsWith('$code#'));
    }
    _changed();
  }

  // ---------------------------------------------------------------- 偏好

  void setDetailDisplay(bool value) {
    if (_detailDisplay == value) return;
    _detailDisplay = value;
    _changed();
  }

  void setShowSelectedOnly(bool value) {
    if (_showSelectedOnly == value) return;
    _showSelectedOnly = value;
    _changed();
  }

  void clearAll() {
    if (_litCities.isEmpty &&
        _litProvinces.isEmpty &&
        _litCountries.isEmpty &&
        _litRegions.isEmpty) {
      return;
    }
    _litCities.clear();
    _litProvinces.clear();
    _litCountries.clear();
    _litRegions.clear();
    _changed();
  }

  void _changed() {
    notifyListeners();
    _saveTimer?.cancel();
    _saveTimer = Timer(const Duration(milliseconds: 350), _save);
  }

  Future<void> load() async {
    final prefs = await SharedPreferences.getInstance();
    _prefs = prefs;
    _readInts(prefs.getString(_keyCities), _litCities);
    _readInts(prefs.getString(_keyProvinces), _litProvinces);
    _readStrings(prefs.getString(_keyCountries), _litCountries);
    _readStrings(prefs.getString(_keyRegions), _litRegions);
    _detailDisplay = prefs.getBool(_keyDetail) ?? false;
    _showSelectedOnly = prefs.getBool(_keySelectedOnly) ?? false;
    _loaded = true;
    notifyListeners();
  }

  void _readInts(String? raw, Set<int> target) {
    if (raw == null || raw.isEmpty) return;
    for (final part in raw.split(',')) {
      final value = int.tryParse(part);
      if (value != null) target.add(value);
    }
  }

  void _readStrings(String? raw, Set<String> target) {
    if (raw == null || raw.isEmpty) return;
    target.addAll(raw.split(',').where((element) => element.isNotEmpty));
  }

  Future<void> _save() async {
    final prefs = _prefs ?? await SharedPreferences.getInstance();
    _prefs = prefs;
    await prefs.setString(_keyCities, _litCities.join(','));
    await prefs.setString(_keyProvinces, _litProvinces.join(','));
    await prefs.setString(_keyCountries, _litCountries.join(','));
    await prefs.setString(_keyRegions, _litRegions.join(','));
    await prefs.setBool(_keyDetail, _detailDisplay);
    await prefs.setBool(_keySelectedOnly, _showSelectedOnly);
  }

  @override
  void dispose() {
    _saveTimer?.cancel();
    super.dispose();
  }
}
