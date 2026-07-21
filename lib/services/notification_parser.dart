import 'dart:convert';

/// ======================================================================
/// 端侧自动记账 · 通知解析引擎（纯 Dart，无平台依赖，方便单测）
/// ======================================================================
///
/// 输入：NotificationListenerService 抓到的通知（包名 / 标题 / 正文 / 时间）
/// 输出：[ParsedBillDraft] 账单草稿（金额 / 商户 / 收支方向 / 时间 + 去重指纹）
///       无法解析或属于噪音时返回 null。
///
/// 规则模板覆盖：
///   - 微信支付（com.tencent.mm）
///   - 支付宝（com.eg.android.AlipayGphone）
///   - 云闪付（com.unionpay）
///   - 主流银行 App：招商 / 工商 / 建设 / 交通 / 中信 / 平安 / 农业 / 中国 /
///     邮储 / 民生 / 兴业 / 浦发 / 光大 / 广发（通用银行文案模板，
///     按「消费/支出/存入/收入 + 金额 + 元」结构解析）
///
/// 注意：银行包名为公开资料整理，可能随厂商改版漂移；解析以通知**正文
/// 关键词**为准，包名只用于来源展示与准入白名单，包名不准不影响解析。

/// 一条从通知解析出的账单草稿
class ParsedBillDraft {
  final String packageName; // 来源 App 包名
  final String sourceApp; // 来源 App 显示名（微信支付 / 支付宝 / 招商银行…）
  final double amount; // 金额（元，正数）
  final String type; // 'expense' | 'income'
  final String merchant; // 商户 / 对方（解析不到为空串）
  final DateTime time; // 交易时间（正文里解析出的优先，否则用通知时间）
  final String rawText; // 通知原文（截断保存，用于备注与排查）
  final String fingerprint; // 去重指纹：包名 + 金额 + 分钟级时间

  const ParsedBillDraft({
    required this.packageName,
    required this.sourceApp,
    required this.amount,
    required this.type,
    required this.merchant,
    required this.time,
    required this.rawText,
    required this.fingerprint,
  });

  bool get isExpense => type == 'expense';

  /// 展示用商户名：解析不到商户时回退来源 App 名
  String get displayMerchant => merchant.isNotEmpty ? merchant : sourceApp;

  Map<String, dynamic> toJson() => {
        'packageName': packageName,
        'sourceApp': sourceApp,
        'amount': amount,
        'type': type,
        'merchant': merchant,
        'time': time.toIso8601String(),
        'rawText': rawText,
        'fingerprint': fingerprint,
      };

  factory ParsedBillDraft.fromJson(Map<String, dynamic> json) => ParsedBillDraft(
        packageName: json['packageName'] as String? ?? '',
        sourceApp: json['sourceApp'] as String? ?? '',
        amount: (json['amount'] as num?)?.toDouble() ?? 0,
        type: json['type'] as String? ?? 'expense',
        merchant: json['merchant'] as String? ?? '',
        time: DateTime.tryParse(json['time'] as String? ?? '') ??
            DateTime.fromMillisecondsSinceEpoch(0),
        rawText: json['rawText'] as String? ?? '',
        fingerprint: json['fingerprint'] as String? ?? '',
      );

  static String encodeList(List<ParsedBillDraft> list) =>
      jsonEncode(list.map((e) => e.toJson()).toList());

  static List<ParsedBillDraft> decodeList(String? raw) {
    if (raw == null || raw.isEmpty) return [];
    try {
      final list = jsonDecode(raw);
      if (list is! List) return [];
      return list
          .whereType<Map>()
          .map((e) => ParsedBillDraft.fromJson(e.cast<String, dynamic>()))
          .where((d) => d.fingerprint.isNotEmpty && d.amount > 0)
          .toList();
    } catch (_) {
      return [];
    }
  }
}

class NotificationParser {
  NotificationParser._();

  // ── 来源 App 白名单（包名 → 显示名）─────────────────────────
  static const Map<String, String> knownPackages = {
    // 支付平台
    'com.tencent.mm': '微信支付',
    'com.eg.android.AlipayGphone': '支付宝',
    'com.unionpay': '云闪付',
    // 银行（包名为公开资料整理，以正文关键词解析为准）
    'com.cmbchina.ccd.pluto.cmbActivity': '招商银行',
    'com.icbc': '工商银行',
    'com.ccb.ccbhome': '建设银行',
    'com.bankcomm.bankcomm': '交通银行',
    'com.bankcomm.maidanba': '交通银行',
    'com.ecitic.bank.mobile': '中信银行',
    'com.pingan.paces.ccms': '平安银行',
    'com.abchina.banking': '农业银行',
    'com.android.bankabc': '农业银行',
    'com.chinamworld.bocmbci': '中国银行',
    'com.psbc.mobilebank': '邮储银行',
    'com.cmbc.mobilebank': '民生银行',
    'com.cib.mobilebank': '兴业银行',
    'com.spdb.mbank': '浦发银行',
    'com.cebbank.mobilebank': '光大银行',
    'com.cgbchina.xpt': '广发银行',
  };

