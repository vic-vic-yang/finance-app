import 'dart:async';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../core/refresh_bus.dart';
import '../core/theme.dart';
import '../widgets/glass.dart';
import '../crypto/key_chain.dart';
import '../models/account.dart';
import '../models/ai_import.dart';
import '../models/bill.dart';
import '../models/proposal.dart';
import '../services/api_service.dart';
import '../services/auth_service.dart';
import '../services/pending_dek_resolver.dart';
import '../services/funding_matcher.dart';
import '../services/payment_method_map.dart';
import 'cfo_screen.dart';

/// AI 智能导入：上传文件让 AI 解析为账单
class AiImportsScreen extends StatefulWidget {
  const AiImportsScreen({super.key});

  @override
  State<AiImportsScreen> createState() => _AiImportsScreenState();
}

class _AiImportsScreenState extends State<AiImportsScreen> {
  bool _loading = true;
  bool _uploading = false;
  List<AiImport> _items = [];
  List<Account> _accounts = [];
  String? _ledgerId;
  Timer? _poll;
  /// 已经触发过自动入库的 importId（防止 polling 重复触发）
  /// 正在入库中的导入 id（防并发重入）
  final Set<String> _applyingIds = {};
  /// 入库失败的导入 id → 原因（卡片上展示 + 提供手动「重试」，不再无限自动重试）
  final Map<String, String> _applyErr = {};
  /// 去重后没有新数据的导入 id（全部和已有账单重复，无需入库）
  final Set<String> _noNewData = {};

  @override
  void initState() {
    super.initState();
    _bootstrap();
  }

  @override
  void dispose() {
    _poll?.cancel();
    super.dispose();
  }

  Future<void> _bootstrap() async {
    _ledgerId = await AuthService.getCurrentLedgerId();
    if (_ledgerId == null) {
      setState(() => _loading = false);
      return;
    }
    try {
      final results = await Future.wait([
        ApiService.aiListImports(_ledgerId!),
        ApiService.getAccounts(),
      ]);
      if (!mounted) return;
      _items = (results[0]['imports'] as List? ?? [])
          .map((i) => AiImport.fromJson(i as Map<String, dynamic>))
          .toList();
      _accounts = (results[1]['accounts'] as List? ?? [])
          .map((a) => Account.fromJson(a as Map<String, dynamic>))
          .toList();
    } catch (_) {}
    if (mounted) setState(() => _loading = false);
    _maybeStartPolling();
    _maybeAutoApply();
  }

  /// 还有 in_progress / review_ready 时持续轮询
  void _maybeStartPolling() {
    final hasActive = _items.any((i) =>
        i.isInProgress || i.status == AiImportStatus.reviewReady);
    if (hasActive) {
      _poll?.cancel();
      _poll = Timer.periodic(const Duration(seconds: 3), (_) => _refresh());
    } else {
      _poll?.cancel();
      _poll = null;
    }
  }

  Future<void> _refresh() async {
    if (_ledgerId == null) return;
    try {
      final res = await ApiService.aiListImports(_ledgerId!);
      if (!mounted) return;
      setState(() {
        _items = (res['imports'] as List? ?? [])
            .map((i) => AiImport.fromJson(i as Map<String, dynamic>))
            .toList();
      });
      _maybeStartPolling();
      _maybeAutoApply();
    } catch (_) {}
  }

  /// 对所有 review_ready 且未在处理/未失败的导入，自动加密 + apply 入库
  Future<void> _maybeAutoApply() async {
    for (final item in _items) {
      if (item.status != AiImportStatus.reviewReady) continue;
      if (!item.hasDrafts) continue;
      if (_applyingIds.contains(item.id)) continue; // 正在处理
      if (_applyErr.containsKey(item.id)) continue;  // 失败的等用户手动重试
      if (_noNewData.contains(item.id)) continue;    // 全部重复，无需入库
      unawaited(_autoApplyOne(item));
    }
  }

