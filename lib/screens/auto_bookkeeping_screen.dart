import 'dart:async';

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../core/refresh_bus.dart';
import '../core/theme.dart';
import '../crypto/key_chain.dart';
import '../models/account.dart';
import '../models/category.dart';
import '../services/api_service.dart';
import '../services/auto_bookkeeping_service.dart';
import '../services/notification_parser.dart';
import '../services/recents_service.dart';
import '../widgets/siku_ui.dart';

/// ======================================================================
/// 自动记账（端侧 MVP）
/// ======================================================================
///
/// 监听用户授权的支付 / 银行 App 通知 → 本机解析成账单草稿 → 用户确认入账。
/// 全程本地处理，契合 E2E 隐私定位。
///
/// 页面结构：
///   - 顶部权限卡：查询「通知使用权」，未开启给引导按钮（3 秒轮询状态）
///   - 草稿列表：商户 / 金额 / 收支方向 / 来源 App / 时间
///     · 点击 → 确认层（选账户 + 选分类 + 备注 + 日期）
///     · 左滑 / 长按 → 忽略草稿
class AutoBookkeepingScreen extends StatefulWidget {
  const AutoBookkeepingScreen({super.key});

  @override
  State<AutoBookkeepingScreen> createState() => _AutoBookkeepingScreenState();
}

class _AutoBookkeepingScreenState extends State<AutoBookkeepingScreen> {
  final _svc = AutoBookkeepingService.instance;

  bool _checking = true;
  bool _enabled = false;
  List<ParsedBillDraft> _drafts = [];
  Timer? _permTimer;

  @override
  void initState() {
    super.initState();
    _svc.start();
    _svc.draftsVersion.addListener(_reloadDrafts);
    _checkPermission();
    _reloadDrafts();
    // 用户可能跳去系统设置页授权，回来后需要尽快感知 → 每 3 秒轮询
    _permTimer = Timer.periodic(
      const Duration(seconds: 3),
      (_) => _checkPermission(),
    );
  }

  @override
  void dispose() {
    _permTimer?.cancel();
    _svc.draftsVersion.removeListener(_reloadDrafts);
    super.dispose();
  }

  Future<void> _checkPermission() async {
    final ok = await _svc.isListenerEnabled();
    if (!mounted) return;
    if (ok != _enabled || _checking) {
      setState(() {
        _enabled = ok;
        _checking = false;
      });
    }
  }

  Future<void> _reloadDrafts() async {
    final list = await _svc.loadQueue();
    if (!mounted) return;
    setState(() => _drafts = list);
  }

