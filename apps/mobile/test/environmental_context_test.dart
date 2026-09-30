import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:urbaneye_mobile/features/weather/data/environmental_context_service.dart';

void main() {
  test('monta chuva e qualidade do ar para o cálculo de risco', () async {
    final client = MockClient((request) async {
      if (request.url.host == 'air-quality-api.open-meteo.com') {
        return http.Response(jsonEncode({'current': {'us_aqi': 132.4}}), 200);
      }
      return http.Response(jsonEncode({
        'current': {'temperature_2m': 29.5, 'precipitation': 1.2},
        'daily': {'precipitation_sum': [42.0]},
      }), 200);
    });

    final context = await OpenMeteoEnvironmentalContextProvider(client: client)
        .contextFor(-23.55, -46.63);

    expect(context['rainfallMm'], 42.0);
    expect(context['airQualityIndex'], 132);
    expect(context['temperatureC'], 29.5);
    expect(context['source'], 'open-meteo');
  });

  test('falha da API não impede o envio do relato', () async {
    final client = MockClient((_) async => throw Exception('sem rede'));
    final context = await OpenMeteoEnvironmentalContextProvider(client: client)
        .contextFor(-23.55, -46.63);
    expect(context, isEmpty);
  });
}
