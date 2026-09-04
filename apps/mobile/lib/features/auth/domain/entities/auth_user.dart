class AuthUser {
  const AuthUser({required this.id, required this.name, required this.email});

  final String id;
  final String name;
  final String email;

  factory AuthUser.fromJson(Map<String, dynamic> json) => AuthUser(
        id: json['id'] as String,
        name: json['name'] as String,
        email: json['email'] as String,
      );

  Map<String, dynamic> toJson() => {'id': id, 'name': name, 'email': email};
}
