import '../models/category.dart';

/// 一段任意中文文本解析成"准备好填进 AddBillScreen 的草稿"。
/// 语音 和 OCR 用同一套规则，所有逻辑都是纯 Dart，可单测。
///
/// 例子：
///   "在沃尔玛买菜花了 89.5 块"        → expense / 89.5 / 餐饮 or 购物
///   "工资到账 12000"                   → income  / 12000 / 工资
///   "打车回家 23"                      → expense / 23   / 交通
///   "星巴克 ¥38.00"                    → expense / 38   / 餐饮（咖啡）
class BillDraft {
  final String type;             // 'expense' | 'income'
  final double? amount;          // 解析失败为 null
  final Category? category;      // 匹配不上为 null（让用户自己选）
  final String note;             // 原始文本，去掉首尾空白
  final String rawText;          // 原始未加工文本（debug / 显示给用户看）

  const BillDraft({
    required this.type,
    required this.amount,
    required this.category,
    required this.note,
    required this.rawText,
  });
}

class BillParser {
  /// 收入关键词（命中任意一个就视作 income）
  static const _incomeKeywords = <String>[
    '工资', '到账', '收入', '收到', '入账', '转入', '退款', '红包', '报销',
    '奖金', '提成', '分红', '利息', '退税', '兼职',
  ];

  /// 一级分类关键词字典 —— key 是分类名（必须能匹配后端预置一级分类）
  /// 注：匹配是"子串包含"，按顺序短路；所以更具体的关键词放前面
  static const Map<String, List<String>> _expenseDict = {
    '餐饮': [
      '吃', '喝', '餐', '饭', '早餐', '午餐', '晚餐', '夜宵', '外卖', '点单',
      '咖啡', '奶茶', '星巴克', '瑞幸', '麦当劳', '肯德基', 'kfc', '汉堡', '披萨',
      '火锅', '烧烤', '酒水', '啤酒', '果汁', '便当', '盒饭',
    ],
    '交通': [
      '打车', '滴滴', '出租', '地铁', '公交', '高铁', '动车', '飞机', '机票',
      '加油', '油费', '停车', '过路费', '高速', '车票', '船票', '快车',
    ],
    '购物': [
      '买', '购买', '淘宝', '京东', '拼多多', '天猫', '超市', '沃尔玛', '永辉',
      '便利店', '罗森', '7-11', '商场', '专卖店',
    ],
    '服饰': [
      '衣服', '裤子', '鞋', '帽子', '袜子', '内衣', '羽绒服', '外套',
      '优衣库', 'zara', 'hm', 'uniqlo',
    ],
    '居住': [
      '房租', '物业', '水费', '电费', '燃气', '煤气', '宽带', '网费',
      '维修', '装修', '家具',
    ],
    '娱乐': [
      '电影', '游戏', 'KTV', '唱歌', '剧本杀', '密室', '展览', '演唱会',
      '门票', 'steam', '订阅',
    ],
    '医疗': [
      '医院', '看病', '挂号', '药', '体检', '药店', '门诊', '住院', '牙医',
    ],
    '教育': [
      '学费', '书', '书店', '当当', '培训', '课程', '考试', '资料',
    ],
    '通讯': [
      '话费', '流量', '充值', '宽带费', '套餐', '手机费',
    ],
    '宠物': [
      '猫', '狗', '宠物', '猫粮', '狗粮', '驱虫', '疫苗',
    ],
    '人情': [
      '红包', '送礼', '随礼', '份子', '请客',
    ],
  };

  static const Map<String, List<String>> _incomeDict = {
    '工资': ['工资', '薪水', '月薪', '到账', '入账'],
    '奖金': ['奖金', '年终', '绩效', '提成'],
    '理财': ['利息', '分红', '理财', '基金', '股票'],
    '兼职': ['兼职', '副业', '稿费'],
    '红包': ['红包', '过年钱', '压岁钱'],
    '报销': ['报销', '退款', '退税'],
    '退款': ['退款', '退货'],
  };

  /// 主入口：输入一段文本 + 当前账本可用分类列表，返回草稿
  static BillDraft parse(String text, List<Category> categories) {
    final raw = text.trim();
    if (raw.isEmpty) {
      return BillDraft(
        type: 'expense',
        amount: null,
        category: null,
        note: '',
        rawText: raw,
      );
    }

    final type = _detectType(raw);
    final amount = _extractAmount(raw);
    final category = _matchCategory(raw, type, categories);

    return BillDraft(
      type: type,
      amount: amount,
      category: category,
      note: raw,
      rawText: raw,
    );
  }

