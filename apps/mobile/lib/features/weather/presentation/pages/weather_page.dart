import 'package:flutter/material.dart';

import '../../../../core/device/location_service.dart';
import '../../data/weather_service.dart';

class WeatherPage extends StatefulWidget {
  const WeatherPage({super.key, required this.locationService});
  final LocationService locationService;

  @override
  State<WeatherPage> createState() => _WeatherPageState();
}

class _WeatherPageState extends State<WeatherPage> {
  final _service = WeatherService();
  late Future<WeatherData> _weather;

  @override
  void initState() {
    super.initState();
    _weather = _load();
  }

  Future<WeatherData> _load() async {
    final position = await widget.locationService.current();
    return _service.getWeather(position.latitude, position.longitude);
  }

  Future<void> _refresh() async {
    final request = _load();
    setState(() => _weather = request);
    await request;
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(
      title: const Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Condições ambientais'),
          Text(
            'Dados da sua localização',
            style: TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w400,
              color: Color(0xFF667C75),
            ),
          ),
        ],
      ),
      actions: [
        IconButton(
          tooltip: 'Atualizar',
          onPressed: _refresh,
          icon: const Icon(Icons.refresh_rounded),
        ),
      ],
    ),
    body: FutureBuilder<WeatherData>(
      future: _weather,
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Center(child: CircularProgressIndicator());
        }
        if (snapshot.hasError) {
          return _ErrorState(onRetry: _refresh);
        }
        return _WeatherContent(data: snapshot.requireData, onRefresh: _refresh);
      },
    ),
  );
}

class _WeatherContent extends StatelessWidget {
  const _WeatherContent({required this.data, required this.onRefresh});
  final WeatherData data;
  final Future<void> Function() onRefresh;

  @override
  Widget build(BuildContext context) {
    final current = data.current;
    final info = weatherInfo(current.code, current.isDay);
    return RefreshIndicator(
      onRefresh: onRefresh,
      child: ListView(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 28),
        children: [
          Container(
            padding: const EdgeInsets.all(24),
            decoration: BoxDecoration(
              gradient: const LinearGradient(
                colors: [Color(0xFF176B5B), Color(0xFF58A68F)],
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              ),
              borderRadius: BorderRadius.circular(28),
              boxShadow: const [
                BoxShadow(
                  color: Color(0x30176B5B),
                  blurRadius: 24,
                  offset: Offset(0, 12),
                ),
              ],
            ),
            child: Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        info.label,
                        style: const TextStyle(
                          color: Colors.white70,
                          fontSize: 16,
                        ),
                      ),
                      const SizedBox(height: 6),
                      Text(
                        '${current.temperature.round()}°',
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 64,
                          height: 1,
                          fontWeight: FontWeight.w300,
                        ),
                      ),
                      const SizedBox(height: 10),
                      Text(
                        'Sensação de ${current.feelsLike.round()}°',
                        style: const TextStyle(
                          color: Colors.white,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ],
                  ),
                ),
                Icon(info.icon, size: 76, color: const Color(0xFFFFE7A1)),
              ],
            ),
          ),
          const SizedBox(height: 20),
          Text(
            'Agora',
            style: Theme.of(context).textTheme.titleLarge
                ?.copyWith(fontWeight: FontWeight.w700),
          ),
          const SizedBox(height: 12),
          GridView.count(
            crossAxisCount: 2,
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            mainAxisSpacing: 12,
            crossAxisSpacing: 12,
            childAspectRatio: 1.55,
            children: [
              _Metric(
                icon: Icons.water_drop_outlined,
                label: 'Umidade',
                value: '${current.humidity}%',
              ),
              _Metric(
                icon: Icons.air_rounded,
                label: 'Vento',
                value: '${current.windSpeed.round()} km/h',
                detail: compass(current.windDirection),
              ),
              _Metric(
                icon: Icons.speed_rounded,
                label: 'Pressão',
                value: '${current.pressure.round()} hPa',
              ),
              _Metric(
                icon: Icons.grain_rounded,
                label: 'Precipitação',
                value: '${current.precipitation.toStringAsFixed(1)} mm',
                detail: 'Rajadas ${current.windGusts.round()} km/h',
              ),
            ],
          ),
          const SizedBox(height: 24),
          Text(
            'Próximos dias',
            style: Theme.of(context).textTheme.titleLarge
                ?.copyWith(fontWeight: FontWeight.w700),
          ),
          const SizedBox(height: 12),
          Card(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 8),
              child: Column(
                children: [
                  for (var i = 0; i < data.forecast.length; i++) ...[
                    _ForecastRow(day: data.forecast[i], today: i == 0),
                    if (i < data.forecast.length - 1)
                      const Divider(height: 1, color: Color(0xFFEAF0ED)),
                  ],
                ],
              ),
            ),
          ),
          const SizedBox(height: 14),
          Text(
            'Atualizado às ${two(current.time.hour)}:${two(current.time.minute)} ${data.timezone} • Fonte: Open-Meteo',
            textAlign: TextAlign.center,
            style: const TextStyle(color: Color(0xFF71857F), fontSize: 12),
          ),
        ],
      ),
    );
  }
}