  Future<void> _autoApplyOne(AiImport item) async {
    if (_applyingIds.contains(item.id)) return;
    if (mounted) {
      setState(() {
        _applyingIds.add(item.id);
        _applyErr.remove(item.id); // 重试时先清掉旧错误
      });
    } else {
      _applyingIds.add(item.id);
    }

    String? failReason;
    bool noNew = false;
    try {
      // 1) 拉草稿
      final res = await ApiService.aiGetImport(item.id);
      final drafts = (res['drafts'] as List? ?? [])
          .map((d) => AiDraft.fromJson(d as Map<String, dynamic>))
          .toList();
      if (drafts.isEmpty) {
        // 去重后没有新账单 —— 全部重复。仍要通知后端把状态置完成
        // （传空 bills 即可），否则后端一直停在 review_ready，
        // 角标会永远显示「入库中」。
        await ApiService.aiApplyImport(item.id, const <Map<String, dynamic>>[]);
        noNew = true;
        bumpRefresh();
        _refresh();
        return;
      }

      // 2) 找该导入用的目标账户 → 拿 ledgerId 给加密用
      Account? acc;
      for (final a in _accounts) {
        if (a.id == item.accountId) { acc = a; break; }
      }
      acc ??= _accounts.isNotEmpty ? _accounts.first : null;
      if (acc == null) {
        failReason = '找不到目标账户，请先创建账户';
        return;
      }
      final ledgerId = acc.ledgerId;

      // 密钥未就绪 → 先尝试 rehydrate（可能已被 wrap 好）；仍拿不到才报错
      if (!KeyChain.instance.hasDek(ledgerId)) {
        await PendingDekResolver.rehydrate(requireLedgerId: ledgerId);
      }
      if (!KeyChain.instance.hasDek(ledgerId)) {
        failReason = '账本密钥未就绪，切到该账本解锁后点重试';
        return;
      }
      final dekVer = KeyChain.instance.dekVersionOf(ledgerId) ?? 1;

      // 3) 客户端逐草稿解析资金账户 + 拆账单/转账
      final saved = await PaymentMethodMap.load(acc.ledgerId);
      final accPairs = _accounts.map((a) => (a.id, a.name)).toList();
      final accNameById = {for (final p in accPairs) p.$1: p.$2};
      String accNameOf(String id) => accNameById[id] ?? '账户';

      // 收支账单一律默认入到「上传时选的账户」：银行卡流水都是该卡本身；
      // 微信零钱→微信、支付宝余额宝→支付宝 等本就属于该来源，无需逐笔指认。
      // 仅当付款方式能明确匹配到另一个已存在的账户时，才自动归过去（不打扰用户）。
      String resolveAccount(AiDraft d) {
        final hint = d.fundingHint ?? '';
        if (hint.isEmpty) return item.accountId; // 兜底默认（上传时选的账户）
        final norm = normalizeFundingHint(hint);
        if (norm.isEmpty) return item.accountId;
        return matchAccountId(norm, accPairs, saved) ?? item.accountId;
      }

      // 「不计收支」转账行的对端账户解析（如花呗还款→转入花呗）。
      // 只在对端能匹配到一个**已存在**账户时才返回它（→ 记成转账，如花呗）；
      // 否则返回 null → 调用处按普通收/支记账，不弹框、不打扰用户。
      String? resolveTransferDest(AiDraft d) {
        final raw = d.counterparty ?? '';
        if (raw.isEmpty) return null;
        final norm = normalizeFundingHint(raw);
        if (norm.isEmpty) return null;
        return matchAccountId(norm, accPairs, saved);
      }

      final bills = <Map<String, dynamic>>[];
      final transfers = <Map<String, dynamic>>[];
      for (final d in drafts) {
        final fromId = resolveAccount(d);
        if (fromId.isEmpty) continue;
        if (d.direction == 'transfer') {
          final toId = resolveTransferDest(d);
          if (toId != null && toId != fromId) {
            // 账户间转账（如 储蓄卡 → 花呗 还款）→ 拆成一支一收两条账单，
            // 都标 isTransfer：在账单列表可见，但不计入收支统计/预算。
            final fromName = accNameOf(fromId);
            final toName = accNameOf(toId);
            final base = d.note.trim();
            final tail = base.isEmpty ? '' : ' · $base';
            final outNote = '转账·转出 → $toName$tail';
            final inNote = '转账·转入 ← $fromName$tail';
            bills.add({
              'accountId': fromId,
              'categoryId': d.categoryId,
              'type': 'expense',
              'amount': d.amount,
              'noteCipher': KeyChain.instance
                  .encryptText(ledgerId: acc.ledgerId, plain: outNote),
              'noteDekVer': dekVer,
              'date': d.date.toIso8601String(),
              if (d.externalId != null) 'externalId': d.externalId,
              'source': _sourceOf(item),
              'isTransfer': true,
            });
            bills.add({
              'accountId': toId,
              'categoryId': d.categoryId,
              'type': 'income',
              'amount': d.amount,
              'noteCipher': KeyChain.instance
                  .encryptText(ledgerId: acc.ledgerId, plain: inNote),
              'noteDekVer': dekVer,
              'date': d.date.toIso8601String(),
              // 转入这条不带 externalId，避免同一笔被跨源去重匹配两次
              'source': _sourceOf(item),
              'isTransfer': true,
            });
          } else {
            // 对端不是已有账户（转给别人/群收款/白条等）→ 不弹框，
            // 按这笔的资金方向默认记一笔收/支（绝不丢、不打扰用户）。
            final cipher = KeyChain.instance
                .encryptText(ledgerId: acc.ledgerId, plain: d.note);
            bills.add({
              'accountId': fromId,
              'categoryId': d.categoryId,
              'type': d.type == 'income' ? 'income' : 'expense',
              'amount': d.amount,
              'noteCipher': cipher,
              'noteDekVer': dekVer,
              'date': d.date.toIso8601String(),
              if (d.externalId != null) 'externalId': d.externalId,
              'source': _sourceOf(item),
            });
          }
        } else {
          final cipher = KeyChain.instance
              .encryptText(ledgerId: acc.ledgerId, plain: d.note);
          bills.add({
            'accountId': fromId,
            'categoryId': d.categoryId,
            'type': d.direction == 'income' ? 'income' : 'expense',
            'amount': d.amount,
            'noteCipher': cipher,
            'noteDekVer': dekVer,
            'date': d.date.toIso8601String(),
            if (d.externalId != null) 'externalId': d.externalId,
            'source': _sourceOf(item),
          });
        }
      }
      if (bills.isEmpty && transfers.isEmpty) {
        await ApiService.aiApplyImport(item.id, const <Map<String, dynamic>>[]);
        noNew = true;
        bumpRefresh();
        _refresh();
        return;
      }
      await ApiService.aiApplyImport(item.id, bills, transfers: transfers);
      // 通知其他屏（账单 / 账户 / 首页）刷新
      bumpRefresh();
      // 刷新列表卡片
      _refresh();
      // 新账单已落库 → 当场拉 CFO，有高优建议就弹提示（内部已 try/catch，不拖累主流程）
      await _watchAfterApply();
    } catch (e) {
      debugPrint('[ai-auto-apply] $e');
      failReason = _friendlyApplyErr(e);
    } finally {
      if (mounted) {
        setState(() {
          _applyingIds.remove(item.id);
          if (noNew) _noNewData.add(item.id);
          if (failReason != null) _applyErr[item.id] = failReason!;
        });
      } else {
        _applyingIds.remove(item.id);
        if (noNew) _noNewData.add(item.id);
      }
    }
  }

