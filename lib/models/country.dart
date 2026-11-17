class Country {
  final String code;
  final String nameZh;
  final double longitude; // x
  final double latitude; // y
  final Map<String, dynamic>? geometry; // 可选，用于多边形

  Country({
    required this.code,
    required this.nameZh,
    required this.longitude,
    required this.latitude,
    this.geometry,
  });

  factory Country.fromJson(Map<String, dynamic> json) {
    final props = json['properties'];
    return Country(
      code: props['id'],
      nameZh: props['nameZh'],
      longitude: props['x'],
      latitude: props['y'],
      geometry: json['geometry'],
    );
  }
}
