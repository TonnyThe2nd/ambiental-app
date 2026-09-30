import 'package:flutter_test/flutter_test.dart';
import 'package:urbaneye_mobile/features/routing/domain/route_option.dart';

void main() {
  test('simplifica a rota mantendo início e fim', () {
    final points = [for (var i = 0; i < 1000; i++) [i.toDouble(), 0.0]];
    final simplified = simplifyRoute(points, 500);
    expect(simplified, hasLength(500));
    expect(simplified.first, points.first);
    expect(simplified.last, points.last);
  });

  test('aplica a avaliação de risco do servidor', () {
    const route = RouteOption(id: '0', points: [[0, 0], [1, 1]], distanceMeters: 4200, durationSeconds: 720);
    final assessed = route.withAssessment({
      'riskScore': 6,
      'blocked': true,
      'recommended': false,
      'incidents': [
        {'id': 'i1', 'category': 'alagamento', 'severity': 'critico', 'distanceMeters': 12.5,
         'latitude': -23.5, 'longitude': -46.6, 'impactRadiusM': 600},
      ],
    });
    expect(assessed.blocked, isTrue);
    expect(assessed.incidents.single.obstructive, isTrue);
    expect(assessed.summary, '4.2 km · 12 min · 1 ocorrência no caminho');
  });
}
