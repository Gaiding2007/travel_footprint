import 'package:hive/hive.dart';

part 'footprint.g.dart';

@HiveType(typeId: 0)
class Footprint {
  @HiveField(0)
  List<int> selectedCityIds;

  @HiveField(1)
  List<String> selectedCountryCodes;

  Footprint({
    required this.selectedCityIds,
    required this.selectedCountryCodes,
  });
}