  String _friendlyApplyErr(Object e) {
    final s = e.toString().toLowerCase();
    if (s.contains('timeout')) return '入库超时（账单较多），点重试继续';
    if (s.contains('socket') || s.contains('connection')) {
      return '网络中断，点重试';
    }
    return '入库失败，点重试';
  }

  /// 一批账单 apply 成功后调用：拉 CFO，有 critical/warning 建议就当场弹提示。
  /// 失败/为空静默，绝不拖累导入主流程。
  Future<void> _watchAfterApply() async {
    try {
      final res = await ApiService.cfoProposals();
      final list = (res is List
              ? res
              : (res is Map
                  ? (res['proposals'] ?? res['data'] ?? const [])
                  : const []))
          as List;
      final items =
          list.map((e) => Proposal.fromJson(e as Map<String, dynamic>)).toList();
      final watch = items
          .where((p) => p.severity == 'critical' || p.severity == 'warning')
          .toList();
      if (watch.isEmpty || !mounted) return;
      _showWatchSheet(watch);
    } catch (_) {/* 静默 */}
  }

  void _showWatchSheet(List<Proposal> items) {
    showModalBottomSheet(
      context: context,
      backgroundColor: AppColors.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(children: [
                const Text('🧮', style: TextStyle(fontSize: 22)),
                const SizedBox(width: 10),
                Expanded(
                  child: Text('CFO 发现 ${items.length} 件值得看',
                      style: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.w700,
                          color: AppColors.text1)),
                ),
              ]),
              const SizedBox(height: 10),
              ...items.take(2).map((p) => Padding(
                    padding: const EdgeInsets.symmetric(vertical: 4),
                    child: Text('· ${p.title}',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(fontSize: 13, color: AppColors.text2)),
                  )),
              const SizedBox(height: 16),
              Row(children: [
                Expanded(
                  child: FilledButton(
                    onPressed: () {
                      Navigator.pop(ctx);
                      Navigator.push(context,
                          MaterialPageRoute(builder: (_) => const CfoScreen()));
                    },
                    child: const Text('查看'),
                  ),
                ),
                const SizedBox(width: 10),
                TextButton(
                  onPressed: () => Navigator.pop(ctx),
                  child: const Text('知道了'),
                ),
              ]),
            ],
          ),
        ),
      ),
    );
  }

  /// 文件名推断来源渠道
  String _sourceOf(AiImport item) {
    final n = item.filename;
    if (n.contains('支付宝') || n.toLowerCase().contains('alipay')) return 'alipay';
    if (n.contains('微信') || n.toLowerCase().contains('wechat') ||
        n.toLowerCase().contains('weixin')) return 'wechat';
    return 'manual';
  }

  Future<void> _pickAndUpload() async {
    if (_ledgerId == null) {
      _toast('请先选一个当前账本');
      return;
    }
    if (_accounts.isEmpty) {
      _toast('请先创建至少一个账户');
      return;
    }
    // 第一步：选目标账户（所有解析出的账单都入到这个账户里）
    final account = await _pickAccount();
    if (account == null) return;

    // 第二步：选文件
    final picked = await FilePicker.platform.pickFiles(
      allowMultiple: false,
      type: FileType.any,
      withData: true,
    );
    if (picked == null || picked.files.isEmpty) return;
    final f = picked.files.first;
    if (f.bytes == null) {
      _toast('文件读取失败');
      return;
    }

    setState(() => _uploading = true);
    try {
      await ApiService.aiUploadImport(
        ledgerId: _ledgerId!,
        accountId: account.id,
        filename: f.name,
        bytes: f.bytes!,
      );
      _toast('已上传到「${account.name}」，AI 处理中…');
      _refresh();
    } catch (e) {
      _toast('上传失败：$e');
    } finally {
      if (mounted) setState(() => _uploading = false);
    }
  }

  Future<Account?> _pickAccount() {
    return showModalBottomSheet<Account>(
      context: context,
      backgroundColor: AppColors.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (_) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 14, 16, 6),
              child: Row(children: [
                Icon(Icons.account_balance_wallet_outlined,
                    size: 18, color: AppColors.primary),
                const SizedBox(width: 8),
                Text('选择目标账户',
                    style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w600,
                        color: AppColors.text1)),
                const Spacer(),
                Text('AI 解析的账单将全部入到此账户',
                    style: TextStyle(
                        fontSize: 11, color: AppColors.text3)),
              ]),
            ),
            Flexible(
              child: ListView.separated(
                shrinkWrap: true,
                padding: const EdgeInsets.symmetric(vertical: 4),
                itemCount: _accounts.length,
                separatorBuilder: (_, __) =>
                    Divider(height: 1, color: AppColors.border),
                itemBuilder: (_, i) {
                  final a = _accounts[i];
                  return ListTile(
                    leading: Text(a.typeEmoji,
                        style: const TextStyle(fontSize: 22)),
                    title: Text(a.name),
                    subtitle: Text(
                        '${a.typeLabel}${a.isShared ? ' · 共享' : ''}',
                        style:
                            TextStyle(fontSize: 12, color: AppColors.text2)),
                    trailing: a.balanceVisible
                        ? Text(fmtMoney(a.balance),
                            style: TextStyle(
                                fontSize: 13,
                                fontWeight: FontWeight.w600,
                                color: AppColors.text1))
                        : null,
                    onTap: () => Navigator.pop(context, a),
                  );
                },
              ),
            ),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
  }

  Future<void> _openItem(AiImport item) async {
    // 流程已经全自动了。点击只在失败时展示失败原因，其他状态忽略。
    if (item.status == AiImportStatus.failed && item.message != null) {
      showDialog(
        context: context,
        builder: (_) => AlertDialog(
          title: const Text('失败原因'),
          content: Text(item.message!),
          actions: [
            TextButton(
                onPressed: () => Navigator.pop(context),
                child: const Text('知道了')),
          ],
        ),
      );
    }
  }

  Future<void> _deleteItem(AiImport item) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('删除导入记录？'),
        content: Text('${item.filename}\n这条记录及其草稿都会被永久删除（已入库的账单不受影响）'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('取消')),
          TextButton(
              onPressed: () => Navigator.pop(context, true),
              child: const Text('删除',
                  style: TextStyle(color: AppColors.expense))),
        ],
      ),
    );
    if (ok != true) return;
    try {
      await ApiService.aiDeleteImport(item.id);
      _refresh();
    } catch (e) {
      _toast('删除失败：$e');
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
    return Scaffold(
      backgroundColor: AppColors.bg,
      appBar: const AuraAppBar(title: 'AI 智能导入'),
      floatingActionButton: FloatingActionButton(
        onPressed: _uploading ? null : _pickAndUpload,
        tooltip: _uploading ? '上传中…' : '上传文件',
        child: _uploading
            ? const SizedBox(
                width: 22,
                height: 22,
                child: CircularProgressIndicator(
                    strokeWidth: 2.5, color: Colors.white),
              )
            : const Icon(Icons.upload_file_rounded, size: 26),
      ),
      body: AuraBackground(
        child: _loading
            ? Center(child: CircularProgressIndicator(color: AppColors.primary))
            : _items.isEmpty
                ? _empty()
                : RefreshIndicator(
                    onRefresh: _refresh,
                    color: AppColors.primary,
                    child: ListView.separated(
                      padding: const EdgeInsets.fromLTRB(16, 12, 16, 100),
                      itemCount: _items.length,
                      separatorBuilder: (_, __) => const SizedBox(height: 10),
                      itemBuilder: (_, i) => _card(_items[i]),
                    ),
                  ),
      ),
    );
  }

  Widget _empty() => Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Text('🤖', style: TextStyle(fontSize: 48)),
            const SizedBox(height: 12),
            Text('还没有 AI 导入记录',
                style: TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w600,
                    color: AppColors.text1)),
            const SizedBox(height: 6),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 40),
              child: Text(
                '点右下角"上传文件"，把图片 / PDF / CSV / Excel 交给 AI 自动记账',
                textAlign: TextAlign.center,
                style: TextStyle(
                    fontSize: 13, color: AppColors.text2, height: 1.5),
              ),
            ),
          ],
        ),
      );

  Widget _card(AiImport item) {
    return Material(
      color: AppColors.surface,
      borderRadius: BorderRadius.circular(14),
      child: InkWell(
        onTap: () => _openItem(item),
        borderRadius: BorderRadius.circular(14),
        child: Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: AppColors.border),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Text(item.fileTypeEmoji,
                      style: const TextStyle(fontSize: 22)),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(item.filename,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                                fontSize: 14,
                                fontWeight: FontWeight.w600,
                                color: AppColors.text1)),
                        const SizedBox(height: 2),
                        Text(
                          DateFormat('M月d日 HH:mm').format(item.createdAt),
                          style: TextStyle(
                              fontSize: 11, color: AppColors.text2),
                        ),
                      ],
                    ),
                  ),
                  _statusBadge(item),
                  IconButton(
                    icon: Icon(Icons.delete_outline_rounded,
                        size: 18, color: AppColors.text3),
                    onPressed: () => _deleteItem(item),
                    visualDensity: VisualDensity.compact,
                  ),
                ],
              ),
              if (item.isInProgress) ...[
                const SizedBox(height: 10),
                ClipRRect(
                  borderRadius: BorderRadius.circular(3),
                  child: LinearProgressIndicator(
                    value: item.progress / 100,
                    minHeight: 5,
                    backgroundColor: AppColors.surfaceAlt,
                    valueColor:
                        AlwaysStoppedAnimation(AppColors.primary),
                  ),
                ),
                if (item.message != null) ...[
                  const SizedBox(height: 6),
                  Text(item.message!,
                      style: TextStyle(
                          fontSize: 11, color: AppColors.text2)),
                ],
              ] else ...[
                const SizedBox(height: 8),
                Wrap(
                  spacing: 14,
                  runSpacing: 4,
                  children: [
                    _stat('解析', item.parsedCount),
                    _stat('去重', item.dupCount),
                    _stat('入库', item.insertedCount),
                  ],
                ),
                if ((item.status == AiImportStatus.reviewReady ||
                        item.status == AiImportStatus.partial) &&
                    item.hasDrafts) ...[
                  const SizedBox(height: 8),
                  if (_noNewData.contains(item.id))
                    Row(children: [
                      Icon(Icons.check_circle_outline_rounded,
                          size: 14, color: AppColors.text3),
                      const SizedBox(width: 6),
                      Expanded(
                        child: Text('全部与已有账单重复，无需入库',
                            style: TextStyle(
                                fontSize: 11, color: AppColors.text3)),
                      ),
                    ])
                  else if (_applyErr[item.id] != null)
                    Row(children: [
                      Icon(Icons.error_outline_rounded,
                          size: 14, color: AppColors.expense),
                      const SizedBox(width: 6),
                      Expanded(
                        child: Text(_applyErr[item.id]!,
                            style: TextStyle(
                                fontSize: 11, color: AppColors.expense)),
                      ),
                      const SizedBox(width: 6),
                      InkWell(
                        onTap: () => _autoApplyOne(item),
                        borderRadius: BorderRadius.circular(6),
                        child: Padding(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 8, vertical: 3),
                          child: Row(mainAxisSize: MainAxisSize.min, children: [
                            Icon(Icons.refresh_rounded,
                                size: 14, color: AppColors.primary),
                            const SizedBox(width: 2),
                            Text('重试',
                                style: TextStyle(
                                    fontSize: 12,
                                    color: AppColors.primary,
                                    fontWeight: FontWeight.w600)),
                          ]),
                        ),
                      ),
                    ])
                  else
                    Row(mainAxisSize: MainAxisSize.min, children: [
                      SizedBox(
                        width: 12,
                        height: 12,
                        child: CircularProgressIndicator(
                            strokeWidth: 2, color: AppColors.primary),
                      ),
                      const SizedBox(width: 6),
                      Text('正在自动加密并入库…',
                          style: TextStyle(
                              fontSize: 11, color: AppColors.primary)),
                    ]),
                ],
                if (item.status == AiImportStatus.failed &&
                    item.message != null) ...[
                  const SizedBox(height: 6),
                  Text(item.message!,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                          fontSize: 11, color: AppColors.expense)),
                ],
              ],
            ],
          ),
        ),
      ),
    );
  }

  Widget _stat(String label, int v) => Text(
        '$label $v',
        style: TextStyle(fontSize: 11, color: AppColors.text2),
      );

  Widget _statusBadge(AiImport item) {
    Color bg, fg;
    switch (item.status) {
      case AiImportStatus.done:
        bg = AppColors.incomeLight;
        fg = AppColors.income;
        break;
      case AiImportStatus.failed:
        bg = AppColors.expenseLight;
        fg = AppColors.expense;
        break;
      case AiImportStatus.reviewReady:
      case AiImportStatus.partial:
        bg = AppColors.primaryLight;
        fg = AppColors.primary;
        break;
      default:
        bg = AppColors.warningLight;
        fg = AppColors.warning;
    }
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(6),
      ),
      child: Text(
        item.statusLabel,
        style: TextStyle(fontSize: 11, color: fg, fontWeight: FontWeight.w600),
      ),
    );
  }
}
