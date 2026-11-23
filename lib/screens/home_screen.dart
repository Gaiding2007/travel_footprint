import 'dart:typed_data';

import 'package:flutter/material.dart';

import '../app_info.dart';
import '../data/geo_data.dart';
import '../map/footprint_map.dart';
import '../map/map_transform_controller.dart';
import '../services/export_service.dart';
import '../state/footprint_store.dart';
import '../theme.dart';
import '../widgets/export_preview_dialog.dart';
import '../widgets/selection_sheet.dart';

/// 主界面：地图 + 计数 + 选择面板 + 存图
class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key, required this.geo, required this.store});

  final GeoData geo;
  final FootprintStore store;

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  final GlobalKey _shotKey = GlobalKey();
  final MapTransformController _controller = MapTransformController();

  MapMode _mode = MapMode.china;

  /// 非空时处于"国家特写"，只显示这个国家的内部一级行政区
  Country? _focusCountry;

  /// 世界地图上点了一下、等待第二下进入的国家（只高亮，不点亮）
  Country? _selectedCountry;
  bool _exporting = false;

  @override
  void initState() {
    super.initState();
    widget.store.addListener(_onStoreChanged);
  }

  @override
  void dispose() {
    widget.store.removeListener(_onStoreChanged);
    _controller.dispose();
    super.dispose();
  }

  void _onStoreChanged() {
    if (mounted) setState(() {});
  }

  String get _counterText {
    final store = widget.store;
    final focus = _focusCountry;
    if (focus != null) {
      if (!focus.hasRegions) {
        return store.isCountryLit(focus.code) ? '已点亮这个国家和地区' : '还没点亮';
      }
      return '已点亮 ${store.litRegionCount(focus.code)} 个省/州';
    }
    if (_mode == MapMode.china) {
      return '已点亮 ${store.litProvinceCount} 省 ${store.litCityCount} 市';
    }
    return '已点亮 ${store.litCountryCount} 个国家和地区';
  }

  void _switchMode(MapMode mode) {
    if (_mode == mode && _focusCountry == null) return;
    setState(() {
      _mode = mode;
      _focusCountry = null;
      _selectedCountry = null;
    });
  }

  /// 世界地图上第一次点到某个国家：只高亮 + 提示，不点亮
  void _selectCountry(Country country) {
    setState(() => _selectedCountry = country);
    _toast('再点一下进入「${country.name}」，看它的省/州');
  }

  void _clearSelection() {
    if (_selectedCountry == null) return;
    setState(() => _selectedCountry = null);
  }

  void _enterCountry(Country country) {
    setState(() => _selectedCountry = null);
    // 中国有专门的"国内"模式（省 + 市两级，数据更细），不重复做国家特写
    if (country.code == 'CHN') {
      setState(() {
        _mode = MapMode.china;
        _focusCountry = null;
      });
      _toast('中国已切到「国内」，可以看到省市两级');
      return;
    }
    if (!country.hasRegions) {
      // 南极洲这类没有下级省州的地方：仍然进特写，界面里给一个"整块"选项
      setState(() => _focusCountry = country);
      return;
    }
    setState(() => _focusCountry = country);
    _toast('点一下省/州就能点亮，点左上角返回');
  }

  void _leaveCountry() {
    setState(() {
      _focusCountry = null;
      _selectedCountry = null;
    });
  }

  void _zoomBy(double factor) {
    final size = _controller.viewport;
    if (size.isEmpty) return;
    _controller.zoomBy(factor, Offset(size.width / 2, size.height / 2));
  }

  /// 国内点到城市：立刻告诉用户点亮/取消了哪个市（地图上不再画地名）
  void _onCityTap(Region city) {
    final lit = widget.store.isCityLit(city.id);
    _toast(lit ? '已点亮「${city.name}」' : '已取消「${city.name}」');
  }

  /// 国家特写点到省/州：同样给个名字提示
  void _onRegionTap(SubRegion region) {
    final focus = _focusCountry;
    if (focus == null) return;
    final lit = widget.store.isRegionLit(focus.code, region.index);
    _toast(lit ? '已点亮「${displayRegionName(region)}」' : '已取消「${displayRegionName(region)}」');
  }

  void _toast(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
      ..clearSnackBars()
      ..showSnackBar(
        SnackBar(
          content: Text(message),
          behavior: SnackBarBehavior.floating,
          duration: const Duration(seconds: 2),
        ),
      );
  }

  Future<void> _openSelection() async {
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => SelectionSheet(
        geo: widget.geo,
        store: widget.store,
        mode: _mode,
        focusCountry: _focusCountry,
        onEnterCountry: _enterCountry,
      ),
    );
  }

  Future<void> _export({required bool share}) async {
    if (_exporting) return;
    setState(() => _exporting = true);
    Uint8List? png;
    try {
      png = await ExportService.capturePng(_shotKey);
    } catch (error) {
      if (mounted) _toast('生成图片失败：$error');
    } finally {
      if (mounted) setState(() => _exporting = false);
    }
    if (!mounted) return;
    if (png == null) {
      _toast('没有可以保存的画面');
      return;
    }

    final choice = await showDialog<String>(
      context: context,
      builder: (_) => ExportPreviewDialog(png: png!, preferShare: share),
    );
    if (!mounted || choice == null || choice == 'cancel') return;

    setState(() => _exporting = true);
    try {
      final uri = await ExportService.saveBytes(png);
      if (!mounted) return;
      if (uri == null) {
        _toast('保存失败：系统没有接受这张图片');
        return;
      }
      _toast('已保存到相册');
      if (choice == 'share') await ExportService.share(uri);
    } catch (error) {
      if (!mounted) return;
      _toast('保存失败：$error');
    } finally {
      if (mounted) setState(() => _exporting = false);
    }
  }

  Future<void> _confirmClear() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('清空全部足迹？'),
        content: const Text('所有已点亮的省市和国家都会取消，无法恢复。'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('取消')),
          FilledButton(onPressed: () => Navigator.pop(context, true), child: const Text('清空')),
        ],
      ),
    );
    if (confirmed ?? false) {
      widget.store.clearAll();
      _toast('已清空');
    }
  }

  void _showAbout() {
    showDialog<void>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text(kAppName),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('版本 $kAppVersion'),
            const SizedBox(height: 10),
            const Text(
              '国内：点省份就点亮这个省（不会连带点亮所有城市），放大后可以点单个城市。\n'
              '全球：点一下国家先高亮，再点一下进去看它的省/州；没有省州数据的国家一点即切换。',
              style: TextStyle(fontSize: 13, height: 1.5),
            ),
            const SizedBox(height: 10),
            Text(
              '数据包含 ${widget.geo.provinces.length} 个省级行政区、'
              '${widget.geo.cities.length} 个地级行政区、'
              '${widget.geo.countries.length} 个国家和地区。',
              style: const TextStyle(fontSize: 13, height: 1.5),
            ),
          ],
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text('知道了')),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: LayoutBuilder(
          builder: (context, constraints) {
            final maxMapHeight = constraints.maxWidth * 1.16;
            final mapHeight =
                (constraints.maxHeight * 0.58).clamp(240.0, maxMapHeight).toDouble();
            return Column(
              children: [
                _buildHeader(),
                SizedBox(
                  height: mapHeight,
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(12, 0, 12, 0),
                    child: _buildMapCard(),
                  ),
                ),
                const SizedBox(height: 10),
                Expanded(
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(12, 0, 12, 0),
                    child: _buildSummary(),
                  ),
                ),
                _buildBottomBar(),
              ],
            );
          },
        ),
      ),
    );
  }

  /// 地图下方的足迹概览卡片。
  ///
  /// 国内 / 全球 / 国家特写三种情况各显示自己的统计口径，
  /// 不会在"全球"页面里还摆着国内的地级市进度（需求 7）。
  Widget _buildSummary() {
    final store = widget.store;
    final focus = _focusCountry;
    final isChina = _mode == MapMode.china && focus == null;

    final litProvinces = widget.geo.provinces
        .where((province) => store.provinceVisited(province.id))
        .toList(growable: false);
    final litCountries = widget.geo.countries
        .where((country) => store.isCountryLit(country.code))
        .toList(growable: false);
    final litRegions = focus == null
        ? const <SubRegion>[]
        : focus.regions
            .where((region) => store.isRegionLit(focus.code, region.index))
            .toList(growable: false);

    final List<(String, String)> stats;
    if (focus != null) {
      stats = [
        ('省/州', '${store.litRegionCount(focus.code)}'),
        ('国家地区', '${store.litCountryCount}'),
      ];
    } else if (isChina) {
      stats = [
        ('省级', '${store.litProvinceCount}'),
        ('城市', '${store.litCityCount}'),
        ('国家地区', '${store.litCountryCount}'),
      ];
    } else {
      stats = [
        ('国家地区', '${store.litCountryCount}'),
        ('点亮的省/州', '${store.litRegionTotal}'),
      ];
    }

    final List<String> chips;
    final String chipTitle;
    if (focus != null) {
      chips = litRegions.map((region) => region.name).toList(growable: false);
      chipTitle = '已点亮的省/州';
    } else if (isChina) {
      chips = litProvinces.map((province) => province.name).toList(growable: false);
      chipTitle = '已点亮的省级行政区';
    } else {
      chips = litCountries.map((country) => country.name).toList(growable: false);
      chipTitle = '已点亮的国家和地区';
    }

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
      ),
      child: SingleChildScrollView(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                for (var index = 0; index < stats.length; index++) ...[
                  if (index > 0) _buildStatDivider(),
                  _buildStat(stats[index].$1, stats[index].$2),
                ],
              ],
            ),
            const SizedBox(height: 14),
            if (focus != null && !focus.hasRegions)
              _buildWholeOption(focus)
            else if (focus != null)
              _buildProgress('${focus.name}的省/州进度', store.litRegionCount(focus.code), focus.regions.length)
            else if (isChina) ...[
              _buildProgress('省级行政区的进度', store.litProvinceCount, widget.geo.provinces.length),
              const SizedBox(height: 10),
              _buildProgress('地级市的进度', store.litCityCount, widget.geo.cities.length),
            ] else
              _buildProgress('国家和地区的进度', store.litCountryCount, widget.geo.countries.length),
            if (focus == null) ...[
              const SizedBox(height: 12),
              _buildDetailToggle(),
            ],
            const SizedBox(height: 14),
            if (chips.isEmpty)
              Text(
                focus != null
                    ? (focus.hasRegions
                        ? '点一下${focus.name}地图上的省/州就能点亮，点左上角可以返回世界地图。'
                        : '${focus.name}没有更细的省/州，点上面的整块选项就能点亮它。')
                    : isChina
                        ? '点一下地图上的哪个城市，就点亮哪个城市；整省可以用「选择城市」里的省份勾选框批量选。'
                        : '先点一下地图上的国家高亮它，再点一下进入它的省/州。',
                style: const TextStyle(fontSize: 12, height: 1.5, color: AppColors.textSecondary),
              )
            else ...[
              Text(
                chipTitle,
                style: const TextStyle(fontSize: 11, color: AppColors.textSecondary),
              ),
              const SizedBox(height: 8),
              Wrap(
                spacing: 6,
                runSpacing: 6,
                children: [
                  for (final name in chips.take(60))
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
                      decoration: BoxDecoration(
                        color: const Color(0xFFEDF4FF),
                        borderRadius: BorderRadius.circular(6),
                      ),
                      child: Text(
                        name,
                        style: const TextStyle(fontSize: 11.5, color: Color(0xFF2F6BD8)),
                      ),
                    ),
                ],
              ),
            ],
          ],
        ),
      ),
    );
  }

  /// 粗略 / 详细 显示开关（需求 9）
  Widget _buildDetailToggle() {
    final detailed = widget.store.detailDisplay;
    return Row(
      children: [
        const Text('地图显示', style: TextStyle(fontSize: 11, color: AppColors.textSecondary)),
        const SizedBox(width: 8),
        Expanded(
          child: Container(
            padding: const EdgeInsets.all(2),
            decoration: BoxDecoration(
              color: const Color(0xFFEFF3F9),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Row(
              children: [
                _buildDetailOption('粗略', !detailed, () => widget.store.setDetailDisplay(false)),
                _buildDetailOption('详细', detailed, () => widget.store.setDetailDisplay(true)),
              ],
            ),
          ),
        ),
      ],
    );
  }

  /// 没有下级省/州的地方（例如南极洲）：给一个"整块"选项
  Widget _buildWholeOption(Country country) {
    final lit = widget.store.isCountryLit(country.code);
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: () => widget.store.toggleCountry(country.code),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 11),
        decoration: BoxDecoration(
          color: lit ? const Color(0xFFEDF4FF) : const Color(0xFFF4F6FA),
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: lit ? const Color(0xFFB9D4FF) : const Color(0xFFE1E6EF)),
        ),
        child: Row(
          children: [
            Icon(
              lit ? Icons.check_box_rounded : Icons.check_box_outline_blank_rounded,
              size: 20,
              color: lit ? const Color(0xFF2F6BD8) : AppColors.textSecondary,
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    '整块${country.name}',
                    style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: AppColors.textPrimary),
                  ),
                  const SizedBox(height: 2),
                  const Text(
                    '这里没有更细的省/州，只能整块勾选',
                    style: TextStyle(fontSize: 11, color: AppColors.textSecondary),
                  ),
                ],
              ),
            ),
            Text(
              lit ? '已点亮' : '未点亮',
              style: TextStyle(
                fontSize: 11.5,
                fontWeight: FontWeight.w600,
                color: lit ? const Color(0xFF2F6BD8) : AppColors.textSecondary,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildDetailOption(String label, bool selected, VoidCallback onTap) {
    return Expanded(
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 140),
          height: 30,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: selected ? Colors.white : Colors.transparent,
            borderRadius: BorderRadius.circular(6),
            boxShadow: selected
                ? const [BoxShadow(color: Color(0x12000000), blurRadius: 2, offset: Offset(0, 1))]
                : null,
          ),
          child: Text(
            label,
            textAlign: TextAlign.center,
            style: TextStyle(
              fontSize: 11.5,
              fontWeight: selected ? FontWeight.w600 : FontWeight.w400,
              color: selected ? AppColors.textPrimary : AppColors.textSecondary,
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildStat(String label, String value) {
    return Expanded(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            value,
            style: const TextStyle(
              fontSize: 21,
              fontWeight: FontWeight.w700,
              color: AppColors.textPrimary,
            ),
          ),
          const SizedBox(height: 2),
          Text(label, style: const TextStyle(fontSize: 11, color: AppColors.textSecondary)),
        ],
      ),
    );
  }

  Widget _buildStatDivider() {
    return Container(width: 1, height: 30, color: AppColors.divider);
  }

  Widget _buildProgress(String label, int current, int total) {
    final ratio = total == 0 ? 0.0 : (current / total).clamp(0.0, 1.0);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Text(label, style: const TextStyle(fontSize: 11, color: AppColors.textSecondary)),
            const Spacer(),
            Text(
              '$current / $total',
              style: const TextStyle(fontSize: 11, color: AppColors.textSecondary),
            ),
          ],
        ),
        const SizedBox(height: 5),
        ClipRRect(
          borderRadius: BorderRadius.circular(3),
          child: LinearProgressIndicator(
            value: ratio,
            minHeight: 5,
            backgroundColor: const Color(0xFFEDF1F6),
            valueColor: const AlwaysStoppedAnimation<Color>(AppColors.primary),
          ),
        ),
      ],
    );
  }

  Widget _buildHeader() {
    final focus = _focusCountry;
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 10, 6, 8),
      child: Row(
        children: [
          if (focus != null) ...[
            GestureDetector(
              onTap: _leaveCountry,
              child: const Padding(
                padding: EdgeInsets.only(right: 6, top: 2, bottom: 2),
                child: Icon(Icons.arrow_back_ios_new_rounded, size: 18),
              ),
            ),
          ],
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                focus?.name ?? kAppName,
                style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w700, letterSpacing: 0.5),
              ),
              const SizedBox(height: 2),
              Text(
                focus != null
                    ? '点一下省/州就能点亮'
                    : _mode == MapMode.china
                        ? '记录走过的地方'
                        : '记录去过的国家',
                style: const TextStyle(fontSize: 11, color: AppColors.textSecondary),
              ),
            ],
          ),
          const Spacer(),
          if (focus == null) _buildModeTabs(),
          PopupMenuButton<String>(
            icon: const Icon(Icons.more_horiz, size: 22),
            onSelected: (value) {
              if (value == 'clear') _confirmClear();
              if (value == 'about') _showAbout();
            },
            itemBuilder: (context) => const [
              PopupMenuItem(value: 'clear', child: Text('清空全部')),
              PopupMenuItem(value: 'about', child: Text('关于')),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildModeTabs() {
    return Container(
      padding: const EdgeInsets.all(3),
      decoration: BoxDecoration(
        color: const Color(0xFFE7EDF5),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          _buildTab('国内', MapMode.china),
          _buildTab('全球', MapMode.world),
        ],
      ),
    );
  }

  Widget _buildTab(String label, MapMode mode) {
    final selected = _mode == mode;
    return GestureDetector(
      onTap: () => _switchMode(mode),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 160),
        padding: const EdgeInsets.symmetric(horizontal: 13, vertical: 6),
        decoration: BoxDecoration(
          color: selected ? Colors.white : Colors.transparent,
          borderRadius: BorderRadius.circular(8),
          boxShadow: selected
              ? const [BoxShadow(color: Color(0x14000000), blurRadius: 3, offset: Offset(0, 1))]
              : null,
        ),
        child: Text(
          label,
          style: TextStyle(
            fontSize: 12.5,
            fontWeight: FontWeight.w600,
            color: selected ? AppColors.textPrimary : AppColors.textSecondary,
          ),
        ),
      ),
    );
  }

  Widget _buildMapCard() {
    return ClipRRect(
      borderRadius: BorderRadius.circular(16),
      child: Container(
        color: Colors.white,
        child: Stack(
          children: [
            Positioned.fill(
              child: RepaintBoundary(
                key: _shotKey,
                child: ColoredBox(
                  color: Colors.white,
                  child: Stack(
                    children: [
                      Positioned.fill(
                        child: FootprintMap(
                          geo: widget.geo,
                          store: widget.store,
                          controller: _controller,
                          mode: _mode,
                          focusCountry: _focusCountry,
                          selectedCountryCode: _selectedCountry?.code,
                          onCountryTap: _selectCountry,
                          onEnterCountry: _enterCountry,
                          onCountryLongPress: _enterCountry,
                          onBackgroundTap: _clearSelection,
                          onCityTap: _onCityTap,
                          onRegionTap: _onRegionTap,
                        ),
                      ),
                      Positioned(left: 12, top: 12, child: _buildCounter()),
                      if (_selectedCountry != null)
                        Positioned(right: 10, top: 10, child: _buildSelectionHint()),
                      const Positioned(
                        left: 12,
                        bottom: 10,
                        child: Text(
                          kWatermark,
                          style: TextStyle(fontSize: 9.5, color: Color(0xFF9AA7B6)),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
            Positioned(right: 10, bottom: 10, child: _buildZoomBar()),
            if (_exporting)
              const Positioned.fill(
                child: ColoredBox(
                  color: Color(0x22FFFFFF),
                  child: Center(child: CircularProgressIndicator(strokeWidth: 2.4)),
                ),
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildCounter() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: const Color(0xF2FFFFFF),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: AppColors.divider),
        boxShadow: const [BoxShadow(color: Color(0x0F000000), blurRadius: 4, offset: Offset(0, 1))],
      ),
      child: Text(
        _counterText,
        style: const TextStyle(fontSize: 12.5, fontWeight: FontWeight.w600),
      ),
    );
  }

  /// 选中国家后的小提示条：再点一下进去
  Widget _buildSelectionHint() {
    final country = _selectedCountry!;
    return Container(
      constraints: const BoxConstraints(maxWidth: 190),
      padding: const EdgeInsets.fromLTRB(10, 6, 6, 6),
      decoration: BoxDecoration(
        color: const Color(0xF2FFFFFF),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: const Color(0xFF2E6BE6)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Flexible(
            child: Text(
              '再点一下进入「${country.name}」',
              style: const TextStyle(fontSize: 11, color: Color(0xFF2E6BE6)),
              overflow: TextOverflow.ellipsis,
            ),
          ),
          GestureDetector(
            onTap: _clearSelection,
            child: const Padding(
              padding: EdgeInsets.only(left: 4),
              child: Icon(Icons.close, size: 14, color: AppColors.textSecondary),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildZoomBar() {
    return Column(
      children: [
        _zoomButton(Icons.add, () => _zoomBy(1.6)),
        const SizedBox(height: 6),
        _zoomButton(Icons.remove, () => _zoomBy(1 / 1.6)),
        const SizedBox(height: 6),
        _zoomButton(Icons.center_focus_strong, _controller.reset),
      ],
    );
  }

  Widget _zoomButton(IconData icon, VoidCallback onTap) {
    return Material(
      color: const Color(0xF2FFFFFF),
      borderRadius: BorderRadius.circular(9),
      elevation: 1,
      child: InkWell(
        borderRadius: BorderRadius.circular(9),
        onTap: onTap,
        child: SizedBox(
          width: 34,
          height: 34,
          child: Icon(icon, size: 18, color: AppColors.textPrimary),
        ),
      ),
    );
  }

  Widget _buildBottomBar() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 2, 12, 10),
      child: Row(
        children: [
          Expanded(
            child: SizedBox(
              height: 48,
              child: FilledButton.icon(
                onPressed: _openSelection,
                icon: const Icon(Icons.checklist_rounded, size: 19),
                label: Text(
                  _focusCountry != null
                      ? '选择省/州'
                      : _mode == MapMode.china
                          ? '选择城市'
                          : '选择国家',
                ),
                style: FilledButton.styleFrom(
                  backgroundColor: AppColors.primary,
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                  textStyle: const TextStyle(fontSize: 14.5, fontWeight: FontWeight.w600),
                ),
              ),
            ),
          ),
          const SizedBox(width: 8),
          _sideButton(Icons.download_rounded, '保存', () => _export(share: false)),
          const SizedBox(width: 8),
          _sideButton(Icons.ios_share_rounded, '分享', () => _export(share: true)),
        ],
      ),
    );
  }

  Widget _sideButton(IconData icon, String label, VoidCallback onTap) {
    return SizedBox(
      height: 48,
      child: OutlinedButton(
        onPressed: _exporting ? null : onTap,
        style: OutlinedButton.styleFrom(
          padding: const EdgeInsets.symmetric(horizontal: 10),
          side: const BorderSide(color: AppColors.divider),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          backgroundColor: Colors.white,
          foregroundColor: AppColors.textPrimary,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 17),
            const SizedBox(height: 1),
            Text(label, style: const TextStyle(fontSize: 10)),
          ],
        ),
      ),
    );
  }
}
