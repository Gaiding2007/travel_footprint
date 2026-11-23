import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:travel_footprint/data/geo_data.dart';
import 'package:travel_footprint/screens/home_screen.dart';
import 'package:travel_footprint/state/footprint_store.dart';

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

void main() {
  testWidgets('概览卡的粗略/详细开关能切换', (tester) async {
    final geo = GeoData.parse(
      '{"meta":{},"provinces":[${_box(11, '测试省', 0, 100, 30, 102, 32)}],'
      '"cities":[${_box(1101, '甲市', 11, 100.1, 30.1, 100.9, 30.9)}]}',
      '{"meta":{},"countries":[${_countryBox('AAA', '甲国', 50, 10, 52, 12)}]}',
    );
    SharedPreferences.setMockInitialValues(<String, Object>{});
    final store = FootprintStore(geo);
    await store.load();

    // 手机比例的画布，保证概览卡里的开关真的在可视区域内
    tester.view.physicalSize = const Size(400, 900);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(MaterialApp(home: HomeScreen(geo: geo, store: store)));
    await tester.pumpAndSettle();

    expect(store.detailDisplay, isFalse);
    await tester.tap(find.text('详细'));
    await tester.pumpAndSettle();
    // 让防抖保存的 350ms 定时器跑完，避免测试结束时报 "Pending timers"
    await tester.pump(const Duration(milliseconds: 400));
    expect(store.detailDisplay, isTrue, reason: '点「详细」应该切到详细模式');

    await tester.tap(find.text('粗略'));
    await tester.pumpAndSettle();
    await tester.pump(const Duration(milliseconds: 400));
    expect(store.detailDisplay, isFalse);
  });
}
