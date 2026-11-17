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
const Color kLabelColor = Color(0xFF3D3D3D);

/// 面积小但重要的行政区，低倍率下也要显示名称
const Set<String> kAlwaysLabeled = {'北京', '上海', '天津', '重庆', '香港', '澳门'};

/// 中国地图的默认取景范围（略去南海深处，避免大片空白海面）
Rect chinaViewBounds() =>
    Rect.fromPoints(projectLonLat(72.5, 54.8), projectLonLat(136.0, 15.5));

/// 达到该倍率即进入"市级"交互与标注层级
const double kCityLevelFactor = 2.2;

class FootprintMap extends StatefulWidget {
  const FootprintMap({
    super.key,
    required this.geo,
    required this.store,
    required this.controller,
    required this.mode,
  });

  final GeoData geo;
  final FootprintStore store;
  final MapTransformController controller;
  final MapMode mode;

  @override
  State<FootprintMap> createState() => _FootprintMapState();
}

class _FootprintMapState extends State<FootprintMap> {
  final Map<String, TextPainter> _textCache = <String, TextPainter>{};

  Path _allPath = Path();
  Path _litPath = Path();
  Path _outlinePath = Path();
  List<_Label> _provinceLabels = const <_Label>[];
  List<_Label> _cityLabels = const <_Label>[];

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
    if (oldWidget.mode != widget.mode || oldWidget.store != widget.store) {
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
    final provinceLabels = <_Label>[];

    if (widget.mode == MapMode.china) {
      for (final city in widget.geo.cities) {
        all.addPath(city.shape.path, Offset.zero);
        if (widget.store.isCityLit(city.id)) lit.addPath(city.shape.path, Offset.zero);
      }
      for (final province in widget.geo.provinces) {
        outline.addPath(province.shape.path, Offset.zero);
        provinceLabels.add(
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
        if (widget.store.isCountryLit(country.code)) lit.addPath(country.shape.path, Offset.zero);
        provinceLabels.add(
          _Label(
            text: country.name,
            anchor: country.shape.anchor,
            area: country.shape.extent,
            always: false,
          ),
        );
      }
    }

    provinceLabels.sort((a, b) {
      if (a.always != b.always) return a.always ? -1 : 1;
      return b.area.compareTo(a.area);
    });

    _allPath = all;
    _litPath = lit;
    _outlinePath = outline;
    _provinceLabels = provinceLabels;
    if (widget.mode == MapMode.china && _cityLabels.isEmpty) {
      _cityLabels = [
        for (final city in widget.geo.cities)
          _Label(text: city.name, anchor: city.shape.anchor, area: city.shape.extent, always: false),
      ]..sort((a, b) => b.area.compareTo(a.area));
    }
  }

  Rect get _contentBounds =>
      widget.mode == MapMode.china ? chinaViewBounds() : widget.geo.worldBounds;

  void _handleTap(Offset localPosition) {
    final controller = widget.controller;
    if (!controller.isReady) return;
    final point = controller.screenToMap(localPosition);
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
    if (widget.mode != MapMode.china) return;
    final point = widget.controller.screenToMap(localPosition);
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
        final labels = widget.mode == MapMode.world
            ? _provinceLabels
            : (cityLevel ? _cityLabels : _provinceLabels);

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
                    labels: labels,
                    mode: widget.mode,
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
    required this.outlinePath,
    required this.labels,
    required this.mode,
    required this.showLabels,
    required this.cityLevel,
    required this.textCache,
  });

  final MapTransformController controller;
  final Path allPath;
  final Path litPath;
  final Path outlinePath;
  final List<_Label> labels;
  final MapMode mode;
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
    canvas.drawPath(litPath, Paint()..color = kLitFill);

    // 市级边界在任何倍率下都画，低倍率时更淡，保证像一张完整的地图
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

    canvas.restore();

    if (showLabels) _paintLabels(canvas, size);
  }

  void _paintLabels(Canvas canvas, Size size) {
    final scale = controller.scale;
    final minArea = mode == MapMode.china ? (cityLevel ? 45.0 : 110.0) : 240.0;
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

      final painter = _painterFor(label.text, cityLevel);
      final rect = Rect.fromCenter(
        center: anchor,
        width: painter.width + 5,
        height: painter.height + 2,
      );
      if (occupied.any((other) => other.overlaps(rect.deflate(1)))) continue;
      occupied.add(rect);
      painter.paint(
        canvas,
        Offset(anchor.dx - painter.width / 2, anchor.dy - painter.height / 2),
      );
    }
  }

  TextPainter _painterFor(String text, bool big) {
    final key = '$text|${big ? 1 : 0}';
    final cached = textCache[key];
    if (cached != null) return cached;
    final painter = TextPainter(
      textDirection: TextDirection.ltr,
      text: TextSpan(
        text: text,
        style: TextStyle(
          fontSize: big ? 10.5 : 11,
          height: 1.05,
          color: kLabelColor,
          fontWeight: big ? FontWeight.w500 : FontWeight.w600,
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
        oldDelegate.showLabels != showLabels ||
        oldDelegate.cityLevel != cityLevel ||
        oldDelegate.mode != mode;
  }
}
