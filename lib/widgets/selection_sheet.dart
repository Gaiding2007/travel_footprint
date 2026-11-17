import 'package:flutter/material.dart';

import '../data/geo_data.dart';
import '../map/footprint_map.dart' show MapMode;
import '../state/footprint_store.dart';
import '../theme.dart';

/// 底部升起的"选择城市 / 国家和地区"面板
class SelectionSheet extends StatefulWidget {
  const SelectionSheet({
    super.key,
    required this.geo,
    required this.store,
    required this.mode,
  });

  final GeoData geo;
  final FootprintStore store;
  final MapMode mode;

  @override
  State<SelectionSheet> createState() => _SelectionSheetState();
}

class _SelectionSheetState extends State<SelectionSheet> {
  final Set<int> _expanded = <int>{};

  @override
  Widget build(BuildContext context) {
    final store = widget.store;
    final isChina = widget.mode == MapMode.china;
    final height = MediaQuery.of(context).size.height * 0.86;

    return Container(
      height: height,
      decoration: const BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      child: AnimatedBuilder(
        animation: store,
        builder: (context, _) {
          return Column(
            children: [
              const SizedBox(height: 8),
              Container(
                width: 38,
                height: 4,
                decoration: BoxDecoration(
                  color: AppColors.divider,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(18, 12, 12, 4),
                child: Row(
                  children: [
                    Text(
                      isChina ? '选择城市' : '选择国家和地区',
                      style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w700),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        isChina
                            ? '已选 ${store.litCityCount} 市 · ${store.litProvinceCount} 省'
                            : '已选 ${store.litCountryCount} 个',
                        style: const TextStyle(fontSize: 12, color: AppColors.textSecondary),
                      ),
                    ),
                    TextButton(
                      onPressed: store.litCityCount == 0 && store.litCountryCount == 0
                          ? null
                          : store.clearAll,
                      child: const Text('清空'),
                    ),
                  ],
                ),
              ),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 18),
                child: Row(
                  children: [
                    _ToggleChip(
                      label: '显示地名',
                      value: store.showLabels,
                      onChanged: store.setShowLabels,
                    ),
                    const SizedBox(width: 8),
                    _ToggleChip(
                      label: '仅看已选',
                      value: store.showSelectedOnly,
                      onChanged: store.setShowSelectedOnly,
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 6),
              const Divider(height: 1, color: AppColors.divider),
              Expanded(
                child: isChina ? _buildChinaList() : _buildWorldList(),
              ),
            ],
          );
        },
      ),
    );
  }

  Widget _buildChinaList() {
    final store = widget.store;
    final provinces = widget.geo.provinces;
    final visible = store.showSelectedOnly
        ? provinces.where((p) => store.provinceStatus(p.id) != ProvinceStatus.none).toList()
        : provinces;

    if (visible.isEmpty) {
      return const _EmptyHint(text: '还没有点亮的城市，回地图点一下试试');
    }

    return ListView.builder(
      padding: const EdgeInsets.only(bottom: 28),
      itemCount: visible.length,
      itemBuilder: (context, index) => _provinceTile(visible[index]),
    );
  }

