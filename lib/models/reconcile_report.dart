import 'dart:convert';

import '../crypto/key_chain.dart';

/// 对账报告（GET /api/reconcile/report 的返回结构）。
///
/// items 按 section.key 不同结构不同，这里保留原始 Map 并提供统一的
/// 密文 / 日期 / 数字取值 helper，页面按 key 取用字段。
class ReconcileReport {
  final String month;
  final DateTime? generatedAt;
  final List<ReconcileSection> sections;

  ReconcileReport({
    required this.month,
    this.generatedAt,
    required this.sections,
  });

  factory ReconcileReport.fromJson(Map<String, dynamic> j) => ReconcileReport(
        month: j['month'] as String? ?? '',
        generatedAt: j['generatedAt'] is String
            ? DateTime.tryParse(j['generatedAt'] as String)?.toLocal()
            : null,
        sections: (j['sections'] as List? ?? [])
            .whereType<Map<String, dynamic>>()
            .map(ReconcileSection.fromJson)
            .toList(),
      );

  int get totalIssues => sections.fold(0, (s, x) => s + x.count);
  bool get allClear => totalIssues == 0;

  ReconcileSection? byKey(String key) {
    for (final s in sections) {
      if (s.key == key) return s;
    }
    return null;
  }
}

class ReconcileSection {
  /// balanceDrift / suspectedDuplicates / recurringMissing / transferOrphans
  final String key;
  final String title;

  /// ok / info / warning / critical
  final String severity;
  final int count;
  final List<ReconcileItem> items;

  ReconcileSection({
    required this.key,
    required this.title,
    required this.severity,
    required this.count,
    required this.items,
  });

  factory ReconcileSection.fromJson(Map<String, dynamic> j) =>
      ReconcileSection(
        key: j['key'] as String? ?? '',
        title: j['title'] as String? ?? '',
        severity: j['severity'] as String? ?? 'ok',
        count: (j['count'] as num?)?.toInt() ?? 0,
        items: (j['items'] as List? ?? [])
            .whereType<Map<String, dynamic>>()
            .map(ReconcileItem.new)
            .toList(),
      );
}

/// 单个检查条目：原始 JSON + 常用取值 / 解密 helper。
class ReconcileItem {
  final Map<String, dynamic> raw;
  ReconcileItem(this.raw);

  String? str(String k) => raw[k] as String?;
  double num_(String k) => (raw[k] as num?)?.toDouble() ?? 0;
  int int_(String k) => (raw[k] as num?)?.toInt() ?? 0;
  bool bool_(String k) => raw[k] as bool? ?? false;

  DateTime? date(String k) {
    final v = raw[k];
    return v is String ? DateTime.tryParse(v)?.toLocal() : null;
  }

  /// 账户名：服务端返回密文（base64），客户端用账本 DEK 解
  String accountName(String ledgerId) {
    final cipher = raw['accountNameCipher'] as String?;
    if (cipher == null || cipher.isEmpty) return '账户';
    return KeyChain.instance.decryptText(
      ledgerId: ledgerId,
      cipherBase64: cipher,
      dekVer: int_('accountNameDekVer') == 0 ? 1 : int_('accountNameDekVer'),
      systemFallback: '账户',
    );
  }

  String? get accountIcon => raw['accountIcon'] as String?;

  /// 备注解密（逻辑同 models/bill.dart 的 note：
  /// dekVer==0 为服务端明文 UTF-8；<48 字节视为空备注）
  static String noteOf(String ledgerId, String? cipher, int dekVer) {
    if (cipher == null || cipher.isEmpty) return '';
    if (dekVer == 0) {
      try {
        final bytes = base64Decode(cipher);
        if (bytes.isEmpty) return '';
        return utf8.decode(bytes);
      } catch (_) {
        return '';
      }
    }
    try {
      if (base64Decode(cipher).length < 48) return '';
    } catch (_) {
      return '';
    }
    return KeyChain.instance.decryptText(
      ledgerId: ledgerId,
      cipherBase64: cipher,
      dekVer: dekVer,
    );
  }

  /// 条目自身的备注（transferOrphans 用）
  String note(String ledgerId) =>
      noteOf(ledgerId, raw['noteCipher'] as String?, int_('noteDekVer'));
}
