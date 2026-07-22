import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../core/theme.dart';
import '../crypto/key_chain.dart';
import '../models/account.dart';
import '../models/category.dart';
import '../services/api_service.dart';
import '../services/auth_service.dart';
import '../services/forecast_service.dart';
import '../widgets/siku_ui.dart';

/// 现金流预测页
///
/// 四块内容（数据全部来自 GET /api/forecast）：
///   1. 月末净资产预测大卡（hero 金额 + 口径说明）
///   2. 未来 30 天周期扣款列表（备注密文本地解密）
///   3. 支出速率与超支预警（本月至今 vs 上月同期 vs 当月总预算）
///   4. 目标达成预测（按近 90 天月均净存入外推）
class ForecastScreen extends StatefulWidget {
  const ForecastScreen({super.key});

  @override
  State<ForecastScreen> createState() => _ForecastScreenState();
}

class _ForecastScreenState extends State<ForecastScreen> {
  CashflowForecast? _data;
  bool _loading = true;
  String? _ledgerId;
  Map<String, Category> _catById = {};
  Map<String, Account> _accById = {};

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    try {
      final futures = await Future.wait([
        ForecastService.getForecast(),
        ApiService.getCategories(),
        ApiService.getAccounts(),
        AuthService.getUser(),
      ]);
      final catsRes = futures[1] as Map<String, dynamic>;
      final accsRes = futures[2] as Map<String, dynamic>;
      final cats = (catsRes['categories'] as List? ?? [])
          .map((j) => Category.fromJson(j as Map<String, dynamic>))
          .toList();
      final accs = (accsRes['accounts'] as List? ?? [])
          .map((j) => Account.fromJson(j as Map<String, dynamic>))
          .toList();
      if (!mounted) return;
      setState(() {
        _data = futures[0] as CashflowForecast;
        _catById = {for (final c in cats) c.id: c};
        _accById = {for (final a in accs) a.id: a};
        _ledgerId = (futures[3] as Map<String, dynamic>?)?['currentLedgerId']
            as String?;
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() => _loading = false);
      _toast('加载失败：$e');
    }
  }