class _Metric extends StatelessWidget {
  const _Metric({
    required this.icon,
    required this.label,
    required this.value,
    this.detail,
  });
  final IconData icon;
  final String label;
  final String value;
  final String? detail;
  @override
  Widget build(BuildContext context) => Card(
    child: Padding(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(icon, size: 19, color: const Color(0xFF2A806F)),
              const SizedBox(width: 7),
              Text(label, style: const TextStyle(color: Color(0xFF71857F))),
            ],
          ),
          const Spacer(),
          Text(
            value,
            style: const TextStyle(
              fontSize: 20,
              fontWeight: FontWeight.w700,
              color: Color(0xFF18332D),
            ),
          ),
          if (detail != null)
            Text(
              detail!,
              style: const TextStyle(fontSize: 11, color: Color(0xFF71857F)),
            ),
        ],
      ),
    ),
  );
}

class _ForecastRow extends StatelessWidget {
  const _ForecastRow({required this.day, required this.today});
  final DailyWeather day;
  final bool today;
  @override
  Widget build(BuildContext context) {
    final info = weatherInfo(day.code, true);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 14),
      child: Row(
        children: [
          SizedBox(
            width: 56,
            child: Text(
              today ? 'Hoje' : weekdays[day.date.weekday - 1],
              style: const TextStyle(fontWeight: FontWeight.w600),
            ),
          ),
          Icon(info.icon, color: const Color(0xFF2A806F)),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              '${day.rainChance}% chuva',
              style: const TextStyle(color: Color(0xFF71857F)),
            ),
          ),
          Text(
            '${day.maximum.round()}°',
            style: const TextStyle(fontWeight: FontWeight.w700),
          ),
          const SizedBox(width: 10),
          Text(
            '${day.minimum.round()}°',
            style: const TextStyle(color: Color(0xFF71857F)),
          ),
        ],
      ),
    );
  }
}

class _ErrorState extends StatelessWidget {
  const _ErrorState({required this.onRetry});
  final Future<void> Function() onRetry;
  @override
  Widget build(BuildContext context) => Center(
    child: Padding(
      padding: const EdgeInsets.all(32),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(
            Icons.cloud_off_outlined,
            size: 54,
            color: Color(0xFF71857F),
          ),
          const SizedBox(height: 16),
          const Text(
            'Não foi possível carregar o clima',
            style: TextStyle(fontSize: 19, fontWeight: FontWeight.w700),
          ),
          const SizedBox(height: 8),
          const Text(
            'Confira a conexão e permita o acesso à localização.',
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 20),
          FilledButton.icon(
            onPressed: onRetry,
            icon: const Icon(Icons.refresh),
            label: const Text('Tentar novamente'),
          ),
        ],
      ),
    ),
  );
}

({IconData icon, String label}) weatherInfo(int code, bool isDay) {
  if (code == 0) {
    return (
      icon: isDay ? Icons.wb_sunny_rounded : Icons.nightlight_round,
      label: 'Céu limpo',
    );
  }
  if (code <= 3) {
    return (icon: Icons.cloud_outlined, label: 'Parcialmente nublado');
  }
  if (code <= 48) {
    return (icon: Icons.foggy, label: 'Neblina');
  }
  if (code <= 67 || code >= 80 && code <= 82) {
    return (icon: Icons.umbrella_outlined, label: 'Chuva');
  }
  if (code >= 95) {
    return (icon: Icons.thunderstorm_outlined, label: 'Trovoadas');
  }
  return (icon: Icons.ac_unit, label: 'Neve');
}

String compass(int degrees) => const [
  'N',
  'NE',
  'L',
  'SE',
  'S',
  'SO',
  'O',
  'NO',
][((degrees + 22.5) ~/ 45) % 8];
String two(int value) => value.toString().padLeft(2, '0');
const weekdays = ['Seg', 'Ter', 'Qua', 'Qui', 'Sex', 'Sáb', 'Dom'];
