import 'package:flutter/material.dart';

import '../data/geo_data.dart';
import '../data/shape.dart';
import '../state/footprint_store.dart';
import 'map_transform_controller.dart';

/// 地图展示模式
enum MapMode { china, world }

const Color kLitFill = Color(0xFF90CEFF);
const Color kPartialFill = Color(0xFFD8EBFF);
const Color kLitBorder = Color(0xFF5A5A5A);
const Color kUnlitBorder = Color(0xFFBFBFBF);
const Color kProvinceBorder = Color(0xFF333333);
const Color kLabelColor = Color(0xFF3D3D3D);

/// 面积小但重要的行政区，低倍率下也要显示名称
const Set<String> kAlwaysLabeled = {'北京', '上海', '天津', '重庆', '香港', '澳门'};

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

class FootprintMap extends StatefulWidget {
  const FootprintMap({
    super.key,
    required this.geo,
    required this.store,
    required this.controller,
    required this.mode,
    this.focusCountry,
    this.onCountryLongPress,
  });

  final GeoData geo;
  final FootprintStore store;
  final MapTransformController controller;
  final MapMode mode;

  /// 非空时进入"国家特写"：只画这个国家的内部一级行政区
  final Country? focusCountry;

  /// 长按某个国家（用于进入国家特写）
  final ValueChanged<Country>? onCountryLongPress;

  @override
  State<FootprintMap> createState() => _FootprintMapState();
}

class _FootprintMapState extends State<FootprintMap> {
  final Map<String, TextPainter> _textCache = <String, TextPainter>{};

  Path _allPath = Path();
  Path _litPath = Path();
  Path _partialPath = Path();
  Path _outlinePath = Path();
  List<_Label> _labels = const <_Label>[];

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
        oldWidget.focusCountry?.code != widget.focusCountry?.code) {
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
    final partial = Path();
    final outline = Path();
    final labels = <_Label>[];

    final focus = widget.focusCountry;
    if (focus != null) {
      final wholeLit = widget.store.isWholeCountryLit(focus.code);
      for (final region in focus.regions) {
        all.addPath(region.shape.path, Offset.zero);
        final regionLit = wholeLit || widget.store.isRegionLit(focus.code, region.index);
        if (regionLit) lit.addPath(region.shape.path, Offset.zero);
        labels.add(
          _Label(
            text: shortRegionName(region.name),
            anchor: region.shape.anchor,
            area: region.shape.extent,
            always: false,
          ),
        );
      }
      outline.addPath(focus.shape.path, Offset.zero);
    } else if (widget.mode == MapMode.china) {
      for (final city in widget.geo.cities) {
        all.addPath(city.shape.path, Offset.zero);
        if (widget.store.isCityLit(city.id)) lit.addPath(city.shape.path, Offset.zero);
      }
      for (final province in widget.geo.provinces) {
        outline.addPath(province.shape.path, Offset.zero);
        if (widget.store.provinceStatus(province.id) == ProvinceStatus.partial) {
          partial.addPath(province.shape.path, Offset.zero);
        }
        labels.add(
          _Label(
            text: province.name,
            anchor: province.shape.anchor,
            area: province.shape.extent,
            always: kAlwaysLabeled.contains(province.name),
          ),
        );
      }
    } else {
      for (final country in widget.geo.countries) {
        all.addPath(country.shape.path, Offset.zero);
        switch (widget.store.countryStatus(country.code)) {
          case ProvinceStatus.lit:
            lit.addPath(country.shape.path, Offset.zero);
          case ProvinceStatus.partial:
            partial.addPath(country.shape.path, Offset.zero);
          case ProvinceStatus.none:
            break;
        }
        labels.add(
          _Label(
            text: country.name,
            anchor: country.shape.anchor,
            area: country.shape.extent,
            always: false,
          ),
        );
      }
    }

    labels.sort((a, b) {
      if (a.always != b.always) return a.always ? -1 : 1;
      return b.area.compareTo(a.area);
    });

    _allPath = all;
    _litPath = lit;
    _partialPath = partial;
    _outlinePath = outline;
    _labels = labels;
  }

  Rect get _contentBounds {
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
  /// 结果地图被缩成一小团。这里以面积最大的省州为中心开一个 ±100° 经度的窗口，
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

    final focus = widget.focusCountry;
    if (focus != null) {
      final region = widget.geo.subRegionAt(focus, point);
      if (region != null) widget.store.toggleRegion(focus.code, region.index);
      return;
    }
    if (widget.mode == MapMode.world) {
      final country = widget.geo.countryAt(point);
      if (country != null) widget.store.toggleCountry(country.code);
      return;
    }
    if (controller.scale >= controller.fitScale * kCityLevelFactor) {
      final city = widget.geo.cityAt(point);
      if (city != null) {
        widget.store.toggleCity(city.id);
        return;
      }
    }
    final province = widget.geo.provinceAt(point);
    if (province != null) widget.store.toggleProvince(province.id);
  }

  void _handleLongPress(Offset localPosition) {
    final controller = widget.controller;
    if (!controller.isReady) return;
    final point = controller.screenToMap(localPosition);
    if (widget.focusCountry == null && widget.mode == MapMode.world) {
      final country = widget.geo.countryAt(point);
      if (country != null) widget.onCountryLongPress?.call(country);
      return;
    }
    if (widget.mode != MapMode.china) return;
    final city = widget.geo.cityAt(point);
    if (city != null) widget.store.toggleCity(city.id);
  }

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final size = Size(constraints.maxWidth, constraints.maxHeight);
        widget.controller.attach(viewport: size, content: _contentBounds, notify: false);
        final cityLevel = widget.controller.isReady &&
            widget.controller.scale >= widget.controller.fitScale * kCityLevelFactor;

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
                    partialPath: _partialPath,
                    outlinePath: _outlinePath,
                    labels: _labels,
                    mode: widget.mode,
                    focus: widget.focusCountry != null,
                    showLabels: widget.store.showLabels,
                    cityLevel: cityLevel,
                    textCache: _textCache,
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

