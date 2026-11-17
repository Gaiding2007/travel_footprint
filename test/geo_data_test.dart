import 'package:flutter_test/flutter_test.dart';
import 'package:travel_footprint/data/geo_data.dart';
import 'package:travel_footprint/data/shape.dart';

/// 数据文件里的坐标是"经纬度 × 10000"的整数
const String _sampleCn = '''
{
  "provinces": [
    {
      "i": 11, "n": "测试省", "e": "测试省", "x": 1010000, "y": 201000,
      "r": [[[1000000, 200000], [1020000, 200000], [1020000, 202000], [1000000, 202000]]]
    }
  ],
  "cities": [
    {
      "i": 1101, "n": "测试市", "e": "测试市", "p": 11, "x": 1010000, "y": 201000,
      "r": [[[1000000, 200000], [1020000, 200000], [1020000, 202000], [1000000, 202000]]]
    }
  ]
}
''';

const String _sampleWorld = '''
{
  "countries": [
    {
      "i": "TST", "n": "测试国", "x": 1010000, "y": 201000,
      "r": [[[1000000, 200000], [1020000, 200000], [1020000, 202000], [1000000, 202000]]]
    }
  ]
}
''';

void main() {
  test('经纬度投影成地图坐标', () {
    final point = projectLonLat(100, 20);
    expect(point.dx, closeTo(280000, 0.001));
    expect(point.dy, closeTo(70000, 0.001));
  });

  test('解析后可以按坐标找到省份 / 城市 / 国家', () {
    final geo = GeoData.parse(_sampleCn, _sampleWorld);

    expect(geo.provinces, hasLength(1));
    expect(geo.cities, hasLength(1));
    expect(geo.countries, hasLength(1));
    expect(geo.citiesByProvince[11], hasLength(1));

    // 落在区域内部
    expect(geo.provinceAt(projectLonLat(101, 20.1))?.name, '测试省');
    expect(geo.cityAt(projectLonLat(101, 20.1))?.name, '测试市');
    expect(geo.countryAt(projectLonLat(101, 20.1))?.code, 'TST');

    // 落在区域外
    expect(geo.provinceAt(projectLonLat(120, 30)), isNull);
  });

  test('包围盒与面积', () {
    final geo = GeoData.parse(_sampleCn, _sampleWorld);
    final city = geo.cities.first;
    expect(city.shape.bounds.width, closeTo(2000, 0.001));
    expect(city.shape.bounds.height, closeTo(200, 0.001));
    expect(city.shape.extent, closeTo(400000, 1));
    expect(geo.chinaBounds.width, closeTo(2000, 0.001));
  });
}
