/// 通知中心条目（对应后端 Notification 模型）
class AppNotification {
  final String id;

  /// 通知类型：cfo_proposal / system …
  final String type;
  final String title;
  final String body;

  /// 关联账本（系统级通知为 null）
  final String? ledgerId;

  /// 结构化负载：dedupeKey / proposalId / severity / detectorType …
  final Map<String, dynamic> payload;

  /// 阅读时间；null = 未读
  final DateTime? readAt;
  final DateTime createdAt;

  AppNotification({
    required this.id,
    required this.type,
    required this.title,
    required this.body,
    this.ledgerId,
    required this.payload,
    this.readAt,
    required this.createdAt,
  });

  bool get isUnread => readAt == null;

  /// 严重级别（cfo_proposal 类通知才有）：info / warning / critical
  String? get severity => payload['severity'] as String?;

  factory AppNotification.fromJson(Map<String, dynamic> j) => AppNotification(
        id: j['id'] as String,
        type: (j['type'] as String?) ?? 'system',
        title: (j['title'] as String?) ?? '',
        body: (j['body'] as String?) ?? '',
        ledgerId: j['ledgerId'] as String?,
        payload: (j['payload'] as Map?)?.cast<String, dynamic>() ?? const {},
        readAt: j['readAt'] != null ? DateTime.parse(j['readAt'] as String) : null,
        createdAt: DateTime.parse(j['createdAt'] as String),
      );
}
