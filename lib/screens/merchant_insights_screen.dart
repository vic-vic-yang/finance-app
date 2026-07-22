import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../core/theme.dart';
import '../services/merchant_analytics.dart';
import '../services/merchant_insight_service.dart';
import '../widgets/siku_ui.dart';

/// 商户画像页（端侧隐私 AI）
///
/// 所有计算在手机本机完成：账单 note 是 E2E 密文，服务端永远看不到明文；
/// 解密与商户统计全部在本机进行，备注明文不会上传到服务器。
///
/// 五个区块：
///   1. 隐私说明卡（🔒 本地计算）
///   2. 本月商户 TOP10 榜（排名 / 金额 / 笔数 / 金额条）
///   3. 常客商户（近 3 个自然月每月都出现）
///   4. 新面孔（本月首次出现）
///   5. 依赖预警（商户占其分类本月支出 > 40% 且金额 > 200 元）
class MerchantInsightsScreen extends StatefulWidget {
  const MerchantInsightsScreen({super.key});

  @override
  State<MerchantInsightsScreen> createState() => _MerchantInsightsScreenState();
}

class _MerchantInsightsScreenState extends State<MerchantInsightsScreen> {
  MerchantInsightsReport? _data;
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    try {
      final data = await MerchantInsightService.load();
      if (!mounted) return;
      setState(() {
        _data = data;
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() => _loading = false);
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text('加载失败：$e')));
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.bg,
      appBar: const AuraAppBar(title: '商户画像'),
      body: AuraBackground(
        child: _loading
            ? const Center(child: CircularProgressIndicator())
            : RefreshIndicator(
                onRefresh: _load,
                child: _data == null || _data!.isEmpty
                    ? ListView(
                        padding: const EdgeInsets.fromLTRB(20, 12, 20, 40),
                        children: const [
                          EmptyState(
                            emoji: '🏪',
                            title: '近 3 个月还没有支出账单',
                            hint: '记几笔带备注的支出后，这里会生成你的商户画像。',
                          ),
                        ],
                      )
                    : _buildBody(_data!),
              ),
      ),
    );
  }

  Widget _buildBody(MerchantInsightsReport r) {
    return ListView(
      padding: const EdgeInsets.fromLTRB(20, 12, 20, 40),
      children: [
        _privacyCard(),
        const SizedBox(height: 10),
        _methodologyNote(r),
        SectionHeader(
          title: '${DateFormat('M月').format(r.generatedAt)}商户 TOP 榜',
          horizontal: 0,
          top: 20,
        ),
        _topSection(r.topMerchants),
        SectionHeader(
          title: '常客商户',
          horizontal: 0,
          top: 20,
          trailing: Text('近 3 个月每月都出现',
              style: TextStyle(fontSize: 11.5, color: AppColors.text3)),
        ),
        _regularsSection(r.regulars),
        SectionHeader(
          title: '新面孔',
          horizontal: 0,
          top: 20,
          trailing: Text('本月首次出现',
              style: TextStyle(fontSize: 11.5, color: AppColors.text3)),
        ),
        _newcomersSection(r.newcomers),
        SectionHeader(
          title: '依赖预警',
          horizontal: 0,
          top: 20,
          trailing: Text('占分类支出 > 40%',
              style: TextStyle(fontSize: 11.5, color: AppColors.text3)),
        ),
        _alertsSection(r.alerts),
      ],
    );
  }

  // ── 1) 隐私说明卡 ───────────────────────────────────────────
  Widget _privacyCard() {
    return GlassCard(
      radius: 16,
      padding: const EdgeInsets.all(16),
      child: Row(
        children: [
          Container(
            width: 40,
            height: 40,
            decoration: BoxDecoration(
              color: AppColors.primaryLight,
              borderRadius: BorderRadius.circular(10),
            ),
            alignment: Alignment.center,
            child: const Text('🔒', style: TextStyle(fontSize: 20)),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '全部在你的手机上计算',
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                    color: AppColors.text1,
                  ),
                ),
                const SizedBox(height: 3),
                Text(
                  '商户画像全部在你的手机上计算，备注明文不会上传到服务器。',
                  style: TextStyle(
                      fontSize: 12, height: 1.4, color: AppColors.text2),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  /// 口径说明小字
  Widget _methodologyNote(MerchantInsightsReport r) {
    return Text(
      '统计口径：${DateFormat('yyyy年M月').format(r.windowStart)}起近 3 个自然月支出（不含转账与股票纸面盈亏），共 ${r.expenseBillCount} 笔；商户取备注「商户:商品」的第一段。',
      style: TextStyle(fontSize: 11, height: 1.5, color: AppColors.text3),
    );
  }

  // ── 2) 本月商户 TOP 榜 ─────────────────────────────────────
  Widget _topSection(List<MerchantStat> top) {
    if (top.isEmpty) {
      return _hintCard('🧾', '本月还没有支出记录', '记账后这里会出现本月消费最多的商户。');
    }
    final max = top.first.monthAmount;
    return Column(
      children: [
        for (var i = 0; i < top.length; i++) ...[
          _topTile(rank: i + 1, s: top[i], max: max),
          const SizedBox(height: 10),
        ],
      ],
    );
  }

  Widget _topTile({
    required int rank,
    required MerchantStat s,
    required double max,
  }) {
    final ratio = max > 0 ? (s.monthAmount / max).clamp(0.0, 1.0) : 0.0;
    return GlassCard(
      radius: 14,
      padding: const EdgeInsets.all(14),
      child: Row(
        children: [
          Container(
            width: 28,
            height: 28,
            decoration: BoxDecoration(
              color: rank <= 3 ? AppColors.primary : AppColors.surfaceAlt,
              borderRadius: BorderRadius.circular(8),
            ),
            alignment: Alignment.center,
            child: Text(
              '$rank',
              style: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w700,
                color: rank <= 3 ? AppColors.onPrimary : AppColors.text2,
              ),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  s.merchant,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w600,
                    color: AppColors.text1,
                  ),
                ),
                const SizedBox(height: 6),
                ClipRRect(
                  borderRadius: BorderRadius.circular(10),
                  child: LinearProgressIndicator(
                    value: ratio,
                    minHeight: 6,
                    backgroundColor: AppColors.surfaceAlt,
                    valueColor: AlwaysStoppedAnimation(AppColors.primary),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 12),
          Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              AmountText(
                -s.monthAmount,
                size: AmountSize.list,
                tone: AmountTone.expense,
                showSign: true,
              ),
              const SizedBox(height: 3),
              Text('${s.monthCount} 笔',
                  style: TextStyle(fontSize: 11.5, color: AppColors.text3)),
            ],
          ),
        ],
      ),
    );
  }

  // ── 3) 常客商户 ─────────────────────────────────────────────
  Widget _regularsSection(List<MerchantStat> regulars) {
    if (regulars.isEmpty) {
      return _hintCard('🔁', '暂时没有常客商户', '同一商户连续 3 个月都消费后会出现在这里。');
    }
    return Column(
      children: [
        for (final s in regulars) ...[
          _merchantTile(
            s: s,
            icon: '🔁',
            amount: s.totalAmount,
            subtitle: '近 3 个月 ¥${formatAmount(s.totalAmount, decimals: 0)} · 每月都出现',
          ),
          const SizedBox(height: 10),
        ],
      ],
    );
  }

  // ── 4) 新面孔 ───────────────────────────────────────────────
  Widget _newcomersSection(List<MerchantStat> newcomers) {
    if (newcomers.isEmpty) {
      return _hintCard('✨', '本月没有新商户', '本月消费的商户在前两个月都出现过。');
    }
    return Column(
      children: [
        for (final s in newcomers) ...[
          _merchantTile(
            s: s,
            icon: '✨',
            amount: s.monthAmount,
            subtitle: '本月 ¥${formatAmount(s.monthAmount, decimals: 0)} · ${s.monthCount} 笔',
          ),
          const SizedBox(height: 10),
        ],
      ],
    );
  }

  Widget _merchantTile({
    required MerchantStat s,
    required String icon,
    required double amount,
    required String subtitle,
  }) {
    return GlassCard(
      radius: 14,
      padding: const EdgeInsets.all(14),
      child: Row(
        children: [
          Container(
            width: 40,
            height: 40,
            decoration: BoxDecoration(
              color: AppColors.primaryLight,
              borderRadius: BorderRadius.circular(10),
            ),
            alignment: Alignment.center,
            child: Text(icon, style: const TextStyle(fontSize: 20)),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  s.merchant,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w600,
                    color: AppColors.text1,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  subtitle,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(fontSize: 12, color: AppColors.text2),
                ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          AmountText(
            -amount,
            size: AmountSize.list,
            tone: AmountTone.expense,
            showSign: true,
          ),
        ],
      ),
    );
  }

  // ── 5) 依赖预警 ─────────────────────────────────────────────
  Widget _alertsSection(List<DependencyAlert> alerts) {
    if (alerts.isEmpty) {
      return _hintCard('🛡️', '本月没有依赖预警', '没有哪家商户占据某个分类支出的 40% 以上。');
    }
    return Column(
      children: [
        for (final a in alerts) ...[
          _alertTile(a),
          const SizedBox(height: 10),
        ],
      ],
    );
  }

  Widget _alertTile(DependencyAlert a) {
    final pct = (a.ratio * 100).toStringAsFixed(0);
    return GlassCard(
      radius: 14,
      padding: const EdgeInsets.all(14),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 3,
            height: 44,
            margin: const EdgeInsets.only(top: 2),
            decoration: BoxDecoration(
              color: AppColors.warning,
              borderRadius: BorderRadius.circular(2),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  a.merchant,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w600,
                    color: AppColors.text1,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  '占「${a.categoryName}」本月支出 $pct%（¥${formatAmount(a.merchantAmount, decimals: 0)} / ¥${formatAmount(a.categoryAmount, decimals: 0)}），消费较依赖单一商户',
                  style: TextStyle(
                      fontSize: 12, height: 1.4, color: AppColors.text2),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  // ── 空区块提示 ───────────────────────────────────────────────
  Widget _hintCard(String emoji, String title, String hint) {
    return GlassCard(
      radius: 14,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 18),
      child: Row(
        children: [
          Text(emoji, style: const TextStyle(fontSize: 24)),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title,
                    style: TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w600,
                        color: AppColors.text1)),
                const SizedBox(height: 3),
                Text(hint,
                    style: TextStyle(
                        fontSize: 12, height: 1.4, color: AppColors.text3)),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