class _Label {
  const _Label({
    required this.text,
    required this.anchor,
    required this.area,
    required this.always,
  });

  final String text;
  final Offset anchor;
  final double area;
  final bool always;
}

class _FootprintPainter extends CustomPainter {
  _FootprintPainter({
    required this.controller,
    required this.allPath,
    required this.litPath,
    required this.partialPath,
    required this.outlinePath,
    required this.labels,
    required this.mode,
    required this.focus,
    required this.showLabels,
    required this.cityLevel,
    required this.textCache,
  });

  final MapTransformController controller;
  final Path allPath;
  final Path litPath;
  final Path partialPath;
  final Path outlinePath;
  final List<_Label> labels;
  final MapMode mode;
  final bool focus;
  final bool showLabels;
  final bool cityLevel;
  final Map<String, TextPainter> textCache;

  @override
  void paint(Canvas canvas, Size size) {
    canvas.drawRect(Offset.zero & size, Paint()..color = Colors.white);
    if (!controller.isReady) return;

    final scale = controller.scale;
    canvas.save();
    canvas.translate(controller.offset.dx, controller.offset.dy);
    canvas.scale(scale);

    canvas.drawPath(allPath, Paint()..color = Colors.white);
    canvas.drawPath(partialPath, Paint()..color = kPartialFill);
    canvas.drawPath(litPath, Paint()..color = kLitFill);

    if (focus) {
      // 国家特写：省/州边界更清楚一些
      canvas.drawPath(
        allPath,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 0.7 / scale
          ..color = const Color(0xFF9AA7B6),
      );
      canvas.drawPath(
        outlinePath,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1.3 / scale
          ..color = kProvinceBorder,
      );
    } else {
      // 国内 / 世界：低倍率下边界更淡，保证像一张完整的地图
      canvas.drawPath(
        allPath,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = (cityLevel ? 0.55 : 0.42) / scale
          ..color = cityLevel ? kUnlitBorder : const Color(0xFFC3CBD5),
      );
      if (scale >= controller.fitScale * 1.6) {
        canvas.drawPath(
          litPath,
          Paint()
            ..style = PaintingStyle.stroke
            ..strokeWidth = 0.75 / scale
            ..color = kLitBorder,
        );
      }
      if (mode == MapMode.china) {
        canvas.drawPath(
          outlinePath,
          Paint()
            ..style = PaintingStyle.stroke
            ..strokeWidth = 1.0 / scale
            ..color = kProvinceBorder,
        );
      }
    }

    canvas.restore();

    if (showLabels) _paintLabels(canvas, size);
  }

  void _paintLabels(Canvas canvas, Size size) {
    final scale = controller.scale;
    final double minArea;
    if (focus) {
      minArea = 55;
    } else if (mode == MapMode.china) {
      minArea = 110;
    } else {
      minArea = 240;
    }
    final occupied = <Rect>[];

    for (final label in labels) {
      final anchor = controller.mapToScreen(label.anchor);
      if (anchor.dx < -80 ||
          anchor.dy < -40 ||
          anchor.dx > size.width + 80 ||
          anchor.dy > size.height + 40) {
        continue;
      }
      final screenArea = label.area * scale * scale;
      if (screenArea < minArea && !label.always) continue;

      final painter = _painterFor(label.text, focus);
      final rect = Rect.fromCenter(
        center: anchor,
        width: painter.width + 5,
        height: painter.height + 2,
      );
      // 边缘不画半个地名：完整文字必须落在卡片里
      if (rect.left < 2 ||
          rect.top < 2 ||
          rect.right > size.width - 2 ||
          rect.bottom > size.height - 2) {
        continue;
      }
      if (occupied.any((other) => other.overlaps(rect.deflate(1)))) continue;
      occupied.add(rect);
      painter.paint(
        canvas,
        Offset(anchor.dx - painter.width / 2, anchor.dy - painter.height / 2),
      );
    }
  }

  TextPainter _painterFor(String text, bool small) {
    final key = '$text|${small ? 1 : 0}';
    final cached = textCache[key];
    if (cached != null) return cached;
    final painter = TextPainter(
      textDirection: TextDirection.ltr,
      text: TextSpan(
        text: text,
        style: TextStyle(
          fontSize: small ? 10 : 11,
          height: 1.05,
          color: kLabelColor,
          fontWeight: small ? FontWeight.w500 : FontWeight.w600,
          shadows: const [Shadow(color: Colors.white, blurRadius: 2.5)],
        ),
      ),
    )..layout();
    if (textCache.length > 600) textCache.clear();
    textCache[key] = painter;
    return painter;
  }

  @override
  bool shouldRepaint(covariant _FootprintPainter oldDelegate) {
    return oldDelegate.controller.scale != controller.scale ||
        oldDelegate.controller.offset != controller.offset ||
        oldDelegate.allPath != allPath ||
        oldDelegate.litPath != litPath ||
        oldDelegate.partialPath != partialPath ||
        oldDelegate.showLabels != showLabels ||
        oldDelegate.cityLevel != cityLevel ||
        oldDelegate.focus != focus ||
        oldDelegate.mode != mode;
  }
}
