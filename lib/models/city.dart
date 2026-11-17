class City {
  final int id;
  final int parentId;
  final int level; // 0: 省/直辖市, 1: 地级市
  final String name;
  final String ename;

  City({
    required this.id,
    required this.parentId,
    required this.level,
    required this.name,
    required this.ename,
  });

  factory City.fromJson(Map<String, dynamic> json) {
    return City(
      id: json['id'],
      parentId: json['p'],
      level: json['d'],
      name: json['n'],
      ename: json['e'],
    );
  }
}
