import 'package:flutter/material.dart';
import 'package:fl_chart/fl_chart.dart';
import '../core/refresh_bus.dart';
import '../core/theme.dart';
import '../models/budget.dart';
import '../models/category.dart';
import '../services/api_service.dart';
import '../models/bill.dart';
import '../widgets/glass.dart';
import 'add_bill_screen.dart' show CategoryPickerSheet;
import 'profile_screen.dart';

/// 预算页面 —— 重新设计：
/// - 只按 *分类* 设预算，"总预算" = 所有分类预算之和（自动算）
/// - 顶部 [当期 | 历史] 两个 tab
/// - "当期" tab 顶部一个 [月度 | 年度] 切换；下方汇总卡 + 各分类卡
/// - "历史" tab 显示最近 12 个周期的总预算/实际折线 + 哪几项超了
class BudgetsScreen extends StatefulWidget {
  const BudgetsScreen({super.key});
  @override
  State<BudgetsScreen> createState() => _BudgetsScreenState();
}

class _BudgetsScreenState extends State<BudgetsScreen>
    with SingleTickerProviderStateMixin {
  late TabController _tab;

  /// 当前查看的周期模式
  String _period = 'MONTHLY';

  // 当期
  List<Budget> _budgets = [];
  /// 用户手填的"总预算目标"（每周期一条；categoryId == null 的 Budget）
  Budget? _monthlyManualTotal;
  Budget? _yearlyManualTotal;
  bool _loading = true;

  // 历史
  List<_HistoryPeriod> _history = [];
  bool _historyLoading = true;

  @override
  void initState() {
    super.initState();
    _tab = TabController(length: 2, vsync: this);
    refreshBus.addListener(_onBump);
    _load();
    _loadHistory();
  }

  @override
  void dispose() {
    refreshBus.removeListener(_onBump);
    _tab.dispose();
    super.dispose();
  }

  void _onBump() {
    if (mounted) {
      _load();
      _loadHistory();
    }
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    try {
      final res = await ApiService.getBudgets();
      if (!mounted) return;
      final all = (res['budgets'] as List? ?? [])
          .map((b) => Budget.fromJson(b as Map<String, dynamic>))
          .toList();
      // 不用 firstWhere + orElse 那一套；显式遍历更可靠
      final cats = <Budget>[];
      Budget? mTotal;
      Budget? yTotal;
      for (final b in all) {
        if (b.categoryId == null) {
          if (b.period == 'MONTHLY') mTotal = b;
          if (b.period == 'YEARLY') yTotal = b;
        } else {
          cats.add(b);
        }
      }
      setState(() {
        _budgets = cats;
        _monthlyManualTotal = mTotal;
        _yearlyManualTotal = yTotal;
        _loading = false;
      });
    } catch (_) {
      if (mounted) {
        setState(() {
          // 出错时也清干净，避免 UI 显示陈旧状态
          _loading = false;
        });
      }
    }
  }

  Future<void> _loadHistory() async {
    setState(() => _historyLoading = true);
    try {
      final res = await ApiService.getBudgetHistory(
          period: _period, count: _period == 'YEARLY' ? 6 : 12);
      if (!mounted) return;
      setState(() {
        _history = (res['periods'] as List? ?? [])
            .map((p) => _HistoryPeriod.fromJson(p as Map<String, dynamic>))
            .toList();
        _historyLoading = false;
      });
    } catch (_) {
      if (mounted) setState(() => _historyLoading = false);
    }
  }

  void _switchPeriod(String p) {
    if (_period == p) return;
    setState(() => _period = p);
    _loadHistory();
  }

  /// 当前 tab 显示的预算（按 _period 过滤）
  List<Budget> get _currentBudgets =>
      _budgets.where((b) => b.period == _period).toList();

  Budget? get _currentManualTotal =>
      _period == 'MONTHLY' ? _monthlyManualTotal : _yearlyManualTotal;

  /// 分类预算求和
  double get _sumCategoryBudgets =>
      _currentBudgets.fold(0.0, (s, b) => s + b.amount);

  /// 手填的总预算目标（用户自己设的"上限"）
  double get _manualTotalTarget => _currentManualTotal?.amount ?? 0;

  /// 展示给用户的总预算：手填的目标 与 分类求和 中较大者
  double get _totalBudget {
    final sum = _sumCategoryBudgets;
    return sum > _manualTotalTarget ? sum : _manualTotalTarget;
  }

  double get _totalSpent =>
      _currentBudgets.fold(0.0, (s, b) => s + b.spent);
  double get _totalRemaining => _totalBudget - _totalSpent;
  double get _totalProgress =>
      _totalBudget > 0 ? _totalSpent / _totalBudget : 0;
  bool get _isOverBudget => _totalSpent > _totalBudget && _totalBudget > 0;

  /// "总预算"是被分类求和自动顶起来的（用户填了较小目标）
  bool get _totalAutoBumped =>
      _manualTotalTarget > 0 && _sumCategoryBudgets > _manualTotalTarget;

  Future<void> _deleteBudget(Budget b) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Text('删除预算'),
        content: Text('确定删除「${b.displayName}」预算？'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('取消')),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('删除', style: TextStyle(color: AppColors.expense)),
          ),
        ],
      ),
    );
    if (ok != true) return;
    await ApiService.deleteBudget(b.id);
    bumpRefresh();
  }

  void _openSheet({Budget? budget}) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => _BudgetSheet(
        budget: budget,
        defaultPeriod: _period,
        existingBudgets: _budgets,
        onSaved: bumpRefresh,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.transparent,
      appBar: AuraAppBar(
        title: '预算管理',
        avatarTap: () => Navigator.push(
          context,
          MaterialPageRoute(builder: (_) => const ProfileScreen()),
        ),
        bottom: TabBar(
          controller: _tab,
          indicatorColor: AppColors.primary,
          labelColor: AppColors.primary,
          unselectedLabelColor: AppColors.text2,
          tabs: const [
            Tab(text: '当期'),
            Tab(text: '历史'),
          ],
        ),
      ),
      body: TabBarView(
        controller: _tab,
        children: [
          _currentTab(),
          _historyTab(),
        ],
      ),
    );
  }

  // ── Tab 1: 当期 ──────────────────────────────────────────
  Widget _currentTab() {
    if (_loading) {
      return Center(child: CircularProgressIndicator(color: AppColors.primary));
    }
    return RefreshIndicator(
      color: AppColors.primary,
      onRefresh: _load,
      child: ListView(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 100),
        children: [
          _periodSelector(),
          const SizedBox(height: 12),
          _summaryCard(),
          const SizedBox(height: 18),
          _categoryBudgets(),
        ],
      ),
    );
  }

  Widget _periodSelector() {
    return Row(children: [
      _periodSeg('月度', 'MONTHLY'),
      const SizedBox(width: 10),
      _periodSeg('年度', 'YEARLY'),
    ]);
  }

  Widget _periodSeg(String label, String value) {
    final sel = _period == value;
    return Expanded(
      child: GestureDetector(
        onTap: () => _switchPeriod(value),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 150),
          height: 42,
          decoration: BoxDecoration(
            color: sel ? AppColors.primaryLight : AppColors.surface,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(
                color: sel ? AppColors.primary : AppColors.border),
          ),
          child: Center(
            child: Text(label,
                style: TextStyle(
                    fontSize: 14,
                    color: sel ? AppColors.primary : AppColors.text1,
                    fontWeight:
                        sel ? FontWeight.w600 : FontWeight.normal)),
          ),
        ),
      ),
    );
  }

  Widget _summaryCard() {
    final items = _currentBudgets;
    final hasManual = _currentManualTotal != null;

    return Container(
      padding: const EdgeInsets.fromLTRB(18, 16, 18, 16),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: AppColors.primaryGradient,
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(18),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(children: [
            Text(
              _period == 'MONTHLY' ? '本月总预算' : '今年总预算',
              style: TextStyle(
                  color: AppColors.onPrimaryGradient.withOpacity(0.85),
                  fontSize: 13),
            ),
            const SizedBox(width: 6),
            InkWell(
              onTap: _editTotalTarget,
              borderRadius: BorderRadius.circular(8),
              child: Padding(
                padding: const EdgeInsets.all(4),
                child: Icon(Icons.edit_outlined,
                    size: 14,
                    color:
                        AppColors.onPrimaryGradient.withOpacity(0.85)),
              ),
            ),
            const Spacer(),
            if (_totalAutoBumped)
              Container(
                padding: const EdgeInsets.symmetric(
                    horizontal: 6, vertical: 1),
                decoration: BoxDecoration(
                  color: AppColors.onPrimaryGradient.withOpacity(0.18),
                  borderRadius: BorderRadius.circular(4),
                ),
                child: Text(
                  '已自动调高',
                  style: TextStyle(
                      color: AppColors.onPrimaryGradient,
                      fontSize: 10,
                      fontWeight: FontWeight.w600),
                ),
              )
            else if (items.isNotEmpty)
              Container(
                padding: const EdgeInsets.symmetric(
                    horizontal: 6, vertical: 1),
                decoration: BoxDecoration(
                  color: AppColors.onPrimaryGradient.withOpacity(0.18),
                  borderRadius: BorderRadius.circular(4),
                ),
                child: Text(
                  '${items.length} 个分类',
                  style: TextStyle(
                      color: AppColors.onPrimaryGradient,
                      fontSize: 10,
                      fontWeight: FontWeight.w600),
                ),
              ),
          ]),
          const SizedBox(height: 6),
          Row(
            crossAxisAlignment: CrossAxisAlignment.baseline,
            textBaseline: TextBaseline.alphabetic,
            children: [
              Text('¥',
                  style: TextStyle(
                      color: AppColors.onPrimaryGradient, fontSize: 18)),
              const SizedBox(width: 2),
              Text(
                fmtMoneyInt(_totalBudget),
                style: TextStyle(
                    color: AppColors.onPrimaryGradient,
                    fontSize: 30,
                    fontWeight: FontWeight.bold,
                    letterSpacing: -0.5),
              ),
            ],
          ),
          const SizedBox(height: 12),
          ClipRRect(
            borderRadius: BorderRadius.circular(4),
            child: LinearProgressIndicator(
              value: _totalProgress.clamp(0.0, 1.0),
              minHeight: 8,
              backgroundColor:
                  AppColors.onPrimaryGradient.withOpacity(0.18),
              valueColor: AlwaysStoppedAnimation<Color>(
                  _isOverBudget ? AppColors.expense : Colors.white),
            ),
          ),
          const SizedBox(height: 10),
          Row(children: [
            Text(
              '已用 ${fmtMoney(_totalSpent)}',
              style: TextStyle(
                  color: AppColors.onPrimaryGradient,
                  fontSize: 13,
                  fontWeight: FontWeight.w500),
            ),
            const Spacer(),
            Text(
              _isOverBudget
                  ? '超支 ${fmtMoney(-_totalRemaining)}'
                  : '剩余 ${fmtMoney(_totalRemaining)}',
              style: TextStyle(
                  color: _isOverBudget
                      ? AppColors.expense
                      : AppColors.onPrimaryGradient,
                  fontSize: 13,
                  fontWeight: FontWeight.w600),
            ),
          ]),
          const SizedBox(height: 4),
          Text(
            _totalAutoBumped
                ? '手填 ${fmtMoneyInt(_manualTotalTarget)} 小于分类合计 ${fmtMoneyInt(_sumCategoryBudgets)}，已自动调高'
                : (hasManual
                    ? '手填总预算 · 分类合计 ${fmtMoneyInt(_sumCategoryBudgets)}'
                    : '总预算 = 各分类预算之和（点 ✎ 可手填）'),
            style: TextStyle(
                color: AppColors.onPrimaryGradient.withOpacity(0.6),
                fontSize: 11),
          ),
          if (_isOverBudget) ...[
            const SizedBox(height: 8),
            Container(
              padding: const EdgeInsets.symmetric(
                  horizontal: 8, vertical: 4),
              decoration: BoxDecoration(
                color: AppColors.expense.withOpacity(0.15),
                borderRadius: BorderRadius.circular(6),
              ),
              child: Row(mainAxisSize: MainAxisSize.min, children: [
                Icon(Icons.warning_amber_rounded,
                    size: 14, color: Colors.white),
                const SizedBox(width: 4),
                Text(
                  '已超支',
                  style: TextStyle(
                      color: Colors.white,
                      fontSize: 11,
                      fontWeight: FontWeight.w600),
                ),
              ]),
            ),
          ],
        ],
      ),
    );
  }

  Widget _categoryBudgets() {
    final items = _currentBudgets;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(4, 0, 4, 8),
          child: Row(children: [
            Text('分类预算',
                style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                    color: AppColors.text2)),
            const SizedBox(width: 6),
            Text('· ${items.length}',
                style: TextStyle(
                    fontSize: 12, color: AppColors.text3)),
            const Spacer(),
            InkWell(
              onTap: () => _openSheet(),
              borderRadius: BorderRadius.circular(8),
              child: Container(
                padding: const EdgeInsets.symmetric(
                    horizontal: 8, vertical: 4),
                decoration: BoxDecoration(
                  color: AppColors.primaryLight,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Row(mainAxisSize: MainAxisSize.min, children: [
                  Icon(Icons.add_rounded,
                      size: 14, color: AppColors.primary),
                  const SizedBox(width: 2),
                  Text('新增',
                      style: TextStyle(
                          fontSize: 12,
                          color: AppColors.primary,
                          fontWeight: FontWeight.w600)),
                ]),
              ),
            ),
          ]),
        ),
        if (items.isEmpty)
          Container(
            padding: const EdgeInsets.symmetric(vertical: 18),
            decoration: BoxDecoration(
              color: AppColors.surface,
              borderRadius: BorderRadius.circular(14),
              border: Border.all(
                  color: AppColors.border, style: BorderStyle.solid),
            ),
            child: Center(
              child: Text(
                _currentManualTotal == null
                    ? '点右上 + 新增第一个分类预算'
                    : '只设了总预算，可继续细分到分类',
                style:
                    TextStyle(fontSize: 12, color: AppColors.text2),
              ),
            ),
          )
        else
          ...items.map((b) => _BudgetCard(
                budget: b,
                onEdit: () => _openSheet(budget: b),
                onDelete: () => _deleteBudget(b),
              )),
      ],
    );
  }

  /// 弹窗里说明文案：根据手填值 / 分类合计 的相对大小给不同提示
  String? _helperForTotalEdit(Budget? cur, double sum) {
    if (cur == null) {
      if (sum > 0) {
        return '已自动填入分类合计 ${fmtMoneyInt(sum)}，可在此基础上加缓冲';
      }
      return null;
    }
    if (sum > cur.amount) {
      return '原手填 ${fmtMoneyInt(cur.amount)} 已被分类合计 ${fmtMoneyInt(sum)} 顶起';
    }
    return null;
  }

  /// 编辑/设置总预算目标（手填的上限）
  Future<void> _editTotalTarget() async {
    final cur = _currentManualTotal;
    final sum = _sumCategoryBudgets;
    // 默认填入"当前显示的总预算" = max(手填, 分类合计)。
    // 这样不管之前手填多少、分类是否已超过，弹窗里看到的初始值都与卡片一致。
    final initial = _totalBudget;
    final ctrl = TextEditingController(
      text: initial > 0 ? initial.toStringAsFixed(0) : '',
    );
    final result = await showDialog<_TotalEditResult>(
      context: context,
      builder: (_) => AlertDialog(
        shape:
            RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: Text(_period == 'MONTHLY' ? '设置本月总预算' : '设置本年总预算'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              '当前分类预算合计 ${fmtMoneyInt(sum)}。\n'
              '总预算 ≥ 分类合计；如果你填得更小，会被分类合计自动顶起来。',
              style: TextStyle(
                  fontSize: 12,
                  color: AppColors.text2,
                  height: 1.5),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: ctrl,
              autofocus: true,
              keyboardType:
                  const TextInputType.numberWithOptions(decimal: true),
              decoration: InputDecoration(
                labelText: '总预算金额',
                prefixText: '¥ ',
                helperText: _helperForTotalEdit(cur, sum),
                helperMaxLines: 2,
              ),
              onTap: () {
                // 方便整段重写
                ctrl.selection = TextSelection(
                  baseOffset: 0,
                  extentOffset: ctrl.text.length,
                );
              },
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, null),
            child: const Text('取消'),
          ),
          if (cur != null)
            TextButton(
              onPressed: () =>
                  Navigator.pop(context, const _TotalEditResult.clear()),
              child: const Text('移除',
                  style: TextStyle(color: AppColors.expense)),
            ),
          TextButton(
            onPressed: () {
              final v = double.tryParse(ctrl.text);
              if (v == null || v <= 0) return;
              Navigator.pop(context, _TotalEditResult.save(v));
            },
            child: const Text('保存'),
          ),
        ],
      ),
    );
    if (result == null) return;
    try {
      if (result.clear) {
        if (cur != null) await ApiService.deleteBudget(cur.id);
      } else if (cur == null) {
        await ApiService.createBudget(
          amount: result.amount!,
          period: _period,
          categoryId: null,
          startDate: DateTime.now().toIso8601String().substring(0, 10),
        );
      } else {
        await ApiService.updateBudget(
          cur.id,
          amount: result.amount,
          period: _period,
        );
      }
      bumpRefresh();
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
        content: Text('保存失败'),
        behavior: SnackBarBehavior.floating,
      ));
    }
  }

  // ── Tab 2: 历史 ──────────────────────────────────────────
  Widget _historyTab() {
    if (_historyLoading) {
      return Center(child: CircularProgressIndicator(color: AppColors.primary));
    }
    if (_history.isEmpty ||
        _history.every((p) => p.totalBudget == 0 && p.totalSpent == 0)) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Text('📈', style: TextStyle(fontSize: 48)),
            const SizedBox(height: 12),
            Text('暂无历史数据',
                style: TextStyle(color: AppColors.text2, fontSize: 15)),
            const SizedBox(height: 6),
            Text('设了分类预算并记账之后，这里会展示每期的执行情况',
                style:
                    TextStyle(color: AppColors.text3, fontSize: 12)),
          ],
        ),
      );
    }
    return RefreshIndicator(
      color: AppColors.primary,
      onRefresh: _loadHistory,
      child: ListView(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 32),
        children: [
          _periodSelector(),
          const SizedBox(height: 12),
          _trendChart(),
          const SizedBox(height: 14),
          _historyOverview(),
          const SizedBox(height: 14),
          _overspentList(),
        ],
      ),
    );
  }

  Widget _trendChart() {
    final maxV = _history.fold<double>(
      0,
      (m, p) => [m, p.totalBudget, p.totalSpent].reduce(
          (a, b) => a > b ? a : b),
    );
    final yMax = maxV <= 0 ? 100.0 : (maxV * 1.15);

    final budgetSpots = <FlSpot>[];
    final spentSpots = <FlSpot>[];
    for (var i = 0; i < _history.length; i++) {
      budgetSpots.add(FlSpot(i.toDouble(), _history[i].totalBudget));
      spentSpots.add(FlSpot(i.toDouble(), _history[i].totalSpent));
    }

    return GlassCard(
      radius: 16,
      padding: const EdgeInsets.fromLTRB(14, 14, 14, 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(children: [
            Text(_period == 'YEARLY' ? '近 6 年趋势' : '近 12 个月趋势',
                style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                    color: AppColors.text1)),
            const Spacer(),
            _legendDot(AppColors.primary, '预算'),
            const SizedBox(width: 10),
            _legendDot(AppColors.expense, '实际'),
          ]),
          const SizedBox(height: 8),
          SizedBox(
            height: 160,
            child: LineChart(
              LineChartData(
                minY: 0,
                maxY: yMax,
                gridData: FlGridData(
                  show: true,
                  drawVerticalLine: false,
                  horizontalInterval: yMax / 4,
                  getDrawingHorizontalLine: (_) => FlLine(
                      color: AppColors.border, strokeWidth: 0.5),
                ),
                borderData: FlBorderData(show: false),
                titlesData: FlTitlesData(
                  topTitles: const AxisTitles(
                      sideTitles: SideTitles(showTitles: false)),
                  rightTitles: const AxisTitles(
                      sideTitles: SideTitles(showTitles: false)),
                  leftTitles: AxisTitles(
                    sideTitles: SideTitles(
                      showTitles: true,
                      reservedSize: 38,
                      interval: yMax / 4,
                      getTitlesWidget: (v, meta) {
                        if (v == 0) return const SizedBox.shrink();
                        return Padding(
                          padding: const EdgeInsets.only(right: 4),
                          child: Text(
                            _kFmt(v),
                            style: TextStyle(
                                fontSize: 10,
                                color: AppColors.text3),
                          ),
                        );
                      },
                    ),
                  ),
                  bottomTitles: AxisTitles(
                    sideTitles: SideTitles(
                      showTitles: true,
                      reservedSize: 22,
                      interval: 1,
                      getTitlesWidget: (v, meta) {
                        final i = v.toInt();
                        if (i < 0 || i >= _history.length) {
                          return const SizedBox.shrink();
                        }
                        // 只显示首/末/中间，避免拥挤
                        if (_history.length > 6 &&
                            i != 0 &&
                            i != _history.length - 1 &&
                            i != (_history.length / 2).floor()) {
                          return const SizedBox.shrink();
                        }
                        return Padding(
                          padding: const EdgeInsets.only(top: 4),
                          child: Text(
                            _shortLabel(_history[i].label),
                            style: TextStyle(
                                fontSize: 10,
                                color: AppColors.text3),
                          ),
                        );
                      },
                    ),
                  ),
                ),
                lineTouchData: LineTouchData(
                  touchTooltipData: LineTouchTooltipData(
                    getTooltipColor: (_) => AppColors.text1,
                    getTooltipItems: (touched) => touched.map((t) {
                      final i = t.x.toInt();
                      final isBudget = t.barIndex == 0;
                      final p = _history[i];
                      return LineTooltipItem(
                        '${p.label}\n${isBudget ? "预算" : "实际"} ${fmtMoneyInt(t.y)}',
                        TextStyle(
                          color: Colors.white,
                          fontSize: 11,
                          fontWeight: FontWeight.w500,
                        ),
                      );
                    }).toList(),
                  ),
                ),
                lineBarsData: [
                  LineChartBarData(
                    spots: budgetSpots,
                    isCurved: true,
                    color: AppColors.primary,
                    barWidth: 2,
                    dotData: const FlDotData(show: false),
                    belowBarData: BarAreaData(
                      show: true,
                      color: AppColors.primary.withOpacity(0.08),
                    ),
                  ),
                  LineChartBarData(
                    spots: spentSpots,
                    isCurved: true,
                    color: AppColors.expense,
                    barWidth: 2,
                    dotData: const FlDotData(show: false),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  String _kFmt(double v) {
    if (v >= 10000) return '${(v / 10000).toStringAsFixed(1)}w';
    if (v >= 1000) return '${(v / 1000).toStringAsFixed(1)}k';
    return v.toStringAsFixed(0);
  }

  /// 把 "2026-05" → "5月"，"2026年" → "2026"
  String _shortLabel(String label) {
    if (label.endsWith('年')) return label.replaceAll('年', '');
    final parts = label.split('-');
    if (parts.length == 2) {
      return '${int.parse(parts[1])}月';
    }
    return label;
  }

  Widget _legendDot(Color c, String text) => Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 8,
            height: 8,
            decoration: BoxDecoration(color: c, shape: BoxShape.circle),
          ),
          const SizedBox(width: 4),
          Text(text,
              style: TextStyle(fontSize: 11, color: AppColors.text2)),
        ],
      );

  Widget _historyOverview() {
    // 取最近一期（不含本期；本期还没结束，纯参考）
    // 列出每期 1 行：日期 + 预算 + 实际 + 差额
    return GlassCard(
      radius: 16,
      padding: const EdgeInsets.fromLTRB(14, 12, 14, 4),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: Text('各期一览',
                style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                    color: AppColors.text1)),
          ),
          ..._history.reversed.map((p) {
            final over = p.totalSpent > p.totalBudget && p.totalBudget > 0;
            final diff = p.totalBudget - p.totalSpent;
            return Padding(
              padding: const EdgeInsets.symmetric(vertical: 6),
              child: Row(children: [
                SizedBox(
                  width: 60,
                  child: Text(p.label,
                      style: TextStyle(
                          fontSize: 12,
                          color: AppColors.text2,
                          fontWeight: FontWeight.w500)),
                ),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(children: [
                        Text(
                          fmtMoneyInt(p.totalSpent),
                          style: TextStyle(
                              fontSize: 14,
                              fontWeight: FontWeight.w600,
                              color: over
                                  ? AppColors.expense
                                  : AppColors.text1),
                        ),
                        Text(' / ${fmtMoneyInt(p.totalBudget)}',
                            style: TextStyle(
                                fontSize: 12, color: AppColors.text3)),
                      ]),
                      const SizedBox(height: 3),
                      ClipRRect(
                        borderRadius: BorderRadius.circular(2),
                        child: LinearProgressIndicator(
                          value: p.totalBudget > 0
                              ? (p.totalSpent / p.totalBudget)
                                  .clamp(0.0, 1.0)
                              : 0,
                          minHeight: 4,
                          backgroundColor: AppColors.border,
                          valueColor: AlwaysStoppedAnimation<Color>(
                              over ? AppColors.expense : AppColors.primary),
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 10),
                SizedBox(
                  width: 70,
                  child: Text(
                    p.totalBudget == 0
                        ? '—'
                        : (over
                            ? '超 ${fmtMoneyInt(-diff)}'
                            : '余 ${fmtMoneyInt(diff)}'),
                    textAlign: TextAlign.right,
                    style: TextStyle(
                        fontSize: 12,
                        color: over
                            ? AppColors.expense
                            : AppColors.income,
                        fontWeight: FontWeight.w600),
                  ),
                ),
              ]),
            );
          }),
        ],
      ),
    );
  }

  Widget _overspentList() {
    // 把所有期的超支项聚到一起，按超支次数倒排
    final stat = <String, _OverspentAgg>{};
    for (final p in _history) {
      for (final o in p.overspent) {
        final s = stat.putIfAbsent(
          o.categoryId,
          () => _OverspentAgg(
            categoryName: o.categoryName,
            categoryIcon: o.categoryIcon,
          ),
        );
        s.times += 1;
        s.totalOver += o.over;
        s.periods.add(p.label);
      }
    }
    final ranking = stat.entries.toList()
      ..sort((a, b) => b.value.times.compareTo(a.value.times));

    if (ranking.isEmpty) {
      return Container(
        padding: const EdgeInsets.symmetric(vertical: 16),
        decoration: BoxDecoration(
          color: AppColors.surface,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: AppColors.border),
        ),
        child: Center(
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(Icons.check_circle_outline_rounded,
                  color: AppColors.income, size: 18),
              const SizedBox(width: 8),
              Text('近期没有超支分类，做得不错',
                  style: TextStyle(
                      color: AppColors.text2,
                      fontSize: 13,
                      fontWeight: FontWeight.w500)),
            ],
          ),
        ),
      );
    }

    return GlassCard(
      radius: 16,
      padding: const EdgeInsets.fromLTRB(14, 12, 14, 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: Row(children: [
              Icon(Icons.warning_amber_rounded,
                  size: 18, color: AppColors.warning),
              const SizedBox(width: 6),
              Text('常超支项 · 规划时重点关注',
                  style: TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w600,
                      color: AppColors.text1)),
            ]),
          ),
          ...ranking.map((e) => Padding(
                padding: const EdgeInsets.symmetric(vertical: 6),
                child: Row(children: [
                  Text(e.value.categoryIcon ?? '📂',
                      style: const TextStyle(fontSize: 18)),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(e.value.categoryName,
                            style: TextStyle(
                                fontSize: 13,
                                color: AppColors.text1,
                                fontWeight: FontWeight.w500)),
                        Text(
                          '${e.value.times} 期超支 · 累计超 ${fmtMoneyInt(e.value.totalOver)}',
                          style: TextStyle(
                              fontSize: 11, color: AppColors.text2),
                        ),
                      ],
                    ),
                  ),
                  Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 8, vertical: 3),
                    decoration: BoxDecoration(
                      color: AppColors.expense.withOpacity(0.12),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Text('×${e.value.times}',
                        style: TextStyle(
                            color: AppColors.expense,
                            fontSize: 12,
                            fontWeight: FontWeight.w700)),
                  ),
                ]),
              )),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────