  void _toast(String s) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(s)));
  }

  String _decrypt(String? cipher, int? dekVer, String fallback) {
    if (cipher == null || cipher.isEmpty || dekVer == null) return fallback;
    final ledgerId = _ledgerId;
    if (ledgerId == null || ledgerId.isEmpty) return fallback;
    final plain = KeyChain.instance.decryptText(
      ledgerId: ledgerId,
      cipherBase64: cipher,
      dekVer: dekVer,
      systemFallback: fallback,
    );
    return plain.isEmpty ? fallback : plain;
  }

  /// 自然日差（忽略时分秒，避免「今晚 vs 明早 9 点」被算成 0 天）
  int _daysUntil(DateTime d) {
    final now = DateTime.now();
    return DateTime(d.year, d.month, d.day)
        .difference(DateTime(now.year, now.month, now.day))
        .inDays;
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.bg,
      appBar: const AuraAppBar(title: '现金流预测'),
      body: AuraBackground(
        child: _loading
            ? const Center(child: CircularProgressIndicator())
            : _data == null
                ? const EmptyState(
                    emoji: '🔮',
                    title: '暂时没有预测数据',
                    hint: '下拉重试，或先记几笔账。',
                  )
                : RefreshIndicator(
                    onRefresh: _load,
                    child: ListView(
                      padding: const EdgeInsets.fromLTRB(20, 12, 20, 40),
                      children: [
                        _heroCard(_data!.monthEnd),
                        const SizedBox(height: 10),
                        _methodologyNote(_data!.monthEnd),
                        SectionHeader(
                          title: '未来 30 天扣款',
                          horizontal: 0,
                          top: 20,
                        ),
                        _upcomingSection(_data!.upcoming30),
                        SectionHeader(
                          title: '支出速率',
                          horizontal: 0,
                          top: 20,
                        ),
                        _paceSection(_data!.pace),
                        SectionHeader(
                          title: '目标达成预测',
                          horizontal: 0,
                          top: 20,
                        ),
                        _goalSection(_data!.goals),
                      ],
                    ),
                  ),
      ),
    );
  }

  // ── 1) 月末净资产预测大卡 ────────────────────────────────────
  Widget _heroCard(MonthEndNetWorth m) {
    final onCard = AppColors.onPrimaryGradient;
    final delta = m.projected - m.current;
    return Container(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: AppColors.primaryGradient,
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(18),
        boxShadow: AppTheme.ambientShadow(
            opacity: 0.16, blur: 36, offset: const Offset(0, 16)),
      ),
      padding: const EdgeInsets.fromLTRB(22, 22, 22, 20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  '月末净资产预测',
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                    letterSpacing: 0.4,
                    color: onCard.withValues(alpha: 0.75),
                  ),
                ),
              ),
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                decoration: BoxDecoration(
                  color: onCard.withValues(alpha: 0.14),
                  borderRadius: BorderRadius.circular(20),
                ),
                child: Text(
                  '${delta >= 0 ? '↗' : '↘'} 较今日 ${delta >= 0 ? '+' : '−'}¥${formatAmount(delta.abs(), decimals: 0)}',
                  style: TextStyle(
                    fontSize: 11.5,
                    fontWeight: FontWeight.w600,
                    color: onCard,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          AmountText(m.projected,
              size: AmountSize.hero, decimals: 0, color: onCard),
          const SizedBox(height: 14),
          _heroBreakdownRow('当前净资产', m.current, onCard),
          if (m.isMonthly) ...[
            const SizedBox(height: 6),
            _heroBreakdownRow(
              '预计剩余收入（固定收入未到账部分）',
              m.remainingIncome ?? 0,
              onCard,
            ),
            const SizedBox(height: 6),
            _heroBreakdownRow(
              '预计剩余支出（剩余 ${m.remainingDays} 天）',
              -(m.remainingExpense ?? 0),
              onCard,
            ),
          ] else ...[
            const SizedBox(height: 6),
            _heroBreakdownRow(
              '日均净流入 × 剩余 ${m.remainingDays} 天',
              m.avgDailyNetInflow * m.remainingDays,
              onCard,
            ),
            const SizedBox(height: 6),
            _heroBreakdownRow('本月剩余周期账单净额', m.remainingRecurringNet, onCard),
          ],
        ],
      ),
    );
  }

  Widget _heroBreakdownRow(String label, double value, Color onCard) {
    return Row(
      children: [
        Expanded(
          child: Text(
            label,
            style: TextStyle(
                fontSize: 12, color: onCard.withValues(alpha: 0.65)),
          ),
        ),
        Text(
          '${value >= 0 ? '+' : '−'}¥${formatAmount(value.abs(), decimals: 0)}',
          style: TextStyle(
            fontSize: 12,
            fontWeight: FontWeight.w600,
            color: onCard.withValues(alpha: 0.9),
          ),
        ),
      ],
    );
  }

  /// 口径说明小字
  Widget _methodologyNote(MonthEndNetWorth m) {
    final text = m.isMonthly
        ? '预测口径：当前净资产 ＋ 预计剩余收入 − 预计剩余支出。'
            '收入按近 ${m.monthsSampled} 个完整月识别出的固定收入项（同分类同金额）是否到账来预期，一次性收入不计；'
            '支出按历史月均与本月节奏取大者。均不含转账与股票纸面盈亏。'
        : '预测口径：当前净资产 ＋ 本月剩余天数 × 近 30 日日均净流入 ＋ 本月剩余周期账单净额；收支均不含转账与股票纸面盈亏。'
            '（暂无完整月历史，累积数据后将切换为月度模式预测）';
    return Text(
      text,
      style: TextStyle(fontSize: 11, height: 1.5, color: AppColors.text3),
    );
  }

  // ── 2) 未来 30 天扣款 ───────────────────────────────────────
  Widget _upcomingSection(List<UpcomingPayment> items) {
    if (items.isEmpty) {
      return _hintCard('🗓️', '未来 30 天没有周期扣款', '在「周期账单」里添加房租、订阅后会出现在这里。');
    }
    return Column(
      children: [
        for (final p in items) ...[
          _upcomingTile(p),
          const SizedBox(height: 10),
        ],
      ],
    );
  }

  Widget _upcomingTile(UpcomingPayment p) {
    final cat = _catById[p.categoryId];
    final acc = _accById[p.accountId];
    final note = _decrypt(p.noteCipher, p.noteDekVer, '');
    final title = note.isNotEmpty ? note : (cat?.fullName ?? '未分类');

    final days = _daysUntil(p.nextDate);
    final String when;
    final Color whenColor;
    if (days < 0) {
      when = '已逾期 ${-days} 天';
      whenColor = AppColors.danger;
    } else if (days == 0) {
      when = '今天到期';
      whenColor = AppColors.danger;
    } else if (days <= 3) {
      when = '$days 天后';
      whenColor = AppColors.warning;
    } else {
      when = '$days 天后';
      whenColor = AppColors.text3;
    }

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
            child: Text(cat?.displayIcon ?? '📋',
                style: const TextStyle(fontSize: 20)),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w600,
                    color: AppColors.text1,
                  ),
                ),
                const SizedBox(height: 4),
                Row(
                  children: [
                    Flexible(
                      child: Text(
                        '${acc?.name ?? '账户'} · ${DateFormat('M月d日').format(p.nextDate)}',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style:
                            TextStyle(fontSize: 12.5, color: AppColors.text2),
                      ),
                    ),
                    const SizedBox(width: 6),
                    Text(when,
                        style: TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.w600,
                            color: whenColor)),
                  ],
                ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          AmountText(
            p.isIncome ? p.amount : -p.amount,
            size: AmountSize.list,
            tone: p.isIncome ? AmountTone.income : AmountTone.expense,
            showSign: true,
          ),
        ],
      ),
    );
  }

  // ── 3) 支出速率与超支预警 ────────────────────────────────────
  Widget _paceSection(ExpensePaceInfo p) {
    final budget = p.monthlyBudget;
    final usedRatio =
        (budget != null && budget > 0) ? p.monthToDateExpense / budget : null;
    return Column(
      children: [
        GlassCard(
          radius: 16,
          padding: const EdgeInsets.all(18),
          child: Column(
            children: [
              _paceRow('本月至今支出', p.monthToDateExpense,
                  tone: AmountTone.expense),
              Divider(height: 24, color: AppColors.border),
              _paceRow('上月同期支出', p.lastMonthSamePeriodExpense,
                  tone: AmountTone.neutral),
              Divider(height: 24, color: AppColors.border),
              _paceRow('预计本月支出', p.projectedMonthExpense,
                  tone: p.overspendRisk
                      ? AmountTone.income
                      : AmountTone.neutral,
                  subtitle: '按当前速率外推（${p.daysElapsed} / ${p.daysInMonth} 天）'),
              if (budget != null) ...[
                Divider(height: 24, color: AppColors.border),
                _paceRow('当月总预算', budget, tone: AmountTone.neutral),
                const SizedBox(height: 10),
                ClipRRect(
                  borderRadius: BorderRadius.circular(10),
                  child: LinearProgressIndicator(
                    value: (usedRatio ?? 0).clamp(0.0, 1.0),
                    minHeight: 8,
                    backgroundColor: AppColors.surfaceAlt,
                    valueColor: AlwaysStoppedAnimation(
                        p.overspendRisk ? AppColors.income : AppColors.primary),
                  ),
                ),
                const SizedBox(height: 6),
                Align(
                  alignment: Alignment.centerRight,
                  child: Text(
                    '已用 ${((usedRatio ?? 0) * 100).toStringAsFixed(0)}%',
                    style: TextStyle(fontSize: 11.5, color: AppColors.text3),
                  ),
                ),
              ],
            ],
          ),
        ),
        if (p.overspendRisk && budget != null) ...[
          const SizedBox(height: 10),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
            decoration: BoxDecoration(
              color: AppColors.warningLight,
              borderRadius: BorderRadius.circular(12),
            ),
            child: Row(
              children: [
                Icon(Icons.warning_amber_rounded,
                    size: 18, color: AppColors.warning),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    '按当前速率，本月支出预计超出预算 ¥${formatAmount(p.projectedMonthExpense - budget, decimals: 0)}',
                    style: TextStyle(
                        fontSize: 12.5,
                        fontWeight: FontWeight.w600,
                        color: AppColors.text1),
                  ),
                ),
              ],
            ),
          ),
        ],
      ],
    );
  }

  Widget _paceRow(String label, double value,
      {required AmountTone tone, String? subtitle}) {
    return Row(
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(label,
                  style: TextStyle(fontSize: 13.5, color: AppColors.text2)),
              if (subtitle != null) ...[
                const SizedBox(height: 2),
                Text(subtitle,
                    style:
                        TextStyle(fontSize: 11, color: AppColors.text3)),
              ],
            ],
          ),
        ),
        AmountText(value, size: AmountSize.card, tone: tone, decimals: 0),
      ],
    );
  }

  // ── 4) 目标达成预测 ──────────────────────────────────────────
  Widget _goalSection(List<GoalForecastItem> goals) {
    if (goals.isEmpty) {
      return _hintCard('🎯', '没有进行中的储蓄目标', '在「储蓄目标」里新建目标后，这里会给出预计达成日期。');
    }
    return Column(
      children: [
        for (final g in goals) ...[
          _goalTile(g),
          const SizedBox(height: 10),
        ],
      ],
    );
  }

  Widget _goalTile(GoalForecastItem g) {
    final name = _decrypt(g.nameCipher, g.nameDekVer, '储蓄目标');
    final pct = (g.progress * 100).clamp(0, 999);
    final p = g.progress.clamp(0.0, 1.0);

    final String etaText;
    final Color etaColor;
    if (g.progress >= 1) {
      etaText = '已达成 🎉';
      etaColor = AppColors.primary;
    } else if (g.etaDate != null) {
      etaText = '预计 ${DateFormat('yyyy年M月').format(g.etaDate!)} 达成';
      etaColor = AppColors.text2;
    } else {
      etaText = '近 90 天净存入不足，暂无法估算';
      etaColor = AppColors.text3;
    }

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
            child: Text(g.icon ?? '🎯', style: const TextStyle(fontSize: 20)),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  name,
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
                  '月均净存入 ¥${formatAmount(g.monthlyRate, decimals: 0)} · $etaText',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(fontSize: 12, color: etaColor),
                ),
                const SizedBox(height: 8),
                ClipRRect(
                  borderRadius: BorderRadius.circular(10),
                  child: LinearProgressIndicator(
                    value: p,
                    minHeight: 6,
                    backgroundColor: AppColors.surfaceAlt,
                    valueColor: AlwaysStoppedAnimation(AppColors.primary),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 10),
          Text(
            '${pct.toStringAsFixed(0)}%',
            style: TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w700,
              color: AppColors.primary,
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
                    style:
                        TextStyle(fontSize: 12, height: 1.4, color: AppColors.text3)),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
