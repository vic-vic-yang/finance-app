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
