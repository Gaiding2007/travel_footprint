import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../providers/footprint_provider.dart';
import '../services/data_loader.dart';
import '../models/city.dart';

class CitiesScreen extends StatefulWidget {
  @override
  _CitiesScreenState createState() => _CitiesScreenState();
}

class _CitiesScreenState extends State<CitiesScreen> {
  late Future<List<City>> _citiesFuture;

  @override
  void initState() {
    super.initState();
    _citiesFuture = DataLoader.loadCities();
  }

  @override
  Widget build(BuildContext context) {
    final footprintProvider = Provider.of<FootprintProvider>(context);
    final selectedIds = footprintProvider.footprint.selectedCityIds;

    return Scaffold(
      appBar: AppBar(title: Text('城市足迹')),
      body: FutureBuilder<List<City>>(
        future: _citiesFuture,
        builder: (context, snapshot) {
          if (!snapshot.hasData)
            return Center(child: CircularProgressIndicator());
          final cities = snapshot.data!;
          return ListView.builder(
            itemCount: cities.length,
            itemBuilder: (ctx, index) {
              final city = cities[index];
              final isSelected = selectedIds.contains(city.id);
              return CheckboxListTile(
                title: Text(city.name),
                subtitle: Text(city.ename),
                value: isSelected,
                onChanged: (selected) {
                  if (selected == true) {
                    footprintProvider.addCity(city.id);
                  } else {
                    footprintProvider.removeCity(city.id);
                  }
                },
              );
            },
          );
        },
      ),
    );
  }
}