// Budget card（每个分类一张）
// ─────────────────────────────────────────────────────────────
class _BudgetCard extends StatelessWidget {
  const _BudgetCard({
    required this.budget,
    required this.onEdit,
    required this.onDelete,
  });

  final Budget budget;
  final VoidCallback onEdit;
  final VoidCallback onDelete;

  @override
  Widget build(BuildContext context) {
    final pct = budget.progress.clamp(0.0, 1.0);
    final color = budget.isOverBudget
        ? AppColors.expense
        : (pct > 0.8 ? AppColors.warning : AppColors.primary);

    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.fromLTRB(14, 12, 8, 12),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppColors.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(children: [
            Container(
              width: 34,
              height: 34,
              decoration: BoxDecoration(
                color: color.withOpacity(0.12),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Center(
                child: Text(budget.displayIcon,
                    style: const TextStyle(fontSize: 17)),
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(budget.displayName,
                      style: TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w600,
                          color: AppColors.text1)),
                  const SizedBox(height: 1),
                  Text('预算 ${fmtMoneyInt(budget.amount)}',
                      style: TextStyle(
                          fontSize: 11, color: AppColors.text3)),
                ],
              ),
            ),
            Text(
              '${(budget.progress * 100).toStringAsFixed(0)}%',
              style: TextStyle(
                  fontSize: 13,
                  color: color,
                  fontWeight: FontWeight.w700),
            ),
            PopupMenuButton<String>(
              padding: EdgeInsets.zero,
              icon: Icon(Icons.more_vert_rounded,
                  color: AppColors.text2, size: 18),
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12)),
              itemBuilder: (_) => [
                PopupMenuItem(
                    value: 'edit',
                    child: Row(children: [
                      Icon(Icons.edit_outlined,
                          size: 18, color: AppColors.text2),
                      const SizedBox(width: 10),
                      const Text('编辑'),
                    ])),
                PopupMenuItem(
                    value: 'delete',
                    child: Row(children: [
                      Icon(Icons.delete_outline_rounded,
                          size: 18, color: AppColors.expense),
                      SizedBox(width: 10),
                      Text('删除',
                          style: TextStyle(color: AppColors.expense)),
                    ])),
              ],
              onSelected: (v) {
                if (v == 'edit') onEdit();
                if (v == 'delete') onDelete();
              },
            ),
          ]),
          const SizedBox(height: 8),
          ClipRRect(
            borderRadius: BorderRadius.circular(3),
            child: LinearProgressIndicator(
              value: pct,
              minHeight: 6,
              backgroundColor: color.withOpacity(0.10),
              valueColor: AlwaysStoppedAnimation<Color>(color),
            ),
          ),
          const SizedBox(height: 6),
          Row(children: [
            Text('已用 ${fmtMoney(budget.spent)}',
                style: TextStyle(
                    fontSize: 11,
                    color: color,
                    fontWeight: FontWeight.w600)),
            const Spacer(),
            Text(
              budget.isOverBudget
                  ? '超 ${fmtMoney(-budget.remaining)}'
                  : '剩 ${fmtMoney(budget.remaining)}',
              style: TextStyle(
                  fontSize: 11,
                  color: budget.isOverBudget
                      ? AppColors.expense
                      : AppColors.text2,
                  fontWeight: FontWeight.w500),
            ),
          ]),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────
