import 'dart:convert';
import 'package:http/http.dart' as http;
import '../../auth/application/auth_service.dart';
import '../domain/app_notification.dart';
import '../domain/notification_gateway.dart';

class HttpNotificationGateway implements NotificationGateway {
  HttpNotificationGateway(this._auth, {http.Client? client, String? baseUrl})
      : _client=client??http.Client(), _baseUri=Uri.parse(baseUrl??const String.fromEnvironment('API_BASE_URL',defaultValue:'http://10.0.2.2:8000'));
  final AuthService _auth; final http.Client _client; final Uri _baseUri;
  @override
  Future<bool> updatePosition({required double latitude,required double longitude,String? fcmToken}) async {
    final response=await _client.put(_baseUri.resolve('/auth/me/location'),headers:_auth.authorizedHeaders(json:true),body:jsonEncode({'latitude':latitude,'longitude':longitude,'fcmToken':?fcmToken}));
    if(response.statusCode==401){await _auth.handleUnauthorized();return false;} return response.statusCode>=200&&response.statusCode<300;
  }
  @override
  Future<List<AppNotification>> list() async {
    final response=await _client.get(_baseUri.resolve('/notifications?unread_only=false'),headers:_auth.authorizedHeaders());
    if(response.statusCode==401){await _auth.handleUnauthorized();return [];} if(response.statusCode<200||response.statusCode>=300)return [];
    return (jsonDecode(response.body) as List).map((item)=>AppNotification.fromJson(item as Map<String,dynamic>)).toList();
  }
  @override
  Future<bool> markRead(String id) async {
    final response=await _client.post(_baseUri.resolve('/notifications/$id/read'),headers:_auth.authorizedHeaders());
    if(response.statusCode==401){await _auth.handleUnauthorized();return false;} return response.statusCode>=200&&response.statusCode<300;
  }
}
