import 'dart:convert';

import 'package:http/http.dart' as http;

/// Metadados ambientais enviados junto com o relato.
///
/// O backend usa ``rainfallMm`` (alagamentos) e ``airQualityIndex`` (poluição,
/// queimadas e incêndios) no cálculo de risco. Antes o app não enviava esses
/// campos e esses fatores do modelo de risco nunca eram aplicados.
abstract class EnvironmentalContextProvider {
  Future<Map<String, Object>> contextFor(double latitude, double longitude);
}

class OpenMeteoEnvironmentalContextProvider implements EnvironmentalContextProvider {
  OpenMeteoEnvironmentalContextProvider({http.Client? client})
    : _client = client ?? http.Client();

  final http.Client _client;
  static const _timeout = Duration(seconds: 8);

  /// Melhor esforço: qualquer falha resulta em contexto parcial ou vazio, sem
  /// impedir a sincronização do relato.
  @override
  Future<Map<String, Object>> contextFor(double latitude, double longitude) async {
    final context = <String, Object>{};
    final coordinates = {
      'latitude': latitude.toStringAsFixed(4),
      'longitude': longitude.toStringAsFixed(4),
    };
    try {
      final weather = await _client
          .get(Uri.https('api.open-meteo.com', '/v1/forecast', {
            ...coordinates,
            'current': 'temperature_2m,precipitation',
            'daily': 'precipitation_sum',
            'forecast_days': '1',
            'timezone': 'auto',
          }))
          .timeout(_timeout);
      if (weather.statusCode == 200) {
        final json = jsonDecode(weather.body) as Map<String, dynamic>;
        final current = json['current'] as Map<String, dynamic>?;
        final daily = json['daily'] as Map<String, dynamic>?;
        final rain = (daily?['precipitation_sum'] as List<dynamic>?)?.firstOrNull;
        if (rain is num) context['rainfallMm'] = rain.toDouble();
        final temperature = current?['temperature_2m'];
        if (temperature is num) context['temperatureC'] = temperature.toDouble();
      }
    } catch (_) {
      // Sem rede ou API fora do ar: segue sem dados de chuva.
    }
    try {
      final air = await _client
          .get(Uri.https('air-quality-api.open-meteo.com', '/v1/air-quality', {
            ...coordinates,
            'current': 'us_aqi',
          }))
          .timeout(_timeout);
      if (air.statusCode == 200) {
        final json = jsonDecode(air.body) as Map<String, dynamic>;
        final aqi = (json['current'] as Map<String, dynamic>?)?['us_aqi'];
        if (aqi is num) context['airQualityIndex'] = aqi.round();
      }
    } catch (_) {
      // Sem dados de qualidade do ar.
    }
    if (context.isNotEmpty) context['source'] = 'open-meteo';
    return context;
  }
}
