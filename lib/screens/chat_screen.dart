import 'package:flutter/material.dart';
import 'package:flutter_markdown/flutter_markdown.dart';
import 'package:markdown/markdown.dart' as md;
import '../widgets/siku_ui.dart';
import '../core/theme.dart';
import '../core/refresh_bus.dart';
import '../crypto/key_chain.dart';
import '../models/account.dart';
import '../models/bill.dart';
import '../models/chat_message.dart';
import '../models/savings_goal.dart';
import '../services/api_service.dart';
import '../services/auth_service.dart';

/// 对话式财务查询页
///
/// - 消息历史在内存里，关闭即丢（避免端到端加密的写入开销）
/// - 每次 send 把最近 N 条 user/assistant 文本作为 history 发回
/// - 服务器返回的卡片（stat/budget）内嵌在 AI 气泡下方
/// - 通路 B：服务器无法解密 note 做商户聚合时，会返回 pendingClientAggregation +
///   billIds，前端拉这些账单解密后本地构造 MerchantCard
class ChatScreen extends StatefulWidget {
  final String ledgerId;
  /// 进入后自动替用户发出的第一句话（如从洞察卡「问 AI」跳来）
  final String? initialPrompt;
  const ChatScreen({super.key, required this.ledgerId, this.initialPrompt});

  @override
  State<ChatScreen> createState() => _ChatScreenState();
}

