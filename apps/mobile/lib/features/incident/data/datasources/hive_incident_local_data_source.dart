import 'package:hive/hive.dart';

import '../../domain/entities/incident.dart';

class HiveIncidentLocalDataSource {
  HiveIncidentLocalDataSource(this.box);
  final Box<Map<dynamic, dynamic>> box;
  Future<void> put(Incident i) => box.put(i.id, {
    'id': i.id,
    'imagePath': i.imagePath,
    'category': i.category,
    'latitude': i.latitude,
    'longitude': i.longitude,
    'createdAt': i.createdAt.millisecondsSinceEpoch,
    'status': i.status.name,
    'attempts': i.attempts,
    'imageUrl': i.imageUrl,
    'lastError': i.lastError,
  });
  List<Incident> all() => box.values
      .map(
        (m) => Incident(
          id: m['id'] as String,
          imagePath: m['imagePath'] as String,
          category: m['category'] as String,
          latitude: (m['latitude'] as num).toDouble(),
          longitude: (m['longitude'] as num).toDouble(),
          createdAt: DateTime.fromMillisecondsSinceEpoch(
            m['createdAt'] as int,
            isUtc: true,
          ),
          status: IncidentStatus.values.byName(m['status'] as String),
          attempts: m['attempts'] as int,
          imageUrl: m['imageUrl'] as String?,
          lastError: m['lastError'] as String?,
        ),
      )
      .toList();
}
