import 'package:flutter/material.dart';
import '../widgets/siku_ui.dart';
import '../core/theme.dart';
import '../services/api_service.dart';
import '../crypto/key_chain.dart';
import '../models/recurring.dart';
import '../models/account.dart';
import '../models/category.dart';
import 'add_bill_screen.dart' show CategoryPickerSheet, AccountPickerSheet;

/// 周期账单 / 订阅管家
///
/// 两 tab：
///   - "已订阅"：当前账本里已确认的周期账单（手动加或 AI 候选确认的）
///   - "AI 候选"：AI 从历史账单聚类出的疑似周期消费
///
/// 所有 note 在客户端用账本 DEK 解密展示；新建/编辑时也在客户端加密。
class RecurringScreen extends StatefulWidget {
  const RecurringScreen({super.key});

  @override
  State<RecurringScreen> createState() => _RecurringScreenState();
}

class _RecurringScreenState extends State<RecurringScreen>
    with SingleTickerProviderStateMixin {
  late TabController _tab;
  bool _loading = true;
  List<RecurringBill> _list = [];
  List<RecurringCandidate> _candidates = [];
  // 分类/账户索引（用于显示名字 / icon）
  Map<String, Category> _catById = {};
  Map<String, Account> _accById = {};

  @override
  void initState() {
    super.initState();
    _tab = TabController(length: 2, vsync: this);
    _load();
  }

  @override
  void dispose() {
    _tab.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    try {
      final futures = await Future.wait([
        ApiService.recurringList(),
        ApiService.recurringCandidates(),
        ApiService.getCategories(),
        ApiService.getAccounts(),
      ]);
      final list = (futures[0]['recurring'] as List? ?? [])
          .map((j) => RecurringBill.fromJson(j as Map<String, dynamic>))
          .toList();
      final cands = (futures[1]['candidates'] as List? ?? [])
          .map((j) => RecurringCandidate.fromJson(j as Map<String, dynamic>))
          .toList();
      final cats = (futures[2]['categories'] as List? ?? [])
          .map((j) => Category.fromJson(j as Map<String, dynamic>))
          .toList();
      final accs = (futures[3]['accounts'] as List? ?? [])
          .map((j) => Account.fromJson(j as Map<String, dynamic>))
          .toList();
      if (!mounted) return;
      setState(() {
        _list = list;
        _candidates = cands;
        _catById = {for (final c in cats) c.id: c};
        _accById = {for (final a in accs) a.id: a};
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

  // ── 候选 → 确认入库 ────────────────────────────────────────
  Future<void> _confirmCandidate(RecurringCandidate c) async {
    final acc = _accById[c.accountId];
    if (acc == null) return _toast('账户不存在');
    try {
      // 候选没有 note 明文；先存空字符串密文（用户后续可编辑）
      final cipher = KeyChain.instance.encryptText(
        ledgerId: acc.ledgerId,
        plain: '',
      );
      final dekVer = KeyChain.instance.dekVersionOf(acc.ledgerId) ?? 1;
      await ApiService.createRecurring({
        'categoryId': c.categoryId,
        'accountId': c.accountId,
        'type': c.type,
        'amount': c.amount,
        'noteCipher': cipher,
        'noteDekVer': dekVer,
        'cycleType': c.cycleType,
        'cycleDay': c.cycleDay,
        'isAuto': true,
        'confidence': c.confidence,
      });
      if (!mounted) return;
      _toast('已加入周期账单');
      _load();
    } catch (e) {
      _toast('保存失败：$e');
    }
  }

  Future<void> _delete(RecurringBill r) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('删除周期账单?'),
        content: const Text('此操作不会删除历史账单，只会停止追踪。'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('取消')),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            style: TextButton.styleFrom(foregroundColor: AppColors.danger),
            child: const Text('删除'),
          ),
        ],
      ),
    );
    if (ok != true) return;
    try {
      await ApiService.deleteRecurring(r.id);
      if (!mounted) return;
      _toast('已删除');
      _load();
    } catch (e) {
      _toast('删除失败：$e');
    }
  }

  Future<void> _openEditSheet({RecurringBill? init}) async {
    final cats = _catById.values
        .where((c) => c.type == 'expense')
        .toList()
      ..sort((a, b) => a.fullName.compareTo(b.fullName));
    final accs = _accById.values.toList();
    if (cats.isEmpty || accs.isEmpty) return _toast('请先创建分类和账户');

    final changed = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      builder: (_) => _RecurringEditSheet(
        init: init,
        categories: cats,
        accounts: accs,
      ),
    );
    if (changed == true) _load();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.bg,
      appBar: AuraAppBar(
        title: '周期账单',
        actions: [
          HeaderAddButton(
            tooltip: '新建周期账单',
            onPressed: () => _openEditSheet(),
          ),
        ],
        bottom: TabBar(
          controller: _tab,
          tabs: [
            Tab(text: '已订阅 (${_list.length})'),
            Tab(
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Text('AI 候选'),
                  if (_candidates.isNotEmpty) ...[
                    const SizedBox(width: 6),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                      decoration: BoxDecoration(
                        color: AppColors.warningLight,
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: Text(
                        '${_candidates.length}',
                        style: TextStyle(
                          color: AppColors.warning,
                          fontSize: 11,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ],
        ),
      ),
      body: AuraBackground(
        child: _loading
            ? const Center(child: CircularProgressIndicator())
            : TabBarView(
                controller: _tab,
                children: [_buildList(), _buildCandidates()],
              ),
      ),
    );
  }

  // ── 已订阅列表 ─────────────────────────────────────────────
  Widget _buildList() {
    if (_list.isEmpty) {
      return _empty(
        title: '还没有周期账单',
        hint: '切到 "AI 候选" 看看 AI 能不能从你的历史账单里找一些',
        emoji: '📋',
      );
    }
    final totalMonthly = _list.fold<double>(
      0,
      (sum, r) => sum + (r.cycleType == 'monthly' ? r.amount : 0),
    );
    return RefreshIndicator(
      onRefresh: _load,
      child: ListView(
        padding: const EdgeInsets.fromLTRB(20, 4, 20, 40),
        children: [
          if (totalMonthly > 0) ...[
            GlassCard(
              radius: 16,
              padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 14),
              child: Row(
                children: [
                  const Text('💰', style: TextStyle(fontSize: 22)),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('每月固定支出',
                            style: TextStyle(fontSize: 12.5, color: AppColors.text2)),
                        const SizedBox(height: 4),
                        AmountText(totalMonthly,
                            size: AmountSize.card, tone: AmountTone.expense),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 14),
          ],
          for (final r in _list) _itemTile(r),
        ],
      ),
    );
  }

  Widget _itemTile(RecurringBill r) {
    final cat = _catById[r.categoryId];
    final acc = _accById[r.accountId];
    final note = (r.noteCipher == null || r.noteDekVer == null)
        ? ''
        : KeyChain.instance.decryptText(
            ledgerId: r.ledgerId,
            cipherBase64: r.noteCipher!,
            dekVer: r.noteDekVer!,
            systemFallback: '',
          );

    final days = r.nextDate.difference(DateTime.now()).inDays;
    String nextLabel;
    Color nextColor = AppColors.text3;
    if (days <= 0) {
      nextLabel = '今天到期';
      nextColor = AppColors.danger;
    } else if (days <= 3) {
      nextLabel = '$days 天后';
      nextColor = AppColors.warning;
    } else {
      nextLabel = '$days 天后';
    }

    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: GestureDetector(
        onLongPress: () => _delete(r),
        child: GlassCard(
          radius: 14,
          padding: const EdgeInsets.all(14),
          onTap: () => _openEditSheet(init: r),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
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
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            cat?.fullName ?? '未分类',
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              fontSize: 15,
                              fontWeight: FontWeight.w600,
                              color: AppColors.text1,
                            ),
                          ),
                        ),
                        if (r.isAuto) ...[
                          const SizedBox(width: 8),
                          Container(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 6, vertical: 2),
                            decoration: BoxDecoration(
                              color: AppColors.primaryLight,
                              borderRadius: BorderRadius.circular(10),
                            ),
                            child: Text('AI 发现',
                                style: TextStyle(
                                    fontSize: 10,
                                    fontWeight: FontWeight.w600,
                                    color: AppColors.primary)),
                          ),
                        ],
                      ],
                    ),
                    const SizedBox(height: 4),
                    Text(
                      '${acc?.name ?? '账户'} · ${r.cycleLabel}',
                      style: TextStyle(fontSize: 12.5, color: AppColors.text2),
                    ),
                    if (note.isNotEmpty)
                      Padding(
                        padding: const EdgeInsets.only(top: 2),
                        child: Text(note,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style:
                                TextStyle(fontSize: 12, color: AppColors.text3)),
                      ),
                    const SizedBox(height: 5),
                    Text(
                      nextLabel,
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                        color: nextColor,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 12),
              Padding(
                padding: const EdgeInsets.only(top: 2),
                child: AmountText(
                  r.amount,
                  size: AmountSize.list,
                  tone: r.type == 'income'
                      ? AmountTone.income
                      : AmountTone.expense,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  // ── 候选列表 ─────────────────────────────────────────────
  Widget _buildCandidates() {
    if (_candidates.isEmpty) {
      return _empty(
        title: '暂时没发现规律消费',
        hint: '记账多一些之后 AI 才能找出周期',
        emoji: '🔍',
      );
    }
    return RefreshIndicator(
      onRefresh: _load,
      child: ListView(
        padding: const EdgeInsets.fromLTRB(20, 4, 20, 40),
        children: [
          for (final c in _candidates) _candidateTile(c),
        ],
      ),
    );
  }

  Widget _candidateTile(RecurringCandidate c) {
    final cat = _catById[c.categoryId];
    final acc = _accById[c.accountId];
    final confPct = (c.confidence * 100).round();
    final confColor = c.confidence >= 0.9
        ? AppColors.expense
        : c.confidence >= 0.7
            ? AppColors.warning
            : AppColors.text3;

    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: GlassCard(
        radius: 16,
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
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
                      Text(cat?.fullName ?? '未分类',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                              fontSize: 15,
                              fontWeight: FontWeight.w600,
                              color: AppColors.text1)),
                      const SizedBox(height: 2),
                      Text(acc?.name ?? '账户',
                          style:
                              TextStyle(fontSize: 12, color: AppColors.text2)),
                    ],
                  ),
                ),
                const SizedBox(width: 12),
                AmountText(c.amount,
                    size: AmountSize.card, tone: AmountTone.expense),
              ],
            ),
            const SizedBox(height: 12),
            Wrap(
              spacing: 8,
              runSpacing: 6,
              children: [
                _chip('每月 ${c.cycleDay} 号'),
                _chip('${c.sampleCount} 笔历史'),
                _chip('间隔 ${c.avgIntervalDays.toStringAsFixed(0)}±${c.stddevDays.toStringAsFixed(1)} 天'),
                _chip('置信度 $confPct%', color: confColor),
              ],
            ),
            const SizedBox(height: 14),
            Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                TextButton(
                  onPressed: () {
                    // 忽略候选：本地从列表移除即可（下次刷新还会出现）
                    setState(() => _candidates.remove(c));
                  },
                  style: TextButton.styleFrom(foregroundColor: AppColors.text2),
                  child: const Text('忽略'),
                ),
                const SizedBox(width: 8),
                FilledButton(
                  onPressed: () => _confirmCandidate(c),
                  child: const Text('确认订阅'),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  /// 信息 chip：统一 surfaceAlt 底 + text2 字；[color] 仅给置信度这类
  /// 语义分级文字上色（高=expense / 中=warning / 低=text3）。
  Widget _chip(String t, {Color? color}) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
        decoration: BoxDecoration(
          color: AppColors.surfaceAlt,
          borderRadius: BorderRadius.circular(10),
        ),
        child: Text(t,
            style: TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w500,
              color: color ?? AppColors.text2,
            )),
      );

  Widget _empty({required String title, required String hint, required String emoji}) =>
      Center(child: EmptyState(emoji: emoji, title: title, hint: hint, top: 0));
}

