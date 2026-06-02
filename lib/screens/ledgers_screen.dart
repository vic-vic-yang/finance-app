import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';
import '../core/refresh_bus.dart';
import '../core/theme.dart';
import '../widgets/glass.dart';
import '../crypto/key_chain.dart';
import '../models/ledger.dart';
import '../services/api_service.dart';
import '../services/auth_service.dart';
import '../services/pending_dek_resolver.dart';

class LedgersScreen extends StatefulWidget {
  const LedgersScreen({super.key});
  @override
  State<LedgersScreen> createState() => _LedgersScreenState();
}

class _LedgersScreenState extends State<LedgersScreen> {
  List<Ledger> _ledgers = [];
  String? _currentId;
  bool _loading = true;
  String _myUserId = '';

  @override
  void initState() {
    super.initState();
    _loadUser();
    _load();
  }

  Future<void> _loadUser() async {
    final u = await AuthService.getUser();
    if (mounted) setState(() => _myUserId = u?['id'] ?? '');
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    try {
      final res = await ApiService.getLedgers();
      if (!mounted) return;
      setState(() {
        _ledgers = (res['ledgers'] as List? ?? [])
            .map((l) => Ledger.fromJson(l as Map<String, dynamic>))
            .toList();
        _currentId = res['currentLedgerId'] as String?;
        _loading = false;
      });
      // 进账本管理页时顺手做一次：
      // 1. 给我所在账本里 pending 的新成员包装 DEK
      // 2. 给我自己还没拿到的 DEK 重拉一次（万一别人刚帮我 wrap 过）
      unawaited(PendingDekResolver.resolveAll());
      unawaited(PendingDekResolver.rehydrate());
    } catch (_) {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _switchTo(Ledger l) async {
    if (l.id == _currentId) return;
    try {
      await ApiService.switchLedger(l.id);
      // 同步本地缓存的 currentLedgerId
      final user = await AuthService.getUser() ?? {};
      user['currentLedgerId'] = l.id;
      await AuthService.saveUser(user);
      // 切到的账本如果还没拿到 DEK（如 Bob 刚加入还在 pending），
      // 重拉一次 keys/mine 看看是不是别人刚帮我 wrap 过了
      if (!KeyChain.instance.hasDek(l.id)) {
        await PendingDekResolver.rehydrate(requireLedgerId: l.id);
      }
      // 自己作为已有成员，借此机会给该账本 pending 的人补 DEK
      unawaited(PendingDekResolver.resolveOne(l.id));
      if (!mounted) return;
      setState(() => _currentId = l.id);
      bumpRefresh();
      _toast('已切换到「${l.name}」');
    } catch (_) {
      _toast('切换失败');
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

  Future<void> _createLedger() async {
    final nameCtrl = TextEditingController();
    final ok = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Text('新建账本'),
        content: TextField(
          controller: nameCtrl,
          autofocus: true,
          maxLength: 20,
          decoration: const InputDecoration(
            hintText: '账本名称，如：我们家、出差',
            counterText: '',
          ),
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('取消')),
          TextButton(
              onPressed: () => Navigator.pop(context, true),
              child: const Text('创建')),
        ],
      ),
    );
    if (ok != true) return;
    final name = nameCtrl.text.trim();
    if (name.isEmpty) return;
    if (!KeyChain.instance.hasKey) {
      _toast('密钥未就绪，请退出后重新登录');
      return;
    }
    try {
      // 客户端本地生成 DEK 并用自己的公钥包装
      final pack = KeyChain.instance.newDekForOwner();
      final res = await ApiService.createLedger(
        name: name,
        dekWrapped: pack.dekWrappedBase64,
      );
      // 立即把 DEK 装进本地缓存，省得马上要用时还要重新拉一次
      final ledger = res['ledger'] as Map<String, dynamic>?;
      final newId = ledger?['id'] as String?;
      if (newId != null) {
        KeyChain.instance.loadDek(
          ledgerId: newId,
          dekWrappedBase64: pack.dekWrappedBase64,
          dekVersion: pack.dekVersion,
        );
      }
      _toast('账本「$name」已创建');
      _load();
    } catch (e) {
      _toast('创建失败：$e');
    }
  }

  Future<void> _joinLedger() async {
    final codeCtrl = TextEditingController();
    final ok = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Text('加入账本'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('请输入对方分享的 6 位邀请码：',
                style: TextStyle(color: AppColors.text2, fontSize: 13)),
            const SizedBox(height: 12),
            TextField(
              controller: codeCtrl,
              autofocus: true,
              maxLength: 6,
              keyboardType: TextInputType.number,
              inputFormatters: [FilteringTextInputFormatter.digitsOnly],
              textAlign: TextAlign.center,
              style: const TextStyle(
                  fontSize: 22, letterSpacing: 6, fontWeight: FontWeight.bold),
              decoration: const InputDecoration(
                hintText: '000000',
                counterText: '',
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('取消')),
          TextButton(
              onPressed: () => Navigator.pop(context, true),
              child: const Text('加入')),
        ],
      ),
    );
    if (ok != true) return;
    final code = codeCtrl.text.trim();
    if (code.length != 6) {
      _toast('请输入 6 位邀请码');
      return;
    }
    try {
      final res = await ApiService.joinLedger(code);
      final ledger = res['ledger'] as Map<String, dynamic>?;
      if (ledger != null) {
        // 后端 join 时已把它设为当前账本，同步本地
        final user = await AuthService.getUser() ?? {};
        user['currentLedgerId'] = ledger['id'];
        await AuthService.saveUser(user);
        bumpRefresh();
      }
      // 提示用户当前还在 pending —— 等原成员上线 wrap DEK
      final pending = res['pending'] == true;
      _toast(pending
          ? '已加入，等待原成员授权解密（请稍候）'
          : (res['message']?.toString() ?? '加入成功'));
      _load();
    } catch (_) {
      _toast('加入失败：邀请码无效或已过期');
    }
  }

