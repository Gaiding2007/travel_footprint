import 'package:flutter/material.dart';

import '../data/geo_data.dart';
import '../data/shape.dart';
import '../state/footprint_store.dart';
import 'map_transform_controller.dart';

/// 地图展示模式
enum MapMode { china, world }

const Color kLitFill = Color(0xFF90CEFF);
const Color kLitBorder = Color(0xFF5A5A5A);
const Color kUnlitBorder = Color(0xFFBFBFBF);
const Color kProvinceBorder = Color(0xFF333333);

/// 世界地图上"选中等待进入"的国家边框色
const Color kSelectedBorder = Color(0xFF2E6BE6);

const Color _kCityBorder = Color(0xFFC3CBD5);
const Color _kRegionBorder = Color(0xFF9AA7B6);

/// 把"新疆维吾尔自治区"这类长名字缩成地图上更顺眼的短名字
String shortRegionName(String name) {
  const suffixes = <String>[
    '维吾尔自治区',
    '壮族自治区',
    '回族自治区',
    '特别行政区',
    '自治区',
  ];
  for (final suffix in suffixes) {
    if (name.endsWith(suffix)) {
      return name.substring(0, name.length - suffix.length);
    }
  }
  return name;
}

/// 省/州名字为空（南极洲的数据里有这种）时给个兜底显示名
String displayRegionName(SubRegion region) {
  final name = shortRegionName(region.name).trim();
  if (name.isNotEmpty) return name;
  final full = region.fullName.trim();
  if (full.isNotEmpty) return full;
  return '未命名区域';
}

/// 中国地图的默认取景范围（略去南海深处，避免大片空白海面）
Rect chinaViewBounds() =>
    Rect.fromPoints(projectLonLat(72.5, 54.8), projectLonLat(136.0, 15.5));

/// 达到该倍率即进入"市级"交互层级（点城市而不是整省）
const double kCityLevelFactor = 2.2;

/// 点击时允许吸附的范围（屏幕像素）
const double _kTapTolerance = 14;

/// 找出"被点亮的图形包住、但自己没点亮"的飞地（例如蒙古的乌兰巴托被中央省包着）。
/// 这些小块要在点亮层之上重新画成白色，否则会跟着一起变蓝。
List<Shape> computeEnclaveHoles({
  required List<Shape> all,
  required List<Shape> lit,
}) {
  if (lit.isEmpty) return const <Shape>[];
  final holes = <Shape>[];
  for (final shape in all) {
    if (lit.any((item) => identical(item, shape))) continue;
    final bounds = shape.bounds;
    final contained = lit.any((outer) {
      if (outer.extent <= shape.extent * 3) return false;
      final outerBounds = outer.bounds;
      // 先看包围盒，再看真实几何（避免小岛之类的误判）
      if (!outerBounds.contains(bounds.topLeft) ||
          !outerBounds.contains(bounds.bottomRight)) {
        return false;
      }
      return outer.contains(bounds.center);
    });
    if (contained) holes.add(shape);
  }
  return holes;
}

class FootprintMap extends StatefulWidget {
  const FootprintMap({
    super.key,
    required this.geo,
    required this.store,
    required this.controller,
    required this.mode,
    this.focusCountry,
    this.selectedCountryCode,
    this.onCountryTap,
    this.onEnterCountry,
    this.onCountryLongPress,
    this.onBackgroundTap,
    this.onCityTap,
    this.onRegionTap,
    this.onWholeTap,
  });

  final GeoData geo;
  final FootprintStore store;
  final MapTransformController controller;
  final MapMode mode;

  /// 非空时进入"国家特写"：只画这个国家的内部一级行政区
  final Country? focusCountry;

  /// 世界地图上已经"点了一下"、等待第二下进入的国家
  final String? selectedCountryCode;

  /// 世界地图上第一次点到某个国家（只高亮，不点亮）
  final ValueChanged<Country>? onCountryTap;

  /// 已经选中的国家被再次点到（进入该国家的省/州视图）
  final ValueChanged<Country>? onEnterCountry;

  /// 长按某个国家（同样进入国家特写，是捷径）
  final ValueChanged<Country>? onCountryLongPress;

  /// 国内模式点到某个城市之后回调（用于顶部提示点到了哪个市）
  final ValueChanged<Region>? onCityTap;

  /// 国家特写里点到某个省/州之后回调
  final ValueChanged<SubRegion>? onRegionTap;

  /// 没有省州划分的区域（南极洲）整块点击之后回调
  final ValueChanged<Country>? onWholeTap;
  /// 点到了空白海面（用来取消选中）
  final VoidCallback? onBackgroundTap;

  @override
  State<FootprintMap> createState() => _FootprintMapState();
}