  /// 营销 / 活动 / 非交易噪音：命中即忽略
  static final RegExp _noise = RegExp(
    r'优惠券|立减金|折扣|积分|能量|蚂蚁森林|蚂蚁庄园|芭芭农场|签到|抽奖|'
    r'恭喜您?获得|点击领取|红包封面|额度提升|提额|新客|福利|金币|集分宝|待领取',
  );

  /// 方向判定规则（**有序**，先命中先生效）。
  /// 顺序设计：收款专用词 → 支出词 → 银行收入词，避免「付款通知里的
  /// 收款方」「付款成功…到账」这类文案被反向误判。
  static final List<(RegExp, String)> _directionRules = [
    (RegExp(r'收款到账|收款成功|转账收款|收到.{0,6}转账|向你转账|已收款|收款通知|二维码收款'), 'income'),
    (RegExp(r'付款|支付成功|支付金额|微信支付凭证|消费|支出|扣款|代扣|取现|缴费|快捷支付|转出'), 'expense'),
    (RegExp(r'存入|入账|工资|退款|返现|利息|收入|转入|到账|收益'), 'income'),
  ];

  /// 金额提取（按优先级依次尝试）
  static final List<RegExp> _amountPatterns = [
    RegExp(r'[¥￥]\s?(\d{1,3}(?:,\d{3})+(?:\.\d{1,2})?|\d+(?:\.\d{1,2})?)'),
    RegExp(
        r'人民币\s?(\d{1,3}(?:,\d{3})+(?:\.\d{1,2})?|\d+(?:\.\d{1,2})?)\s?元'),
    RegExp(
        r'(?:金额|收款|付款|消费|支出|收入|存入|转入|转出|到账|扣款|代扣|取现|缴费|退款|工资)'
        r'\s?[:：]?\s?(\d{1,3}(?:,\d{3})+(?:\.\d{1,2})?|\d+(?:\.\d{1,2})?)\s?元'),
  ];

  /// 商户 / 对方提取（按优先级依次尝试）
  static final List<RegExp> _merchantPatterns = [
    RegExp(r'收款方[：:\s]?([^\n，,。；;]{1,30})'),
    RegExp(r'付款方[：:\s]?([^\n，,。；;]{1,30})'),
    RegExp(r'交易对方[：:\s]?([^\n，,。；;]{1,30})'),
    RegExp(r'商户全称[：:\s]?([^\n，,。；;]{1,30})'),
    RegExp(r'商户名称[：:\s]?([^\n，,。；;]{1,30})'),
    RegExp(r'商户[：:\s]?([^\n，,。；;]{1,30})'),
    RegExp(r'(?:向|给)\s?([^\n，,。；;]{1,20}?)\s?(?:付款|转账)'),
    RegExp(r'在\s?([^\n，,。；;]{1,20}?)\s?(?:消费|购物|交易)'),
    RegExp(r'(?:附言|摘要|用途)[：:\s]?([^\n，,。；;]{1,30})'),
  ];

  /// 交易时间提取：「1月2日12:30」「1月2日12时30分」「01-02 12:30」
  static final List<RegExp> _timePatterns = [
    RegExp(r'(\d{1,2})\s?月\s?(\d{1,2})\s?[日号]?\s*(\d{1,2})\s?[:时]\s?(\d{1,2})'),
    RegExp(r'(\d{1,2})-(\d{1,2})\s+(\d{1,2}):(\d{2})'),
  ];

  /// 金额合理上限（防止把卡号 / 余额串误当金额）
  static const double _maxAmount = 9999999.99;

  // ── 主入口 ─────────────────────────────────────────────────

  /// 解析一条通知；无法解析 / 应忽略时返回 null。
  static ParsedBillDraft? parse({
    required String packageName,
    required String title,
    required String text,
    required DateTime postTime,
  }) {
    final sourceApp = knownPackages[packageName];
    if (sourceApp == null) return null; // 非白名单来源，不碰

    final content = '$title\n$text'.trim();
    if (content.isEmpty) return null;
    if (_noise.hasMatch(content)) return null;

    final type = _detectDirection(content);
    if (type == null) return null;

    final amount = _extractAmount(content);
    if (amount == null || amount <= 0 || amount > _maxAmount) return null;

    final merchant = _extractMerchant(content);
    final time = _extractTime(content, postTime) ?? postTime;

    final raw = content.length > 120 ? content.substring(0, 120) : content;

    return ParsedBillDraft(
      packageName: packageName,
      sourceApp: sourceApp,
      amount: amount,
      type: type,
      merchant: merchant,
      time: time,
      rawText: raw,
      fingerprint: fingerprint(packageName, amount, time),
    );
  }

