class User {
  final String id;
  final String username;
  final String? nickname;

  User({
    required this.id,
    required this.username,
    this.nickname,
  });

  factory User.fromJson(Map<String, dynamic> json) {
    return User(
      id: json['id'].toString(),
      username: json['username'] as String,
      nickname: json['nickname'] as String?,
    );
  }

  /// 优先用昵称显示，没有则回退到用户名
  String get displayName {
    final n = (nickname ?? '').trim();
    if (n.isNotEmpty) return n;
    return username;
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'username': username,
      if (nickname != null) 'nickname': nickname,
    };
  }
}