  /// 判断收 / 支
  static String _detectType(String text) {
    final lower = text.toLowerCase();
    for (final kw in _incomeKeywords) {
      if (lower.contains(kw.toLowerCase())) return 'income';
    }
    return 'expense';
  }

  /// 从文本里抠出金额。
  /// 优先级：
  ///   1. ¥ / 元 / 块 紧邻数字
  ///   2. "合计/总计/应付/小计/Total/Amount Due" 等关键词后面的数字（OCR 小票）
  ///   3. 文本里最大的那个带小数的数字
  ///   4. 文本里最大的那个整数
  static double? _extractAmount(String text) {
    final candidates = <double>[];

    // 1. 带货币符号的（最强信号）
    final symRe = RegExp(
      r'(?:¥|￥|\$|RMB|CNY|元|块)\s*([0-9]+(?:\.[0-9]{1,2})?)'
      r'|([0-9]+(?:\.[0-9]{1,2})?)\s*(?:元|块|RMB|CNY)',
      caseSensitive: false,
    );
    for (final m in symRe.allMatches(text)) {
      final s = m.group(1) ?? m.group(2);
      final v = double.tryParse(s ?? '');
      if (v != null && v > 0) return v;
    }

    // 2. 小票关键词附近的金额
    final receiptRe = RegExp(
      r'(?:合计|总计|应付|实付|小计|应收|金额|总额|TOTAL|AMOUNT|SUBTOTAL)'
      r'[^0-9]{0,6}([0-9]+(?:\.[0-9]{1,2})?)',
      caseSensitive: false,
    );
    for (final m in receiptRe.allMatches(text)) {
      final v = double.tryParse(m.group(1) ?? '');
      if (v != null && v > 0) candidates.add(v);
    }
    if (candidates.isNotEmpty) {
      candidates.sort();
      return candidates.last; // 通常合计是最大的
    }

    // 3. 文本里所有"数字.数字"，取最大
    final decRe = RegExp(r'(\d+\.\d{1,2})');
    for (final m in decRe.allMatches(text)) {
      final v = double.tryParse(m.group(1) ?? '');
      if (v != null && v > 0) candidates.add(v);
    }
    if (candidates.isNotEmpty) {
      candidates.sort();
      return candidates.last;
    }

    // 4. 文本里所有整数，取最大（< 1,000,000，过滤年份/电话）
    final intRe = RegExp(r'(?<![\d.])(\d{1,6})(?![\d.])');
    for (final m in intRe.allMatches(text)) {
      final v = double.tryParse(m.group(1) ?? '');
      if (v != null && v > 0 && v < 1000000) candidates.add(v);
    }
    if (candidates.isNotEmpty) {
      candidates.sort();
      return candidates.last;
    }

    return null;
  }

  /// 从分类列表里挑一个最匹配的（按关键词字典 + 模糊命中）
  static Category? _matchCategory(
    String text,
    String type,
    List<Category> categories,
  ) {
    if (categories.isEmpty) return null;
    final lower = text.toLowerCase();
    final dict = type == 'income' ? _incomeDict : _expenseDict;

    final ofType = categories.where((c) => c.type == type).toList();
    if (ofType.isEmpty) return null;

    // 1. 直接命名命中（用户文本里直接说出了"餐饮""购物"这种分类名）
    for (final c in ofType) {
      if (lower.contains(c.name.toLowerCase())) return c;
    }

    // 2. 字典关键词命中 → 找到分类名 → 在 ofType 里找名字匹配的
    for (final entry in dict.entries) {
      final catName = entry.key;
      for (final kw in entry.value) {
        if (lower.contains(kw.toLowerCase())) {
          // 优先一级分类匹配（避免无意中挑到某个子分类）
          final root = ofType.firstWhere(
            (c) => c.isRoot && c.name == catName,
            orElse: () => ofType.firstWhere(
              (c) => c.name == catName,
              orElse: () => Category(id: '', name: '', type: type),
            ),
          );
          if (root.id.isNotEmpty) return root;
        }
      }
    }

    return null;
  }
}
