import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:travel_footprint/data/geo_data.dart';
import 'package:travel_footprint/state/footprint_store.dart';

/// 造一块方形区域（经纬度×10000 的整数坐标）
String _box(int id, String name, int parent, double lon0, double lat0, double lon1, double lat1) {
  final x0 = (lon0 * 10000).round();
  final y0 = (lat0 * 10000).round();
  final x1 = (lon1 * 10000).round();
  final y1 = (lat1 * 10000).round();
  return '{"i":$id,"n":"$name","e":"$name","p":$parent,'
      '"x":${(x0 + x1) ~/ 2},"y":${(y0 + y1) ~/ 2},'
      '"b":[$x0,$y0,$x1,$y1],'
      '"r":[[[$x0,$y0],[$x1,$y0],[$x1,$y1],[$x0,$y1]]]}';
}

String _countryBox(String code, String name, double lon0, double lat0, double lon1, double lat1) {
  final x0 = (lon0 * 10000).round();
  final y0 = (lat0 * 10000).round();
  final x1 = (lon1 * 10000).round();
  final y1 = (lat1 * 10000).round();
  return '{"i":"$code","n":"$name","x":${(x0 + x1) ~/ 2},"y":${(y0 + y1) ~/ 2},'
      '"b":[$x0,$y0,$x1,$y1],'
      '"r":[[[$x0,$y0],[$x1,$y0],[$x1,$y1],[$x0,$y1]]]}';
}

GeoData _buildGeo() {
  final province = _box(11, '测试省', 0, 100, 30, 102, 32);
  final cityA = _box(1101, '甲市', 11, 100.1, 30.1, 100.9, 30.9);
  final cityB = _box(1102, '乙市', 11, 100.9, 30.1, 101.9, 30.9);
  final cn = '{"meta":{},"provinces":[$province],"cities":[$cityA,$cityB]}';

  final world = '{"meta":{},"countries":['
      '${_countryBox('AAA', '甲国', 50, 10, 52, 12)},'
      '${_countryBox('BBB', '乙国', 60, 10, 62, 12)}]}';

  final admin1 = '{"meta":{},"countries":{"AAA":['
      '${_box(1, '州一', 0, 50.1, 10.1, 50.9, 11.0)},'
      '${_box(2, '州二', 0, 51.0, 10.1, 51.9, 11.0)}]}}';

  return GeoData.parse(cn, world, admin1);
}

void main() {
  late GeoData geo;
  late FootprintStore store;

  setUp(() async {
    geo = _buildGeo();
    SharedPreferences.setMockInitialValues(<String, Object>{});
    store = FootprintStore(geo);
    await store.load();
  });

  tearDown(() async {
    // 让 350ms 的防抖保存定时器跑完，避免测试结束时还有挂起的 Timer
    await Future<void>.delayed(const Duration(milliseconds: 420));
  });

  test('点亮单个城市不会连带点亮整个省', () {
    expect(store.litCityCount, 0);
    store.toggleCity(1101);
    expect(store.litCityCount, 1);
    expect(store.isCityLit(1101), isTrue);
    expect(store.isProvinceLit(11), isFalse, reason: '省份本身没有被点亮');
    expect(store.provinceVisited(11), isTrue, reason: '去过省里的一个市算去过这个省');
  });

  test('省份可以单独点亮，且不会把所有市一起点亮', () {
    store.toggleProvince(11);
    expect(store.isProvinceLit(11), isTrue);
    expect(store.litProvinceCount, 1);
    expect(store.litCityCountInProvince(11), 0, reason: '点省份不应该连带点亮城市');

    store.toggleProvince(11);
    expect(store.isProvinceLit(11), isFalse);
    expect(store.provinceVisited(11), isFalse);
  });

  test('国家里点亮一个省州，整个国家就算去过', () {
    final country = geo.countryByCode['AAA']!;
    expect(country.hasRegions, isTrue);
    store.toggleRegion('AAA', country.regions.first.index);

    expect(store.isCountryLit('AAA'), isTrue, reason: '显示上整个国家点亮');
    expect(store.isWholeCountryLit('AAA'), isFalse, reason: '并没有走遍所有省州');
    expect(store.litRegionCount('AAA'), 1);
    expect(country.regions.length, 2);
    expect(store.isCountryLit('BBB'), isFalse);
  });

  test('全部省州都点亮时算走遍该国', () {
    final country = geo.countryByCode['AAA']!;
    for (final region in country.regions) {
      store.toggleRegion('AAA', region.index);
    }
    expect(store.isWholeCountryLit('AAA'), isTrue);
    expect(store.litRegionCount('AAA'), country.regions.length);
  });

  test('没有省州数据的国家一点即切换', () {
    expect(geo.countryByCode['BBB']!.hasRegions, isFalse);
    store.toggleCountry('BBB');
    expect(store.isCountryLit('BBB'), isTrue);
    store.toggleCountry('BBB');
    expect(store.isCountryLit('BBB'), isFalse);
  });

  test('粗略/详细开关可以切换', () {
    expect(store.detailDisplay, isFalse);
    store.setDetailDisplay(true);
    expect(store.detailDisplay, isTrue);
  });

  test('清空会把国内和国外一起清掉', () {
    store.toggleCity(1101);
    store.toggleProvince(11);
    store.toggleCountry('BBB');
    store.clearAll();
    expect(store.litCityCount, 0);
    expect(store.litProvinceCount, 0);
    expect(store.litCountryCount, 0);
  });
}
