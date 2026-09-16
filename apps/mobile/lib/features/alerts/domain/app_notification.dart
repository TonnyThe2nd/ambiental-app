class AppNotification {
  const AppNotification({required this.id, required this.title, required this.message, required this.createdAt, this.readAt});
  final String id; final String title; final String message; final DateTime createdAt; final DateTime? readAt;
  factory AppNotification.fromJson(Map<String, dynamic> json) => AppNotification(
    id: json['id'] as String, title: json['title'] as String, message: json['message'] as String,
    createdAt: DateTime.parse(json['createdAt'] as String),
    readAt: json['readAt'] == null ? null : DateTime.parse(json['readAt'] as String));
}