// 新建 / 编辑 预算 Sheet —— 现在必须选分类，"总预算"概念已废弃
// ─────────────────────────────────────────────────────────────
class _BudgetSheet extends StatefulWidget {
  const _BudgetSheet({
    this.budget,
    required this.defaultPeriod,
    required this.existingBudgets,
    required this.onSaved,
  });
  final Budget? budget;
  final String defaultPeriod;
  final List<Budget> existingBudgets;
  final VoidCallback onSaved;

  @override
  State<_BudgetSheet> createState() => _BudgetSheetState();
}

class _BudgetSheetState extends State<_BudgetSheet> {
  final _amountCtrl = TextEditingController();
  String _period = 'MONTHLY';
  String? _categoryId;
  Category? _selectedCat; // 当前选中的分类（供选择器回显）
  List<Category> _categories = [];
  bool _saving = false;
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    final b = widget.budget;
    if (b != null) {
      _amountCtrl.text = b.amount.toStringAsFixed(2);
      _period = b.period;
      _categoryId = b.categoryId;
    } else {
      _period = widget.defaultPeriod;
    }
    _loadCategories();
  }

  Future<void> _loadCategories() async {
    try {
      final res = await ApiService.getCategories();
      if (!mounted) return;
      setState(() {
        _categories = (res['categories'] as List? ?? [])
            .map((c) => Category.fromJson(c as Map<String, dynamic>))
            .where((c) => c.type == 'expense') // L1 + L2 都要，支持选到二级
            .toList();
        // 编辑态：按已有 categoryId 回显当前分类
        for (final c in _categories) {
          if (c.id == _categoryId) {
            _selectedCat = c;
            break;
          }
        }
        _loading = false;
      });
    } catch (_) {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  void dispose() {
    _amountCtrl.dispose();
    super.dispose();
  }

  bool _categoryHasBudget(String catId) {
    if (widget.budget != null && widget.budget!.categoryId == catId) {
      return false; // 自己不算
    }
    return widget.existingBudgets.any(
        (b) => b.categoryId == catId && b.period == _period);
  }

  Future<void> _save() async {
    if (_categoryId == null) {
      _toast('请选择分类');
      return;
    }
    if (_categoryHasBudget(_categoryId!)) {
      _toast('该分类在本周期已有预算');
      return;
    }
    final amount = double.tryParse(_amountCtrl.text);
    if (amount == null || amount <= 0) {
      _toast('请输入有效金额');
      return;
    }
    setState(() => _saving = true);
    try {
      if (widget.budget != null) {
        await ApiService.updateBudget(
          widget.budget!.id,
          amount: amount,
          period: _period,
          categoryId: _categoryId,
        );
      } else {
        await ApiService.createBudget(
          amount: amount,
          period: _period,
          categoryId: _categoryId,
          startDate: DateTime.now().toIso8601String().substring(0, 10),
        );
      }
      if (!mounted) return;
      Navigator.pop(context);
      widget.onSaved();
    } catch (_) {
      _toast('保存失败');
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  void _toast(String msg) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(msg),
      behavior: SnackBarBehavior.floating,
      backgroundColor: AppColors.text1,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
    ));
  }

  @override
  Widget build(BuildContext context) {
    final isEdit = widget.budget != null;
    final maxH = MediaQuery.of(context).size.height * 0.85;
    final bottomInset = MediaQuery.of(context).viewInsets.bottom;

    return ConstrainedBox(
      constraints: BoxConstraints(maxHeight: maxH),
      child: Container(
        decoration: BoxDecoration(
          color: AppColors.bg,
          borderRadius:
              const BorderRadius.vertical(top: Radius.circular(24)),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const SizedBox(height: 12),
            Center(
              child: Container(
                width: 36,
                height: 4,
                decoration: BoxDecoration(
                  color: AppColors.border,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),
            const SizedBox(height: 16),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20),
              child: Align(
                alignment: Alignment.centerLeft,
                child: Text(isEdit ? '编辑分类预算' : '添加分类预算',
                    style: TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                        color: AppColors.text1)),
              ),
            ),
            const SizedBox(height: 4),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20),
              child: Align(
                alignment: Alignment.centerLeft,
                child: Text('总预算会自动 = 所有分类预算之和',
                    style: TextStyle(
                        fontSize: 12, color: AppColors.text2)),
              ),
            ),
            const SizedBox(height: 16),
            Flexible(
              child: SingleChildScrollView(
                padding: const EdgeInsets.fromLTRB(20, 0, 20, 16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // 顺序：周期 → 分类 → 金额
                    _label('周期'),
                    const SizedBox(height: 8),
                    Row(children: [
                      _periodChip('月度', 'MONTHLY'),
                      const SizedBox(width: 10),
                      _periodChip('年度', 'YEARLY'),
                    ]),
                    const SizedBox(height: 16),
                    _label('分类'),
                    const SizedBox(height: 8),
                    if (_loading)
                      Padding(
                        padding: const EdgeInsets.symmetric(vertical: 16),
                        child: Center(
                            child: CircularProgressIndicator(
                                color: AppColors.primary)),
                      )
                    else
                      _categorySelector(),
                    const SizedBox(height: 16),
                    _label('预算金额'),
                    const SizedBox(height: 8),
                    TextField(
                      controller: _amountCtrl,
                      keyboardType:
                          const TextInputType.numberWithOptions(decimal: true),
                      decoration: const InputDecoration(
                        hintText: '请输入金额',
                        prefixText: '¥ ',
                      ),
                    ),
                  ],
                ),
              ),
            ),
            Padding(
              padding:
                  EdgeInsets.fromLTRB(20, 12, 20, bottomInset + 20),
              child: SizedBox(
                width: double.infinity,
                height: 50,
                child: ElevatedButton(
                  onPressed: _saving ? null : _save,
                  child: _saving
                      ? SizedBox(
                          width: 20,
                          height: 20,
                          child: CircularProgressIndicator(
                              strokeWidth: 2,
                              color: AppColors.onPrimary),
                        )
                      : Text(isEdit ? '保存修改' : '创建预算',
                          style: const TextStyle(fontSize: 15)),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _label(String t) => Text(t,
      style: TextStyle(
          fontSize: 13,
          fontWeight: FontWeight.w500,
          color: AppColors.text2));

  Widget _periodChip(String label, String value) {
    final sel = _period == value;
    return Expanded(
      child: GestureDetector(
        onTap: () => setState(() => _period = value),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 150),
          height: 44,
          decoration: BoxDecoration(
            color: sel ? AppColors.primaryLight : AppColors.surface,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(
                color: sel ? AppColors.primary : AppColors.border),
          ),
          child: Center(
            child: Text(label,
                style: TextStyle(
                    fontSize: 14,
                    color: sel ? AppColors.primary : AppColors.text1,
                    fontWeight:
                        sel ? FontWeight.w600 : FontWeight.normal)),
          ),
        ),
      ),
    );
  }

  /// 「记一笔」同款分类选择器入口：点开双列（一级/二级）分类选择弹窗
  Widget _categorySelector() {
    final sel = _selectedCat;
    final label =
        sel == null ? '选择分类' : '${sel.icon ?? "📂"} ${sel.fullName}';
    return GestureDetector(
      onTap: _pickCategory,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
        decoration: BoxDecoration(
          color: AppColors.surface,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: AppColors.border),
        ),
        child: Row(children: [
          Expanded(
            child: Text(label,
                style: TextStyle(
                    fontSize: 14,
                    color: sel == null ? AppColors.text3 : AppColors.text1,
                    fontWeight:
                        sel == null ? FontWeight.normal : FontWeight.w500)),
          ),
          Icon(Icons.chevron_right_rounded,
              color: AppColors.text3, size: 20),
        ]),
      ),
    );
  }

  Future<void> _pickCategory() async {
    final result = await showModalBottomSheet<Category>(
      context: context,
      isScrollControlled: true,
      backgroundColor: AppColors.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (_) => CategoryPickerSheet(
        categories: _categories,
        selectedId: _categoryId,
        type: 'expense',
      ),
    );
    if (result != null && mounted) {
      setState(() {
        _categoryId = result.id;
        _selectedCat = result;
      });
    }
    // 选择器里可能新建过分类 → 重拉一遍，保证回显与服务端一致
    if (mounted) _loadCategories();
  }
}

