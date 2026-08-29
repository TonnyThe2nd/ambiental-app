enum IncidentStatus { pending, synced, failed }

class Incident {
  const Incident({
    required this.id,
    required this.imagePath,
    required this.category,
    required this.latitude,
    required this.longitude,
    required this.createdAt,
    this.status = IncidentStatus.pending,
    this.attempts = 0,
    this.imageUrl,
    this.lastError,
    this.reportedById,
    this.reportedByName,
  });
  final String id, imagePath, category;
  final double latitude, longitude;
  final DateTime createdAt;
  final IncidentStatus status;
  final int attempts;
  final String? imageUrl, lastError, reportedById, reportedByName;
  Incident copyWith({
    IncidentStatus? status,
    int? attempts,
    String? imageUrl,
    String? lastError,
    String? reportedById,
    String? reportedByName,
  }) => Incident(
    id: id,
    imagePath: imagePath,
    category: category,
    latitude: latitude,
    longitude: longitude,
    createdAt: createdAt,
    status: status ?? this.status,
    attempts: attempts ?? this.attempts,
    imageUrl: imageUrl ?? this.imageUrl,
    lastError: lastError ?? this.lastError,
    reportedById: reportedById ?? this.reportedById,
    reportedByName: reportedByName ?? this.reportedByName,
  );
}
