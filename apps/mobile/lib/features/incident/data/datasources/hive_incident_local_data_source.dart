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
    'reportedById': i.reportedById,
    'reportedByName': i.reportedByName,
    'severity': i.severity,
    'workflowStatus': i.workflowStatus,
    'riskScore': i.riskScore,
    'confidenceScore': i.confidenceScore,
    'priorityScore': i.priorityScore,
    'confirmationCount': i.confirmationCount,
    'rejectionCount': i.rejectionCount,
    'complementCount': i.complementCount,
    'updatedAt': i.updatedAt?.millisecondsSinceEpoch,
    'nextAttemptAt': i.nextAttemptAt?.millisecondsSinceEpoch,
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
          reportedById: m['reportedById'] as String?,
          reportedByName: m['reportedByName'] as String?,
          severity: m['severity'] as String? ?? 'moderado',
          workflowStatus: m['workflowStatus'] as String? ?? 'reportado',
          riskScore: (m['riskScore'] as num?)?.toDouble() ?? 50,
          confidenceScore: (m['confidenceScore'] as num?)?.toDouble() ?? 50,
          priorityScore: (m['priorityScore'] as num?)?.toDouble() ?? 50,
          confirmationCount: m['confirmationCount'] as int? ?? 0,
          rejectionCount: m['rejectionCount'] as int? ?? 0,
          complementCount: m['complementCount'] as int? ?? 0,
          updatedAt: m['updatedAt'] == null ? null : DateTime.fromMillisecondsSinceEpoch(m['updatedAt'] as int, isUtc: true),
          nextAttemptAt: m['nextAttemptAt'] == null ? null : DateTime.fromMillisecondsSinceEpoch(m['nextAttemptAt'] as int, isUtc: true),
        ),
      )
      .toList();
}