// ── 新建 / 编辑 弹窗 ───────────────────────────────────────────
class _RecurringEditSheet extends StatefulWidget {
  final RecurringBill? init;
  final List<Category> categories;
  final List<Account> accounts;

  const _RecurringEditSheet({
    this.init,
    required this.categories,
    required this.accounts,
  });

  @override
  State<_RecurringEditSheet> createState() => _RecurringEditSheetState();
}

class _RecurringEditSheetState extends State<_RecurringEditSheet> {
  final _amountCtrl = TextEditingController();
  final _noteCtrl = TextEditingController();
  Category? _category;
  Account? _account;
  int _cycleDay = 1;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    final init = widget.init;
    if (init != null) {
      _amountCtrl.text = init.amount.toString();
      _category = widget.categories
          .where((c) => c.id == init.categoryId)
          .firstOrNull;
      _account =
          widget.accounts.where((a) => a.id == init.accountId).firstOrNull;
      _cycleDay = init.cycleDay;
      // 解密原始 note 填入
      if (init.noteCipher != null && init.noteDekVer != null) {
        _noteCtrl.text = KeyChain.instance.decryptText(
          ledgerId: init.ledgerId,
          cipherBase64: init.noteCipher!,
          dekVer: init.noteDekVer!,
          systemFallback: '',
        );
      }
    } else {
      _cycleDay = DateTime.now().day;
    }
  }

  @override
  void dispose() {
    _amountCtrl.dispose();
    _noteCtrl.dispose();
    super.dispose();
  }

  void _toast(String s) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(s)));
  }

  Future<void> _save() async {
    final amount = double.tryParse(_amountCtrl.text);
    if (amount == null || amount <= 0) return _toast('请输入有效金额');
    if (_category == null) return _toast('请选择分类');
    if (_account == null) return _toast('请选择账户');

    final acc = _account!;
    setState(() => _saving = true);
    try {
      final cipher = KeyChain.instance.encryptText(
        ledgerId: acc.ledgerId,
        plain: _noteCtrl.text.trim(),
      );
      final dekVer = KeyChain.instance.dekVersionOf(acc.ledgerId) ?? 1;
      final body = {
        'categoryId': _category!.id,
        'accountId': _account!.id,
        'type': 'expense',
        'amount': amount,
        'noteCipher': cipher,
        'noteDekVer': dekVer,
        'cycleType': 'monthly',
        'cycleDay': _cycleDay,
      };
      if (widget.init == null) {
        await ApiService.createRecurring(body);
      } else {
        await ApiService.updateRecurring(widget.init!.id, body);
      }
      if (!mounted) return;
      Navigator.pop(context, true);
    } catch (e) {
      _toast('保存失败：$e');
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _openCategoryPicker() async {
    final result = await showModalBottomSheet<Category>(
      context: context,
      isScrollControlled: true,
      builder: (_) => CategoryPickerSheet(
        categories: widget.categories,
        selectedId: _category?.id,
        type: 'expense',
      ),
    );
    if (result != null) setState(() => _category = result);
  }

  Future<void> _openAccountPicker() async {
    final result = await showModalBottomSheet<Account>(
      context: context,
      isScrollControlled: true,
      builder: (_) => AccountPickerSheet(
        accounts: widget.accounts,
        selectedId: _account?.id,
      ),
    );
    if (result != null) setState(() => _account = result);
  }

  /// 与金额/备注输入框同一填充风格的可点选字段
  Widget _pickerField({
    required String label,
    required String emoji,
    required String? value,
    required String placeholder,
    required VoidCallback onTap,
  }) {
    final hasValue = value != null;
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(12),
      child: InputDecorator(
        decoration: InputDecoration(labelText: label),
        child: Row(children: [
          Text(emoji, style: const TextStyle(fontSize: 20)),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              hasValue ? value : placeholder,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontSize: 15,
                color: hasValue ? AppColors.text1 : AppColors.text2,
              ),
            ),
          ),
          Icon(Icons.unfold_more_rounded, size: 18, color: AppColors.text3),
        ]),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final viewInsets = MediaQuery.of(context).viewInsets.bottom;
    return Padding(
      padding: EdgeInsets.only(bottom: viewInsets),
      child: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                widget.init == null ? '新建周期账单' : '编辑周期账单',
                style: TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.w600,
                    color: AppColors.text1),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 16),
              TextField(
                controller: _amountCtrl,
                keyboardType: const TextInputType.numberWithOptions(decimal: true),
                decoration: const InputDecoration(
                  labelText: '金额',
                  prefixText: '¥ ',
                ),
              ),
              const SizedBox(height: 12),
              _pickerField(
                label: '分类',
                emoji: _category?.displayIcon ?? '📂',
                value: _category?.fullName,
                placeholder: '选择分类',
                onTap: _openCategoryPicker,
              ),
              const SizedBox(height: 12),
              _pickerField(
                label: '账户',
                emoji: _account?.typeEmoji ?? '💰',
                value: _account?.name,
                placeholder: '选择账户',
                onTap: _openAccountPicker,
              ),
              const SizedBox(height: 12),
              Row(
                children: [
                  Text('每月', style: TextStyle(color: AppColors.text2)),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Slider(
                      min: 1,
                      max: 31,
                      divisions: 30,
                      value: _cycleDay.toDouble(),
                      label: '$_cycleDay 号',
                      onChanged: (v) => setState(() => _cycleDay = v.round()),
                    ),
                  ),
                  Text('$_cycleDay 号',
                      style: TextStyle(
                          fontWeight: FontWeight.w600, color: AppColors.text1)),
                ],
              ),
              const SizedBox(height: 12),
              TextField(
                controller: _noteCtrl,
                decoration: const InputDecoration(
                  labelText: '备注 (可选，加密存储)',
                ),
              ),
              const SizedBox(height: 16),
              FilledButton(
                onPressed: _saving ? null : _save,
                child: _saving
                    ? SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(
                            strokeWidth: 2, color: AppColors.onPrimary),
                      )
                    : const Text('保存'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
