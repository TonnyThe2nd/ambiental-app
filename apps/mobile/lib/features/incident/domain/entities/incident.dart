enum IncidentStatus { pending, synced, failed }

const _unchanged = Object();

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
    Object? imageUrl = _unchanged,
    Object? lastError = _unchanged,
    Object? reportedById = _unchanged,
    Object? reportedByName = _unchanged,
    String? severity,
    String? workflowStatus,
    double? riskScore,
    double? confidenceScore,
    double? priorityScore,
    int? confirmationCount,
    int? rejectionCount,
    int? complementCount,
    Object? updatedAt = _unchanged,
    Object? nextAttemptAt = _unchanged,
  }) => Incident(
    id: id,
    imagePath: imagePath,
    category: category,
    latitude: latitude,
    longitude: longitude,
    createdAt: createdAt,
    status: status ?? this.status,
    attempts: attempts ?? this.attempts,
    imageUrl: identical(imageUrl, _unchanged) ? this.imageUrl : imageUrl as String?,
    lastError: identical(lastError, _unchanged) ? this.lastError : lastError as String?,
    reportedById: identical(reportedById, _unchanged) ? this.reportedById : reportedById as String?,
    reportedByName: identical(reportedByName, _unchanged) ? this.reportedByName : reportedByName as String?,
    severity: severity ?? this.severity,
    workflowStatus: workflowStatus ?? this.workflowStatus,
    riskScore: riskScore ?? this.riskScore,
    confidenceScore: confidenceScore ?? this.confidenceScore,
    priorityScore: priorityScore ?? this.priorityScore,
    confirmationCount: confirmationCount ?? this.confirmationCount,
    rejectionCount: rejectionCount ?? this.rejectionCount,
    complementCount: complementCount ?? this.complementCount,
    updatedAt: identical(updatedAt, _unchanged) ? this.updatedAt : updatedAt as DateTime?,
    nextAttemptAt: identical(nextAttemptAt, _unchanged) ? this.nextAttemptAt : nextAttemptAt as DateTime?,
  );
}
