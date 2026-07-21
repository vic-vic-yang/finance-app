import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../core/theme.dart';
import '../models/reconcile_report.dart';
import '../services/auth_service.dart';
import '../services/reconcile_service.dart';
import '../widgets/siku_ui.dart';

/// 对账中心（只读报告，不做修复）
///
/// 对指定月份做四项内部一致性检查：
///   1. balanceDrift        余额一致性（初始余额 + 全部流水 vs 当前余额）
///   2. suspectedDuplicates 疑似重复账单（±4 天同金额同方向，含跨账户对）
///   3. recurringMissing    周期账单缺记（nextDate 已过但当月无匹配账单）
///   4. transferOrphans     转账缺腿（isTransfer 但找不到配对腿）
///
/// 账户名 / 备注密文由服务端原样返回，本页用账本 DEK 解密展示。
class ReconcileScreen extends StatefulWidget {
  const ReconcileScreen({super.key});

  @override
  State<ReconcileScreen> createState() => _ReconcileScreenState();
}

class _ReconcileScreenState extends State<ReconcileScreen> {
  late DateTime _month;
  ReconcileReport? _report;
  bool _loading = true;
  String? _ledgerId;

  @override
  void initState() {
    super.initState();
    final now = DateTime.now();
    _month = DateTime(now.year, now.month);
    _init();
  }

  Future<void> _init() async {
    final user = await AuthService.getUser();
    _ledgerId = user?['currentLedgerId'] as String?;
    await _load();
  }

  String get _monthKey =>
      '${_month.year}-${_month.month.toString().padLeft(2, '0')}';

