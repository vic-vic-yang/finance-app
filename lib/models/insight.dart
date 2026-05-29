/// AI 洞察。后端实时算，不入库（只持久化"已忽略"）。
///
/// 服务器只用明文（amount / categoryName / date / 预算等）就能生成，
/// 不依赖 noteCipher 解密。
class AiInsight {
  /// "<type>|<target>" 拼出的稳定 id
  final String id;
  /// anomaly_bill / anomaly_cat_up / anomaly_cat_down / budget_alert / recurring_due
  final String type;
  /// info / warning / critical
  final String severity;
  /// 关联对象 id（billId / categoryId / "budgetId_70" / recurringId）
  final String target;
  final String title;
  final String body;
  final Map<String, dynamic>? data;
  final List<InsightAction> actions;

  AiInsight({
    required this.id,
    required this.type,
    required this.severity,
    required this.target,
    required this.title,
    required this.body,
    this.data,
    this.actions = const [],
  });

  factory AiInsight.fromJson(Map<String, dynamic> j) => AiInsight(
        id: j['id'] as String,
        type: j['type'] as String,
        severity: j['severity'] as String? ?? 'info',
        target: j['target'] as String,
        title: j['title'] as String,
        body: j['body'] as String? ?? '',
        data: j['data'] as Map<String, dynamic>?,
        actions: (j['actions'] as List?)
                ?.cast<Map<String, dynamic>>()
                .map(InsightAction.fromJson)
                .toList() ??
            const [],
      );
}

class InsightAction {
  final String label;
  final String intent;
  final Map<String, dynamic>? params;

  InsightAction({required this.label, required this.intent, this.params});

  factory InsightAction.fromJson(Map<String, dynamic> j) => InsightAction(
        label: j['label'] as String,
        intent: j['intent'] as String,
        params: j['params'] as Map<String, dynamic>?,
      );
}
