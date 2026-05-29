import 'dart:async';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../core/refresh_bus.dart';
import '../crypto/key_chain.dart';
import '../models/account.dart';
import '../models/bill.dart';
import '../models/category.dart';
import '../models/nl_draft.dart';
import '../screens/chat_screen.dart';
import '../services/api_service.dart';

/// 首页常驻的"一句话记账"输入区。
///
/// 三个状态：
///   1. 待输入 —— 一个 TextField + 发送按钮
///   2. 解析中 —— loading bar
///   3. 确认中 —— 草稿确认卡片：金额 / 分类 / 账户 / 日期 / 备注 可改
///
/// 通路 C：用户输入的整句文本会发送给服务端的 LLM，**首次使用必须弹隐私说明**。
class NlInputSection extends StatefulWidget {
  /// 当前账本 id
  final String ledgerId;
  /// 当前账本下可用的账户（用户筛选好的，共享 + 自己的私人）
  final List<Account> availableAccounts;
  /// 该账本的分类（用于确认卡片显示 + 编辑选择）
  final List<Category> categories;
  /// 默认账户 id（用户记账时通常用这个）；可空
  final String? defaultAccountId;

  const NlInputSection({
    super.key,
    required this.ledgerId,
    required this.availableAccounts,
    required this.categories,
    this.defaultAccountId,
  });

  @override
  State<NlInputSection> createState() => _NlInputSectionState();
}

class _NlInputSectionState extends State<NlInputSection> {
  static const _kPrivacyAckKey = 'nl_privacy_ack_v1';

  final _textCtrl = TextEditingController();
  final _focus = FocusNode();
  bool _busy = false;
  NlDraft? _draft;
  String? _error;
  // 会话上下文：上一笔的 accountId/type/date 用作 prevDraft
  NlDraft? _lastConfirmed;

  /// 客户端学习的快捷模板（取最近 50 笔聚类）
  List<_QuickTemplate> _templates = [];

  @override
  void initState() {
    super.initState();
    _learnTemplates();
  }

  @override
  void didUpdateWidget(covariant NlInputSection old) {
    super.didUpdateWidget(old);
    if (old.ledgerId != widget.ledgerId) _learnTemplates();
  }

  /// 取最近 50 笔账单，按 (categoryId, 金额取整到 5 的倍数) 聚类，
  /// 取 top 5 高频组合作为快捷模板。
  Future<void> _learnTemplates() async {
    try {
      final res = await ApiService.getBills(limit: 50);
      final bills = (res['bills'] as List? ?? [])
          .map((b) => Bill.fromJson(b as Map<String, dynamic>))
          .toList();
      final freq = <String, int>{};
      final byKey = <String, _QuickTemplate>{};
      for (final b in bills) {
        if (b.type == 'income') continue; // 模板只做支出（最常用）
        final catId = b.category.id;
        if (catId.isEmpty) continue;
        // 金额取整到 5 的倍数，便于聚类
        final bucket = (b.amount / 5).round() * 5;
        if (bucket <= 0) continue;
        final key = '$catId|$bucket';
        freq[key] = (freq[key] ?? 0) + 1;
        if (!byKey.containsKey(key)) {
          final cat = widget.categories.firstWhere(
            (c) => c.id == catId,
            orElse: () => Category(id: catId, name: b.category.name, type: 'expense'),
          );
          byKey[key] = _QuickTemplate(
            icon: cat.displayIcon,
            label: cat.name,
            amount: bucket.toDouble(),
            categoryId: catId,
          );
        }
      }
      final sorted = freq.entries.toList()
        ..sort((a, b) => b.value.compareTo(a.value));
      final top = sorted
          .where((e) => e.value >= 2) // 至少出现 2 次才有意义
          .take(5)
          .map((e) => byKey[e.key]!)
          .toList();
      if (mounted) setState(() => _templates = top);
    } catch (_) {
      // 学不到就不显示，正常用户路径不受影响
    }
  }

