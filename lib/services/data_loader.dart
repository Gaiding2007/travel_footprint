import 'dart:convert';
import 'package:flutter/services.dart';
import '../models/city.dart';
import '../models/country.dart';

class DataLoader {
  static Future<List<City>> loadCities() async {
    final jsonString = await rootBundle.loadString('assets/data/cities.json');
    final List<dynamic> jsonList = json.decode(jsonString);
    return jsonList.map((e) => City.fromJson(e)).toList();
  }

  static Future<List<Country>> loadCountries() async {
    final jsonString = await rootBundle.loadString(
      'assets/data/countries.json',
    );
    final List<dynamic> jsonList = json.decode(jsonString);
    return jsonList.map((e) => Country.fromJson(e)).toList();
  }
}
