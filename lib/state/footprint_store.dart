import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../data/geo_data.dart';

/// 省的点亮状态
enum ProvinceStatus {
  /// 一个市都没点亮
  none,

  /// 点亮了一部分
  partial,

  /// 全省点满
  lit,
}

/// 旅行足迹的业务状态：点亮了哪些城市 / 国家，以及界面偏好。
///
/// 所有改动都会防抖后写入 shared_preferences。
class FootprintStore extends ChangeNotifier {
  FootprintStore(this.geo);

  final GeoData geo;

  static const String _keyCities = 'lit_cities';
  static const String _keyCountries = 'lit_countries';
  static const String _keyDirectProvinces = 'lit_provinces';
  static const String _keyRegions = 'lit_regions';
  static const String _keyShowLabels = 'show_labels';
  static const String _keySelectedOnly = 'show_selected_only';

  final Set<int> _litCities = <int>{};
  final Set<String> _litCountries = <String>{};

  /// 国家内部点亮的省/州，键是 `国家代码#序号`
  final Set<String> _litRegions = <String>{};

  /// 没有下级市、整体点亮的省（如台湾、香港、澳门）
  final Set<int> _litDirectProvinces = <int>{};

  bool _showLabels = true;
  bool _showSelectedOnly = false;

  Timer? _saveTimer;
  SharedPreferences? _prefs;
  bool _loaded = false;

  bool get isLoaded => _loaded;
  bool get showLabels => _showLabels;
  bool get showSelectedOnly => _showSelectedOnly;

  int get litCityCount => _litCities.length;

  /// 去过的国家/地区（点到任意一个省/州也算）
  int get litCountryCount {
    var count = 0;
    for (final country in geo.countries) {
      if (countryStatus(country.code) != ProvinceStatus.none) count++;
    }
    return count;
  }

  /// 完全点亮的省份数量
  int get litProvinceCount {
    var count = 0;
    for (final province in geo.provinces) {
      if (provinceStatus(province.id) == ProvinceStatus.lit) count++;
    }
    return count;
  }

  /// 点亮的省份里包含的城市总数（用于"已点亮 N 省 M 市"里的 M 只统计市级）
  bool isCityLit(int id) => _litCities.contains(id);

  /// 是否整国点亮（不看内部省州）
  bool isWholeCountryLit(String code) => _litCountries.contains(code);

  bool isCountryLit(String code) => countryStatus(code) != ProvinceStatus.none;

  /// 国家整体的点亮状态：整国点亮 / 只有部分省州 / 没去过
  ProvinceStatus countryStatus(String code) {
    if (_litCountries.contains(code)) return ProvinceStatus.lit;
    final regions = geo.countryByCode[code]?.regions ?? const <SubRegion>[];
    if (regions.isEmpty) return ProvinceStatus.none;
    var lit = 0;
    for (final region in regions) {
      if (_litRegions.contains('$code#${region.index}')) lit++;
    }
    if (lit == 0) return ProvinceStatus.none;
    return lit == regions.length ? ProvinceStatus.lit : ProvinceStatus.partial;
  }

  bool isRegionLit(String code, int index) => _litRegions.contains('$code#$index');

  /// 所有国家特写里已点亮的省/州总数
  int get litRegionTotal => _litRegions.length;

  int litRegionCount(String code) {
    final regions = geo.countryByCode[code]?.regions ?? const <SubRegion>[];
    var lit = 0;
    for (final region in regions) {
      if (_litRegions.contains('$code#${region.index}')) lit++;
    }
    return lit;
  }

  int regionCount(String code) => geo.countryByCode[code]?.regions.length ?? 0;

  /// 该国内已点亮省州的序号集合
  Set<int> litRegionIndexes(String code) {
    final regions = geo.countryByCode[code]?.regions ?? const <SubRegion>[];
    return {
      for (final region in regions)
        if (_litRegions.contains('$code#${region.index}')) region.index,
    };
  }

  ProvinceStatus provinceStatus(int provinceId) {
    final cities = geo.citiesByProvince[provinceId] ?? const <Region>[];
    if (cities.isEmpty) {
      return _litDirectProvinces.contains(provinceId) ? ProvinceStatus.lit : ProvinceStatus.none;
    }
    var lit = 0;
    for (final city in cities) {
      if (_litCities.contains(city.id)) lit++;
    }
    if (lit == 0) return ProvinceStatus.none;
    if (lit == cities.length) return ProvinceStatus.lit;
    return ProvinceStatus.partial;
  }

  int litCityCountInProvince(int provinceId) {
    final cities = geo.citiesByProvince[provinceId] ?? const <Region>[];
    var lit = 0;
    for (final city in cities) {
      if (_litCities.contains(city.id)) lit++;
    }
    return lit;
  }

