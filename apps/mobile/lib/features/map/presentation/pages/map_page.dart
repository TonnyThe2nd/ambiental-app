import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:geolocator/geolocator.dart';
import 'package:latlong2/latlong.dart';

import '../../../incident/domain/entities/incident.dart';
import '../../../incident/domain/repositories/incident_repository.dart';

class MapPage extends StatefulWidget {
  const MapPage({super.key, required this.repository});
  final IncidentRepository repository;

  @override
  State<MapPage> createState() => _MapPageState();
}

class _MapPageState extends State<MapPage> {
  static const _initialCenter = LatLng(-23.5505, -46.6333);
  final _mapController = MapController();
  LatLng? _userLocation;
  bool _locating = false;
  final _categories = <String>{};
  final _severities = <String>{};
  bool _showDensity = true;

  @override
  void initState() {
    super.initState();
    _locateUser(showError: false);
  }

  Future<void> _locateUser({bool showError = true}) async {
    if (_locating) return;
    setState(() => _locating = true);
    try {
      if (!await Geolocator.isLocationServiceEnabled()) {
        throw StateError('Ative o serviço de localização.');
      }
      var permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) {
        permission = await Geolocator.requestPermission();
      }
      if (permission == LocationPermission.denied ||
          permission == LocationPermission.deniedForever) {
        throw StateError('Permissão de localização necessária.');
      }
      final position = await Geolocator.getCurrentPosition();
      if (!mounted) return;
      final location = LatLng(position.latitude, position.longitude);
      setState(() => _userLocation = location);
      _mapController.move(location, 15);
    } catch (error) {
      if (mounted && showError) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(error.toString().replaceFirst('Bad state: ', '')),
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _locating = false);
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(
      title: const Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Mapa de ocorrências'),
          Text(
            'Acompanhe relatos próximos',
            style: TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w400,
              color: Color(0xFF667C75),
            ),
          ),
        ],
      ),
    ),
    body: StreamBuilder<List<Incident>>(
      stream: widget.repository.watchRemote(),
      builder: (context, remote) => FutureBuilder<List<Incident>>(
        future: widget.repository.getAll(),
        builder: (context, local) {
          final byId = <String, Incident>{
            for (final item in [...?local.data, ...?remote.data]) item.id: item,
          };
          final incidents = byId.values.where((item) => item.isActive &&
            (_categories.isEmpty || _categories.contains(item.category)) &&
            (_severities.isEmpty || _severities.contains(item.severity))).toList()
            ..sort((a, b) => b.priorityScore.compareTo(a.priorityScore));
          return Stack(
            children: [
              ClipRRect(
                borderRadius: const BorderRadius.vertical(
                  top: Radius.circular(24),
                ),
                child: FlutterMap(
                  mapController: _mapController,
                  options: const MapOptions(
                    initialCenter: _initialCenter,
                    initialZoom: 11,
                  ),
                  children: [
                    TileLayer(
                      urlTemplate:
                          'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
                      userAgentPackageName: 'urbaneye_mobile',
                    ),
                    if (_showDensity)
                      CircleLayer(circles: _densityCircles(incidents)),
                    MarkerLayer(
                      markers: [
                        ...incidents.map(
                          (incident) => Marker(
                            point: LatLng(
                              incident.latitude,
                              incident.longitude,
                            ),
                            width: 44,
                            height: 44,
                            child: GestureDetector(
                              onTap: () => _showIncident(incident),
                              child: Tooltip(
                                message: _markerDescription(incident),
                                child: Icon(
                                  Icons.location_pin,
                                  color: _severityColor(incident.severity),
                                  size: incident.priorityScore >= 75 ? 44 : 38,
                                  semanticLabel: _categoryLabel(incident.category),
                                ),
                              ),
                            ),
                          ),
                        ),
                        if (_userLocation case final location?)
                          Marker(
                            point: location,
                            width: 32,
                            height: 32,
                            child: const Tooltip(
                              message: 'Sua localização',
                              child: Icon(
                                Icons.my_location,
                                color: Colors.blue,
                                size: 28,
                              ),
                            ),
                          ),
                      ],
                    ),
                    RichAttributionWidget(
                      attributions: const [
                        TextSourceAttribution('OpenStreetMap contributors'),
                      ],
                    ),
                  ],
                ),
              ),
              Positioned(
                left: 16,
                top: 16,
                child: Card(
                  child: Padding(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 14,
                      vertical: 10,
                    ),
                    child: Row(
                      children: [
                        const Icon(
                          Icons.eco_outlined,
                          color: Color(0xFF176B5B),
                          size: 20,
                        ),
                        const SizedBox(width: 8),
                        Text(
                          '${incidents.length} ${incidents.length == 1 ? 'registro' : 'registros'}',
                          style: const TextStyle(fontWeight: FontWeight.w700),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
              Positioned(
                left: 12,
                right: 12,
                top: 72,
                child: Card(
                  child: SingleChildScrollView(
                    scrollDirection: Axis.horizontal,
                    padding: const EdgeInsets.symmetric(horizontal: 8),
                    child: Row(children: [
                      ...['alagamento', 'lixo', 'incendio', 'poluicao'].map((value) =>
                        FilterChip(label: Text(_categoryLabel(value)), selected: _categories.contains(value),
                          onSelected: (selected) => setState(() => selected ? _categories.add(value) : _categories.remove(value)))),
                      ...['critico', 'moderado'].map((value) =>
                        FilterChip(label: Text(value), selected: _severities.contains(value),
                          onSelected: (selected) => setState(() => selected ? _severities.add(value) : _severities.remove(value)))),
                      FilterChip(label: const Text('Densidade'), selected: _showDensity,
                        onSelected: (value) => setState(() => _showDensity = value)),
                    ]),
                  ),
                ),
              ),
              Positioned(
                right: 16,
                bottom: 24,
                child: FloatingActionButton.small(
                  heroTag: 'map-user-location',
                  onPressed: _locating ? null : _locateUser,
                  tooltip: 'Minha localização',
                  child: _locating
                      ? const SizedBox.square(
                          dimension: 20,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Icon(Icons.my_location),
                ),
              ),
            ],
          );
        },
      ),
    ),
  );

  Future<void> _showIncident(Incident incident) async {
    final vote = await showModalBottomSheet<String>(context: context, builder: (context) =>
      SafeArea(child: Padding(padding: const EdgeInsets.all(20), child: Column(mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(_categoryLabel(incident.category), style: Theme.of(context).textTheme.titleLarge),
          Text('Risco ${incident.riskScore.toStringAsFixed(0)} · confiança ${incident.confidenceScore.toStringAsFixed(0)}%'),
          const SizedBox(height: 12),
          Wrap(spacing: 8, children: [
            FilledButton.icon(onPressed: () => Navigator.pop(context, 'confirmar'), icon: const Icon(Icons.check), label: const Text('Confirmar')),
            OutlinedButton.icon(onPressed: () => Navigator.pop(context, 'complementar'), icon: const Icon(Icons.add_comment), label: const Text('Complementar')),
            TextButton.icon(onPressed: () => Navigator.pop(context, 'rejeitar'), icon: const Icon(Icons.close), label: const Text('Não procede')),
          ])
        ]))));
    if (vote == null) return;
    try {
      await widget.repository.validate(incident.id, vote);
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Validação registrada.')));
    } catch (error) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(error.toString())));
    }
  }
}

