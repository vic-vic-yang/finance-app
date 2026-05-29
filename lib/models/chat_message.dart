/// 一条对话消息（前端会话内存）
class ChatTurn {
  /// user / assistant
  final String role;
  /// 文本
  final String content;
  /// AI 回复带的卡片
  final List<ReplyCard> cards;
  /// 本地构造的"商户聚合"卡片（通路 B 客户端解密后生成）
  /// 在 messages 历史里不参与 LLM 上下文，仅 UI 展示
  final MerchantCard? merchantCard;
  /// 用于显示
  final DateTime ts;

  ChatTurn({
    required this.role,
    required this.content,
    this.cards = const [],
    this.merchantCard,
    DateTime? ts,
  }) : ts = ts ?? DateTime.now();

  bool get isUser => role == 'user';
}

/// 服务端返回的可渲染卡片（stat / budget）
class ReplyCard {
  /// 'stat' / 'budget'
  final String type;
  final Map<String, dynamic> data;

  ReplyCard({required this.type, required this.data});

  factory ReplyCard.fromJson(Map<String, dynamic> j) => ReplyCard(
        type: j['type'] as String,
        data: (j['data'] as Map?)?.cast<String, dynamic>() ?? const {},
      );
}

/// 客户端聚合出来的商户卡片
class MerchantCard {
  final String period;
  final int totalCount;
  /// [{merchant, amount, count}]
  final List<Map<String, dynamic>> buckets;

  MerchantCard({
    required this.period,
    required this.totalCount,
    required this.buckets,
  });
}