  void toggleCity(int id) {
    if (!_litCities.remove(id)) _litCities.add(id);
    _changed();
  }

  void setCity(int id, bool lit) {
    final changed = lit ? _litCities.add(id) : _litCities.remove(id);
    if (changed) _changed();
  }

  /// 点整个省：没满就全点亮，满了就全部取消
  void toggleProvince(int provinceId) {
    final cities = geo.citiesByProvince[provinceId] ?? const <Region>[];
    if (cities.isEmpty) {
      if (!_litDirectProvinces.remove(provinceId)) _litDirectProvinces.add(provinceId);
      _changed();
      return;
    }
    final allLit = provinceStatus(provinceId) == ProvinceStatus.lit;
    for (final city in cities) {
      if (allLit) {
        _litCities.remove(city.id);
      } else {
        _litCities.add(city.id);
      }
    }
    _changed();
  }

  void setProvince(int provinceId, bool lit) {
    final cities = geo.citiesByProvince[provinceId] ?? const <Region>[];
    if (cities.isEmpty) {
      final changed = lit ? _litDirectProvinces.add(provinceId) : _litDirectProvinces.remove(provinceId);
      if (changed) _changed();
      return;
    }
    var changed = false;
    for (final city in cities) {
      changed = (lit ? _litCities.add(city.id) : _litCities.remove(city.id)) || changed;
    }
    if (changed) _changed();
  }

  /// 点整个国家：去过就整个取消（含内部省州），没去过就整国点亮
  void toggleCountry(String code) {
    if (countryStatus(code) != ProvinceStatus.none) {
      _litCountries.remove(code);
      _litRegions.removeWhere((key) => key.startsWith('$code#'));
    } else {
      _litCountries.add(code);
    }
    _changed();
  }

  void setCountry(String code, bool lit) {
    final wasLit = countryStatus(code) != ProvinceStatus.none;
    if (lit == wasLit) return;
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
    if (changed) _changed();
  }

  /// 国内一次性点亮/取消整国（用于国家特写页里的"全选"）
  void setAllRegions(String code, bool lit) {
    final regions = geo.countryByCode[code]?.regions ?? const <SubRegion>[];
    if (regions.isEmpty) return;
    _litCountries.remove(code);
    for (final region in regions) {
      final key = '$code#${region.index}';
      if (lit) {
        _litRegions.add(key);
      } else {
        _litRegions.remove(key);
      }
    }
    _changed();
  }

  void setShowLabels(bool value) {
    if (_showLabels == value) return;
    _showLabels = value;
    _changed();
  }

  void setShowSelectedOnly(bool value) {
    if (_showSelectedOnly == value) return;
    _showSelectedOnly = value;
    _changed();
  }

  void clearAll() {
    if (_litCities.isEmpty &&
        _litCountries.isEmpty &&
        _litDirectProvinces.isEmpty &&
        _litRegions.isEmpty) {
      return;
    }
    _litCities.clear();
    _litCountries.clear();
    _litDirectProvinces.clear();
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
    _readIds(prefs.getString(_keyCities), _litCities);
    _readIds(prefs.getString(_keyDirectProvinces), _litDirectProvinces);
    final countries = prefs.getString(_keyCountries);
    if (countries != null && countries.isNotEmpty) {
      _litCountries.addAll(countries.split(',').where((e) => e.isNotEmpty));
    }
    final regions = prefs.getString(_keyRegions);
    if (regions != null && regions.isNotEmpty) {
      _litRegions.addAll(regions.split(',').where((e) => e.isNotEmpty));
    }
    _showLabels = prefs.getBool(_keyShowLabels) ?? true;
    _showSelectedOnly = prefs.getBool(_keySelectedOnly) ?? false;
    _loaded = true;
    notifyListeners();
  }

  void _readIds(String? raw, Set<int> target) {
    if (raw == null || raw.isEmpty) return;
    for (final part in raw.split(',')) {
      final id = int.tryParse(part);
      if (id != null) target.add(id);
    }
  }

  Future<void> _save() async {
    final prefs = _prefs ?? await SharedPreferences.getInstance();
    _prefs = prefs;
    await prefs.setString(_keyCities, _litCities.join(','));
    await prefs.setString(_keyCountries, _litCountries.join(','));
    await prefs.setString(_keyDirectProvinces, _litDirectProvinces.join(','));
    await prefs.setString(_keyRegions, _litRegions.join(','));
    await prefs.setBool(_keyShowLabels, _showLabels);
    await prefs.setBool(_keySelectedOnly, _showSelectedOnly);
  }

  @override
  void dispose() {
    _saveTimer?.cancel();
    super.dispose();
  }
}