// ─────────────────────────────────────────────────────────────
// 历史 - 数据结构
// ─────────────────────────────────────────────────────────────
class _HistoryPeriod {
  final DateTime periodStart;
  final DateTime periodEnd;
  final String label;
  final double totalBudget;
  final double totalSpent;
  final double remaining;
  final double progress;
  final List<_OverspentItem> overspent;
  final List<_HistoryCat> byCategory;

  _HistoryPeriod({
    required this.periodStart,
    required this.periodEnd,
    required this.label,
    required this.totalBudget,
    required this.totalSpent,
    required this.remaining,
    required this.progress,
    required this.overspent,
    required this.byCategory,
  });

  factory _HistoryPeriod.fromJson(Map<String, dynamic> j) => _HistoryPeriod(
        periodStart: DateTime.parse(j['periodStart'] as String),
        periodEnd: DateTime.parse(j['periodEnd'] as String),
        label: j['label'] as String? ?? '',
        totalBudget: (j['totalBudget'] as num?)?.toDouble() ?? 0,
        totalSpent: (j['totalSpent'] as num?)?.toDouble() ?? 0,
        remaining: (j['remaining'] as num?)?.toDouble() ?? 0,
        progress: (j['progress'] as num?)?.toDouble() ?? 0,
        overspent: ((j['overspent'] as List?) ?? [])
            .map((o) => _OverspentItem.fromJson(o as Map<String, dynamic>))
            .toList(),
        byCategory: ((j['byCategory'] as List?) ?? [])
            .map((c) => _HistoryCat.fromJson(c as Map<String, dynamic>))
            .toList(),
      );
}