  bool get _isCurrentMonth {
    final now = DateTime.now();
    return _month.year == now.year && _month.month == now.month;
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    try {
      final res = await ReconcileService.getReport(_monthKey);
      if (!mounted) return;
      setState(() {
        _report = ReconcileReport.fromJson(res);
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() => _loading = false);
      _toast('加载失败：$e');
    }
  }

  void _shiftMonth(int delta) {
    setState(() {
      _month = DateTime(_month.year, _month.month + delta);
      _report = null; // 切月后旧数据不展示，避免误读
    });
    _load();
  }

  void _toast(String s) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(s)));
  }

  // ── 严重度 → 颜色 / 图标（严重度色约定：critical=income 哑红 ·
  //    warning=warning 琥珀 · info=primary；正常用 expense 绿）─────────
  Color _sevColor(String sev) => switch (sev) {
        'critical' => AppColors.income,
        'warning' => AppColors.warning,
        'info' => AppColors.primary,
        _ => AppColors.expense,
      };

  IconData _sevIcon(String sev) => switch (sev) {
        'critical' => Icons.error_outline_rounded,
        'warning' => Icons.warning_amber_rounded,
        'info' => Icons.info_outline_rounded,
        _ => Icons.check_circle_rounded,
      };

  @override
  Widget build(BuildContext context) {
    final report = _report;
    return Scaffold(
      backgroundColor: AppColors.bg,
      appBar: const AuraAppBar(title: '对账中心'),
      body: AuraBackground(
        child: _loading && report == null
            ? const Center(child: CircularProgressIndicator())
            : RefreshIndicator(
                onRefresh: _load,
                child: ListView(
                  physics: const AlwaysScrollableScrollPhysics(),
                  padding: const EdgeInsets.fromLTRB(20, 12, 20, 40),
                  children: [
                    _monthSwitcher(),
                    if (_loading)
                      const Padding(
                        padding: EdgeInsets.only(top: 8),
                        child: LinearProgressIndicator(minHeight: 2),
                      ),
                    if (report != null) ...[
                      const SizedBox(height: 16),
                      _summaryLine(report),
                      if (report.allClear)
                        const EmptyState(
                          emoji: '✅',
                          title: '账目一致',
                          hint: '余额、重复、周期、转账四项检查均未发现问题。',
                          top: 28,
                        ),
                      const SizedBox(height: 8),
                      for (final s in report.sections) ...[
                        _sectionCard(s),
                        const SizedBox(height: 14),
                      ],
                    ] else if (!_loading) ...[
                      const SizedBox(height: 16),
                      const EmptyState(
                        emoji: '🧾',
                        title: '暂时没有报告',
                        hint: '下拉重试，或切换月份看看。',
                        top: 28,
                      ),
                    ],
                  ],
                ),
              ),
      ),
    );
  }

  // ── 月份切换 ──────────────────────────────────────────────────
  Widget _monthSwitcher() {
    return GlassCard(
      radius: 16,
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
      child: Row(
        children: [
          IconButton(
            tooltip: '上个月',
            onPressed: () => _shiftMonth(-1),
            icon: Icon(Icons.chevron_left_rounded, color: AppColors.text1),
          ),
          Expanded(
            child: Column(
              children: [
                Text(
                  DateFormat('yyyy年M月').format(_month),
                  style: TextStyle(
                    fontSize: 17,
                    fontWeight: FontWeight.w700,
                    color: AppColors.text1,
                  ),
                ),
                Text(
                  _isCurrentMonth ? '本月（进行中）' : '对账月份',
                  style: TextStyle(fontSize: 11, color: AppColors.text3),
                ),
              ],
            ),
          ),
          IconButton(
            tooltip: '下个月',
            onPressed: _isCurrentMonth ? null : () => _shiftMonth(1),
            icon: Icon(
              Icons.chevron_right_rounded,
              color: _isCurrentMonth ? AppColors.text3 : AppColors.text1,
            ),
          ),
        ],
      ),
    );
  }

  Widget _summaryLine(ReconcileReport r) {
    final n = r.totalIssues;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 4),
      child: Text(
        n == 0 ? '4 项检查全部通过' : '4 项检查 · 共发现 $n 处需核对',
        style: TextStyle(
          fontSize: 12.5,
          color: n == 0 ? AppColors.expense : AppColors.text2,
          fontWeight: FontWeight.w500,
        ),
      ),
    );
  }

  // ── 检查区块卡 ────────────────────────────────────────────────
  Widget _sectionCard(ReconcileSection s) {
    final color = _sevColor(s.severity);
    return GlassCard(
      radius: 18,
      padding: const EdgeInsets.fromLTRB(18, 16, 18, 14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // 标题行：severity 图标 + 标题 + 计数 pill
          Row(
            children: [
              Icon(_sevIcon(s.severity), size: 20, color: color),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  s.title,
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w600,
                    color: AppColors.text1,
                  ),
                ),
              ),
              if (s.count > 0)
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 10, vertical: 3),
                  decoration: BoxDecoration(
                    color: color.withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: Text(
                    '${s.count} 项',
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                      color: color,
                    ),
                  ),
                ),
            ],
          ),
          const SizedBox(height: 4),
          Text(
            _sectionHint(s.key),
            style: TextStyle(fontSize: 11.5, color: AppColors.text3),
          ),
          const SizedBox(height: 10),
          if (s.count == 0)
            Row(
              children: [
                Icon(Icons.check_circle_rounded,
                    size: 17, color: AppColors.expense),
                const SizedBox(width: 6),
                Text('未发现异常',
                    style: TextStyle(fontSize: 13, color: AppColors.text2)),
              ],
            )
          else
            for (var i = 0; i < s.items.length; i++) ...[
              if (i > 0) Divider(height: 18, color: AppColors.border),
              _buildItem(s.key, s.items[i]),
            ],
        ],
      ),
    );
  }

  String _sectionHint(String key) => switch (key) {
        'balanceDrift' => '初始余额 + 全部流水净额，应当等于当前余额',
        'suspectedDuplicates' => '±4 天内同金额、同方向的多条账单（含不同账户间）',
        'recurringMissing' => '周期账单已到触发日，但当月没有对应记账',
        'transferOrphans' => '转账应有收支两条大腿，找不到配对腿会错两边余额',
        _ => '',
      };

  Widget _buildItem(String key, ReconcileItem it) {
    final ledgerId = _ledgerId ?? '';
    return switch (key) {
      'balanceDrift' => _driftItem(it, ledgerId),
      'suspectedDuplicates' => _dupItem(it, ledgerId),
      'recurringMissing' => _missingItem(it, ledgerId),
      'transferOrphans' => _orphanItem(it, ledgerId),
      _ => const SizedBox.shrink(),
    };
  }

  String _fmtDate(DateTime? d) =>
      d == null ? '-' : DateFormat('M月d日').format(d);

  // ── 1. 余额一致性 ─────────────────────────────────────────────
  Widget _driftItem(ReconcileItem it, String ledgerId) {
    final drift = it.num_('drift');
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(it.accountIcon ?? '💰', style: const TextStyle(fontSize: 20)),
        const SizedBox(width: 10),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                it.accountName(ledgerId),
                style: TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
                  color: AppColors.text1,
                ),
              ),
              const SizedBox(height: 2),
              Text(
                '账面 ¥${formatAmount(it.num_('actual'))}'
                ' · 推算 ¥${formatAmount(it.num_('expected'))}',
                style: TextStyle(fontSize: 12, color: AppColors.text2),
              ),
              if (it.bool_('hasStock'))
                Text(
                  '该账户含股票纸面盈亏，偏差或为正常结算差异',
                  style: TextStyle(fontSize: 11, color: AppColors.warning),
                ),
            ],
          ),
        ),
        const SizedBox(width: 8),
        Column(
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            AmountText(
              drift,
              size: AmountSize.list,
              tone: AmountTone.auto,
              showSign: true,
            ),
            Text('偏差',
                style: TextStyle(fontSize: 10, color: AppColors.text3)),
          ],
        ),
      ],
    );
  }

  // ── 2. 疑似重复账单 ───────────────────────────────────────────
  Widget _dupItem(ReconcileItem it, String ledgerId) {
    final isIncome = it.str('type') == 'income';
    final cross = it.bool_('crossAccount');
    final bills = (it.raw['bills'] as List? ?? [])
        .whereType<Map<String, dynamic>>()
        .toList();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            AmountText(
              it.num_('amount'),
              size: AmountSize.list,
              tone: isIncome ? AmountTone.income : AmountTone.expense,
            ),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                cross
                    ? '${isIncome ? '收入' : '支出'} · 跨账户重复'
                    : '${isIncome ? '收入' : '支出'} · ${it.accountName(ledgerId)}',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontSize: 12,
                  color: cross ? AppColors.primary : AppColors.text2,
                  fontWeight: cross ? FontWeight.w600 : FontWeight.w400,
                ),
              ),
            ),
            Text('相差 ${it.int_('gapDays')} 天',
                style: TextStyle(fontSize: 11, color: AppColors.text3)),
          ],
        ),
        const SizedBox(height: 4),
        for (final b in bills)
          Builder(builder: (_) {
            final note = ReconcileItem.noteOf(
              ledgerId,
              b['noteCipher'] as String?,
              (b['noteDekVer'] as num?)?.toInt() ?? 1,
            );
            // 跨账户对：每条腿显示「账户名 · 备注」，一眼看出两人各记了一笔
            final label = cross
                ? '${ReconcileItem(b).accountName(ledgerId)}${note.isNotEmpty ? ' · $note' : ''}'
                : note;
            return Padding(
              padding: const EdgeInsets.only(top: 2),
              child: Row(
                children: [
                  Text('• ${_fmtDate(_parseDate(b['date']))}',
                      style: TextStyle(fontSize: 12, color: AppColors.text1)),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      label,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(fontSize: 12, color: AppColors.text3),
                    ),
                  ),
                ],
              ),
            );
          }),
      ],
    );
  }

  DateTime? _parseDate(dynamic v) =>
      v is String ? DateTime.tryParse(v)?.toLocal() : null;

  // ── 3. 周期账单缺记 ───────────────────────────────────────────
  Widget _missingItem(ReconcileItem it, String ledgerId) {
    final isIncome = it.str('type') == 'income';
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(it.str('categoryIcon') ?? '📅',
            style: const TextStyle(fontSize: 20)),
        const SizedBox(width: 10),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Text(
                      it.str('categoryName') ?? '未分类',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w600,
                        color: AppColors.text1,
                      ),
                    ),
                  ),
                  AmountText(
                    it.num_('amount'),
                    size: AmountSize.list,
                    tone: isIncome ? AmountTone.income : AmountTone.expense,
                  ),
                ],
              ),
              const SizedBox(height: 2),
              Text(
                '应于 ${_fmtDate(it.date('dueDate'))} 记账'
                ' · ${it.accountName(ledgerId)}'
                ' · ${isIncome ? '收入' : '支出'}',
                style: TextStyle(fontSize: 12, color: AppColors.text2),
              ),
            ],
          ),
        ),
      ],
    );
  }

  // ── 4. 转账缺腿 ───────────────────────────────────────────────
  Widget _orphanItem(ReconcileItem it, String ledgerId) {
    final isOut = it.str('type') == 'expense';
    final note = it.note(ledgerId);
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(
          isOut ? Icons.call_made_rounded : Icons.call_received_rounded,
          size: 18,
          color: isOut ? AppColors.expense : AppColors.income,
        ),
        const SizedBox(width: 10),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Text(
                    isOut ? '转出' : '转入',
                    style: TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w600,
                      color: AppColors.text1,
                    ),
                  ),
                  const Spacer(),
                  AmountText(
                    it.num_('amount'),
                    size: AmountSize.list,
                    tone: isOut ? AmountTone.expense : AmountTone.income,
                  ),
                ],
              ),
              const SizedBox(height: 2),
              Text(
                '${_fmtDate(it.date('date'))} · ${it.accountName(ledgerId)}',
                style: TextStyle(fontSize: 12, color: AppColors.text2),
              ),
              if (note.isNotEmpty)
                Text(
                  note,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(fontSize: 12, color: AppColors.text3),
                ),
              Text(
                '未找到同金额、方向相反、±2 天内的配对腿',
                style: TextStyle(fontSize: 11, color: AppColors.warning),
              ),
            ],
          ),
        ),
      ],
    );
  }
}
