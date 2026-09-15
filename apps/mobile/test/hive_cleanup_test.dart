import 'package:flutter_test/flutter_test.dart';
import 'package:urbaneye_mobile/features/incident/data/datasources/hive_incident_local_data_source.dart';

void main() {
  final cutoff = DateTime.utc(2026, 9, 15).subtract(const Duration(days: 30));

  test('remove somente incidente sincronizado anterior ao limite', () {
    expect(
      shouldPurgeSyncedIncident({
        'status': 'synced',
        'createdAt': cutoff.subtract(const Duration(seconds: 1)).millisecondsSinceEpoch,
      }, cutoff),
      isTrue,
    );
  });

  test('mantem incidente pendente e sincronizado recente', () {
    expect(
      shouldPurgeSyncedIncident({
        'status': 'pending',
        'createdAt': cutoff.subtract(const Duration(days: 31)).millisecondsSinceEpoch,
      }, cutoff),
      isFalse,
    );
    expect(
      shouldPurgeSyncedIncident({
        'status': 'synced',
        'createdAt': cutoff.add(const Duration(seconds: 1)).millisecondsSinceEpoch,
      }, cutoff),
      isFalse,
    );
  });
}
