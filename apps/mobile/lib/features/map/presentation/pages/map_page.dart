import 'package:flutter/material.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';

import '../../../incident/domain/entities/incident.dart';
import '../../../incident/domain/repositories/incident_repository.dart';

class MapPage extends StatelessWidget {
  const MapPage({super.key, required this.repository});
  final IncidentRepository repository;
  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('Mapa de ocorrências')),
    body: StreamBuilder<List<Incident>>(
      stream: repository.watchRemote(),
      builder: (context, remote) => FutureBuilder<List<Incident>>(
        future: repository.getAll(),
        builder: (context, local) {
          final incidents = [...?local.data, ...?remote.data];
          return GoogleMap(
            initialCameraPosition: const CameraPosition(
              target: LatLng(-23.5505, -46.6333),
              zoom: 11,
            ),
            markers: incidents
                .map(
                  (i) => Marker(
                    markerId: MarkerId(i.id),
                    position: LatLng(i.latitude, i.longitude),
                    infoWindow: InfoWindow(
                      title: i.category,
                      snippet: i.status.name,
                    ),
                  ),
                )
                .toSet(),
          );
        },
      ),
    ),
  );
}