class _ChatScreenState extends State<ChatScreen> {
  final _ctrl = TextEditingController();
  final _scroll = ScrollController();
  final List<ChatTurn> _turns = [];
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    final p = widget.initialPrompt?.trim();
    if (p != null && p.isNotEmpty) {
      WidgetsBinding.instance.addPostFrameCallback((_) => _send(p));
    }
  }

  static const _suggestions = <String>[
    '上个月哪类花最多',
    '预算还剩多少',
    '储蓄目标进度',
    '我有多少负债',
  ];

  @override
  void dispose() {
    _ctrl.dispose();
    _scroll.dispose();
    super.dispose();
  }

  Future<void> _send([String? preset]) async {
    final text = (preset ?? _ctrl.text).trim();
    if (text.isEmpty || _busy) return;
    if (preset == null) _ctrl.clear();

    setState(() {
      _turns.add(ChatTurn(role: 'user', content: text));
      _busy = true;
    });
    _scrollToBottom();

    try {
      // 取最近 10 轮（5 user + 5 assistant）作为 history
      final hist = _turns
          .where((t) => t.role == 'user' || t.role == 'assistant')
          .toList();
      // 不把当前这条 user 发回（服务端会单独取 message 字段）
      final histForApi = hist
          .sublist(0, hist.length - 1)
          .map((t) => {'role': t.role, 'content': t.content})
          .toList()
        ..take(20); // 客户端再保险截一下
      final res = await ApiService.aiChat(
        ledgerId: widget.ledgerId,
        message: text,
        history: histForApi,
      );
      final reply = (res['reply'] as String?) ?? '';
      final cardList = (res['cards'] as List? ?? [])
          .map((c) => ReplyCard.fromJson(c as Map<String, dynamic>))
          .toList();
      final pending = res['pendingClientAggregation'] as Map<String, dynamic>?;

      // 商户聚合（通路 B）
      MerchantCard? merchant;
      if (pending != null && pending['task'] == 'merchant') {
        final ids = (pending['billIds'] as List).cast<String>();
        final period = (pending['period'] as String?) ?? '';
        merchant = await _aggregateMerchants(ids, period);
      }

      if (!mounted) return;
      setState(() {
        _turns.add(ChatTurn(
          role: 'assistant',
          content: reply,
          cards: cardList,
          merchantCard: merchant,
        ));
        _busy = false;
      });
      _scrollToBottom();
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _turns.add(ChatTurn(role: 'assistant', content: '出错了：$e'));
        _busy = false;
      });
      _scrollToBottom();
    }
  }

  /// 通路 B：客户端解密这些 bills 的 note，从中提取商户名（取前 N 个非空段）聚合
  Future<MerchantCard> _aggregateMerchants(
    List<String> billIds,
    String period,
  ) async {
    // 拉这些 bill（已经按 ledgerId 隔离）
    // ApiService.getBills 取最近 limit 条；这里直接调一次拿够，然后过滤
    final res = await ApiService.getBills(limit: 200);
    final bills = (res['bills'] as List? ?? [])
        .map((b) => Bill.fromJson(b as Map<String, dynamic>))
        .where((b) => billIds.contains(b.id))
        .toList();

    final byMerchant = <String, _MerchantAgg>{};
    for (final b in bills) {
      final note = b.note;
      // note 形如 "美团外卖·麻辣烫·堂食"，第一段当 merchant
      final merchant = note.split('·').first.trim();
      if (merchant.isEmpty || merchant.startsWith('【')) continue;
      final agg = byMerchant.putIfAbsent(
        merchant,
        () => _MerchantAgg(name: merchant),
      );
      agg.amount += b.amount;
      agg.count += 1;
    }
    final buckets = byMerchant.values.toList()
      ..sort((a, b) => b.amount.compareTo(a.amount));
    return MerchantCard(
      period: period,
      totalCount: bills.length,
      buckets: buckets
          .take(10)
          .map((m) => {
                'merchant': m.name,
                'amount': m.amount,
                'count': m.count,
              })
          .toList(),
    );
  }

  void _scrollToBottom() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!_scroll.hasClients) return;
      _scroll.animateTo(
        _scroll.position.maxScrollExtent + 200,
        duration: const Duration(milliseconds: 200),
        curve: Curves.easeOut,
      );
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.bg,
      appBar: const AuraAppBar(title: '司库助手'),
      body: AuraBackground(
        child: Column(
          children: [
            Expanded(
              child: _turns.isEmpty
                  ? _empty()
                  : ListView.builder(
                      controller: _scroll,
                      padding: const EdgeInsets.symmetric(vertical: 12),
                      itemCount: _turns.length + (_busy ? 1 : 0),
                      itemBuilder: (_, i) {
                        if (i == _turns.length) return _thinkingBubble();
                        return _bubble(_turns[i]);
                      },
                    ),
            ),
            _inputBar(),
          ],
        ),
      ),
    );
  }

  // ── 空状态 ─────────────────────────────────────────────
  Widget _empty() {
    return Center(
      child: EmptyState(
        emoji: '💬',
        title: '问问你的钱去哪了',
        hint: '我可以帮你查统计、看预算、找趋势',
        top: 0,
        action: Wrap(
          spacing: 8,
          runSpacing: 8,
          alignment: WrapAlignment.center,
          children: [
            for (final s in _suggestions)
              ActionChip(label: Text(s), onPressed: () => _send(s)),
          ],
        ),
      ),
    );
  }

  // ── 气泡 ─────────────────────────────────────────────
  Widget _bubble(ChatTurn t) {
    final isUser = t.isUser;
    // 气泡配色：用户 = primaryLight 轻强调，助手 = surfaceAlt，文字统一 text1
    final fg = AppColors.text1;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisAlignment: isUser ? MainAxisAlignment.end : MainAxisAlignment.start,
        children: [
          if (!isUser) ...[
            CircleAvatar(
              radius: 16,
              backgroundColor: AppColors.primaryLight,
              child: Icon(Icons.auto_awesome_rounded,
                  size: 16, color: AppColors.primary),
            ),
            const SizedBox(width: 8),
          ],
          Flexible(
            child: Column(
              crossAxisAlignment:
                  isUser ? CrossAxisAlignment.end : CrossAxisAlignment.start,
              children: [
                Container(
                  padding: const EdgeInsets.all(12),
                  constraints: BoxConstraints(
                    maxWidth: MediaQuery.of(context).size.width * 0.78,
                  ),
                  decoration: BoxDecoration(
                    color: isUser ? AppColors.primaryLight : AppColors.surfaceAlt,
                    borderRadius: BorderRadius.circular(14).copyWith(
                      topLeft: isUser ? null : const Radius.circular(2),
                      topRight: isUser ? const Radius.circular(2) : null,
                    ),
                  ),
                  // 助手回复按 Markdown 渲染（表格/加粗/列表都正常显示）；
                  // 用户消息保持纯文本
                  child: isUser
                      ? Text(
                          t.content,
                          style: TextStyle(fontSize: 14, height: 1.5, color: fg),
                        )
                      : _markdown(t.content, fg),
                ),
                for (final c in t.cards) ...[
                  const SizedBox(height: 6),
                  _renderCard(c),
                ],
                if (t.merchantCard != null) ...[
                  const SizedBox(height: 6),
                  _merchantCardWidget(t.merchantCard!),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }

  /// 助手 Markdown 渲染：GFM（含表格），配色对齐主题。
  /// [fg] = 气泡文字色（text1），保证任何气泡底色上文字可读。
  Widget _markdown(String content, Color fg) {
    final base = TextStyle(fontSize: 14, height: 1.5, color: fg);
    return MarkdownBody(
      data: content,
      selectable: true,
      extensionSet: md.ExtensionSet.gitHubFlavored,
      styleSheet: MarkdownStyleSheet(
        p: base,
        strong: base.copyWith(fontWeight: FontWeight.w700),
        listBullet: base,
        h1: TextStyle(fontSize: 17, fontWeight: FontWeight.w700, color: fg),
        h2: TextStyle(fontSize: 16, fontWeight: FontWeight.w700, color: fg),
        h3: TextStyle(fontSize: 15, fontWeight: FontWeight.w600, color: fg),
        code: TextStyle(
            fontSize: 13, backgroundColor: AppColors.surfaceAlt, color: fg),
        blockquoteDecoration: BoxDecoration(
          color: AppColors.surfaceAlt,
          borderRadius: BorderRadius.circular(8),
        ),
        tableHead: base.copyWith(
            fontWeight: FontWeight.w700, fontSize: 12.5),
        tableBody: base.copyWith(fontSize: 12.5),
        tableBorder: TableBorder.all(color: AppColors.border, width: 0.7),
        tableCellsPadding:
            const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
        tableColumnWidth: const IntrinsicColumnWidth(),
      ),
    );
  }

  Widget _thinkingBubble() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
      child: Row(
        children: [
          CircleAvatar(
            radius: 16,
            backgroundColor: AppColors.primaryLight,
            child: Icon(Icons.auto_awesome_rounded,
                size: 16, color: AppColors.primary),
          ),
          const SizedBox(width: 8),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
            decoration: BoxDecoration(
              color: AppColors.surfaceAlt,
              borderRadius: BorderRadius.circular(14),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                const SizedBox(
                  width: 12,
                  height: 12,
                  child: CircularProgressIndicator(strokeWidth: 2),
                ),
                const SizedBox(width: 8),
                Text('思考中…',
                    style: TextStyle(fontSize: 13, color: AppColors.text2)),
              ],
            ),
          ),
        ],
      ),
    );
  }

  // ── 卡片渲染 ───────────────────────────────────────────
  Widget _renderCard(ReplyCard c) {
    if (c.type == 'stat') {
      return _statCard(c.data);
    }
    if (c.type == 'budget') {
      return _budgetCard(c.data);
    }
    if (c.type == 'bill_draft') {
      return _BillDraftCard(data: c.data);
    }
    if (c.type == 'cfo_action') {
      return _CfoActionCard(
        proposalId: c.data['proposalId'] as String,
        title: (c.data['title'] as String?) ?? '待确认操作',
        body: (c.data['body'] as String?) ?? '',
        requiresClient: (c.data['requiresClient'] as bool?) ?? false,
        actionKind: (c.data['actionKind'] as String?) ?? '',
        params:
            (c.data['actionParams'] as Map?)?.cast<String, dynamic>() ??
                const {},
      );
    }
    // 未知类型：JSON 兜底
    return Container(
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: AppColors.border),
      ),
      child: Text(c.data.toString(),
          style: Theme.of(context).textTheme.bodySmall),
    );
  }

  Widget _statCard(Map<String, dynamic> data) {
    final title = (data['title'] as String?) ?? '统计';
    final total = ((data['total'] as num?) ?? 0).toDouble();
    final count = (data['count'] as num?)?.toInt();
    final period = data['period'] as String?;
    final buckets = (data['buckets'] as List? ?? [])
        .cast<Map>()
        .map((b) => b.cast<String, dynamic>())
        .toList();

    return _ReplyCardShell(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Text(title, style: Theme.of(context).textTheme.bodySmall),
              if (period != null) ...[
                const Spacer(),
                Text(period, style: Theme.of(context).textTheme.bodySmall),
              ],
            ],
          ),
          const SizedBox(height: 4),
          Row(
            crossAxisAlignment: CrossAxisAlignment.baseline,
            textBaseline: TextBaseline.alphabetic,
            children: [
              AmountText(total, size: AmountSize.card),
              if (count != null) ...[
                const SizedBox(width: 8),
                Text('$count 笔', style: Theme.of(context).textTheme.bodySmall),
              ],
            ],
          ),
          if (buckets.isNotEmpty) ...[
            const Divider(height: 16),
            for (final b in buckets.take(8))
              _bucketRow(
                (b['label'] as String?) ?? '?',
                ((b['amount'] as num?) ?? 0).toDouble(),
                total,
                count: (b['count'] as num?)?.toInt(),
              ),
          ],
        ],
      ),
    );
  }

  Widget _bucketRow(String label, double amount, double total, {int? count}) {
    final ratio = total > 0 ? (amount / total).clamp(0.0, 1.0) : 0.0;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                  child: Text(label,
                      style: TextStyle(fontSize: 13, color: AppColors.text1))),
              if (count != null)
                Padding(
                  padding: const EdgeInsets.only(right: 8),
                  child: Text('$count',
                      style: Theme.of(context).textTheme.bodySmall),
                ),
              AmountText(amount, size: AmountSize.aux),
            ],
          ),
          const SizedBox(height: 2),
          LinearProgressIndicator(
            value: ratio,
            minHeight: 4,
            borderRadius: BorderRadius.circular(2),
            backgroundColor: AppColors.surfaceAlt,
            valueColor: AlwaysStoppedAnimation(AppColors.primary),
          ),
        ],
      ),
    );
  }

  Widget _budgetCard(Map<String, dynamic> data) {
    final items = (data['items'] as List? ?? [])
        .cast<Map>()
        .map((m) => m.cast<String, dynamic>())
        .toList();
    if (items.isEmpty) {
      return _ReplyCardShell(
        padding: const EdgeInsets.all(12),
        child: Text('未设预算',
            style: TextStyle(fontSize: 12, color: AppColors.text3)),
      );
    }
    return _ReplyCardShell(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('预算执行', style: Theme.of(context).textTheme.bodySmall),
          const SizedBox(height: 6),
          for (final it in items)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 4),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          (it['categoryName'] as String?) ?? '',
                          style:
                              TextStyle(fontSize: 13, color: AppColors.text1),
                        ),
                      ),
                      AmountText(
                        ((it['spent'] as num?) ?? 0).toDouble(),
                        size: AmountSize.aux,
                        decimals: 0,
                      ),
                      Text(' / ',
                          style:
                              TextStyle(fontSize: 12, color: AppColors.text3)),
                      AmountText(
                        ((it['limit'] as num?) ?? 0).toDouble(),
                        size: AmountSize.aux,
                        decimals: 0,
                        color: AppColors.text2,
                      ),
                    ],
                  ),
                  const SizedBox(height: 2),
                  // 进度语义色：超支 danger · 将尽 warning · 正常 expense
                  LinearProgressIndicator(
                    value: ((it['rate'] as num?) ?? 0).toDouble().clamp(0.0, 1.0),
                    minHeight: 4,
                    borderRadius: BorderRadius.circular(2),
                    backgroundColor: AppColors.surfaceAlt,
                    valueColor: AlwaysStoppedAnimation(
                      ((it['rate'] as num?) ?? 0) >= 1
                          ? AppColors.danger
                          : ((it['rate'] as num?) ?? 0) >= 0.9
                              ? AppColors.warning
                              : AppColors.expense,
                    ),
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }

  Widget _merchantCardWidget(MerchantCard m) {
    return _ReplyCardShell(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Text('🏪 商户分布',
                  style: Theme.of(context).textTheme.bodySmall),
              const Spacer(),
              Text(m.period, style: Theme.of(context).textTheme.bodySmall),
            ],
          ),
          const SizedBox(height: 4),
          if (m.buckets.isEmpty)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 4),
              child: Text('没识别出商户名（账单可能没填备注）',
                  style: TextStyle(fontSize: 12, color: AppColors.text3)),
            )
          else
            for (final b in m.buckets)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 3),
                child: Row(
                  children: [
                    Expanded(
                      child: Text(
                        b['merchant'] as String,
                        style:
                            TextStyle(fontSize: 13, color: AppColors.text1),
                      ),
                    ),
                    Text(
                      '${(b['count'] as int)} 笔',
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                    const SizedBox(width: 8),
                    AmountText(b['amount'] as double, size: AmountSize.aux),
                  ],
                ),
              ),
          if (m.totalCount > m.buckets.length)
            Padding(
              padding: const EdgeInsets.only(top: 6),
              child: Text(
                '共 ${m.totalCount} 笔，仅显示 top ${m.buckets.length}',
                style: TextStyle(fontSize: 11, color: AppColors.text3),
              ),
            ),
        ],
      ),
    );
  }

  // ── 输入栏 ─────────────────────────────────────────────
  Widget _inputBar() {
    return SafeArea(
      child: Container(
        padding: const EdgeInsets.fromLTRB(12, 8, 12, 8),
        decoration: BoxDecoration(
          color: AppColors.surface,
          border: Border(top: BorderSide(color: AppColors.border, width: 0.6)),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // 快捷提问 chips：点击直接发送（_send 内部会在 _busy 时忽略）
            SizedBox(
              height: 36,
              child: ListView.separated(
                scrollDirection: Axis.horizontal,
                itemCount: _suggestions.length,
                separatorBuilder: (_, __) => const SizedBox(width: 8),
                itemBuilder: (_, i) {
                  final s = _suggestions[i];
                  return ActionChip(
                    label: Text(s),
                    onPressed: _busy ? null : () => _send(s),
                  );
                },
              ),
            ),
            const SizedBox(height: 8),
            Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _ctrl,
                    enabled: !_busy,
                    minLines: 1,
                    maxLines: 3,
                    textInputAction: TextInputAction.send,
                    onSubmitted: (_) => _send(),
                    // 样式交给全局 InputDecorationTheme（填充式 surfaceAlt + 聚焦描边），
                    // 这里只保留尺寸微调，不再自设 border
                    decoration: const InputDecoration(
                      hintText: '问问你的财务情况…',
                      isDense: true,
                      contentPadding: EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                FilledButton(
                  onPressed: _busy ? null : () => _send(),
                  style: FilledButton.styleFrom(
                    shape: const CircleBorder(),
                    padding: const EdgeInsets.all(12),
                  ),
                  child: const Icon(Icons.send_rounded, size: 18),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _MerchantAgg {
  final String name;
  double amount = 0;
  int count = 0;
  _MerchantAgg({required this.name});
}

/// 对话内回复卡（stat / budget / 商户分布）统一外壳：
/// surface 底 + border 幽灵描边 + 16 圆角，替代旧「白底 + 彩色描边」。
class _ReplyCardShell extends StatelessWidget {
  const _ReplyCardShell({
    required this.child,
    this.padding = const EdgeInsets.all(14),
  });
  final Widget child;
  final EdgeInsetsGeometry padding;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: padding,
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppColors.border),
      ),
      child: child,
    );
  }
}

class _CfoActionCard extends StatefulWidget {
  const _CfoActionCard({
    required this.proposalId,
    required this.title,
    required this.body,
    required this.requiresClient,
    required this.actionKind,
    required this.params,
  });
  final String proposalId, title, body, actionKind;
  final bool requiresClient;
  final Map<String, dynamic> params;
  @override
  State<_CfoActionCard> createState() => _CfoActionCardState();
}

class _CfoActionCardState extends State<_CfoActionCard> {
  String _state = 'pending'; // pending|done|cancelled
  bool _busy = false;

  Future<void> _confirm() async {
    if (widget.requiresClient) {
      if (widget.actionKind == 'allocate_to_goal_byname') {
        setState(() => _busy = true);
        try {
          final ok = await _runAllocateByName(widget.params);
          if (!ok) {
            if (mounted) setState(() => _busy = false);
            return;
          }
          await ApiService.cfoDecide(widget.proposalId, 'resolve');
          if (mounted) {
            setState(() {
              _state = 'done';
              _busy = false;
            });
          }
        } catch (_) {
          if (mounted) {
            _toast('执行失败');
            setState(() => _busy = false);
          }
        }
        return;
      }
      // 其它需客户端处理的动作暂不在对话里执行
      ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('这个操作请到「复盘」页确认执行')));
      return;
    }
    setState(() => _busy = true);
    try {
      await ApiService.cfoDecide(widget.proposalId, 'approve');
      if (mounted) setState(() => _state = 'done');
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(const SnackBar(content: Text('执行失败，请重试')));
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  /// 客户端解析名字 → id 后执行带备注转账（仅客户端有 DEK）
  Future<bool> _runAllocateByName(Map<String, dynamic> params) async {
    final lid = await AuthService.getCurrentLedgerId();
    if (lid == null || !KeyChain.instance.hasDek(lid)) {
      _toast('账本密钥未就绪');
      return false;
    }
    final fromName = (params['fromAccountName'] as String?)?.trim() ?? '';
    final goalName = (params['goalName'] as String?)?.trim() ?? '';
    final amount = (params['amount'] as num?)?.toDouble() ?? 0;
    if (fromName.isEmpty || amount <= 0) {
      _toast('转账参数无效');
      return false;
    }

    // 账户（客户端解密名）按名字匹配
    final accRes = await ApiService.getAccounts();
    final accounts = (accRes['accounts'] as List? ?? [])
        .map((a) => Account.fromJson(a as Map<String, dynamic>))
        .toList();
    Account? from;
    for (final a in accounts) {
      if (a.name.contains(fromName)) {
        from = a;
        break;
      }
    }
    if (from == null) {
      _toast('没找到账户「$fromName」');
      return false;
    }

    // 目标（客户端解密名）匹配，且必须绑定了账户
    final goalRes = await ApiService.getGoals();
    final goals = (goalRes['goals'] as List? ?? [])
        .map((g) => SavingsGoal.fromJson(g as Map<String, dynamic>))
        .toList();
    SavingsGoal? goal;
    for (final g in goals) {
      if (g.accountId != null &&
          g.accountId!.isNotEmpty &&
          (goalName.isEmpty || g.name.contains(goalName))) {
        goal = g;
        break;
      }
    }
    if (goal == null || goal.accountId == null || goal.accountId!.isEmpty) {
      _toast('没找到绑定账户的目标「$goalName」');
      return false;
    }

    final dekVer = KeyChain.instance.dekVersionOf(lid) ?? 1;
    final fromCipher = KeyChain.instance
        .encryptText(ledgerId: lid, plain: '转账·转出 → 储蓄目标');
    final toCipher = KeyChain.instance
        .encryptText(ledgerId: lid, plain: '转账·转入 ← 闲钱归集');
    await ApiService.transfer(
      fromAccountId: from.id,
      toAccountId: goal.accountId!,
      amount: amount,
      fromNoteCipher: fromCipher,
      toNoteCipher: toCipher,
      noteDekVer: dekVer,
    );
    return true;
  }

  void _toast(String m) {
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(m)));
    }
  }

  Future<void> _cancel() async {
    setState(() => _busy = true);
    try {
      await ApiService.cfoDecide(widget.proposalId, 'dismiss');
    } catch (_) {}
    if (mounted) {
      setState(() {
        _state = 'cancelled';
        _busy = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(top: 8),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppColors.border),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text(widget.title,
            style: TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.w600,
                color: AppColors.text1)),
        if (widget.body.isNotEmpty) ...[
          const SizedBox(height: 4),
          Text(widget.body,
              style: TextStyle(fontSize: 12, color: AppColors.text2)),
        ],
        const SizedBox(height: 12),
        if (_state == 'pending')
          Row(children: [
            Expanded(
              child: FilledButton(
                onPressed: _busy ? null : _confirm,
                child: Text(_busy ? '处理中…' : '确认'),
              ),
            ),
            const SizedBox(width: 8),
            TextButton(
                onPressed: _busy ? null : _cancel, child: const Text('取消')),
          ])
        else
          Text(_state == 'done' ? '✅ 已执行' : '已取消',
              style: TextStyle(fontSize: 12, color: AppColors.text3)),
      ]),
    );
  }
}