class _OverspentItem {
  final String categoryId;
  final String categoryName;
  final String? categoryIcon;
  final double budget;
  final double spent;
  final double over;

  _OverspentItem({
    required this.categoryId,
    required this.categoryName,
    this.categoryIcon,
    required this.budget,
    required this.spent,
    required this.over,
  });

  factory _OverspentItem.fromJson(Map<String, dynamic> j) => _OverspentItem(
        categoryId: j['categoryId'] as String,
        categoryName: j['categoryName'] as String? ?? '',
        categoryIcon: j['categoryIcon'] as String?,
        budget: (j['budget'] as num?)?.toDouble() ?? 0,
        spent: (j['spent'] as num?)?.toDouble() ?? 0,
        over: (j['over'] as num?)?.toDouble() ?? 0,
      );
}

class _HistoryCat {
  final String categoryId;
  final String categoryName;
  final String? categoryIcon;
  final double budget;
  final double spent;

  _HistoryCat({
    required this.categoryId,
    required this.categoryName,
    this.categoryIcon,
    required this.budget,
    required this.spent,
  });

  factory _HistoryCat.fromJson(Map<String, dynamic> j) => _HistoryCat(
        categoryId: j['categoryId'] as String,
        categoryName: j['categoryName'] as String? ?? '',
        categoryIcon: j['categoryIcon'] as String?,
        budget: (j['budget'] as num?)?.toDouble() ?? 0,
        spent: (j['spent'] as num?)?.toDouble() ?? 0,
      );
}

/// 总预算编辑弹窗的返回值
class _TotalEditResult {
  final double? amount;
  final bool clear;
  const _TotalEditResult.save(double this.amount) : clear = false;
  const _TotalEditResult.clear()
      : amount = null,
        clear = true;
}

class _OverspentAgg {
  final String categoryName;
  final String? categoryIcon;
  int times = 0;
  double totalOver = 0;
  final List<String> periods = [];
  _OverspentAgg({required this.categoryName, this.categoryIcon});
}