  Future<void> _applyTemplate(_QuickTemplate t) async {
    if (widget.availableAccounts.isEmpty) return;
    final acc = widget.availableAccounts.firstWhere(
      (a) => a.id == widget.defaultAccountId,
      orElse: () => widget.availableAccounts.first,
    );
    setState(() => _busy = true);
    try {
      final cipher = KeyChain.instance.encryptText(
        ledgerId: acc.ledgerId,
        plain: '',
      );
      final dekVer = KeyChain.instance.dekVersionOf(acc.ledgerId) ?? 1;
      await ApiService.createBill(
        type: 'expense',
        amount: t.amount,
        categoryId: t.categoryId,
        accountId: acc.id,
        noteCipher: cipher,
        noteDekVer: dekVer,
        date: DateTime.now(),
      );
      if (!mounted) return;
      setState(() => _busy = false);
      bumpRefresh();
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('已记一笔 ${t.label} ¥${t.amount.toStringAsFixed(0)}'),
          duration: const Duration(seconds: 1),
        ),
      );
      _learnTemplates(); // 重新学习，让频次最高的浮出来
    } catch (e) {
      if (!mounted) return;
      setState(() => _busy = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('保存失败：$e')),
      );
    }
  }

  @override
  void dispose() {
    _textCtrl.dispose();
    _focus.dispose();
    super.dispose();
  }

  Future<bool> _ensurePrivacyAck() async {
    final sp = await SharedPreferences.getInstance();
    if (sp.getBool(_kPrivacyAckKey) == true) return true;
    if (!mounted) return false;
    final ok = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (_) => AlertDialog(
        title: const Text('一句话记账：隐私说明'),
        content: const Text(
          '为了识别你这句话，输入的文本会被发送到 AI 模型方解析。\n\n'
          '• 解析后的草稿在你确认前不会入库\n'
          '• 入库时备注会用账本密钥加密\n'
          '• 模型方一般不会持久化你的请求内容，但请不要在这里粘贴敏感信息（密码、身份证、卡号…）\n\n'
          '不接受的话仍可以用手动记账（右下 +）',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('不接受'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('我同意'),
          ),
        ],
      ),
    );
    if (ok == true) {
      await sp.setBool(_kPrivacyAckKey, true);
      return true;
    }
    return false;
  }

  Future<void> _parse() async {
    final text = _textCtrl.text.trim();
    if (text.isEmpty) return;
    if (!await _ensurePrivacyAck()) return;

    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final res = await ApiService.aiParseText(
        ledgerId: widget.ledgerId,
        text: text,
        accountId: widget.defaultAccountId,
        prevDraft: _lastConfirmed == null
            ? null
            : {
                'accountId': _lastConfirmed!.accountId,
                'type': _lastConfirmed!.type,
                'date': _lastConfirmed!.date.toIso8601String(),
              },
      );
      final parsed = NlParseResult.fromJson(res);
      if (!mounted) return;
      setState(() {
        _busy = false;
        _draft = parsed.draft;
        _error = parsed.error;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _busy = false;
        _error = '网络错误：$e';
      });
    }
  }

  Future<void> _confirm() async {
    final d = _draft;
    if (d == null) return;
    final acc = widget.availableAccounts.firstWhere(
      (a) => a.id == d.accountId,
      orElse: () => widget.availableAccounts.first,
    );
    setState(() => _busy = true);
    try {
      final cipher = KeyChain.instance.encryptText(
        ledgerId: acc.ledgerId,
        plain: d.note,
      );
      final dekVer = KeyChain.instance.dekVersionOf(acc.ledgerId) ?? 1;
      await ApiService.createBill(
        type: d.type,
        amount: d.amount,
        categoryId: d.categoryId,
        accountId: d.accountId,
        noteCipher: cipher,
        noteDekVer: dekVer,
        date: d.date,
      );
      if (!mounted) return;
      setState(() {
        _busy = false;
        _lastConfirmed = d;
        _draft = null;
        _textCtrl.clear();
        _error = null;
      });
      bumpRefresh();
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('记好了 ✓'), duration: Duration(seconds: 1)),
      );
    } catch (e) {
      if (!mounted) return;
      setState(() => _busy = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('保存失败：$e')),
      );
    }
  }

  void _reset() {
    setState(() {
      _draft = null;
      _error = null;
    });
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (_draft == null && _templates.isNotEmpty) ...[
            SizedBox(
              height: 36,
              child: ListView.separated(
                scrollDirection: Axis.horizontal,
                itemCount: _templates.length,
                separatorBuilder: (_, __) => const SizedBox(width: 6),
                itemBuilder: (_, i) {
                  final t = _templates[i];
                  return ActionChip(
                    visualDensity: VisualDensity.compact,
                    label: Text(
                      '${t.icon} ${t.label} ${t.amount.toStringAsFixed(0)}',
                      style: const TextStyle(fontSize: 12),
                    ),
                    onPressed: _busy ? null : () => _applyTemplate(t),
                  );
                },
              ),
            ),
            const SizedBox(height: 8),
          ],
          AnimatedSize(
            duration: const Duration(milliseconds: 200),
            alignment: Alignment.topCenter,
            child: _draft != null ? _confirmCard() : _inputBar(),
          ),
        ],
      ),
    );
  }

  Widget _inputBar() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Container(
          decoration: BoxDecoration(
            color: Theme.of(context).cardColor,
            borderRadius: BorderRadius.circular(28),
            border: Border.all(color: Colors.grey.shade300),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withOpacity(0.04),
                blurRadius: 8,
                offset: const Offset(0, 2),
              ),
            ],
          ),
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
          child: Row(
            children: [
              const Text('💬', style: TextStyle(fontSize: 20)),
              const SizedBox(width: 8),
              Expanded(
                child: TextField(
                  controller: _textCtrl,
                  focusNode: _focus,
                  enabled: !_busy,
                  textInputAction: TextInputAction.send,
                  onSubmitted: (_) => _parse(),
                  decoration: const InputDecoration(
                    hintText: '说说你花了什么…（中午湘菜馆180）',
                    border: InputBorder.none,
                    isDense: true,
                  ),
                ),
              ),
              IconButton(
                tooltip: '对话助手',
                icon: const Text('🤖', style: TextStyle(fontSize: 18)),
                onPressed: _busy
                    ? null
                    : () => Navigator.push(
                          context,
                          MaterialPageRoute(
                            builder: (_) =>
                                ChatScreen(ledgerId: widget.ledgerId),
                          ),
                        ),
              ),
              _busy
                  ? const SizedBox(
                      width: 24,
                      height: 24,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : IconButton(
                      icon: const Icon(Icons.send_rounded),
                      onPressed: _parse,
                    ),
            ],
          ),
        ),
        if (_error != null) ...[
          const SizedBox(height: 6),
          Text(
            _error!,
            style: TextStyle(fontSize: 12, color: Colors.red.shade700),
          ),
        ],
      ],
    );
  }

  Widget _confirmCard() {
    final d = _draft!;
    final cat = widget.categories.firstWhere(
      (c) => c.id == d.categoryId,
      orElse: () => widget.categories.isNotEmpty
          ? widget.categories.first
          : Category(id: '', name: d.categoryName, type: d.type),
    );
    final acc = widget.availableAccounts.firstWhere(
      (a) => a.id == d.accountId,
      orElse: () => widget.availableAccounts.first,
    );

    final lowConf = d.confidence < 0.6;
    return Container(
      decoration: BoxDecoration(
        color: Theme.of(context).cardColor,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: lowConf ? Colors.orange.shade300 : Colors.green.shade300,
          width: 1,
        ),
      ),
      padding: const EdgeInsets.all(14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Text(
                lowConf ? '🤔 不太确定' : '🤖 已识别',
                style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600),
              ),
              const Spacer(),
              if (lowConf)
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                  decoration: BoxDecoration(
                    color: Colors.orange.shade50,
                    borderRadius: BorderRadius.circular(4),
                  ),
                  child: Text(
                    '置信度 ${(d.confidence * 100).round()}%',
                    style: TextStyle(fontSize: 10, color: Colors.orange.shade800),
                  ),
                ),
            ],
          ),
          const SizedBox(height: 10),
          // 金额行
          Row(
            children: [
              Text(
                d.isIncome ? '+' : '-',
                style: TextStyle(
                  fontSize: 26,
                  fontWeight: FontWeight.bold,
                  color: d.isIncome ? Colors.green : Colors.red,
                ),
              ),
              Text(
                d.amount.toStringAsFixed(2),
                style: TextStyle(
                  fontSize: 26,
                  fontWeight: FontWeight.bold,
                  color: d.isIncome ? Colors.green : Colors.red,
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          _fieldRow(cat.displayIcon, cat.fullName, '分类', onTap: _pickCategory),
          _fieldRow('💳', acc.name, '账户', onTap: _pickAccount),
          if (d.note.isNotEmpty) _fieldRow('📝', d.note, '备注', onTap: _editNote),
          _fieldRow(
            '📅',
            _formatDate(d.date),
            '日期',
            onTap: _pickDate,
          ),
          const SizedBox(height: 8),
          Row(
            mainAxisAlignment: MainAxisAlignment.end,
            children: [
              TextButton(
                onPressed: _busy ? null : _reset,
                child: const Text('取消'),
              ),
              const SizedBox(width: 4),
              FilledButton.icon(
                onPressed: _busy ? null : _confirm,
                icon: const Icon(Icons.check, size: 18),
                label: const Text('确认'),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _fieldRow(
    String icon,
    String value,
    String label, {
    VoidCallback? onTap,
  }) {
    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 4),
        child: Row(
          children: [
            Text(icon, style: const TextStyle(fontSize: 16)),
            const SizedBox(width: 8),
            Text('$label：', style: TextStyle(fontSize: 13, color: Colors.grey.shade600)),
            Expanded(
              child: Text(
                value,
                style: const TextStyle(fontSize: 14),
                overflow: TextOverflow.ellipsis,
              ),
            ),
            if (onTap != null)
              Icon(Icons.edit, size: 14, color: Colors.grey.shade400),
          ],
        ),
      ),
    );
  }

  String _formatDate(DateTime d) {
    final now = DateTime.now();
    final isToday = d.year == now.year && d.month == now.month && d.day == now.day;
    final hhmm =
        '${d.hour.toString().padLeft(2, '0')}:${d.minute.toString().padLeft(2, '0')}';
    if (isToday) return '今天 $hhmm';
    return '${d.month}月${d.day}日 $hhmm';
  }

  // ── 编辑器们 ─────────────────────────────────────────────
  Future<void> _pickCategory() async {
    final d = _draft!;
    final list = widget.categories
        .where((c) => c.type == d.type)
        .toList()
      ..sort((a, b) => a.fullName.compareTo(b.fullName));
    final picked = await showModalBottomSheet<String>(
      context: context,
      isScrollControlled: true,
      builder: (_) => _PickerSheet<Category>(
        title: '选择分类',
        items: list,
        itemBuilder: (c) => ListTile(
          leading: Text(c.displayIcon, style: const TextStyle(fontSize: 22)),
          title: Text(c.fullName),
          onTap: () => Navigator.pop(context, c.id),
          selected: c.id == d.categoryId,
        ),
      ),
    );
    if (picked != null) {
      final c = list.firstWhere((x) => x.id == picked);
      setState(() {
        _draft = d.copyWith(categoryId: picked, categoryName: c.fullName);
      });
    }
  }

  Future<void> _pickAccount() async {
    final d = _draft!;
    final picked = await showModalBottomSheet<String>(
      context: context,
      isScrollControlled: true,
      builder: (_) => _PickerSheet<Account>(
        title: '选择账户',
        items: widget.availableAccounts,
        itemBuilder: (a) => ListTile(
          leading: Text(a.icon ?? '💳', style: const TextStyle(fontSize: 22)),
          title: Text(a.name),
          subtitle: Text('¥${a.balance.toStringAsFixed(2)}'),
          onTap: () => Navigator.pop(context, a.id),
          selected: a.id == d.accountId,
        ),
      ),
    );
    if (picked != null) {
      setState(() => _draft = d.copyWith(accountId: picked));
    }
  }

  Future<void> _editNote() async {
    final d = _draft!;
    final ctrl = TextEditingController(text: d.note);
    final v = await showDialog<String>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('修改备注'),
        content: TextField(
          controller: ctrl,
          autofocus: true,
          maxLines: 3,
          decoration: const InputDecoration(border: OutlineInputBorder()),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text('取消')),
          FilledButton(
            onPressed: () => Navigator.pop(context, ctrl.text.trim()),
            child: const Text('保存'),
          ),
        ],
      ),
    );
    if (v != null) setState(() => _draft = d.copyWith(note: v));
  }

  Future<void> _pickDate() async {
    final d = _draft!;
    final picked = await showDatePicker(
      context: context,
      initialDate: d.date,
      firstDate: DateTime(2000),
      lastDate: DateTime(2100),
    );
    if (picked != null) {
      setState(() => _draft = d.copyWith(
            date: DateTime(
              picked.year,
              picked.month,
              picked.day,
              d.date.hour,
              d.date.minute,
            ),
          ));
    }
  }
}

/// 客户端学习出来的快捷模板：(分类, 取整金额) 的高频组合
class _QuickTemplate {
  final String icon;
  final String label;
  final double amount;
  final String categoryId;
  _QuickTemplate({
    required this.icon,
    required this.label,
    required this.amount,
    required this.categoryId,
  });
}

class _PickerSheet<T> extends StatelessWidget {
  final String title;
  final List<T> items;
  final Widget Function(T) itemBuilder;

  const _PickerSheet({
    required this.title,
    required this.items,
    required this.itemBuilder,
  });

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: Container(
        constraints: BoxConstraints(
          maxHeight: MediaQuery.of(context).size.height * 0.7,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Padding(
              padding: const EdgeInsets.all(16),
              child: Text(title, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
            ),
            const Divider(height: 1),
            Expanded(
              child: ListView(
                children: items.map(itemBuilder).toList(),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