  Widget _provinceTile(Region province) {
    final store = widget.store;
    final cities = widget.geo.citiesByProvince[province.id] ?? const <Region>[];
    final status = store.provinceStatus(province.id);
    final litCount = store.litCityCountInProvince(province.id);
    final expanded = _expanded.contains(province.id);

    return Column(
      children: [
        InkWell(
          onTap: () {
            if (cities.isEmpty) {
              store.toggleProvince(province.id);
              return;
            }
            setState(() {
              if (expanded) {
                _expanded.remove(province.id);
              } else {
                _expanded.add(province.id);
              }
            });
          },
          child: Padding(
            padding: const EdgeInsets.fromLTRB(10, 4, 12, 4),
            child: Row(
              children: [
                Checkbox(
                  value: status == ProvinceStatus.lit
                      ? true
                      : (status == ProvinceStatus.partial ? null : false),
                  tristate: true,
                  materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                  visualDensity: VisualDensity.compact,
                  onChanged: (_) => store.toggleProvince(province.id),
                ),
                Expanded(
                  child: Text(
                    province.name,
                    style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w500),
                  ),
                ),
                if (cities.isNotEmpty)
                  Text(
                    '$litCount/${cities.length}',
                    style: TextStyle(
                      fontSize: 12,
                      color: litCount == 0 ? AppColors.textSecondary : AppColors.primary,
                      fontWeight: litCount == 0 ? FontWeight.w400 : FontWeight.w600,
                    ),
                  ),
                if (cities.isNotEmpty)
                  Icon(
                    expanded ? Icons.expand_less : Icons.expand_more,
                    size: 20,
                    color: AppColors.textSecondary,
                  ),
              ],
            ),
          ),
        ),
        if (expanded)
          Padding(
            padding: const EdgeInsets.fromLTRB(46, 0, 14, 12),
            child: Wrap(
              spacing: 6,
              runSpacing: 6,
              children: [
                for (final city in cities) _cityChip(city),
              ],
            ),
          ),
      ],
    );
  }

  Widget _cityChip(Region city) {
    final store = widget.store;
    final lit = store.isCityLit(city.id);
    return FilterChip(
      label: Text(city.name, style: const TextStyle(fontSize: 12)),
      selected: lit,
      showCheckmark: false,
      onSelected: (value) => store.setCity(city.id, value),
      backgroundColor: const Color(0xFFF3F6FA),
      selectedColor: AppColors.lit,
      side: BorderSide(color: lit ? const Color(0xFF4A90C2) : AppColors.divider, width: 0.8),
      materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
      visualDensity: VisualDensity.compact,
      labelPadding: const EdgeInsets.symmetric(horizontal: 2),
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
    );
  }

  Widget _buildWorldList() {
    final store = widget.store;
    final all = [...widget.geo.countries]..sort((a, b) => a.name.compareTo(b.name));
    final visible = store.showSelectedOnly
        ? all.where((c) => store.isCountryLit(c.code)).toList()
        : all;

    if (visible.isEmpty) {
      return const _EmptyHint(text: '还没有点亮的国家，回地图点一下试试');
    }

    return ListView.builder(
      padding: const EdgeInsets.only(bottom: 28),
      itemCount: visible.length,
      itemBuilder: (context, index) {
        final country = visible[index];
        final lit = store.isCountryLit(country.code);
        return InkWell(
          onTap: () => store.toggleCountry(country.code),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(10, 2, 14, 2),
            child: Row(
              children: [
                Checkbox(
                  value: lit,
                  materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                  visualDensity: VisualDensity.compact,
                  onChanged: (_) => store.toggleCountry(country.code),
                ),
                Expanded(
                  child: Text(
                    country.name,
                    style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w500),
                  ),
                ),
                Text(
                  country.code,
                  style: const TextStyle(fontSize: 11, color: AppColors.textSecondary),
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}

class _ToggleChip extends StatelessWidget {
  const _ToggleChip({required this.label, required this.value, required this.onChanged});

  final String label;
  final bool value;
  final ValueChanged<bool> onChanged;

  @override
  Widget build(BuildContext context) {
    return FilterChip(
      label: Text(label, style: const TextStyle(fontSize: 12)),
      selected: value,
      showCheckmark: true,
      checkmarkColor: Colors.white,
      onSelected: onChanged,
      backgroundColor: const Color(0xFFF3F6FA),
      selectedColor: AppColors.primary,
      side: BorderSide(color: value ? AppColors.primary : AppColors.divider, width: 0.8),
      labelStyle: TextStyle(
        color: value ? Colors.white : AppColors.textPrimary,
        fontSize: 12,
      ),
      materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
      visualDensity: VisualDensity.compact,
    );
  }
}

class _EmptyHint extends StatelessWidget {
  const _EmptyHint({required this.text});

  final String text;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Text(
          text,
          textAlign: TextAlign.center,
          style: const TextStyle(fontSize: 13, color: AppColors.textSecondary),
        ),
      ),
    );
  }
}
