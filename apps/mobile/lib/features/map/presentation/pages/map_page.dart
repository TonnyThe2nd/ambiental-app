import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';

import '../../../../core/device/location_service.dart';
import '../../../alerts/application/proximity_monitor.dart';
import '../../../alerts/domain/proximity_zone.dart' show distanceMeters;
import '../../../alerts/presentation/proximity_settings.dart';
import '../../../incident/domain/entities/incident.dart';
import '../../../incident/domain/incident_impact.dart';
import '../../../incident/domain/repositories/incident_repository.dart';
import '../../../incident/presentation/models/incident_category_visual.dart';
import '../../../routing/domain/route_option.dart';
import '../../../routing/infrastructure/route_planner.dart';
import '../../infrastructure/map_layers_service.dart';

/// Camadas que o usuário liga e desliga no mapa.
enum MapLayer { incidents, riskAreas, density, heatmap, airQuality, temperature }

extension MapLayerX on MapLayer {
  String get label => switch (this) {
    MapLayer.incidents => 'Ocorrências',
    MapLayer.riskAreas => 'Áreas de risco (raio de impacto)',
    MapLayer.density => 'Densidade de relatos',
    MapLayer.heatmap => 'Mapa de calor (servidor)',
    MapLayer.airQuality => 'Qualidade do ar (AQI)',
    MapLayer.temperature => 'Temperatura e ilhas de calor',
  };

  IconData get icon => switch (this) {
    MapLayer.incidents => Icons.place_outlined,
    MapLayer.riskAreas => Icons.radar,
    MapLayer.density => Icons.bubble_chart_outlined,
    MapLayer.heatmap => Icons.grid_on,
    MapLayer.airQuality => Icons.air,
    MapLayer.temperature => Icons.thermostat,
  };
}

/// Atalhos de filtro para os riscos de deslocamento citados na proposta.
const _floodPreset = {'alagamento'};
const _obstructedRoutePreset = {'alagamento', 'arvore_caida', 'erosao', 'queimada'};

class MapPage extends StatefulWidget {
  const MapPage({
    super.key,
    required this.repository,
    required this.locationService,
    this.layers,
    this.routePlanner,
    this.proximity,
  });

  final IncidentRepository repository;
  final LocationService locationService;
  final MapLayersService? layers;
  final RoutePlanner? routePlanner;
  final ProximityMonitor? proximity;

  @override
  State<MapPage> createState() => _MapPageState();
}

class _MapPageState extends State<MapPage> {
  static const _initialCenter = LatLng(-23.5505, -46.6333);
  static const _feedRadiusMeters = 50000;

  /// O feed só é refeito quando o centro se desloca mais que isso (antes cada
  /// arrasto e cada filtro recriava o stream e a conexão).
  static const _feedRecenterMeters = 5000.0;

  final _mapController = MapController();
  LatLng? _userLocation;
  LatLng _feedCenter = _initialCenter;
  late Stream<List<Incident>> _remoteFeed;
  late Future<List<Incident>> _localIncidents;
  Timer? _cameraIdle;
  bool _mapReady = false;
  bool _locating = false;
  final _categories = <String>{};
  final _severities = <String>{};
  final _layers = <MapLayer>{MapLayer.incidents, MapLayer.riskAreas, MapLayer.density};

  List<EnvironmentalCell> _environment = const [];
  List<HeatmapCell> _heatmap = const [];
  bool _loadingLayers = false;

  LatLng? _destination;
  TravelMode _travelMode = TravelMode.foot;
  List<RouteOption> _routes = const [];
  String? _selectedRouteId;
  bool _planning = false;

  @override
  void initState() {
    super.initState();
    _subscribeFeed();
    widget.proximity?.addListener(_onProximityChanged);
    _locateUser(showError: false);
  }

  @override
  void dispose() {
    _cameraIdle?.cancel();
    widget.proximity?.removeListener(_onProximityChanged);
    super.dispose();
  }

  void _subscribeFeed() {
    _remoteFeed = widget.repository.watchRemote(
      latitude: _feedCenter.latitude,
      longitude: _feedCenter.longitude,
      radiusMeters: _feedRadiusMeters,
    );
    _localIncidents = widget.repository.getAll();
  }

  void _onProximityChanged() {
    final position = widget.proximity?.lastPosition;
    if (!mounted || position == null) return;
    setState(() => _userLocation = LatLng(position.latitude, position.longitude));
  }

