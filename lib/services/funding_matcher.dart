/// 把支付宝/微信「收/付款方式」原始串归一成稳定的匹配 key。
String normalizeFundingHint(String raw) {
  final s = raw.trim();
  if (s.isEmpty) return '';
  if (s.contains('花呗')) return '花呗';
  if (s.contains('白条')) return '白条';
  if (s.contains('余额宝')) return '余额宝';
  if (s.contains('零钱通')) return '零钱通';
  if (s == '账户余额' || s == '余额') return '支付宝余额';
  if (s.contains('零钱')) return '微信零钱';
  final tail = RegExp(r'(\d{4})\)?\s*$').firstMatch(s)?.group(1);
  final bank = _bankShort(s);
  if (bank != null && tail != null) return '$bank:$tail';
  // 无银行关键词但末尾带卡号（如 "羊绍波 6217003800352"）→ 尾号比对账户名
  if (tail != null) return 'card:$tail';
  return s;
}

String? _bankShort(String s) {
  const map = {
    '招商': '招商', '工商': '工商', '建设': '建行', '建行': '建行',
    '农业': '农行', '农行': '农行', '中国银行': '中行', '交通': '交通',
    '邮储': '邮储', '浦发': '浦发', '民生': '民生', '兴业': '兴业',
    '光大': '光大', '中信': '中信', '平安': '平安', '广发': '广发',
  };
  for (final e in map.entries) {
    if (s.contains(e.key)) return e.value;
  }
  return null;
}

/// 从转账类备注里提取"交易对方"的学习键：
/// - 卡号（≥6 位数字）→ 'card:尾4位'
/// - 第一个人名/机构名片段（滤掉 转账/汇款 等业务词）
/// 用于手动「转为账户间转账」后写入 PaymentMethodMap，
/// 下次导入同对手时自动识别为转账。
List<String> counterpartyLearnKeys(String note) {
  final keys = <String>[];
  // 卡号 → 尾 4 位
  for (final m in RegExp(r'\d{6,}').allMatches(note)) {
    final d = m.group(0)!;
    keys.add('card:${d.substring(d.length - 4)}');
  }
  // 中文名片段
  const stop = [
    '转账', '汇款', '转账汇款', '行内转账', '汇入汇款', '跨行转出',
    '转出', '转入', '快捷支付', '快捷退款', '银联', '代付',
    '还款', '主动还款', '信用购', '花呗', '白条', '支付', '退款',
  ];
  for (final seg in note.split(RegExp(r'[·\s→←:：,，]+'))) {
    final s = seg.trim();
    if (s.length < 2 || s.length > 15) continue;
    if (!RegExp(r'[\u4e00-\u9fff]').hasMatch(s)) continue;
    if (RegExp(r'\d').hasMatch(s)) continue;
    if (stop.any((w) => s == w)) continue;
    keys.add(s);
    break; // 只取第一个像名字的
  }
  return keys;
}

/// 在账户列表里找匹配的 accountId。
/// [accounts] 是 (id, 解密后名称) 列表；[saved] 是已记忆的 归一key→accountId。
String? matchAccountId(
  String normalizedHint,
  List<(String, String)> accounts,
  Map<String, String> saved,
) {
  if (normalizedHint.isEmpty) return null;
  final remembered = saved[normalizedHint];
  if (remembered != null) return remembered;
  final tail = normalizedHint.contains(':')
      ? normalizedHint.split(':').last
      : null;
  for (final a in accounts) {
    if (tail != null && a.$2.contains(tail)) return a.$1;
  }
  final body = normalizedHint.contains(':')
      ? normalizedHint.split(':').first
      : normalizedHint;
  for (final a in accounts) {
    if (a.$2.contains(body)) return a.$1;
  }
  return null;
}
