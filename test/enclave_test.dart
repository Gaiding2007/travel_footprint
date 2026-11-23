import 'dart:convert';
import 'dart:io';
import 'dart:ui';

import 'package:flutter_test/flutter_test.dart';
import 'package:travel_footprint/data/shape.dart';
import 'package:travel_footprint/map/footprint_map.dart';

Shape rectShape(Rect rect) {
  return Shape(
    anchor: rect.center,
    rings: [
      [
        rect.topLeft,
        rect.topRight,
        rect.bottomRight,
        rect.bottomLeft,
      ],
    ],
    bounds: rect,
  );
}

void main() {
  test('被点亮的大块包住没点亮的小块时，小块要重新盖白', () {
    final outer = rectShape(const Rect.fromLTRB(0, 0, 100, 100));
    final inner = rectShape(const Rect.fromLTRB(40, 40, 60, 60));
    final holes = computeEnclaveHoles(all: [outer, inner], lit: [outer]);
    expect(holes.length, 1);
    expect(identical(holes.first, inner), isTrue);
  });

  test('两块并排时不算飞地', () {
    final left = rectShape(const Rect.fromLTRB(0, 0, 100, 100));
    final right = rectShape(const Rect.fromLTRB(100, 0, 200, 100));
    expect(computeEnclaveHoles(all: [left, right], lit: [left]), isEmpty);
  });

  test('蒙古国：点亮中央省不会把乌兰巴托一起点亮', () {
    final raw = File('assets/geo/admin1.json').readAsStringSync();
    final json = jsonDecode(raw) as Map<String, dynamic>;
    final countries = (json['countries'] as Map).cast<String, dynamic>();
    final mongolia = (countries['MNG'] as List).cast<Map<String, dynamic>>();
    final regions = [
      for (final item in mongolia)
        (
          name: item['n'] as String,
          shape: Shape.fromJson(item),
        ),
    ];

    // 数据里确实分成了两条：中央省 + 乌兰巴托
    final ubt = regions.firstWhere((item) => item.name.contains('乌兰巴托'));
    final tow = regions.firstWhere(
      (item) => item.name.contains('中央') || item.name.contains('Töv'),
    );
    expect(identical(ubt, tow), isFalse);

    // 乌兰巴托整块落在中央省内部 —— 这就是用户说的"点中央省乌兰巴托也亮了"
    expect(tow.shape.bounds.contains(ubt.shape.bounds.topLeft), isTrue);
    expect(tow.shape.bounds.contains(ubt.shape.bounds.bottomRight), isTrue);
    expect(tow.shape.contains(ubt.shape.bounds.center), isTrue);

    // 只点亮中央省时，飞地修正必须把乌兰巴托挑出来盖回白色
    final holes = computeEnclaveHoles(
      all: [for (final region in regions) region.shape],
      lit: [tow.shape],
    );
    expect(holes.any((shape) => identical(shape, ubt.shape)), isTrue);
  });
}