/// 对话记账草稿卡：备注明文只在此卡片里（瞬时，不落库）。
/// 用户点「确认」时，客户端加密备注 + 调 createBill 真正记账。
class _BillDraftCard extends StatefulWidget {
  const _BillDraftCard({required this.data});
  final Map<String, dynamic> data;
  @override
  State<_BillDraftCard> createState() => _BillDraftCardState();
}

class _BillDraftCardState extends State<_BillDraftCard> {
  String _state = 'pending'; // pending|done|cancelled
  bool _busy = false;

  double get _amount => ((widget.data['amount'] as num?) ?? 0).toDouble();
  String get _categoryId => (widget.data['categoryId'] as String?) ?? '';
  String get _categoryName => (widget.data['categoryName'] as String?) ?? '';
  String get _accountName =>
      ((widget.data['accountName'] as String?) ?? '').trim();
  String get _note => (widget.data['note'] as String?) ?? '';
  String get _billType =>
      (widget.data['billType'] as String?) == 'income' ? 'income' : 'expense';

  void _toast(String m) {
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(m)));
    }
  }

  Future<void> _confirm() async {
    if (_categoryId.isEmpty) {
      _toast('分类缺失');
      return;
    }
    setState(() => _busy = true);
    try {
      final lid = await AuthService.getCurrentLedgerId();
      if (lid == null || !KeyChain.instance.hasDek(lid)) {
        _toast('账本密钥未就绪');
        if (mounted) setState(() => _busy = false);
        return;
      }

      // 取账户（客户端用 DEK 解密名字后匹配）
      final accRes = await ApiService.getAccounts();
      final accounts = (accRes['accounts'] as List? ?? [])
          .map((a) => Account.fromJson(a as Map<String, dynamic>))
          .toList();
      if (accounts.isEmpty) {
        _toast('请先创建账户');
        if (mounted) setState(() => _busy = false);
        return;
      }
      // 指定了账户名→按解密名包含匹配；否则/匹配不到→用第一个账户
      Account? acc;
      if (_accountName.isNotEmpty) {
        for (final a in accounts) {
          if (a.name.contains(_accountName)) {
            acc = a;
            break;
          }
        }
      }
      acc ??= accounts.first;

      final dekVer = KeyChain.instance.dekVersionOf(lid) ?? 1;
      // 备注可能为空——空字符串也加密（与 app 其他处一致）
      final cipher = KeyChain.instance.encryptText(ledgerId: lid, plain: _note);

      await ApiService.createBill(
        type: _billType,
        amount: _amount,
        categoryId: _categoryId,
        accountId: acc.id,
        noteCipher: cipher,
        noteDekVer: dekVer,
        date: DateTime.now(),
      );
      bumpRefresh();
      if (mounted) {
        setState(() {
          _state = 'done';
          _busy = false;
        });
        _toast('✅ 已记一笔');
      }
    } catch (_) {
      if (mounted) {
        _toast('记账失败');
        setState(() => _busy = false);
      }
    }
  }

  void _cancel() {
    // 没有创建任何东西，纯本地标记取消
    setState(() => _state = 'cancelled');
  }

  @override
  Widget build(BuildContext context) {
    final acc = _accountName;
    final note = _note.trim();
    final parts = <String>[
      '¥${formatAmount(_amount)}',
      _categoryName,
      if (acc.isNotEmpty) acc,
      if (note.isNotEmpty) note,
    ];
    return Container(
      margin: const EdgeInsets.only(top: 8),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppColors.border),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text(
          '记一笔 · ${parts.join(' · ')}',
          style: TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.w600,
              color: AppColors.text1),
        ),
        const SizedBox(height: 12),
        if (_state == 'pending')
          Row(children: [
            Expanded(
              child: FilledButton(
                onPressed: _busy ? null : _confirm,
                child: Text(_busy ? '处理中…' : '确认'),
              ),
            ),
            const SizedBox(width: 8),
            TextButton(
                onPressed: _busy ? null : _cancel, child: const Text('取消')),
          ])
        else
          Text(_state == 'done' ? '✅ 已记一笔' : '已取消',
              style: TextStyle(fontSize: 12, color: AppColors.text3)),
      ]),
    );
  }
}