  void _toast(String s) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(s)));
  }

  Future<void> _openSettings() async {
    final ok = await _svc.openListenerSettings();
    if (!ok) _toast('无法打开系统设置，请在系统设置中搜索「通知使用权」手动开启');
  }

  Future<void> _ignore(ParsedBillDraft d) async {
    await _svc.removeDraft(d.fingerprint);
    _toast('已忽略该草稿');
  }

  Future<void> _confirmIgnore(ParsedBillDraft d) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('忽略这条草稿？'),
        content: Text(
            '${d.displayMerchant} ¥${d.amount.toStringAsFixed(2)} 将不入账'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('取消')),
          TextButton(
              onPressed: () => Navigator.pop(context, true),
              child: const Text('忽略')),
        ],
      ),
    );
    if (ok == true) _ignore(d);
  }

  Future<void> _openConfirm(ParsedBillDraft d) async {
    final saved = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      builder: (_) => _ConfirmDraftSheet(draft: d),
    );
    if (saved == true) {
      await _svc.removeDraft(d.fingerprint);
      bumpRefresh();
      _toast('已入账');
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.bg,
      appBar: AuraAppBar(title: '自动记账'),
      body: AuraBackground(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(20, 12, 20, 40),
          children: [
            _permissionCard(),
            SectionHeader(
              title: _drafts.isEmpty ? '待确认草稿' : '待确认草稿（${_drafts.length}）',
              top: 24,
            ),
            if (_drafts.isEmpty)
              _emptyState()
            else
              for (var i = 0; i < _drafts.length; i++) ...[
                _draftTile(_drafts[i]),
                const SizedBox(height: 12),
              ],
          ],
        ),
      ),
    );
  }

  // ── 顶部权限卡 ──────────────────────────────────────────────

  Widget _permissionCard() {
    final statusColor = _checking
        ? AppColors.text3
        : _enabled
            ? AppColors.expense
            : AppColors.warning;
    final statusText = _checking ? '检测中…' : (_enabled ? '已开启' : '未开启');
    return GlassCard(
      radius: 18,
      padding: const EdgeInsets.all(18),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(children: [
            Container(
              width: 42,
              height: 42,
              decoration: BoxDecoration(
                color: AppColors.primaryLight,
                borderRadius: BorderRadius.circular(12),
              ),
              child: Icon(Icons.notifications_active_outlined,
                  color: AppColors.primary, size: 22),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('通知监听权限',
                      style: TextStyle(
                          fontSize: 15,
                          fontWeight: FontWeight.w600,
                          color: AppColors.text1)),
                  const SizedBox(height: 2),
                  Text(
                    _enabled ? '新收付款通知会在本机自动解析' : '授权后自动捕捉收付款通知',
                    style: TextStyle(fontSize: 12, color: AppColors.text2),
                  ),
                ],
              ),
            ),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
              decoration: BoxDecoration(
                color: AppColors.surfaceAlt,
                borderRadius: BorderRadius.circular(20),
              ),
              child: Text(statusText,
                  style: TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w600,
                      color: statusColor)),
            ),
          ]),
          if (!_checking && !_enabled) ...[
            const SizedBox(height: 14),
            Text(
              '司库只在本机解析支付 / 银行 App 的通知文案，生成草稿需你确认后才入账，通知内容不会上传到任何服务器。',
              style: TextStyle(fontSize: 12, height: 1.5, color: AppColors.text2),
            ),
            const SizedBox(height: 12),
            FilledButton.icon(
              onPressed: _openSettings,
              icon: const Icon(Icons.settings_outlined, size: 18),
              label: const Text('去开启「通知使用权」'),
            ),
          ],
        ],
      ),
    );
  }

  // ── 空状态 ─────────────────────────────────────────────────

  Widget _emptyState() {
    if (!_enabled) {
      return const EmptyState(
        emoji: '🔔',
        title: '开启通知监听，自动捕捉每一笔',
        hint: '授权后，微信 / 支付宝 / 云闪付 / 银行 App 的收付款通知\n会在这里生成账单草稿，全程本地处理。',
        top: 32,
      );
    }
    return const EmptyState(
      emoji: '🧾',
      title: '暂无待确认草稿',
      hint: '收到支付 / 银行 App 的收付款通知后，\n会自动生成草稿出现在这里。',
      top: 32,
    );
  }

  // ── 草稿条目 ────────────────────────────────────────────────

  Widget _draftTile(ParsedBillDraft d) {
    final dirColor = d.isExpense ? AppColors.expense : AppColors.income;
    final dirBg = d.isExpense ? AppColors.expenseLight : AppColors.incomeLight;
    return Dismissible(
      key: ValueKey(d.fingerprint),
      direction: DismissDirection.endToStart,
      background: Container(
        alignment: Alignment.centerRight,
        padding: const EdgeInsets.only(right: 20),
        decoration: BoxDecoration(
          color: AppColors.dangerLight,
          borderRadius: BorderRadius.circular(16),
        ),
        child: Row(mainAxisSize: MainAxisSize.min, children: [
          Icon(Icons.visibility_off_outlined, size: 18, color: AppColors.danger),
          const SizedBox(width: 6),
          Text('忽略',
              style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                  color: AppColors.danger)),
        ]),
      ),
      onDismissed: (_) => _ignore(d),
      child: GlassCard(
        radius: 16,
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        onTap: () => _openConfirm(d),
        child: GestureDetector(
          onLongPress: () => _confirmIgnore(d),
          behavior: HitTestBehavior.opaque,
          child: Row(children: [
            Container(
              width: 40,
              height: 40,
              decoration: BoxDecoration(
                color: dirBg,
                borderRadius: BorderRadius.circular(12),
              ),
              child: Icon(
                d.isExpense
                    ? Icons.arrow_upward_rounded
                    : Icons.arrow_downward_rounded,
                size: 20,
                color: dirColor,
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    d.displayMerchant,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.w600,
                        color: AppColors.text1),
                  ),
                  const SizedBox(height: 3),
                  Text(
                    '${d.sourceApp} · ${DateFormat('M月d日 HH:mm').format(d.time)}',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(fontSize: 12, color: AppColors.text2),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 10),
            Column(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                AmountText(
                  d.isExpense ? -d.amount : d.amount,
                  size: AmountSize.list,
                  tone: d.isExpense ? AmountTone.expense : AmountTone.income,
                  showSign: true,
                ),
                const SizedBox(height: 3),
                Text(d.isExpense ? '支出' : '收入',
                    style: TextStyle(fontSize: 11, color: dirColor)),
              ],
            ),
          ]),
        ),
      ),
    );
  }
}

// ═══════════════════════════════════════════════════════════════
// 确认入账弹层
// ═══════════════════════════════════════════════════════════════

class _ConfirmDraftSheet extends StatefulWidget {
  final ParsedBillDraft draft;
  const _ConfirmDraftSheet({required this.draft});

  @override
  State<_ConfirmDraftSheet> createState() => _ConfirmDraftSheetState();
}

