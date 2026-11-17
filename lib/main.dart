import 'package:flutter/material.dart';

import 'app_info.dart';
import 'data/geo_data.dart';
import 'screens/home_screen.dart';
import 'state/footprint_store.dart';
import 'theme.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(const TravelFootprintApp());
}

class _Bootstrap {
  const _Bootstrap(this.geo, this.store);

  final GeoData geo;
  final FootprintStore store;
}

class TravelFootprintApp extends StatefulWidget {
  const TravelFootprintApp({super.key});

  @override
  State<TravelFootprintApp> createState() => _TravelFootprintAppState();
}

class _TravelFootprintAppState extends State<TravelFootprintApp> {
  late Future<_Bootstrap> _future;

  @override
  void initState() {
    super.initState();
    _future = _load();
  }

  Future<_Bootstrap> _load() async {
    final geo = await GeoData.load();
    final store = FootprintStore(geo);
    await store.load();
    return _Bootstrap(geo, store);
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: kAppName,
      debugShowCheckedModeBanner: false,
      theme: AppTheme.build(),
      home: FutureBuilder<_Bootstrap>(
        future: _future,
        builder: (context, snapshot) {
          if (snapshot.hasError) {
            return _ErrorScreen(
              error: '${snapshot.error}',
              onRetry: () => setState(() => _future = _load()),
            );
          }
          final data = snapshot.data;
          if (data == null) return const _LoadingScreen();
          return HomeScreen(geo: data.geo, store: data.store);
        },
      ),
    );
  }
}

class _LoadingScreen extends StatelessWidget {
  const _LoadingScreen();

  @override
  Widget build(BuildContext context) {
    return const Scaffold(
      backgroundColor: Colors.white,
      body: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              kAppName,
              style: TextStyle(fontSize: 24, fontWeight: FontWeight.w700, letterSpacing: 2),
            ),
            SizedBox(height: 18),
            SizedBox(
              width: 22,
              height: 22,
              child: CircularProgressIndicator(strokeWidth: 2.2),
            ),
            SizedBox(height: 14),
            Text(
              '正在加载地图数据…',
              style: TextStyle(fontSize: 12, color: AppColors.textSecondary),
            ),
          ],
        ),
      ),
    );
  }
}

class _ErrorScreen extends StatelessWidget {
  const _ErrorScreen({required this.error, required this.onRetry});

  final String error;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Text('地图数据加载失败', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600)),
            const SizedBox(height: 10),
            Text(
              error,
              textAlign: TextAlign.center,
              style: const TextStyle(fontSize: 12, color: AppColors.textSecondary),
            ),
            const SizedBox(height: 18),
            FilledButton(onPressed: onRetry, child: const Text('重试')),
          ],
        ),
      ),
    );
  }
}