List<CircleMarker> _densityCircles(List<Incident> incidents) {
  final cells = <String, List<Incident>>{};
  for (final item in incidents) {
    final key = '${(item.latitude * 100).floor()}:${(item.longitude * 100).floor()}';
    cells.putIfAbsent(key, () => []).add(item);
  }
  return cells.values.where((items) => items.length >= 2).map((items) {
    final lat = items.map((i) => i.latitude).reduce((a, b) => a + b) / items.length;
    final lng = items.map((i) => i.longitude).reduce((a, b) => a + b) / items.length;
    return CircleMarker(point: LatLng(lat, lng), radius: 18.0 + items.length.clamp(0, 20),
      color: Colors.red.withValues(alpha: .18), borderColor: Colors.red.withValues(alpha: .45), borderStrokeWidth: 2);
  }).toList();
}

String _markerDescription(Incident incident) {
  final detail = incident.reportedByName == null
      ? incident.status.name
      : 'Registrado por ${incident.reportedByName}';
  return '${_categoryLabel(incident.category)}\n$detail';
}

String _categoryLabel(String category) => switch (category) {
  'alagamento' => 'Alagamento',
  'poluicao' => 'Poluição',
  'lixo' => 'Descarte de lixo',
  'incendio' => 'Risco de incêndio',
  _ => 'Outro',
};

Color _severityColor(String severity) => switch (severity) {
  'critico' => Colors.red,
  'moderado' => Colors.orange,
  _ => Colors.green,
};