class _ConfirmDraftSheetState extends State<_ConfirmDraftSheet> {
  bool _loading = true;
  bool _saving = false;

  List<Account> _accounts = [];
  List<Category> _categories = [];
  Account? _account;
  Category? _category;
  late DateTime _date;
  late final TextEditingController _noteCtrl;

  ParsedBillDraft get d => widget.draft;

  @override
  void initState() {
    super.initState();
    _date = d.time;
    _noteCtrl = TextEditingController(
      text: '自动记账·${d.sourceApp}${d.merchant.isNotEmpty ? '·${d.merchant}' : ''}',
    );
    _load();
  }

  @override
  void dispose() {
    _noteCtrl.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    try {
      final results = await Future.wait([
        ApiService.getAccounts(),
        ApiService.getCategories(),
        RecentsService.get(d.type),
        RecentsService.lastAccount(),
      ]);
      if (!mounted) return;

      final accounts = (results[0] as Map<String, dynamic>)['accounts']
              as List? ??
          [];
      final categories = (results[1] as Map<String, dynamic>)['categories']
              as List? ??
          [];
      final recentCats = (results[2] as List).cast<String>();
      final lastAccId = results[3] as String?;

      final accs = accounts
          .map((a) => Account.fromJson(a as Map<String, dynamic>))
          .toList();
      final typedCats = categories
          .map((c) => Category.fromJson(c as Map<String, dynamic>))
          .where((c) => c.type == d.type)
          .toList();

      // 账户默认：上次使用 > 第一个
      Account? acc;
      if (accs.isNotEmpty) {
        acc = accs.firstWhere((a) => a.id == lastAccId,
            orElse: () => accs.first);
      }

      // 分类默认：关键词智能默认 > 最近使用 > 第一个
      Category? cat = _smartDefaultCategory(typedCats, recentCats);

      setState(() {
        _accounts = accs;
        _categories = typedCats;
        _account = acc;
        _category = cat;
        _loading = false;
      });
    } catch (_) {
      if (mounted) setState(() => _loading = false);
    }
  }

  Category? _smartDefaultCategory(
      List<Category> typedCats, List<String> recentCats) {
    if (typedCats.isEmpty) return null;
    final suggested = NotificationParser.suggestCategory(d);
    if (suggested != null) {
      for (final c in typedCats) {
        if (c.name.contains(suggested)) return c;
      }
    }
    for (final id in recentCats) {
      for (final c in typedCats) {
        if (c.id == id) return c;
      }
    }
    return typedCats.first;
  }

