import 'package:flutter/foundation.dart';
import '../models/footprint.dart';
import 'package:hive/hive.dart';

class FootprintProvider extends ChangeNotifier {
  late Box<Footprint> _box;
  Footprint _footprint = Footprint(
    selectedCityIds: [],
    selectedCountryCodes: [],
  );

  FootprintProvider() {
    _load();
  }

  void _load() {
    _box = Hive.box<Footprint>('footprintBox');
    final saved = _box.get('current');
    if (saved != null) {
      _footprint = saved;
    }
    notifyListeners();
  }

  void _save() {
    _box.put('current', _footprint);
  }

  Footprint get footprint => _footprint;

  void addCity(int id) {
    if (!_footprint.selectedCityIds.contains(id)) {
      _footprint = Footprint(
        selectedCityIds: [..._footprint.selectedCityIds, id],
        selectedCountryCodes: _footprint.selectedCountryCodes,
      );
      _save();
      notifyListeners();
    }
  }

  void removeCity(int id) {
    _footprint = Footprint(
      selectedCityIds: _footprint.selectedCityIds
          .where((i) => i != id)
          .toList(),
      selectedCountryCodes: _footprint.selectedCountryCodes,
    );
    _save();
    notifyListeners();
  }

  void addCountry(String code) {
    if (!_footprint.selectedCountryCodes.contains(code)) {
      _footprint = Footprint(
        selectedCityIds: _footprint.selectedCityIds,
        selectedCountryCodes: [..._footprint.selectedCountryCodes, code],
      );
      _save();
      notifyListeners();
    }
  }

  void removeCountry(String code) {
    _footprint = Footprint(
      selectedCityIds: _footprint.selectedCityIds,
      selectedCountryCodes: _footprint.selectedCountryCodes
          .where((c) => c != code)
          .toList(),
    );
    _save();
    notifyListeners();
  }

  void toggleCity(int id) {
    if (_footprint.selectedCityIds.contains(id)) {
      removeCity(id);
    } else {
      addCity(id);
    }
  }

  void toggleCountry(String code) {
    if (_footprint.selectedCountryCodes.contains(code)) {
      removeCountry(code);
    } else {
      addCountry(code);
    }
  }
}
