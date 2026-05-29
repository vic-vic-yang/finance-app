import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../core/theme.dart';
import '../crypto/key_chain.dart';
import '../models/account.dart';
import '../models/savings_goal.dart';
import '../services/api_service.dart';
import '../services/auth_service.dart';

class GoalsScreen extends StatefulWidget {
  const GoalsScreen({super.key});
  @override
  State<GoalsScreen> createState() => _GoalsScreenState();
}

class _GoalsScreenState extends State<GoalsScreen> {
  List<SavingsGoal> _goals = [];
  bool _loading = true;
  String? _currentLedgerId;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    try {
      final user = await AuthService.getUser();
      _currentLedgerId = user?['currentLedgerId'] as String?;
      final res = await ApiService.getGoals();
      final list = (res['goals'] as List? ?? [])
          .map((g) => SavingsGoal.fromJson(g as Map<String, dynamic>))
          .toList();
      if (!mounted) return;
      setState(() {
        _goals = list;
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

  Future<void> _openEdit({SavingsGoal? init}) async {
    if (_currentLedgerId == null || _currentLedgerId!.isEmpty) {
      _toast('请先选择一个账本');
      return;
    }
    final changed = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      builder: (_) => _GoalEditSheet(
        ledgerId: _currentLedgerId!,
        init: init,
      ),
    );
    if (changed == true) _load();
  }

  Future<void> _delete(SavingsGoal g) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('删除目标？'),
        content: Text('"${g.name}" 将被删除（已存的钱不受影响）'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('取消')),
          TextButton(
              onPressed: () => Navigator.pop(context, true),
              child: const Text('删除')),
        ],
      ),
    );
    if (ok != true) return;
    try {
      await ApiService.deleteGoal(g.id);
      _toast('已删除');
      _load();
    } catch (e) {
      _toast('删除失败：$e');
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('储蓄目标')),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _goals.isEmpty
              ? _empty()
              : RefreshIndicator(
                  onRefresh: _load,
                  child: ListView(
                    padding: const EdgeInsets.all(12),
                    children: [for (final g in _goals) _goalCard(g)],
                  ),
                ),
      floatingActionButton: FloatingActionButton(
        onPressed: () => _openEdit(),
        child: const Icon(Icons.add),
      ),
    );
  }

  Widget _empty() => Center(
        child: Padding(
          padding: const EdgeInsets.all(36),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Text('🎯', style: TextStyle(fontSize: 56)),
              const SizedBox(height: 12),
              Text(
                '还没有储蓄目标\n点 + 设一个，比如"半年存够2万"',
                textAlign: TextAlign.center,
                style: TextStyle(color: Colors.grey.shade600),
              ),
            ],
          ),
        ),
      );

  Widget _goalCard(SavingsGoal g) {
    final pct = (g.progress * 100).clamp(0, 999);
    final done = g.progress >= 1;
    final color = done
        ? Colors.green
        : g.progress >= 0.7
            ? Colors.blue
            : Colors.orange;
    final dl = g.deadline;
    final dlText = dl == null
        ? ''
        : '截止 ${DateFormat('yyyy-MM-dd').format(dl)}';
    final accName = g.accountName();

    return Card(
      margin: const EdgeInsets.only(bottom: 10),
      child: InkWell(
        onTap: () => _openEdit(init: g),
        onLongPress: () => _delete(g),
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Text(g.icon ?? '🎯', style: const TextStyle(fontSize: 22)),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(g.name,
                            style: const TextStyle(
                                fontSize: 15, fontWeight: FontWeight.w600)),
                        if (dlText.isNotEmpty)
                          Text(dlText,
                              style: TextStyle(
                                  fontSize: 11, color: Colors.grey.shade600)),
                      ],
                    ),
                  ),
                  if (done)
                    const Padding(
                      padding: EdgeInsets.only(left: 4),
                      child: Icon(Icons.check_circle,
                          color: Colors.green, size: 22),
                    ),
                ],
              ),
              if (accName != null) ...[
                const SizedBox(height: 4),
                Row(
                  children: [
                    Icon(Icons.account_balance_wallet,
                        size: 13, color: Colors.grey.shade500),
                    const SizedBox(width: 4),
                    Text(
                      '绑定：$accName',
                      style:
                          TextStyle(fontSize: 11, color: Colors.grey.shade500),
                    ),
                    if (g.account?.balanceVisible == true) ...[
                      const SizedBox(width: 6),
                      Text(
                        '(余额 ¥${g.account!.balance.toStringAsFixed(0)})',
                        style: TextStyle(
                            fontSize: 11, color: Colors.grey.shade500),
                      ),
                    ],
                  ],
                ),
              ],
              const SizedBox(height: 10),
              Row(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Text(
                    '¥${g.currentSaved.toStringAsFixed(0)}',
                    style: const TextStyle(
                        fontSize: 20, fontWeight: FontWeight.bold),
                  ),
                  Text(
                    ' / ¥${g.targetAmount.toStringAsFixed(0)}',
                    style:
                        TextStyle(fontSize: 13, color: Colors.grey.shade600),
                  ),
                  const Spacer(),
                  Text(
                    '${pct.toStringAsFixed(0)}%',
                    style: TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.bold,
                      color: color,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 6),
              ClipRRect(
                borderRadius: BorderRadius.circular(4),
                child: LinearProgressIndicator(
                  value: g.progress.clamp(0.0, 1.0),
                  minHeight: 8,
                  backgroundColor: Colors.grey.shade200,
                  valueColor: AlwaysStoppedAnimation(color),
                ),
              ),
              if (g.etaDays != null && !done) ...[
                const SizedBox(height: 8),
                Text(
                  '按目前速度，预计还需 ${g.etaDays} 天达成',
                  style:
                      TextStyle(fontSize: 12, color: Colors.grey.shade600),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

// ═══════════════════════════════════════════════════════════════
// 编辑弹窗
// ═══════════════════════════════════════════════════════════════

class _GoalEditSheet extends StatefulWidget {
  final String ledgerId;
  final SavingsGoal? init;
  const _GoalEditSheet({required this.ledgerId, this.init});

  @override
  State<_GoalEditSheet> createState() => _GoalEditSheetState();
}

class _GoalEditSheetState extends State<_GoalEditSheet> {
  final _nameCtrl = TextEditingController();
  final _amountCtrl = TextEditingController();
  DateTime? _deadline;
  String? _icon;
  bool _saving = false;

  // ── 账户绑定 ──
  List<Account> _accounts = [];
  bool _loadingAccounts = true;
  Account? _selectedAccount;
  bool _useExistingBalance = true;

  static const _icons = ['🎯', '🏠', '🚗', '✈️', '💍', '🎓', '👶', '💼', '📱'];

  @override
  void initState() {
    super.initState();
    final i = widget.init;
    if (i != null) {
      _nameCtrl.text = i.name;
      _amountCtrl.text = i.targetAmount.toString();
      _deadline = i.deadline;
      _icon = i.icon;
      _useExistingBalance = i.useExistingBalance ?? true;
    } else {
      _icon = '🎯';
    }
    _loadAccounts();
  }

  Future<void> _loadAccounts() async {
    try {
      final res = await ApiService.getAccounts();
      final list = (res['accounts'] as List? ?? [])
          .map((a) => Account.fromJson(a as Map<String, dynamic>))
          .where((a) => a.balanceVisible)
          .toList();
      if (!mounted) return;

      // 编辑时匹配已绑定账户
      Account? sel;
      final boundId = widget.init?.accountId;
      if (boundId != null) {
        sel = list.where((a) => a.id == boundId).firstOrNull;
      }

      setState(() {
        _accounts = list;
        _selectedAccount = sel;
        _loadingAccounts = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() => _loadingAccounts = false);
    }
  }

  @override
  void dispose() {
    _nameCtrl.dispose();
    _amountCtrl.dispose();
    super.dispose();
  }

  void _toast(String s) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(s)));
  }

  Future<void> _openAccountPicker() async {
    final result = await showModalBottomSheet<Account>(
      context: context,
      isScrollControlled: true,
      builder: (_) => _AccountPickerSheet(
        accounts: _accounts,
        selectedId: _selectedAccount?.id,
      ),
    );
    if (result != null) {
      setState(() => _selectedAccount = result);
    }
  }

  Future<void> _save() async {
    final name = _nameCtrl.text.trim();
    final amount = double.tryParse(_amountCtrl.text);
    if (name.isEmpty) return _toast('请输入目标名称');
    if (amount == null || amount <= 0) return _toast('请输入有效金额');

    setState(() => _saving = true);
    try {
      final cipher = KeyChain.instance.encryptText(
        ledgerId: widget.ledgerId,
        plain: name,
      );
      final dekVer = KeyChain.instance.dekVersionOf(widget.ledgerId) ?? 1;
      final body = <String, dynamic>{
        'nameCipher': cipher,
        'nameDekVer': dekVer,
        'targetAmount': amount,
        if (_deadline != null) 'deadline': _deadline!.toIso8601String(),
        if (_icon != null) 'icon': _icon,
      };

      if (_selectedAccount != null) {
        body['accountId'] = _selectedAccount!.id;
        body['useExistingBalance'] = _useExistingBalance;
      }

      if (widget.init == null) {
        await ApiService.createGoal(body);
      } else {
        // 编辑时如果清空了账户绑定，传空串解绑
        if (widget.init!.accountId != null && _selectedAccount == null) {
          body['accountId'] = '';
        }
        await ApiService.updateGoal(widget.init!.id, body);
      }
      if (!mounted) return;
      Navigator.pop(context, true);
    } catch (e) {
      _toast('保存失败：$e');
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final viewInsets = MediaQuery.of(context).viewInsets.bottom;
    final acc = _selectedAccount;
    final hasExistingBalance = acc != null && acc.balance > 0;

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
                widget.init == null ? '新建目标' : '编辑目标',
                textAlign: TextAlign.center,
                style:
                    const TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 16),

              // ── 图标选择 ──
              SizedBox(
                height: 44,
                child: ListView.separated(
                  scrollDirection: Axis.horizontal,
                  itemCount: _icons.length,
                  separatorBuilder: (_, __) => const SizedBox(width: 6),
                  itemBuilder: (_, i) {
                    final ic = _icons[i];
                    final selected = ic == _icon;
                    return GestureDetector(
                      onTap: () => setState(() => _icon = ic),
                      child: Container(
                        width: 44,
                        decoration: BoxDecoration(
                          color: selected
                              ? Theme.of(context)
                                  .primaryColor
                                  .withOpacity(0.12)
                              : Colors.grey.shade100,
                          borderRadius: BorderRadius.circular(8),
                          border: selected
                              ? Border.all(
                                  color: Theme.of(context).primaryColor,
                                  width: 1.5)
                              : null,
                        ),
                        alignment: Alignment.center,
                        child:
                            Text(ic, style: const TextStyle(fontSize: 22)),
                      ),
                    );
                  },
                ),
              ),
              const SizedBox(height: 12),

              // ── 名称 ──
              TextField(
                controller: _nameCtrl,
                decoration: const InputDecoration(
                  labelText: '目标名',
                  hintText: '比如：半年存够 2 万',
                  border: OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 12),

              // ── 金额 ──
              TextField(
                controller: _amountCtrl,
                keyboardType:
                    const TextInputType.numberWithOptions(decimal: true),
                decoration: const InputDecoration(
                  labelText: '目标金额',
                  prefixText: '¥ ',
                  border: OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 12),

              // ── 绑定账户 ──
              Text(
                '绑定账户（可选，绑定后自动用余额追踪进度）',
                style: TextStyle(fontSize: 12, color: Colors.grey.shade600),
              ),
              const SizedBox(height: 6),
              _loadingAccounts
                  ? const Padding(
                      padding: EdgeInsets.symmetric(vertical: 8),
                      child: SizedBox(
                          width: 16,
                          height: 16,
                          child: CircularProgressIndicator(strokeWidth: 2)),
                    )
                  : _accountSelector(),

              // ── 计入现有余额开关 ──
              if (acc != null && hasExistingBalance) ...[
                const SizedBox(height: 10),
                Row(
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text('计入现有余额',
                              style: TextStyle(fontSize: 14)),
                          Text(
                            '当前余额 ¥${acc.balance.toStringAsFixed(0)}，'
                            '关闭则从 0 开始只算增量',
                            style: TextStyle(
                                fontSize: 11, color: Colors.grey.shade600),
                          ),
                        ],
                      ),
                    ),
                    Switch(
                      value: _useExistingBalance,
                      onChanged: (v) =>
                          setState(() => _useExistingBalance = v),
                    ),
                  ],
                ),
                if (!_useExistingBalance) ...[
                  Container(
                    padding: const EdgeInsets.all(8),
                    margin: const EdgeInsets.only(bottom: 4),
                    decoration: BoxDecoration(
                      color: Colors.blue.shade50,
                      borderRadius: BorderRadius.circular(6),
                    ),
                    child: Row(
                      children: [
                        Icon(Icons.info_outline,
                            size: 14, color: Colors.blue.shade700),
                        const SizedBox(width: 6),
                        Expanded(
                          child: Text(
                            '现有 ¥${acc.balance.toStringAsFixed(0)} 不计入进度，'
                            '仅跟踪新增存款',
                            style: TextStyle(
                                fontSize: 11, color: Colors.blue.shade700),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ],

              const SizedBox(height: 12),

              // ── 截止日期 ──
              InkWell(
                onTap: () async {
                  final picked = await showDatePicker(
                    context: context,
                    initialDate: _deadline ??
                        DateTime.now().add(const Duration(days: 90)),
                    firstDate: DateTime.now(),
                    lastDate: DateTime(2100),
                  );
                  if (picked != null) setState(() => _deadline = picked);
                },
                child: InputDecorator(
                  decoration: const InputDecoration(
                    labelText: '截止日期（可空）',
                    border: OutlineInputBorder(),
                  ),
                  child: Row(
                    children: [
                      Expanded(
                        child: Text(
                          _deadline == null
                              ? '不设'
                              : DateFormat('yyyy-MM-dd').format(_deadline!),
                        ),
                      ),
                      if (_deadline != null)
                        IconButton(
                          icon: const Icon(Icons.close, size: 16),
                          onPressed: () => setState(() => _deadline = null),
                        ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 16),

              // ── 保存 ──
              FilledButton(
                onPressed: _saving ? null : _save,
                child: _saving
                    ? const SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(
                            strokeWidth: 2, color: Colors.white),
                      )
                    : const Text('保存'),
              ),
            ],
          ),
        ),
      ),
    );
  }

  /// 绑定账户的选择入口（复用记账页同样的交互）
  Widget _accountSelector() {
    final acc = _selectedAccount;
    return InkWell(
      onTap: _openAccountPicker,
      borderRadius: BorderRadius.circular(8),
      child: InputDecorator(
        decoration: const InputDecoration(
          border: OutlineInputBorder(),
          contentPadding: EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        ),
        child: Row(
          children: [
            Text(acc?.typeEmoji ?? '💰',
                style: const TextStyle(fontSize: 18)),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                acc?.name ?? '不绑定（手动追踪）',
                style: TextStyle(
                  fontSize: 14,
                  color: acc != null ? AppColors.text1 : Colors.grey,
                ),
              ),
            ),
            if (acc != null) ...[
              Text(
                '¥${acc.balance.toStringAsFixed(0)}',
                style: TextStyle(fontSize: 13, color: AppColors.text2),
              ),
              const SizedBox(width: 4),
              GestureDetector(
                onTap: () => setState(() => _selectedAccount = null),
                child: Icon(Icons.close, size: 18, color: AppColors.text2),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

// ═══════════════════════════════════════════════════════════════
// 账户选择器 BottomSheet（与 add_bill_screen 同样式）
// ═══════════════════════════════════════════════════════════════

class _AccountPickerSheet extends StatelessWidget {
  final List<Account> accounts;
  final String? selectedId;
  const _AccountPickerSheet({required this.accounts, required this.selectedId});

  @override
  Widget build(BuildContext context) {
    final mine = accounts.where((a) => !a.isShared).toList();
    final shared = accounts.where((a) => a.isShared).toList();
    final maxH = MediaQuery.of(context).size.height * 0.7;
    return ConstrainedBox(
      constraints: BoxConstraints(maxHeight: maxH),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // Header
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 14, 8, 10),
            child: Row(children: [
              Text('选择账户',
                  style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w600,
                      color: AppColors.text1)),
              const Spacer(),
              IconButton(
                onPressed: () => Navigator.pop(context),
                icon: Icon(Icons.close_rounded, color: AppColors.text2),
              ),
            ]),
          ),
          Divider(height: 1, color: AppColors.border),
          Flexible(
            child: ListView(
              padding: const EdgeInsets.fromLTRB(12, 8, 12, 20),
              children: [
                if (mine.isNotEmpty) _sectionHead('我的账户'),
                ...mine.map((a) => _accountTile(context, a)),
                if (shared.isNotEmpty) ...[
                  const SizedBox(height: 4),
                  _sectionHead('共享账户', hint: '账本成员共用'),
                ],
                ...shared.map((a) => _accountTile(context, a)),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _sectionHead(String title, {String? hint}) => Padding(
        padding: const EdgeInsets.fromLTRB(6, 8, 4, 6),
        child: Row(children: [
          Text(title,
              style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                  color: AppColors.text2)),
          if (hint != null) ...[
            const Spacer(),
            Text(hint,
                style: TextStyle(fontSize: 11, color: AppColors.text3)),
          ],
        ]),
      );

  Widget _accountTile(BuildContext context, Account a) {
    final sel = a.id == selectedId;
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: InkWell(
        onTap: () => Navigator.pop(context, a),
        borderRadius: BorderRadius.circular(12),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
          decoration: BoxDecoration(
            color: sel ? AppColors.primaryLight : AppColors.surface,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(
              color: sel ? AppColors.primary : AppColors.border,
              width: sel ? 1.5 : 1,
            ),
          ),
          child: Row(children: [
            Container(
              width: 38,
              height: 38,
              decoration: BoxDecoration(
                color: AppColors.surfaceAlt,
                borderRadius: BorderRadius.circular(10),
              ),
              child: Center(
                  child: Text(a.typeEmoji,
                      style: const TextStyle(fontSize: 20))),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(children: [
                    Flexible(
                      child: Text(a.name,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                              fontSize: 15,
                              fontWeight: FontWeight.w600,
                              color: AppColors.text1)),
                    ),
                    if (a.isShared) ...[
                      const SizedBox(width: 6),
                      Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 6, vertical: 2),
                        decoration: BoxDecoration(
                          color: AppColors.primaryLight,
                          borderRadius: BorderRadius.circular(4),
                        ),
                        child: Text('共享',
                            style: TextStyle(
                                fontSize: 10, color: AppColors.primary)),
                      ),
                    ],
                  ]),
                  const SizedBox(height: 2),
                  Text(
                    '${a.typeLabel}  ·  ¥${a.balance.toStringAsFixed(0)}',
                    style:
                        TextStyle(fontSize: 12, color: AppColors.text2),
                  ),
                ],
              ),
            ),
            if (sel)
              Icon(Icons.check_circle_rounded,
                  size: 22, color: AppColors.primary),
          ]),
        ),
      ),
    );
  }
}