  Future<void> _locateUser({bool showError = true}) async {
    if (_locating) return;
    setState(() => _locating = true);
    try {
      final position = await widget.locationService.current();
      if (!mounted) return;
      final location = LatLng(position.latitude, position.longitude);
      setState(() {
        _userLocation = location;
        _feedCenter = location;
        _subscribeFeed();
      });
      if (_mapReady) _mapController.move(location, 15);
    } catch (error) {
      if (mounted && showError) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(error.toString().replaceFirst('Bad state: ', ''))),
        );
      }
    } finally {
      if (mounted) setState(() => _locating = false);
    }
  }

  void _onMapPositionChanged(MapCamera camera, bool hasGesture) {
    if (!hasGesture) return;
    _cameraIdle?.cancel();
    _cameraIdle = Timer(const Duration(milliseconds: 700), () {
      if (!mounted) return;
      final moved = distanceMeters(camera.center.latitude, camera.center.longitude,
          _feedCenter.latitude, _feedCenter.longitude);
      if (moved > _feedRecenterMeters) {
        setState(() {
          _feedCenter = camera.center;
          _subscribeFeed();
        });
      }
      unawaited(_loadDataLayers());
    });
  }

  Future<void> _loadDataLayers() async {
    final service = widget.layers;
    if (service == null || !_mapReady) return;
    final needsEnvironment = _layers.contains(MapLayer.airQuality) || _layers.contains(MapLayer.temperature);
    final needsHeatmap = _layers.contains(MapLayer.heatmap);
    if (!needsEnvironment && !needsHeatmap) return;
    final camera = _mapController.camera;
    final bounds = camera.visibleBounds;
    setState(() => _loadingLayers = true);
    try {
      final environment = needsEnvironment
          ? await service.environmentalGrid(
              south: bounds.south, west: bounds.west, north: bounds.north, east: bounds.east)
          : _environment;
      final heatmap = needsHeatmap
          ? await service.heatmap(
              latitude: camera.center.latitude,
              longitude: camera.center.longitude,
              radiusMeters: _feedRadiusMeters)
          : _heatmap;
      if (!mounted) return;
      setState(() {
        _environment = environment;
        _heatmap = heatmap;
      });
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Camadas indisponíveis agora: $error')),
        );
      }
    } finally {
      if (mounted) setState(() => _loadingLayers = false);
    }
  }

  Future<void> _openLayers() async {
    await showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      builder: (context) => StatefulBuilder(
        builder: (context, setSheetState) => SafeArea(
          child: ListView(
            shrinkWrap: true,
            children: [
              const ListTile(title: Text('Camadas do mapa', style: TextStyle(fontWeight: FontWeight.w700))),
              for (final layer in MapLayer.values)
                SwitchListTile(
                  secondary: Icon(layer.icon),
                  title: Text(layer.label),
                  value: _layers.contains(layer),
                  onChanged: (value) {
                    setState(() => value ? _layers.add(layer) : _layers.remove(layer));
                    setSheetState(() {});
                  },
                ),
            ],
          ),
        ),
      ),
    );
    unawaited(_loadDataLayers());
  }

  void _applyPreset(Set<String> categories) {
    setState(() {
      final active = _categories.length == categories.length && _categories.containsAll(categories);
      _categories
        ..clear()
        ..addAll(active ? const <String>{} : categories);
    });
  }

  // ---------------------------------------------------------------- rotas

  Future<void> _onLongPress(TapPosition _, LatLng point) async {
    if (widget.routePlanner == null) return;
    setState(() {
      _destination = point;
      _routes = const [];
      _selectedRouteId = null;
    });
    final mode = await showModalBottomSheet<TravelMode>(
      context: context,
      showDragHandle: true,
      builder: (context) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const ListTile(
              leading: Icon(Icons.alt_route),
              title: Text('Rota segura até aqui'),
              subtitle: Text('Compara rotas alternativas e evita ocorrências no caminho.'),
            ),
            for (final value in TravelMode.values)
              ListTile(
                leading: Icon(value == TravelMode.foot ? Icons.directions_walk : Icons.directions_car),
                title: Text(value.label),
                onTap: () => Navigator.pop(context, value),
              ),
          ],
        ),
      ),
    );
    if (mode == null) {
      if (mounted) setState(() => _destination = null);
      return;
    }
    _travelMode = mode;
    await _planRoute();
  }

  Future<void> _planRoute() async {
    final planner = widget.routePlanner;
    final destination = _destination;
    if (planner == null || destination == null) return;
    var origin = _userLocation;
    if (origin == null) {
      await _locateUser();
      origin = _userLocation;
    }
    if (origin == null || !mounted) return;
    setState(() => _planning = true);
    try {
      final routes = await planner.plan(
        fromLatitude: origin.latitude,
        fromLongitude: origin.longitude,
        toLatitude: destination.latitude,
        toLongitude: destination.longitude,
        mode: _travelMode,
      );
      if (!mounted) return;
      setState(() {
        _routes = routes;
        _selectedRouteId = routes.first.id;
      });
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(error.toString().replaceFirst('Bad state: ', ''))),
        );
      }
    } finally {
      if (mounted) setState(() => _planning = false);
    }
  }

  RouteOption? get _selectedRoute {
    for (final route in _routes) {
      if (route.id == _selectedRouteId) return route;
    }
    return null;
  }

  Future<void> _startRoute() async {
    final route = _selectedRoute;
    final monitor = widget.proximity;
    if (route == null || monitor == null) return;
    final messenger = ScaffoldMessenger.of(context);
    final ok = await monitor.setRoute(simplifyRoute(route.points, RoutePlanner.alertRouteMaxPoints));
    messenger.showSnackBar(SnackBar(
      content: Text(ok
          ? 'Rota ativa: você será avisado de novas ocorrências no caminho por 2 horas.'
          : 'Rota salva no aparelho; o servidor será avisado quando houver conexão.'),
    ));
  }

  Future<void> _clearRoute() async {
    final hadActiveRoute = widget.proximity?.activeRoute != null;
    setState(() {
      _destination = null;
      _routes = const [];
      _selectedRouteId = null;
    });
    if (hadActiveRoute) await widget.proximity?.setRoute(null);
  }

  // ---------------------------------------------------------------- build

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(
      title: const Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Mapa de ocorrências'),
          Text(
            'Toque e segure no mapa para traçar uma rota segura',
            style: TextStyle(fontSize: 13, fontWeight: FontWeight.w400, color: Color(0xFF667C75)),
          ),
        ],
      ),
    ),
    body: StreamBuilder<List<Incident>>(
      stream: _remoteFeed,
      builder: (context, remote) => FutureBuilder<List<Incident>>(
        future: _localIncidents,
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
                borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
                child: _buildMap(incidents),
              ),
              Positioned(left: 12, right: 12, top: 12, child: _buildFilters(incidents.length)),
              if (_loadingLayers || _planning)
                const Positioned(left: 0, right: 0, top: 0, child: LinearProgressIndicator()),
              Positioned(right: 16, bottom: _routes.isEmpty ? 24 : 250, child: _buildActions()),
              if (_routes.isNotEmpty)
                Positioned(left: 12, right: 12, bottom: 12, child: _buildRoutePanel()),
              if (_routes.isEmpty && widget.proximity != null)
                Positioned(left: 12, bottom: 24, right: 80, child: _ProximityBanner(monitor: widget.proximity!)),
            ],
          );
        },
      ),
    ),
  );

  Widget _buildMap(List<Incident> incidents) {
    final heatIslands = heatIslandIndexes(_environment);
    final selected = _selectedRoute;
    return FlutterMap(
      mapController: _mapController,
      options: MapOptions(
        initialCenter: _initialCenter,
        initialZoom: 11,
        onPositionChanged: _onMapPositionChanged,
        onLongPress: _onLongPress,
        onMapReady: () {
          _mapReady = true;
          final location = _userLocation;
          if (location != null) _mapController.move(location, 15);
        },
      ),
      children: [
        TileLayer(
          urlTemplate: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
          userAgentPackageName: 'urbaneye_mobile',
        ),
        if (_layers.contains(MapLayer.airQuality) || _layers.contains(MapLayer.temperature))
          PolygonLayer(polygons: [
            for (var i = 0; i < _environment.length; i++)
              if (_environmentColor(_environment[i]) case final color?)
                Polygon(
                  points: _cellRectangle(_environment[i]),
                  color: color.withValues(alpha: .28),
                  borderColor: heatIslands.contains(i) && _layers.contains(MapLayer.temperature)
                      ? Colors.red.shade900
                      : color.withValues(alpha: .5),
                  borderStrokeWidth: heatIslands.contains(i) && _layers.contains(MapLayer.temperature) ? 3 : 1,
                ),
          ]),
        if (_layers.contains(MapLayer.heatmap))
          PolygonLayer(polygons: [
            for (final cell in _heatmap)
              Polygon(
                points: [
                  LatLng(cell.south, cell.west),
                  LatLng(cell.south, cell.east),
                  LatLng(cell.north, cell.east),
                  LatLng(cell.north, cell.west),
                ],
                color: _riskColor(cell.averageRisk).withValues(alpha: (0.15 + cell.total * 0.05).clamp(0.15, 0.6).toDouble()),
                borderColor: _riskColor(cell.averageRisk),
                borderStrokeWidth: cell.critical > 0 ? 2 : 1,
              ),
          ]),
        if (_layers.contains(MapLayer.density)) CircleLayer(circles: _densityCircles(incidents)),
        if (_layers.contains(MapLayer.riskAreas))
          CircleLayer(circles: [
            for (final incident in incidents)
              CircleMarker(
                point: LatLng(incident.latitude, incident.longitude),
                radius: incidentImpactRadiusMeters(incident.category, incident.severity).toDouble(),
                useRadiusInMeter: true,
                color: _severityColor(incident.severity).withValues(alpha: .10),
                borderColor: _severityColor(incident.severity).withValues(alpha: .55),
                borderStrokeWidth: 1.5,
              ),
          ]),
        if (_routes.isNotEmpty)
          PolylineLayer(polylines: [
            for (final route in _routes.where((r) => r.id != _selectedRouteId))
              Polyline(points: _latLngs(route.points), strokeWidth: 5, color: Colors.grey.withValues(alpha: .7)),
            if (selected != null)
              Polyline(
                points: _latLngs(selected.points),
                strokeWidth: 7,
                color: _routeColor(selected),
                borderStrokeWidth: 2,
                borderColor: Colors.white,
              ),
          ]),
        if (_layers.contains(MapLayer.airQuality) || _layers.contains(MapLayer.temperature))
          MarkerLayer(markers: [
            for (var i = 0; i < _environment.length; i++)
              if (_environmentLabel(_environment[i], heatIslands.contains(i)) case final label?)
                Marker(
                  point: LatLng(_environment[i].latitude, _environment[i].longitude),
                  width: 96,
                  height: 36,
                  child: _MapLabel(text: label),
                ),
          ]),
        MarkerLayer(markers: [
          if (_layers.contains(MapLayer.incidents))
            ...incidents.map((incident) => Marker(
              point: LatLng(incident.latitude, incident.longitude),
              width: 44,
              height: 44,
              child: GestureDetector(
                onTap: () => _showIncident(incident),
                child: Tooltip(
                  message: _markerDescription(incident),
                  child: _IncidentMarker(incident: incident),
                ),
              ),
            )),
          if (_destination case final destination?)
            Marker(
              point: destination,
              width: 40,
              height: 40,
              alignment: Alignment.topCenter,
              child: const Icon(Icons.flag, color: Color(0xFF176B5B), size: 36),
            ),
          if (_userLocation case final location?)
            Marker(
              point: location,
              width: 32,
              height: 32,
              child: const Tooltip(
                message: 'Sua localização',
                child: Icon(Icons.my_location, color: Colors.blue, size: 28),
              ),
            ),
        ]),
        RichAttributionWidget(
          attributions: const [
            TextSourceAttribution('OpenStreetMap contributors'),
            TextSourceAttribution('Open-Meteo (ar e temperatura)'),
          ],
        ),
      ],
    );
  }

  Widget _buildFilters(int count) => Card(
    child: SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      child: Row(children: [
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 8),
          child: Text('$count ${count == 1 ? 'registro' : 'registros'}',
              style: const TextStyle(fontWeight: FontWeight.w700)),
        ),
        FilterChip(
          avatar: const Icon(Icons.flood, size: 17),
          label: const Text('Alagamentos'),
          selected: _categories.length == 1 && _categories.contains('alagamento'),
          onSelected: (_) => _applyPreset(_floodPreset),
        ),
        const SizedBox(width: 6),
        FilterChip(
          avatar: const Icon(Icons.block, size: 17),
          label: const Text('Rotas obstruídas'),
          selected: _categories.length == _obstructedRoutePreset.length &&
              _categories.containsAll(_obstructedRoutePreset),
          onSelected: (_) => _applyPreset(_obstructedRoutePreset),
        ),
        const SizedBox(width: 6),
        ...incidentCategories.where((item) => item.id != 'outro').map((item) => Padding(
          padding: const EdgeInsets.only(right: 6),
          child: FilterChip(
            avatar: Icon(item.icon, size: 17, color: item.color),
            label: Text(item.label),
            selected: _categories.contains(item.id),
            onSelected: (selected) =>
                setState(() => selected ? _categories.add(item.id) : _categories.remove(item.id)),
          ),
        )),
        ...['critico', 'moderado'].map((value) => Padding(
          padding: const EdgeInsets.only(right: 6),
          child: FilterChip(
            label: Text(value),
            selected: _severities.contains(value),
            onSelected: (selected) =>
                setState(() => selected ? _severities.add(value) : _severities.remove(value)),
          ),
        )),
      ]),
    ),
  );

  Widget _buildActions() => Column(
    mainAxisSize: MainAxisSize.min,
    children: [
      FloatingActionButton.small(
        heroTag: 'map-layers',
        onPressed: _openLayers,
        tooltip: 'Camadas',
        child: const Icon(Icons.layers_outlined),
      ),
      const SizedBox(height: 12),
      FloatingActionButton.small(
        heroTag: 'map-user-location',
        onPressed: _locating ? null : _locateUser,
        tooltip: 'Minha localização',
        child: _locating
            ? const SizedBox.square(dimension: 20, child: CircularProgressIndicator(strokeWidth: 2))
            : const Icon(Icons.my_location),
      ),
    ],
  );

  Widget _buildRoutePanel() {
    final selected = _selectedRoute;
    final activeRoute = widget.proximity?.activeRoute != null;
    return Card(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(12, 8, 12, 12),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(children: [
              const Icon(Icons.alt_route, color: Color(0xFF176B5B)),
              const SizedBox(width: 8),
              Expanded(
                child: Text('Rotas (${_travelMode.label.toLowerCase()})',
                    style: const TextStyle(fontWeight: FontWeight.w700)),
              ),
              IconButton(onPressed: _clearRoute, icon: const Icon(Icons.close), tooltip: 'Limpar rota'),
            ]),
            ConstrainedBox(
              constraints: const BoxConstraints(maxHeight: 130),
              child: ListView(
                shrinkWrap: true,
                children: [
                  for (final route in _routes)
                    ListTile(
                      dense: true,
                      contentPadding: EdgeInsets.zero,
                      leading: Icon(
                        route.id == _selectedRouteId ? Icons.radio_button_checked : Icons.radio_button_off,
                        color: _routeColor(route),
                      ),
                      title: Text(route.recommended
                          ? 'Recomendada${route.blocked ? ' (atenção: caminho bloqueado)' : ''}'
                          : route.blocked ? 'Bloqueada por ocorrência crítica' : 'Alternativa'),
                      subtitle: Text(route.summary),
                      onTap: () => setState(() => _selectedRouteId = route.id),
                    ),
                ],
              ),
            ),
            if (selected != null && selected.incidents.isNotEmpty)
              Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: Text(
                  'No caminho: ${selected.incidents.map((i) => incidentCategoryVisual(i.category).label).toSet().join(', ')}',
                  style: TextStyle(color: _routeColor(selected), fontWeight: FontWeight.w600),
                ),
              ),
            FilledButton.icon(
              onPressed: selected == null || widget.proximity == null ? null : _startRoute,
              icon: const Icon(Icons.notifications_active_outlined),
              label: Text(activeRoute ? 'Atualizar rota monitorada' : 'Iniciar rota e receber alertas'),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _showIncident(Incident incident) async {
    final radius = incidentImpactRadiusMeters(incident.category, incident.severity);
    final user = _userLocation;
    final inside = user != null &&
        distanceMeters(user.latitude, user.longitude, incident.latitude, incident.longitude) <= radius;
    final vote = await showModalBottomSheet<String>(context: context, builder: (context) =>
      SafeArea(child: Padding(padding: const EdgeInsets.all(20), child: Column(mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(incidentCategoryVisual(incident.category).label, style: Theme.of(context).textTheme.titleLarge),
          Text('Risco ${incident.riskScore.toStringAsFixed(0)} · confiança ${incident.confidenceScore.toStringAsFixed(0)}%'),
          Text('Área de impacto: $radius m'),
          if (inside)
            const Padding(
              padding: EdgeInsets.only(top: 6),
              child: Text('Você está dentro desta área.',
                  style: TextStyle(color: Colors.red, fontWeight: FontWeight.w700)),
            ),
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

  Color? _environmentColor(EnvironmentalCell cell) {
    if (_layers.contains(MapLayer.airQuality) && cell.airQualityIndex != null) {
      return aqiColor(cell.airQualityIndex!);
    }
    if (_layers.contains(MapLayer.temperature) && cell.apparentTemperature != null) {
      return temperatureColor(cell.apparentTemperature!);
    }
    return null;
  }

  String? _environmentLabel(EnvironmentalCell cell, bool heatIsland) {
    final parts = <String>[
      if (_layers.contains(MapLayer.airQuality) && cell.airQualityIndex != null) 'AQI ${cell.airQualityIndex}',
      if (_layers.contains(MapLayer.temperature) && cell.apparentTemperature != null)
        '${cell.apparentTemperature!.round()}°${heatIsland ? ' ilha' : ''}',
    ];
    return parts.isEmpty ? null : parts.join(' · ');
  }
}

List<LatLng> _latLngs(List<List<double>> points) => [for (final p in points) LatLng(p[0], p[1])];

List<LatLng> _cellRectangle(EnvironmentalCell cell) {
  final halfLat = cell.latitudeSpan / 2;
  final halfLon = cell.longitudeSpan / 2;
  return [
    LatLng(cell.latitude - halfLat, cell.longitude - halfLon),
    LatLng(cell.latitude - halfLat, cell.longitude + halfLon),
    LatLng(cell.latitude + halfLat, cell.longitude + halfLon),
    LatLng(cell.latitude + halfLat, cell.longitude - halfLon),
  ];
}

/// Escala oficial do US AQI (EPA).
Color aqiColor(int aqi) {
  if (aqi <= 50) return const Color(0xFF4CAF50);
  if (aqi <= 100) return const Color(0xFFFBC02D);
  if (aqi <= 150) return const Color(0xFFFF9800);
  if (aqi <= 200) return const Color(0xFFF44336);
  if (aqi <= 300) return const Color(0xFF9C27B0);
  return const Color(0xFF7E0023);
}

Color temperatureColor(double celsius) {
  if (celsius < 20) return const Color(0xFF42A5F5);
  if (celsius < 25) return const Color(0xFF66BB6A);
  if (celsius < 30) return const Color(0xFFFFCA28);
  if (celsius < 35) return const Color(0xFFFF7043);
  return const Color(0xFFD32F2F);
}

Color _riskColor(double risk) {
  if (risk >= 75) return Colors.red;
  if (risk >= 45) return Colors.orange;
  return Colors.amber;
}

Color _routeColor(RouteOption route) {
  if (route.blocked) return Colors.red;
  if (route.riskScore > 0) return Colors.orange.shade800;
  return const Color(0xFF2E7D32);
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
  return '${incidentCategoryVisual(incident.category).label}\n$detail';
}

class _MapLabel extends StatelessWidget {
  const _MapLabel({required this.text});
  final String text;

  @override
  Widget build(BuildContext context) => Center(
    child: Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: .85),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Text(text, style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w700)),
    ),
  );
}

/// Convite para ativar os alertas de área quando ainda não estão funcionando.
class _ProximityBanner extends StatelessWidget {
  const _ProximityBanner({required this.monitor});
  final ProximityMonitor monitor;

  @override
  Widget build(BuildContext context) => AnimatedBuilder(
    animation: monitor,
    builder: (context, _) {
      if (monitor.enabled && monitor.access == LocationAccess.always) return const SizedBox.shrink();
      return Card(
        color: const Color(0xFFFFF8E1),
        child: ListTile(
          dense: true,
          leading: const Icon(Icons.shield_outlined, color: Color(0xFFF57F17)),
          title: const Text('Alertas de área de risco'),
          subtitle: Text(proximityStatusText(monitor)),
          trailing: const Icon(Icons.chevron_right),
          onTap: () => enableProximityAlerts(context, monitor),
        ),
      );
    },
  );
}

class _IncidentMarker extends StatelessWidget {
  const _IncidentMarker({required this.incident});
  final Incident incident;
  @override
  Widget build(BuildContext context) {
    final category = incidentCategoryVisual(incident.category);
    final size = incident.priorityScore >= 75 ? 44.0 : 40.0;
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        color: category.color,
        shape: BoxShape.circle,
        border: Border.all(color: _severityColor(incident.severity), width: 3),
        boxShadow: const [BoxShadow(color: Color(0x55000000), blurRadius: 6, offset: Offset(0, 3))],
      ),
      child: Icon(category.icon, color: Colors.white, size: size * .58, semanticLabel: category.label),
    );
  }
}

Color _severityColor(String severity) => switch (severity) {
  'critico' => Colors.red,
  'moderado' => Colors.orange,
  _ => Colors.green,
};
