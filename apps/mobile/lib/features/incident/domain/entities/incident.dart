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
    this.severity = 'moderado',
    this.workflowStatus = 'reportado',
    this.riskScore = 50,
    this.confidenceScore = 50,
    this.priorityScore = 50,
    this.confirmationCount = 0,
    this.rejectionCount = 0,
    this.complementCount = 0,
    this.updatedAt,
    this.nextAttemptAt,
  });
  final String id, imagePath, category;
  final double latitude, longitude;
  final DateTime createdAt;
  final IncidentStatus status;
  final int attempts;
  final String? imageUrl, lastError, reportedById, reportedByName;
  final String severity, workflowStatus;
  final double riskScore, confidenceScore, priorityScore;
  final int confirmationCount, rejectionCount, complementCount;
  final DateTime? updatedAt, nextAttemptAt;
  bool get isActive => workflowStatus != 'rejeitado' && workflowStatus != 'resolvido';
  Incident copyWith({
    IncidentStatus? status,
    int? attempts,
    String? imageUrl,
    String? lastError,
    String? reportedById,
    String? reportedByName,
    String? severity,
    String? workflowStatus,
    double? riskScore,
    double? confidenceScore,
    double? priorityScore,
    int? confirmationCount,
    int? rejectionCount,
    int? complementCount,
    DateTime? updatedAt,
    DateTime? nextAttemptAt,
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
    severity: severity ?? this.severity,
    workflowStatus: workflowStatus ?? this.workflowStatus,
    riskScore: riskScore ?? this.riskScore,
    confidenceScore: confidenceScore ?? this.confidenceScore,
    priorityScore: priorityScore ?? this.priorityScore,
    confirmationCount: confirmationCount ?? this.confirmationCount,
    rejectionCount: rejectionCount ?? this.rejectionCount,
    complementCount: complementCount ?? this.complementCount,
    updatedAt: updatedAt ?? this.updatedAt,
    nextAttemptAt: nextAttemptAt ?? this.nextAttemptAt,
  );
}