  /// 去重指纹：包名 + 金额 + 分钟级时间。
  /// 同一笔交易的重复推送（重发 / 展开态二次回调）指纹相同。
  static String fingerprint(String packageName, double amount, DateTime time) {
    final minute = time.millisecondsSinceEpoch ~/ 60000;
    return '$packageName|${amount.toStringAsFixed(2)}|$minute';
  }

  // ── 方向 ───────────────────────────────────────────────────

  static String? _detectDirection(String content) {
    for (final (re, type) in _directionRules) {
      if (re.hasMatch(content)) return type;
    }
    return null;
  }

  // ── 金额 ───────────────────────────────────────────────────

  static double? _extractAmount(String content) {
    for (final re in _amountPatterns) {
      final m = re.firstMatch(content);
      if (m == null) continue;
      final raw = m.group(1)!.replaceAll(',', '');
      final v = double.tryParse(raw);
      if (v != null) return v;
    }
    return null;
  }

  // ── 商户 ───────────────────────────────────────────────────

  static String _extractMerchant(String content) {
    for (final re in _merchantPatterns) {
      final m = re.firstMatch(content);
      if (m == null) continue;
      var v = m.group(1)!.trim();
      // 去掉尾部残余标点
      v = v.replaceAll(RegExp(r'[，,。；;：:\s]+$'), '');
      if (v.isNotEmpty) return v;
    }
    return '';
  }

  // ── 时间 ───────────────────────────────────────────────────

  static DateTime? _extractTime(String content, DateTime postTime) {
    for (final re in _timePatterns) {
      final m = re.firstMatch(content);
      if (m == null) continue;
      final month = int.tryParse(m.group(1)!);
      final day = int.tryParse(m.group(2)!);
      final hour = int.tryParse(m.group(3)!);
      final minute = int.tryParse(m.group(4)!);
      if (month == null || day == null || hour == null || minute == null) {
        continue;
      }
      if (month < 1 || month > 12 || day < 1 || day > 31 || hour > 23 || minute > 59) {
        continue;
      }
      try {
        var t = DateTime(postTime.year, month, day, hour, minute);
        // 通知正文一般不带年份：若拼出来的时间比通知时间晚一天以上，
        // 说明是去年底的流水，回退一年
        if (t.isAfter(postTime.add(const Duration(days: 1)))) {
          t = DateTime(postTime.year - 1, month, day, hour, minute);
        }
        return t;
      } catch (_) {
        continue;
      }
    }
    return null;
  }

  // ── 分类智能默认（关键词 → 常见分类名）─────────────────────
  //
  // 产出的是「分类名候选」，由页面侧在当前账本的分类列表里按名称匹配，
  // 匹配不上再回退「最近使用 / 第一个」。

  static const Map<String, List<String>> _categoryKeywords = {
    '转账': ['转账', '还款', '信用卡还款'],
    '餐饮': [
      '餐', '饭', '美食', '肯德基', '麦当劳', '星巴克', '瑞幸', '咖啡', '奶茶',
      '美团', '饿了么', '外卖', '火锅', '烧烤', '食堂', '汉堡', '披萨', '餐厅',
      '小吃', '早点', '早餐', '必胜客', '喜茶', '奈雪', '蜜雪',
    ],
    '购物': [
      '超市', '便利店', '商场', '百货', '淘宝', '天猫', '京东', '拼多多', '购物',
      '商贸', '商店', '罗森', '全家', '物美', '永辉', '盒马', '山姆', '服装',
      '优衣库', '屈臣氏', '名创',
    ],
    '交通': [
      '地铁', '公交', '滴滴', '打车', '出行', '加油', '停车', '高铁', '火车',
      '机票', '航空', 'ETC', '出租车', '网约车', '哈啰', '青桔', '摩拜', '12306',
    ],
    '住房': ['房租', '物业', '水费', '电费', '燃气', '宽带', '供暖'],
    '通讯': ['话费', '移动营业厅', '联通', '电信', '充值'],
    '娱乐': ['电影', '游戏', 'KTV', '爱奇艺', '腾讯视频', '优酷', '哔哩', '音乐', '演出'],
    '医疗': ['医院', '药店', '药房', '门诊', '诊所', '体检', '医药'],
    '教育': ['学费', '培训', '课程', '书店', '教辅'],
    '工资': ['工资', '薪资', '奖金', '劳务费'],
  };

  /// 根据商户 + 原文猜测分类名；猜不到返回 null。
  static String? suggestCategory(ParsedBillDraft draft) {
    final hay = '${draft.merchant}\n${draft.rawText}';
    for (final entry in _categoryKeywords.entries) {
      for (final kw in entry.value) {
        if (hay.contains(kw)) return entry.key;
      }
    }
    return null;
  }
}