  void _toast(String s) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(s)));
  }

  Future<void> _pickAccount() async {
    final result = await showModalBottomSheet<Account>(
      context: context,
      isScrollControlled: true,
      builder: (_) => _AccountPickerSheet(
        accounts: _accounts,
        selectedId: _account?.id,
      ),
    );
    if (result != null) setState(() => _account = result);
  }

  Future<void> _pickDate() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _date,
      firstDate: DateTime(2020),
      lastDate: DateTime.now().add(const Duration(days: 1)),
    );
    if (picked != null) {
      setState(() => _date = DateTime(picked.year, picked.month, picked.day,
          _date.hour, _date.minute));
    }
  }

  Future<void> _save() async {
    final acc = _account;
    final cat = _category;
    if (acc == null) return _toast('请选择账户');
    if (cat == null) return _toast('请选择分类');

    setState(() => _saving = true);
    try {
      // 备注用所选账户所在账本的 DEK 加密（与手动记账一致，服务端不见明文）
      final ledgerId = acc.ledgerId;
      final dekVer = KeyChain.instance.dekVersionOf(ledgerId) ?? 1;
      final noteCipher = KeyChain.instance.encryptText(
        ledgerId: ledgerId,
        plain: _noteCtrl.text.trim(),
      );

      await ApiService.createBill(
        type: d.type,
        amount: d.amount,
        categoryId: cat.id,
        accountId: acc.id,
        noteCipher: noteCipher,
        noteDekVer: dekVer,
        date: _date,
      );
      // 记住本次选择，作为下次的智能默认
      await RecentsService.add(d.type, cat.id);
      await RecentsService.setLastAccount(acc.id);
      if (!mounted) return;
      Navigator.pop(context, true);
    } catch (e) {
      _toast(e is ApiException ? e.message : '入账失败，请重试');
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final viewInsets = MediaQuery.of(context).viewInsets.bottom;

    return Padding(
      padding: EdgeInsets.only(bottom: viewInsets),
      child: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(16, 14, 16, 20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // ── 标题 ──
              Row(children: [
                const SizedBox(width: 40),
                Expanded(
                  child: Text('确认入账',
                      textAlign: TextAlign.center,
                      style: TextStyle(
                          fontSize: 17,
                          fontWeight: FontWeight.w700,
                          color: AppColors.text1)),
                ),
                SizedBox(
                  width: 40,
                  child: IconButton(
                    onPressed: () => Navigator.pop(context),
                    icon: Icon(Icons.close_rounded, color: AppColors.text2),
                  ),
                ),
              ]),
              const SizedBox(height: 12),

              // ── 摘要卡 ──
              Container(
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  color: AppColors.surfaceAlt,
                  borderRadius: BorderRadius.circular(14),
                ),
                child: Row(children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(d.displayMerchant,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                                fontSize: 15,
                                fontWeight: FontWeight.w600,
                                color: AppColors.text1)),
                        const SizedBox(height: 3),
                        Text(
                          '${d.sourceApp} · ${d.isExpense ? '支出' : '收入'}',
                          style: TextStyle(fontSize: 12, color: AppColors.text2),
                        ),
                      ],
                    ),
                  ),
                  AmountText(
                    d.isExpense ? -d.amount : d.amount,
                    size: AmountSize.card,
                    tone: d.isExpense ? AmountTone.expense : AmountTone.income,
                    showSign: true,
                  ),
                ]),
              ),
              const SizedBox(height: 16),

              if (_loading)
                const Padding(
                  padding: EdgeInsets.symmetric(vertical: 32),
                  child: Center(child: CircularProgressIndicator()),
                )
              else ...[
                // ── 账户 ──
                _fieldLabel('入账账户'),
                InkWell(
                  onTap: _pickAccount,
                  borderRadius: BorderRadius.circular(12),
                  child: InputDecorator(
                    decoration: const InputDecoration(
                      contentPadding:
                          EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                    ),
                    child: Row(children: [
                      Text(_account?.typeEmoji ?? '💰',
                          style: const TextStyle(fontSize: 18)),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          _account?.name ?? '请选择账户',
                          style: TextStyle(
                            fontSize: 14,
                            color: _account != null
                                ? AppColors.text1
                                : AppColors.text3,
                          ),
                        ),
                      ),
                      Icon(Icons.chevron_right_rounded,
                          size: 20, color: AppColors.text3),
                    ]),
                  ),
                ),
                const SizedBox(height: 14),

                // ── 分类 ──
                _fieldLabel('分类'),
                if (_categories.isEmpty)
                  Text('当前账本暂无${d.isExpense ? '支出' : '收入'}分类',
                      style: TextStyle(fontSize: 13, color: AppColors.text3))
                else
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      for (final c in _categories)
                        ChoiceChip(
                          label: Text('${c.displayIcon} ${c.name}'),
                          selected: _category?.id == c.id,
                          onSelected: (_) => setState(() => _category = c),
                        ),
                    ],
                  ),
                const SizedBox(height: 14),

                // ── 备注 ──
                _fieldLabel('备注'),
                TextField(
                  controller: _noteCtrl,
                  maxLength: 50,
                  decoration: const InputDecoration(
                    hintText: '可修改，将端到端加密后上传',
                    counterText: '',
                  ),
                ),
                const SizedBox(height: 14),

                // ── 日期 ──
                _fieldLabel('日期'),
                InkWell(
                  onTap: _pickDate,
                  borderRadius: BorderRadius.circular(12),
                  child: InputDecorator(
                    decoration: const InputDecoration(
                      contentPadding:
                          EdgeInsets.symmetric(horizontal: 12, vertical: 12),
                    ),
                    child: Row(children: [
                      Expanded(
                        child: Text(
                          DateFormat('yyyy年M月d日 HH:mm').format(_date),
                          style:
                              TextStyle(fontSize: 14, color: AppColors.text1),
                        ),
                      ),
                      Icon(Icons.calendar_month_outlined,
                          size: 18, color: AppColors.text3),
                    ]),
                  ),
                ),
                const SizedBox(height: 20),

                // ── 确认 ──
                FilledButton(
                  onPressed: _saving ? null : _save,
                  child: _saving
                      ? SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(
                              strokeWidth: 2, color: AppColors.onPrimary),
                        )
                      : const Text('确认入账'),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }

  Widget _fieldLabel(String text) => Padding(
        padding: const EdgeInsets.only(bottom: 6, left: 2),
        child: Text(text,
            style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w600,
                color: AppColors.text2)),
      );
}

// ═══════════════════════════════════════════════════════════════
// 账户选择器 BottomSheet（复刻 goals 页同款交互）
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
            Text(hint, style: TextStyle(fontSize: 11, color: AppColors.text3)),
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
                  child:
                      Text(a.typeEmoji, style: const TextStyle(fontSize: 20))),
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
                    a.balanceVisible
                        ? '${a.typeLabel}  ·  ¥${a.balance.toStringAsFixed(0)}'
                        : a.typeLabel,
                    style: TextStyle(fontSize: 12, color: AppColors.text2),
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
