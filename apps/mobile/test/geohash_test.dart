import 'package:flutter_test/flutter_test.dart';
import 'package:urbaneye_mobile/core/geo/geohash.dart';

void main() {
  test('codifica igual ao backend e ao PostGIS', () {
    expect(geohashEncode(57.64911, 10.40744, precision: 11), 'u4pruydqqvj');
    expect(geohashEncode(-23.5505, -46.6333), '6gyf4bf');
  });

  test('cobre o raio do mapa sem passar do limite do servidor', () {
    final cells = geohashCellsAround(-23.55, -46.63, 50000);
    expect(cells, contains('6gyf'));
    expect(cells.length, lessThanOrEqualTo(geohashMaxSubscriptions));
    expect(cells.every((cell) => cell.length >= 3 && cell.length <= 7), isTrue);
  });

  test('raio pequeno assina poucas células', () {
    final cells = geohashCellsAround(-23.55, -46.63, 5000);
    expect(cells, contains('6gyf'));
    expect(cells.length, lessThanOrEqualTo(4));
  });
}