class _FootprintMapState extends State<FootprintMap> {
  Path _allPath = Path();
  Path _litPath = Path();
  Path _overlayPath = Path();
  Path _outlinePath = Path();
  Path _selectedPath = Path();

  double _gestureStartScale = 1;

  @override
  void initState() {
    super.initState();
    widget.store.addListener(_onDataChanged);
    _rebuild();
  }

  @override
  void didUpdateWidget(covariant FootprintMap oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.store != widget.store) {
      oldWidget.store.removeListener(_onDataChanged);
      widget.store.addListener(_onDataChanged);
    }
    if (oldWidget.mode != widget.mode ||
        oldWidget.store != widget.store ||
        oldWidget.focusCountry?.code != widget.focusCountry?.code ||
        oldWidget.selectedCountryCode != widget.selectedCountryCode) {
      _rebuild();
    }
  }

  @override
  void dispose() {
    widget.store.removeListener(_onDataChanged);
    super.dispose();
  }

  void _onDataChanged() {
    if (!mounted) return;
    setState(_rebuild);
  }

  void _rebuild() {
    final all = Path();
    final lit = Path();
    final overlay = Path();
    final outline = Path();
    final selected = Path();

    final focus = widget.focusCountry;
    if (focus != null) {
      final litRegions = <SubRegion>[];
      for (final region in focus.regions) {
        all.addPath(region.shape.path, Offset.zero);
        if (widget.store.isRegionLit(focus.code, region.index)) {
          lit.addPath(region.shape.path, Offset.zero);
          litRegions.add(region);
        }
      }
      // 没有下级省州的地方，或者用户勾了"整块"（南极洲）：整块点亮
      if (widget.store.isCountryMarkedWhole(focus.code) || !focus.hasRegions) {
        if (widget.store.isCountryLit(focus.code)) {
          lit.addPath(focus.shape.path, Offset.zero);
        }
      }
      outline.addPath(focus.shape.path, Offset.zero);
      // 飞地修正：被点亮的省州把里面没点亮的小块（如蒙古的乌兰巴托）重新盖成白色。
      // 勾了"整块"的时候不需要挖洞，否则整个国家会被自己的子区域盖白。
      if (!widget.store.isCountryMarkedWhole(focus.code)) {
        for (final shape in computeEnclaveHoles(
          all: [for (final region in focus.regions) region.shape],
          lit: [for (final region in litRegions) region.shape],
        )) {
          overlay.addPath(shape.path, Offset.zero);
        }
      }
    } else if (widget.mode == MapMode.china) {
      for (final city in widget.geo.cities) {
        all.addPath(city.shape.path, Offset.zero);
      }
      for (final province in widget.geo.provinces) {
        outline.addPath(province.shape.path, Offset.zero);
      }
      // 国内永远是"点到哪个市就只亮哪个市"，不参与粗略/详细
      for (final city in widget.geo.cities) {
        if (widget.store.isCityLit(city.id)) {
          lit.addPath(city.shape.path, Offset.zero);
        }
      }
      for (final province in widget.geo.provinces) {
        if (widget.store.isProvinceLit(province.id)) {
          lit.addPath(province.shape.path, Offset.zero);
        }
      }
    } else {
      for (final country in widget.geo.countries) {
        all.addPath(country.shape.path, Offset.zero);
        if (country.code == widget.selectedCountryCode) {
          selected.addPath(country.shape.path, Offset.zero);
        }
      }
      if (widget.store.detailDisplay) {
        // 详细：只亮去过的省/州；没有省州数据的国家整块亮
        for (final country in widget.geo.countries) {
          if (country.code == 'CHN') continue; // 中国单独按省级形状画
          final wholeLit = widget.store.isWholeCountryLit(country.code);
          if (!country.hasRegions) {
            if (wholeLit) lit.addPath(country.shape.path, Offset.zero);
            continue;
          }
          if (wholeLit) {
            lit.addPath(country.shape.path, Offset.zero);
            continue;
          }
          for (final region in country.regions) {
            if (widget.store.isRegionLit(country.code, region.index)) {
              lit.addPath(region.shape.path, Offset.zero);
            }
          }
        }
        // 中国：详细模式只亮真正去过的那几个省
        for (final province in widget.geo.provinces) {
          if (widget.store.provinceVisited(province.id)) {
            lit.addPath(province.shape.path, Offset.zero);
          }
        }
      } else {
        // 粗略：只要去过任意一个省/州就亮整个国家
        for (final country in widget.geo.countries) {
          if (widget.store.isCountryLit(country.code)) {
            lit.addPath(country.shape.path, Offset.zero);
          }
        }
      }
    }

    _allPath = all;
    _litPath = lit;
    _overlayPath = overlay;
    _outlinePath = outline;
    _selectedPath = selected;
  }

  /// 允许拖到的范围
  Rect get _contentBounds {
    final focus = widget.focusCountry;
    if (focus != null) {
      final bounds = _coreBounds(focus);
      return bounds.inflate(bounds.longestSide * 0.06);
    }
    return widget.mode == MapMode.china ? widget.geo.chinaFullBounds : widget.geo.worldBounds;
  }

  /// 初始取景范围
  Rect get _frameBounds {
    final focus = widget.focusCountry;
    if (focus != null) {
      final bounds = _coreBounds(focus).inflate(
        _coreBounds(focus).longestSide * 0.06,
      );
      // 南极洲这种"又宽又扁"的地方，按宽度取景会缩成一条线，
      // 这里改成按高度取景、左右可以拖（content 仍是完整范围）。
      final aspect = bounds.width / bounds.height;
      if (aspect > 5) {
        final halfWidth = bounds.height * 1.25;
        return Rect.fromLTRB(
          bounds.center.dx - halfWidth,
          bounds.top,
          bounds.center.dx + halfWidth,
          bounds.bottom,
        );
      }
      return bounds;
    }
    return widget.mode == MapMode.china ? chinaViewBounds() : widget.geo.worldBounds;
  }

  /// 国家的取景范围只算"主体部分"。
  ///
  /// 像俄罗斯这种跨 180° 经线的国家，把所有省州的包围盒合起来会得到横跨整个地球的宽度，
  /// 结果地图被缩成一小团。这里以面积最大的省州为中心开一个 ±130° 经度的窗口，
  /// **按坐标点**筛：窗口外的点（楚科奇东端那一小截）不参与取景，但它们依然能点、依然会画出来。
  Rect _coreBounds(Country country) {
    final regions = country.regions;
    if (regions.isEmpty) return country.shape.bounds;

    var anchorRegion = regions.first;
    for (final region in regions) {
      if (region.shape.extent > anchorRegion.shape.extent) anchorRegion = region;
    }
    final anchorX = anchorRegion.shape.anchor.dx;
    const maxGap = 130 * kUnitsPerDegree;
    final windowLeft = anchorX - maxGap;
    final windowRight = anchorX + maxGap;

    double? minX;
    double? minY;
    double? maxX;
    double? maxY;
    for (final region in regions) {
      final bounds = region.shape.bounds;
      if (bounds.right < windowLeft || bounds.left > windowRight) continue;
      for (final ring in region.shape.rings) {
        for (final point in ring) {
          final x = point.dx;
          if (x < windowLeft || x > windowRight) continue;
          final y = point.dy;
          if (minX == null || x < minX) minX = x;
          if (maxX == null || x > maxX) maxX = x;
          if (minY == null || y < minY) minY = y;
          if (maxY == null || y > maxY) maxY = y;
        }
      }
    }
    if (minX == null || minY == null || maxX == null || maxY == null) {
      return country.shape.bounds;
    }
    return Rect.fromLTRB(minX, minY, maxX, maxY);
  }

  void _handleTap(Offset localPosition) {
    final controller = widget.controller;
    if (!controller.isReady) return;
    final point = controller.screenToMap(localPosition);
    final tolerance = _kTapTolerance / controller.scale;

    final focus = widget.focusCountry;
    if (focus != null) {
      if (!focus.hasRegions) {
        // 南极洲这种没有省州划分的：点一下整块切换
        widget.store.toggleCountry(focus.code);
        widget.onWholeTap?.call(focus);
        return;
      }
      final region = widget.geo.subRegionAt(focus, point, tolerance: tolerance);
      if (region != null) {
        widget.store.toggleRegion(focus.code, region.index);
        widget.onRegionTap?.call(region);
      }
      return;
    }

    if (widget.mode == MapMode.world) {
      final country = widget.geo.countryAt(point, tolerance: tolerance);
      if (country == null) {
        widget.onBackgroundTap?.call();
        return;
      }
      if (country.code == widget.selectedCountryCode) {
        widget.onEnterCountry?.call(country);
      } else {
        widget.onCountryTap?.call(country);
      }
      return;
    }

    // 国内：点到哪个市就只点亮那个市（需求 2）。
    // 直辖市、港澳台这种只有一条记录的省级行政区，点到的也是它下面的那一条。
    final city = widget.geo.cityAt(point, tolerance: tolerance);
    if (city != null) {
      widget.store.toggleCity(city.id);
      widget.onCityTap?.call(city);
      return;
    }
    // 极少数没有下级记录的空白区域，退一步按省级处理
    final province = widget.geo.provinceAt(point, tolerance: tolerance);
    if (province != null) widget.store.toggleProvince(province.id);
  }

  void _handleLongPress(Offset localPosition) {
    final controller = widget.controller;
    if (!controller.isReady) return;
    final point = controller.screenToMap(localPosition);
    final tolerance = _kTapTolerance / controller.scale;

    if (widget.focusCountry == null && widget.mode == MapMode.world) {
      final country = widget.geo.countryAt(point, tolerance: tolerance);
      if (country != null) widget.onCountryLongPress?.call(country);
      return;
    }
    if (widget.mode != MapMode.china) return;
    final city = widget.geo.cityAt(point, tolerance: tolerance);
    if (city != null) widget.store.toggleCity(city.id);
  }

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final size = Size(constraints.maxWidth, constraints.maxHeight);
        widget.controller.attach(
          viewport: size,
          content: _contentBounds,
          frame: _frameBounds,
          notify: false,
        );

        return GestureDetector(
          behavior: HitTestBehavior.opaque,
          onScaleStart: (_) => _gestureStartScale = widget.controller.scale,
          onScaleUpdate: (details) {
            if (details.pointerCount >= 2) {
              widget.controller.transformTo(
                scale: _gestureStartScale * details.scale,
                focal: details.localFocalPoint,
              );
            } else if (details.focalPointDelta != Offset.zero) {
              widget.controller.panBy(details.focalPointDelta);
            }
          },
          onTapUp: (details) => _handleTap(details.localPosition),
          onLongPressStart: (details) => _handleLongPress(details.localPosition),
          child: ClipRect(
            child: AnimatedBuilder(
              animation: widget.controller,
              builder: (context, _) {
                return CustomPaint(
                  size: size,
                  isComplex: true,
                  painter: _FootprintPainter(
                    controller: widget.controller,
                    allPath: _allPath,
                    litPath: _litPath,
                    overlayPath: _overlayPath,
                    outlinePath: _outlinePath,
                    selectedPath: _selectedPath,
                    mode: widget.mode,
                    focus: widget.focusCountry != null,
                  ),
                );
              },
            ),
          ),
        );
      },
    );
  }
}

