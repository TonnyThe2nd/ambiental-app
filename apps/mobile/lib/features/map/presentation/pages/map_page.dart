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
          final incidents = [...?local.data, ...?remote.data];
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
                            child: Tooltip(
                              message: _markerDescription(incident),
                              child: Icon(
                                Icons.location_pin,
                                color: _categoryColor(incident.category),
                                size: 40,
                                semanticLabel: _categoryLabel(
                                  incident.category,
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
  _ => 'Outro',
};

Color _categoryColor(String category) => switch (category) {
  'alagamento' => Colors.blue,
  'poluicao' => Colors.deepOrange,
  'lixo' => Colors.green,
  _ => const Color(0xFF176B5B),
};
