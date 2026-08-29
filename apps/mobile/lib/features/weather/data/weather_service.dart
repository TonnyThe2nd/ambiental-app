import 'dart:convert';

import 'package:http/http.dart' as http;

class WeatherService {
  WeatherService({http.Client? client}) : _client = client ?? http.Client();

  final http.Client _client;

  Future<WeatherData> getWeather(double latitude, double longitude) async {
    final uri = Uri.https('api.open-meteo.com', '/v1/forecast', {
      'latitude': latitude.toString(),
      'longitude': longitude.toString(),
      'current': [
        'temperature_2m',
        'relative_humidity_2m',
        'apparent_temperature',
        'weather_code',
        'wind_speed_10m',
        'wind_direction_10m',
        'wind_gusts_10m',
        'surface_pressure',
        'precipitation',
        'is_day',
      ].join(','),
      'daily': [
        'weather_code',
        'temperature_2m_max',
        'temperature_2m_min',
        'precipitation_probability_max',
      ].join(','),
      'timezone': 'auto',
      'forecast_days': '5',
    });
    final response = await _client
        .get(uri)
        .timeout(const Duration(seconds: 12));
    if (response.statusCode != 200) {
      throw Exception('Não foi possível consultar a previsão agora.');
    }
    return WeatherData.fromJson(
      jsonDecode(response.body) as Map<String, dynamic>,
    );
  }
}

class WeatherData {
  const WeatherData({
    required this.current,
    required this.forecast,
    required this.timezone,
  });

  final CurrentWeather current;
  final List<DailyWeather> forecast;
  final String timezone;

  factory WeatherData.fromJson(Map<String, dynamic> json) {
    final daily = json['daily'] as Map<String, dynamic>;
    final dates = daily['time'] as List<dynamic>;
    return WeatherData(
      current: CurrentWeather.fromJson(json['current'] as Map<String, dynamic>),
      timezone: json['timezone_abbreviation'] as String? ?? '',
      forecast: List.generate(
        dates.length,
        (index) => DailyWeather(
          date: DateTime.parse(dates[index] as String),
          code: (daily['weather_code'][index] as num).toInt(),
          maximum: (daily['temperature_2m_max'][index] as num).toDouble(),
          minimum: (daily['temperature_2m_min'][index] as num).toDouble(),
          rainChance:
              (daily['precipitation_probability_max'][index] as num?)
                  ?.toInt() ??
              0,
        ),
      ),
    );
  }
}

class CurrentWeather {
  const CurrentWeather({
    required this.temperature,
    required this.feelsLike,
    required this.humidity,
    required this.windSpeed,
    required this.windDirection,
    required this.windGusts,
    required this.pressure,
    required this.precipitation,
    required this.code,
    required this.isDay,
    required this.time,
  });

  final double temperature;
  final double feelsLike;
  final int humidity;
  final double windSpeed;
  final int windDirection;
  final double windGusts;
  final double pressure;
  final double precipitation;
  final int code;
  final bool isDay;
  final DateTime time;

  factory CurrentWeather.fromJson(Map<String, dynamic> json) => CurrentWeather(
    temperature: (json['temperature_2m'] as num).toDouble(),
    feelsLike: (json['apparent_temperature'] as num).toDouble(),
    humidity: (json['relative_humidity_2m'] as num).toInt(),
    windSpeed: (json['wind_speed_10m'] as num).toDouble(),
    windDirection: (json['wind_direction_10m'] as num).toInt(),
    windGusts: (json['wind_gusts_10m'] as num).toDouble(),
    pressure: (json['surface_pressure'] as num).toDouble(),
    precipitation: (json['precipitation'] as num).toDouble(),
    code: (json['weather_code'] as num).toInt(),
    isDay: json['is_day'] == 1,
    time: DateTime.parse(json['time'] as String),
  );
}

class DailyWeather {
  const DailyWeather({
    required this.date,
    required this.code,
    required this.maximum,
    required this.minimum,
    required this.rainChance,
  });
  final DateTime date;
  final int code;
  final double maximum;
  final double minimum;
  final int rainChance;
}
