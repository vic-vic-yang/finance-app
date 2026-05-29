/// 自然语言解析返回的单条草稿
class NlDraft {
  /// expense / income
  final String type;
  final double amount;
  final String categoryId;
  /// AI 原始返回的 "一级>二级" 名字，显示用
  final String categoryName;
  final String accountId;
  final String note;
  final DateTime date;
  final String? merchant;
  /// 0..1
  final double confidence;

  NlDraft({
    required this.type,
    required this.amount,
    required this.categoryId,
    required this.categoryName,
    required this.accountId,
    required this.note,
    required this.date,
    this.merchant,
    required this.confidence,
  });

  factory NlDraft.fromJson(Map<String, dynamic> j) => NlDraft(
        type: (j['type'] as String?) == 'income' ? 'income' : 'expense',
        amount: (j['amount'] as num).toDouble(),
        categoryId: j['categoryId'] as String? ?? '',
        categoryName: j['categoryName'] as String? ?? '',
        accountId: j['accountId'] as String? ?? '',
        note: j['note'] as String? ?? '',
        date: DateTime.tryParse(j['date'] as String? ?? '') ?? DateTime.now(),
        merchant: (j['merchant'] as String?)?.trim().isEmpty == true
            ? null
            : j['merchant'] as String?,
        confidence: ((j['confidence'] as num?)?.toDouble() ?? 0.5)
            .clamp(0.0, 1.0)
            .toDouble(),
      );

  bool get isIncome => type == 'income';

  NlDraft copyWith({
    String? type,
    double? amount,
    String? categoryId,
    String? categoryName,
    String? accountId,
    String? note,
    DateTime? date,
    String? merchant,
    double? confidence,
  }) =>
      NlDraft(
        type: type ?? this.type,
        amount: amount ?? this.amount,
        categoryId: categoryId ?? this.categoryId,
        categoryName: categoryName ?? this.categoryName,
        accountId: accountId ?? this.accountId,
        note: note ?? this.note,
        date: date ?? this.date,
        merchant: merchant ?? this.merchant,
        confidence: confidence ?? this.confidence,
      );
}

/// /api/ai/parse-text 完整返回
class NlParseResult {
  final NlDraft? draft;
  final String? error;

  NlParseResult({this.draft, this.error});

  factory NlParseResult.fromJson(Map<String, dynamic> j) => NlParseResult(
        draft: j['draft'] == null
            ? null
            : NlDraft.fromJson(j['draft'] as Map<String, dynamic>),
        error: j['error'] as String?,
      );
}
