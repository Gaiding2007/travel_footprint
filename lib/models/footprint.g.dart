// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'footprint.dart';

// **************************************************************************
// TypeAdapterGenerator
// **************************************************************************

class FootprintAdapter extends TypeAdapter<Footprint> {
  @override
  final int typeId = 0;

  @override
  Footprint read(BinaryReader reader) {
    final numOfFields = reader.readByte();
    final fields = <int, dynamic>{
      for (int i = 0; i < numOfFields; i++) reader.readByte(): reader.read(),
    };
    return Footprint(
      selectedCityIds: (fields[0] as List).cast<int>(),
      selectedCountryCodes: (fields[1] as List).cast<String>(),
    );
  }

  @override
  void write(BinaryWriter writer, Footprint obj) {
    writer
      ..writeByte(2)
      ..writeByte(0)
      ..write(obj.selectedCityIds)
      ..writeByte(1)
      ..write(obj.selectedCountryCodes);
  }

  @override
  int get hashCode => typeId.hashCode;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is FootprintAdapter &&
          runtimeType == other.runtimeType &&
          typeId == other.typeId;
}
