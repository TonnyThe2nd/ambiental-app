import 'package:flutter_test/flutter_test.dart';
import 'package:urbaneye_mobile/features/alerts/application/notification_service.dart';
import 'package:urbaneye_mobile/features/incident/infrastructure/remote/http_incident_remote_data_source.dart';

void main() {
  test('polling periodico e somente fallback de cinco minutos', () {
    const fallbackInterval = Duration(minutes: 5);

    expect(notificationFallbackPollingInterval, fallbackInterval);
    expect(locationFallbackPollingInterval, fallbackInterval);
    expect(incidentFeedFallbackPollingInterval, fallbackInterval);
  });
}