class _FootprintPainter extends CustomPainter {
  _FootprintPainter({
    required this.controller,
    required this.allPath,
    required this.litPath,
    required this.overlayPath,
    required this.outlinePath,
    required this.selectedPath,
    required this.mode,
    required this.focus,
  });

  final MapTransformController controller;
  final Path allPath;
  final Path litPath;
  final Path overlayPath;
  final Path outlinePath;
  final Path selectedPath;
  final MapMode mode;
  final bool focus;

  Paint _stroke(double width, Color color) => Paint()
    ..style = PaintingStyle.stroke
    ..strokeWidth = width
    ..strokeJoin = StrokeJoin.round
    ..color = color;

  @override
  void paint(Canvas canvas, Size size) {
    canvas.drawRect(Offset.zero & size, Paint()..color = Colors.white);
    if (!controller.isReady) return;

    final scale = controller.scale;
    canvas.save();
    canvas.translate(controller.offset.dx, controller.offset.dy);
    canvas.scale(scale);

    canvas.drawPath(allPath, Paint()..color = Colors.white);
    canvas.drawPath(litPath, Paint()..color = kLitFill);
    // 飞地：被点亮的大块里，没点亮的小块要重新盖回白色
    if (overlayPath.getBounds().isEmpty == false) {
      canvas.drawPath(overlayPath, Paint()..color = Colors.white);
    }

    if (focus) {
      canvas.drawPath(allPath, _stroke(0.7 / scale, _kRegionBorder));
      canvas.drawPath(outlinePath, _stroke(1.3 / scale, kProvinceBorder));
    } else if (mode == MapMode.china) {
      canvas.drawPath(allPath, _stroke(0.5 / scale, _kCityBorder));
      canvas.drawPath(outlinePath, _stroke(1.0 / scale, kProvinceBorder));
    } else {
      canvas.drawPath(allPath, _stroke(0.45 / scale, _kCityBorder));
      if (litPath.getBounds().isEmpty == false) {
        canvas.drawPath(litPath, _stroke(0.6 / scale, const Color(0xFF7C8B9C)));
      }
    }

    if (selectedPath.getBounds().isEmpty == false) {
      canvas.drawPath(selectedPath, _stroke(2.2 / scale, kSelectedBorder));
    }

    canvas.restore();
  }

  @override
  bool shouldRepaint(covariant _FootprintPainter oldDelegate) {
    return oldDelegate.controller.scale != controller.scale ||
        oldDelegate.controller.offset != controller.offset ||
        oldDelegate.allPath != allPath ||
        oldDelegate.litPath != litPath ||
        oldDelegate.overlayPath != overlayPath ||
        oldDelegate.selectedPath != selectedPath ||
        oldDelegate.focus != focus ||
        oldDelegate.mode != mode;
  }
}
