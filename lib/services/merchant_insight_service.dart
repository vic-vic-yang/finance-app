import '../crypto/key_chain.dart';
import '../models/bill.dart';
import '../models/category.dart';
import '../models/reconcile_report.dart';
import 'api_service.dart';
import 'auth_service.dart';
import 'merchant_analytics.dart';
import 'pending_dek_resolver.dart';

/// ======================================================================
/// 商户画像 · 数据装载层
/// ======================================================================
///
/// 端侧隐私 AI：只从服务端拉账单（note 仍是 E2E 密文），解密与全部统计
/// 都在本机完成，备注明文不会离开设备。纯计算见 merchant_analytics.dart。
class MerchantInsightService {
  /// 单页拉取条数（分页循环覆盖时间窗）
  static const int _pageSize = 100;

  /// 防御上限：最多拉取 2000 条支出账单
  static const int _maxBills = 2000;

  /// 拉取当前账本近 3 个自然月的支出账单，本地解密 + 计算商户画像。
  static Future<MerchantInsightsReport> load() async {
    final ledgerId = await AuthService.getCurrentLedgerId();
    if (ledgerId == null || ledgerId.isEmpty) {
      throw ApiException(401, '尚未选择账本');
    }
    if (!KeyChain.instance.hasDek(ledgerId)) {
      await PendingDekResolver.rehydrate(requireLedgerId: ledgerId);
    }

    final now = DateTime.now();
    final start = DateTime(now.year, now.month - 2, 1);
    final startStr =
        '${start.year}-${start.month.toString().padLeft(2, '0')}-01';

    // 分类列表（明文）与账单并行拉
    final catsFuture = ApiService.getCategories();

    // 分页循环，直到覆盖时间窗（type=expense 时后端已排除转账与股票盈亏，
    // 本地仍再过滤一次做防御）
    final bills = <Bill>[];
    var page = 1;
    while (bills.length < _maxBills) {
      final res = await ApiService.getBills(
        page: page,
        limit: _pageSize,
        type: 'expense',
        startDate: startStr,
      );
      final list = (res['bills'] as List? ?? [])
          .whereType<Map<String, dynamic>>()
          .map(Bill.fromJson)
          .toList();
      bills.addAll(list);
      final total =
          (res['pagination']?['total'] as num?)?.toInt() ?? bills.length;
      if (list.length < _pageSize || bills.length >= total) break;
      page++;
    }

    final catsRes = await catsFuture;
    final catNames = <String, String>{
      for (final j in (catsRes['categories'] as List? ?? [])
          .whereType<Map<String, dynamic>>())
        j['id'] as String: Category.fromJson(j).fullName,
    };

    // 本地解密备注 → 提取商户（解密逻辑同 ReconcileItem.noteOf：
    // dekVer==0 为服务端明文 UTF-8；<48 字节视为空备注）
    final inputs = <MerchantBillInput>[
      for (final b in bills)
        if (!b.isTransfer && b.source != 'stock')
          MerchantBillInput(
            merchant: extractMerchant(
              ReconcileItem.noteOf(ledgerId, b.noteCipher, b.noteDekVer),
            ),
            amount: b.amount,
            categoryId: b.category.id,
            date: b.date,
          ),
    ];

    return buildMerchantInsights(inputs, now: now, categoryNames: catNames);
  }
}