  Future<void> _showInviteCode(Ledger l) async {
    try {
      final res = await ApiService.createInvite(l.id);
      final code = res['code'] as String;
      final expiresAt = res['expiresAt'] as String?;
      if (!mounted) return;
      showDialog(
        context: context,
        builder: (_) => AlertDialog(
          shape:
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          title: Text('邀请加入「${l.name}」'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text('把下方邀请码发给 TA',
                  style:
                      TextStyle(color: AppColors.text2, fontSize: 13)),
              const SizedBox(height: 16),
              Container(
                padding: const EdgeInsets.symmetric(
                    horizontal: 24, vertical: 16),
                decoration: BoxDecoration(
                  color: AppColors.primaryLight,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Text(
                  code,
                  style: TextStyle(
                    fontSize: 32,
                    letterSpacing: 8,
                    fontWeight: FontWeight.bold,
                    color: AppColors.primary,
                  ),
                ),
              ),
              const SizedBox(height: 12),
              if (expiresAt != null)
                Text(
                  '有效期至 ${DateFormat('M月d日 HH:mm').format(DateTime.parse(expiresAt))}',
                  style: TextStyle(
                      fontSize: 12, color: AppColors.text2),
                ),
              const SizedBox(height: 4),
              Text('一次性使用，过期作废',
                  style: TextStyle(
                      fontSize: 12, color: AppColors.text2)),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () {
                Clipboard.setData(ClipboardData(text: code));
                _toast('已复制到剪贴板');
              },
              child: const Text('复制'),
            ),
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('完成'),
            ),
          ],
        ),
      );
    } catch (_) {
      _toast('生成邀请码失败');
    }
  }

  Future<void> _deleteLedger(Ledger l) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Text('删除账本'),
        content: Text('确定删除「${l.name}」？\n所有账户、账单、预算都会一并清除。'),
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
    try {
      await ApiService.deleteLedger(l.id);
      // 若当前账本被删，重新拉数据时后端会自动改为个人账本
      bumpRefresh();
      _load();
      _toast('已删除');
    } catch (_) {
      _toast('删除失败');
    }
  }

  Future<void> _leaveLedger(Ledger l) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Text('退出账本'),
        content: Text('确定退出「${l.name}」？\n退出后将看不到其中的数据。'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('取消')),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('退出', style: TextStyle(color: AppColors.expense)),
          ),
        ],
      ),
    );
    if (ok != true) return;
    try {
      await ApiService.removeMember(l.id, _myUserId);
      bumpRefresh();
      _load();
      _toast('已退出');
    } catch (_) {
      _toast('退出失败');
    }
  }

  Future<void> _viewMembers(Ledger l) async {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (_) => _MembersSheet(
        ledger: l,
        myUserId: _myUserId,
        onChanged: _load,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.bg,
      appBar: AuraAppBar(
        title: '账本管理',
        actions: [
          PopupMenuButton<String>(
            icon: const Icon(Icons.add_rounded),
            shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12)),
            itemBuilder: (_) => [
              PopupMenuItem(
                value: 'create',
                child: Row(children: [
                  Icon(Icons.add_box_outlined,
                      size: 18, color: AppColors.text2),
                  const SizedBox(width: 10),
                  const Text('新建账本'),
                ]),
              ),
              PopupMenuItem(
                value: 'join',
                child: Row(children: [
                  Icon(Icons.group_add_outlined,
                      size: 18, color: AppColors.text2),
                  const SizedBox(width: 10),
                  const Text('用邀请码加入'),
                ]),
              ),
            ],
            onSelected: (v) {
              if (v == 'create') _createLedger();
              if (v == 'join') _joinLedger();
            },
          ),
        ],
      ),
      body: AuraBackground(
        child: _loading
            ? Center(
                child: CircularProgressIndicator(color: AppColors.primary))
            : RefreshIndicator(
                color: AppColors.primary,
                onRefresh: _load,
                child: ListView.builder(
                  padding: const EdgeInsets.fromLTRB(16, 12, 16, 40),
                  itemCount: _ledgers.length,
                  itemBuilder: (_, i) {
                    final l = _ledgers[i];
                    return _ledgerCard(l);
                  },
                ),
              ),
      ),
    );
  }

  Widget _ledgerCard(Ledger l) {
    final isCurrent = l.id == _currentId;
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      decoration: BoxDecoration(
        color: isCurrent ? AppColors.primaryLight : AppColors.surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: isCurrent ? AppColors.primary : AppColors.border,
          width: isCurrent ? 1.5 : 1,
        ),
      ),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: BorderRadius.circular(16),
          onTap: isCurrent ? null : () => _switchTo(l),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 14, 12, 14),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(children: [
                  Container(
                    width: 44,
                    height: 44,
                    decoration: BoxDecoration(
                      color: AppColors.surfaceAlt,
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Center(
                      child: Text(l.displayIcon,
                          style: const TextStyle(fontSize: 22)),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(children: [
                          Flexible(
                            child: Text(
                              l.name,
                              style: TextStyle(
                                fontSize: 16,
                                fontWeight: FontWeight.w600,
                                color: AppColors.text1,
                              ),
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                          const SizedBox(width: 6),
                          if (isCurrent)
                            Container(
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 6, vertical: 1),
                              decoration: BoxDecoration(
                                color: AppColors.primary,
                                borderRadius: BorderRadius.circular(4),
                              ),
                              child: const Text(
                                '当前',
                                style: TextStyle(
                                  fontSize: 10,
                                  color: Colors.white,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                            ),
                        ]),
                        const SizedBox(height: 2),
                        Text(
                          [
                            if (l.isPersonal) '个人账本',
                            if (!l.isPersonal && l.isOwner) '我创建的',
                            if (!l.isPersonal && !l.isOwner)
                              'TA「${l.ownerDisplayName}」的',
                            '${l.memberCount} 人',
                            '${l.billCount} 笔账',
                          ].join(' · '),
                          style: TextStyle(
                              fontSize: 12, color: AppColors.text2),
                        ),
                      ],
                    ),
                  ),
                  PopupMenuButton<String>(
                    icon: Icon(Icons.more_vert_rounded,
                        color: AppColors.text2, size: 20),
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12)),
                    itemBuilder: (_) => [
                      if (!l.isPersonal)
                        PopupMenuItem(
                          value: 'members',
                          child: Row(children: [
                            Icon(Icons.people_outline_rounded,
                                size: 18, color: AppColors.text2),
                            SizedBox(width: 10),
                            Text('成员管理'),
                          ]),
                        ),
                      if (l.isOwner)
                        PopupMenuItem(
                          value: 'invite',
                          child: Row(children: [
                            Icon(Icons.person_add_alt_outlined,
                                size: 18, color: AppColors.primary),
                            SizedBox(width: 10),
                            Text('邀请他人'),
                          ]),
                        ),
                      if (!l.isPersonal && l.isOwner)
                        const PopupMenuItem(
                          value: 'delete',
                          child: Row(children: [
                            Icon(Icons.delete_outline_rounded,
                                size: 18, color: AppColors.expense),
                            SizedBox(width: 10),
                            Text('删除账本',
                                style:
                                    TextStyle(color: AppColors.expense)),
                          ]),
                        ),
                      if (!l.isPersonal && !l.isOwner)
                        const PopupMenuItem(
                          value: 'leave',
                          child: Row(children: [
                            Icon(Icons.logout_rounded,
                                size: 18, color: AppColors.expense),
                            SizedBox(width: 10),
                            Text('退出账本',
                                style:
                                    TextStyle(color: AppColors.expense)),
                          ]),
                        ),
                    ],
                    onSelected: (v) {
                      switch (v) {
                        case 'invite':
                          _showInviteCode(l);
                          break;
                        case 'members':
                          _viewMembers(l);
                          break;
                        case 'delete':
                          _deleteLedger(l);
                          break;
                        case 'leave':
                          _leaveLedger(l);
                          break;
                      }
                    },
                  ),
                ]),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

// ── 成员管理 sheet ────────────────────────────────────────────
class _MembersSheet extends StatefulWidget {
  const _MembersSheet({
    required this.ledger,
    required this.myUserId,
    required this.onChanged,
  });
  final Ledger ledger;
  final String myUserId;
  final VoidCallback onChanged;

  @override
  State<_MembersSheet> createState() => _MembersSheetState();
}

class _MembersSheetState extends State<_MembersSheet> {
  List<LedgerMember> _members = [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final res = await ApiService.getMembers(widget.ledger.id);
      if (!mounted) return;
      setState(() {
        _members = (res['members'] as List? ?? [])
            .map((m) => LedgerMember.fromJson(m as Map<String, dynamic>))
            .toList();
        _loading = false;
      });
    } catch (_) {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _kick(LedgerMember m) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Text('移除成员'),
        content: Text('确定把「${m.displayName}」移除出账本？'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('取消')),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('移除',
                style: TextStyle(color: AppColors.expense)),
          ),
        ],
      ),
    );
    if (ok != true) return;
    try {
      await ApiService.removeMember(widget.ledger.id, m.userId);
      widget.onChanged();
      _load();
    } catch (_) {}
  }

  @override
  Widget build(BuildContext context) {
    final iAmOwner = widget.ledger.isOwner;
    return Container(
      decoration: BoxDecoration(
        color: AppColors.bg,
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 32),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
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
            padding: const EdgeInsets.symmetric(horizontal: 4),
            child: Text('「${widget.ledger.name}」成员',
                style: const TextStyle(
                    fontSize: 16, fontWeight: FontWeight.bold)),
          ),
          const SizedBox(height: 12),
          if (_loading)
            Padding(
              padding: EdgeInsets.symmetric(vertical: 32),
              child: Center(
                  child: CircularProgressIndicator(color: AppColors.primary)),
            )
          else
            ..._members.map((m) {
              final isMe = m.userId == widget.myUserId;
              return Container(
                margin: const EdgeInsets.only(bottom: 8),
                decoration: BoxDecoration(
                  color: AppColors.surface,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: AppColors.border),
                ),
                child: ListTile(
                  leading: Container(
                    width: 36,
                    height: 36,
                    decoration: BoxDecoration(
                      color: AppColors.surfaceAlt,
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Center(
                      child: Text(
                        m.displayName.isEmpty
                            ? '?'
                            : m.displayName.substring(0, 1).toUpperCase(),
                        style: TextStyle(
                          color: AppColors.primary,
                          fontWeight: FontWeight.bold,
                          fontSize: 16,
                        ),
                      ),
                    ),
                  ),
                  title: Row(children: [
                    Flexible(
                      child: Text(m.displayName,
                          style: const TextStyle(
                              fontWeight: FontWeight.w500),
                          overflow: TextOverflow.ellipsis),
                    ),
                    if (isMe) ...[
                      const SizedBox(width: 4),
                      Text('（我）',
                          style: TextStyle(
                              fontSize: 12, color: AppColors.text2)),
                    ],
                  ]),
                  subtitle: Text(
                    m.isOwner ? '账本创建者' : '成员',
                    style: TextStyle(
                      fontSize: 12,
                      color: m.isOwner
                          ? AppColors.primary
                          : AppColors.text2,
                    ),
                  ),
                  trailing: (iAmOwner && !m.isOwner)
                      ? IconButton(
                          icon: const Icon(
                              Icons.person_remove_outlined,
                              color: AppColors.expense,
                              size: 20),
                          onPressed: () => _kick(m),
                        )
                      : null,
                ),
              );
            }),
        ],
      ),
    );
  }
}
