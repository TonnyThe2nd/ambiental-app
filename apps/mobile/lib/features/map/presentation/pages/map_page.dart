import 'package:flutter/material.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';

import '../../../incident/domain/entities/incident.dart';
import '../../../incident/domain/repositories/incident_repository.dart';

class MapPage extends StatelessWidget {
  const MapPage({super.key, required this.repository});
  final IncidentRepository repository;
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
      stream: repository.watchRemote(),
      builder: (context, remote) => FutureBuilder<List<Incident>>(
        future: repository.getAll(),
        builder: (context, local) {
          final incidents = [...?local.data, ...?remote.data];
          return Stack(
            children: [
              ClipRRect(
                borderRadius: const BorderRadius.vertical(
                  top: Radius.circular(24),
                ),
                child: GoogleMap(
                  initialCameraPosition: const CameraPosition(
                    target: LatLng(-23.5505, -46.6333),
                    zoom: 11,
                  ),
                  myLocationButtonEnabled: true,
                  myLocationEnabled: true,
                  zoomControlsEnabled: false,
                  markers: incidents
                      .map(
                        (i) => Marker(
                          markerId: MarkerId(i.id),
                          position: LatLng(i.latitude, i.longitude),
                          infoWindow: InfoWindow(
                            title: i.category,
                            snippet: i.reportedByName == null
                                ? i.status.name
                                : 'Registrado por ${i.reportedByName}',
                          ),
                        ),
                      )
                      .toSet(),
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
            ],
          );
        },
      ),
    ),
  );
}
