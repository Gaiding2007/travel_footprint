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

/// 中国地图的默认取景范围（略去南海深处，避免大片空白海面）
Rect chinaViewBounds() =>
    Rect.fromPoints(projectLonLat(72.5, 54.8), projectLonLat(136.0, 15.5));

/// 达到该倍率即进入"市级"交互层级（点城市而不是整省）
const double kCityLevelFactor = 2.2;

/// 点击时允许吸附的范围（屏幕像素）
const double _kTapTolerance = 14;

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

  /// 点到了空白海面（用来取消选中）
  final VoidCallback? onBackgroundTap;

  @override
  State<FootprintMap> createState() => _FootprintMapState();
}

class _FootprintMapState extends State<FootprintMap> {
  Path _allPath = Path();
  Path _litPath = Path();
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
    final outline = Path();
    final selected = Path();

    final focus = widget.focusCountry;
    if (focus != null) {
      for (final region in focus.regions) {
        all.addPath(region.shape.path, Offset.zero);
        if (widget.store.isRegionLit(focus.code, region.index)) {
          lit.addPath(region.shape.path, Offset.zero);
        }
      }
      outline.addPath(focus.shape.path, Offset.zero);
    } else if (widget.mode == MapMode.china) {
      for (final city in widget.geo.cities) {
        all.addPath(city.shape.path, Offset.zero);
      }
      for (final province in widget.geo.provinces) {
        outline.addPath(province.shape.path, Offset.zero);
      }
      if (widget.store.detailDisplay) {
        // 详细：只亮真正去过的城市（整省点亮的省份则整块亮）
        for (final city in widget.geo.cities) {
          if (widget.store.isCityLit(city.id)) lit.addPath(city.shape.path, Offset.zero);
        }
        for (final province in widget.geo.provinces) {
          if (widget.store.isProvinceLit(province.id)) {
            lit.addPath(province.shape.path, Offset.zero);
          }
        }
      } else {
        // 粗略：去过一个市就把整个省点亮
        for (final province in widget.geo.provinces) {
          if (widget.store.provinceVisited(province.id)) {
            lit.addPath(province.shape.path, Offset.zero);
          }
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
      final bounds = _coreBounds(focus);
      return bounds.inflate(bounds.longestSide * 0.06);
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
      final region = widget.geo.subRegionAt(focus, point, tolerance: tolerance);
      if (region != null) widget.store.toggleRegion(focus.code, region.index);
      return;
    }

    if (widget.mode == MapMode.world) {
      final country = widget.geo.countryAt(point, tolerance: tolerance);
      if (country == null) {
        widget.onBackgroundTap?.call();
        return;
      }
      if (!country.hasRegions) {
        // 没有下级省州的国家，点一下就点亮/取消
        widget.store.toggleCountry(country.code);
        return;
      }
      if (country.code == widget.selectedCountryCode) {
        widget.onEnterCountry?.call(country);
      } else {
        widget.onCountryTap?.call(country);
      }
      return;
    }

    if (controller.scale >= controller.fitScale * kCityLevelFactor) {
      final city = widget.geo.cityAt(point, tolerance: tolerance);
      if (city != null) {
        widget.store.toggleCity(city.id);
        return;
      }
    }
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
    required this.outlinePath,
    required this.selectedPath,
    required this.mode,
    required this.focus,
  });

  final MapTransformController controller;
  final Path allPath;
  final Path litPath;
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
        oldDelegate.selectedPath != selectedPath ||
        oldDelegate.focus != focus ||
        oldDelegate.mode != mode;
  }
}
