enum AiImportStatus {
  pending,
  extracting,
  parsing,
  dedupping,
  reviewReady,
  applying,
  done,
  failed,
  partial,
}

AiImportStatus _parseStatus(String? s) {
  switch (s) {
    case 'pending': return AiImportStatus.pending;
    case 'extracting': return AiImportStatus.extracting;
    case 'parsing': return AiImportStatus.parsing;
    case 'dedupping': return AiImportStatus.dedupping;
    case 'review_ready': return AiImportStatus.reviewReady;
    case 'applying': return AiImportStatus.applying;
    case 'done': return AiImportStatus.done;
    case 'failed': return AiImportStatus.failed;
    case 'partial': return AiImportStatus.partial;
    default: return AiImportStatus.pending;
  }
}

/// 一条 AI 导入记录
class AiImport {
  final String id;
  final String ledgerId;
  final String userId;
  final String accountId;
  final String filename;
  /// image / pdf / csv / xlsx / text
  final String fileType;
  final int fileSize;
  final String modelName;
  final AiImportStatus status;
  final int progress; // 0..100
  final String? message;
  final int parsedCount;
  final int dupCount;
  final int insertedCount;
  final bool hasDrafts;
  final DateTime createdAt;
  final DateTime updatedAt;

  AiImport({
    required this.id,
    required this.ledgerId,
    required this.userId,
    required this.accountId,
    required this.filename,
    required this.fileType,
    required this.fileSize,
    required this.modelName,
    required this.status,
    required this.progress,
    this.message,
    required this.parsedCount,
    required this.dupCount,
    required this.insertedCount,
    required this.hasDrafts,
    required this.createdAt,
    required this.updatedAt,
  });

  factory AiImport.fromJson(Map<String, dynamic> j) => AiImport(
        id: j['id'] as String,
        ledgerId: j['ledgerId'] as String,
        userId: j['userId'] as String,
        accountId: (j['accountId'] as String?) ?? '',
        filename: j['filename'] as String,
        fileType: j['fileType'] as String,
        fileSize: (j['fileSize'] as num?)?.toInt() ?? 0,
        modelName: j['modelName'] as String? ?? '',
        status: _parseStatus(j['status'] as String?),
        progress: (j['progress'] as num?)?.toInt() ?? 0,
        message: j['message'] as String?,
        parsedCount: (j['parsedCount'] as num?)?.toInt() ?? 0,
        dupCount: (j['dupCount'] as num?)?.toInt() ?? 0,
        insertedCount: (j['insertedCount'] as num?)?.toInt() ?? 0,
        hasDrafts: j['hasDrafts'] as bool? ?? false,
        createdAt: DateTime.parse(j['createdAt'] as String),
        updatedAt: DateTime.parse(j['updatedAt'] as String),
      );

  bool get isInProgress =>
      status == AiImportStatus.pending ||
      status == AiImportStatus.extracting ||
      status == AiImportStatus.parsing ||
      status == AiImportStatus.dedupping ||
      status == AiImportStatus.applying;

  String get statusLabel {
    switch (status) {
      case AiImportStatus.pending: return '排队中';
      case AiImportStatus.extracting: return '提取内容';
      case AiImportStatus.parsing: return 'AI 解析';
      case AiImportStatus.dedupping: return '去重中';
      case AiImportStatus.reviewReady: return '入库中';
      case AiImportStatus.applying: return '入库中';
      case AiImportStatus.done: return '完成';
      case AiImportStatus.failed: return '失败';
      case AiImportStatus.partial: return '部分成功';
    }
  }

  String get fileTypeEmoji {
    switch (fileType) {
      case 'image': return '🖼️';
      case 'pdf': return '📄';
      case 'csv': return '📊';
      case 'xlsx': return '📊';
      case 'text': return '📝';
      default: return '📎';
    }
  }
}

/// AI 解析出来的单条草稿。categoryId / accountId 后端已经填好，
/// 客户端只需用账本 DEK 加密 note 后 POST apply
class AiDraft {
  final String type; // 'expense' / 'income'
  final double amount;
  final String categoryName; // AI 原始返回（仅用于显示/调试）
  final String categoryId;   // 后端解析好（包括"其他"自动建）
  final String accountId;    // 后端从 AiImport.accountId 填的
  final String note;
  final DateTime date;
  final String? externalId;
  final String? fundingHint; // 收/付款方式原始串
  final String direction;    // 'expense' / 'income' / 'transfer'
  final String? counterparty;
  final double? balance;     // 银行联机余额（去重 + 校准用）
  final String? merchantHash; // 商户哈希（后端算好，apply 时原样回传，分类纠正记忆用）

  AiDraft({
    required this.type,
    required this.amount,
    required this.categoryName,
    required this.categoryId,
    required this.accountId,
    required this.note,
    required this.date,
    this.externalId,
    this.fundingHint,
    this.direction = 'expense',
    this.counterparty,
    this.balance,
    this.merchantHash,
  });

  factory AiDraft.fromJson(Map<String, dynamic> j) => AiDraft(
        type: (j['type'] as String?) == 'income' ? 'income' : 'expense',
        amount: (j['amount'] as num).toDouble(),
        categoryName: j['categoryName'] as String? ?? '',
        categoryId: j['categoryId'] as String? ?? '',
        accountId: j['accountId'] as String? ?? '',
        note: j['note'] as String? ?? '',
        date: DateTime.tryParse(j['date'] as String? ?? '') ?? DateTime.now(),
        externalId: (j['externalId'] as String?)?.trim().isEmpty == true
            ? null
            : j['externalId'] as String?,
        fundingHint: j['fundingHint'] as String?,
        direction: (j['direction'] as String?) ?? 'expense',
        counterparty: j['counterparty'] as String?,
        balance: (j['balance'] as num?)?.toDouble(),
        merchantHash: j['merchantHash'] as String?,
      );

  bool get isIncome => type == 'income';
}

/// 可选模型（GET /ai/models）
class AiModel {
  final String name;
  final bool supportsVision;
  AiModel({required this.name, required this.supportsVision});
  factory AiModel.fromJson(Map<String, dynamic> j) => AiModel(
        name: j['name'] as String,
        supportsVision: j['supportsVision'] as bool? ?? false,
      );
}
