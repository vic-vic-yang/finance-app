import 'package:flutter/material.dart';

import '../core/theme.dart';
import '../services/api_service.dart';
import '../services/auth_service.dart';
import '../services/voice_input_service.dart';
import 'bill_draft_card.dart';

/// 语音记账解析结果：要么拿到 bill_draft 草稿卡数据，要么拿到用户可读的失败原因
class VoiceParseResult {
  const VoiceParseResult.draft(this.draft) : errorText = null;
  const VoiceParseResult.error(this.errorText) : draft = null;
  final Map<String, dynamic>? draft;
  final String? errorText;
}

/// 把识别文字解析成账单草稿。注入式，测试里换成假实现。
typedef VoiceDraftParser = Future<VoiceParseResult> Function(String text);

/// 生产解析器：走与「司库助手」对话记账完全相同的链路（POST /ai/chat），
/// 从返回卡片里取 bill_draft 草稿；BYOK / 无账本等报错话术与 chat 页一致。
Future<VoiceParseResult> parseVoiceDraftWithChat(String text) async {
  final ledgerId = await AuthService.getCurrentLedgerId();
  if (ledgerId == null) {
    return const VoiceParseResult.error('还没有可用账本，请先创建账本');
  }
  final res = await ApiService.aiChat(ledgerId: ledgerId, message: text);
  for (final c in (res['cards'] as List? ?? [])) {
    if (c is Map && c['type'] == 'bill_draft' && c['data'] is Map) {
      return VoiceParseResult.draft(
          (c['data'] as Map).cast<String, dynamic>());
    }
  }
  final reply = ((res['reply'] as String?) ?? '').trim();
  return VoiceParseResult.error(
      reply.isNotEmpty ? reply : '没听明白，请换个说法，比如「午饭 35」');
}

/// 打开语音记账弹层。返回 true = 成功记了一笔。
Future<bool?> showVoiceEntrySheet(BuildContext context) {
  return showModalBottomSheet<bool>(
    context: context,
    isScrollControlled: true,
    backgroundColor: AppColors.surface,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
    ),
    builder: (_) => const VoiceEntrySheet(),
  );
}

/// 语音记账弹层：收音（可编辑识别文本）→ 解析 → 草稿卡确认入库。
///
/// 状态流转：
///   收音中（部分结果实时上屏，点「结束收音」）
///   → 文本确认（可编辑，点「生成草稿」）
///   → 解析中 → 草稿卡（确认入库 / 取消）
/// 任何一步出错都有中文提示 + 重试入口。
class VoiceEntrySheet extends StatefulWidget {
  const VoiceEntrySheet({super.key, this.controller, this.parser});

  /// 可注入（测试）；缺省自建 zh_CN 识别器
  final VoiceInputController? controller;

  /// 可注入（测试）；缺省走 [parseVoiceDraftWithChat]
  final VoiceDraftParser? parser;

  @override
  State<VoiceEntrySheet> createState() => _VoiceEntrySheetState();
}

class _VoiceEntrySheetState extends State<VoiceEntrySheet>
    with SingleTickerProviderStateMixin {
  late final VoiceInputController _controller =
      widget.controller ?? VoiceInputController();
  late final VoiceDraftParser _parser =
      widget.parser ?? parseVoiceDraftWithChat;

  /// 收音态呼吸圈动画（克制：一圈缓慢缩放的描边环）
  late final AnimationController _pulse = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1200),
  );

  final _textCtrl = TextEditingController();
  bool _parsing = false;
  Map<String, dynamic>? _draft;
  String? _parseError;

  @override
  void initState() {
    super.initState();
    _controller.addListener(_onVoiceChange);
    // 进弹层即开始收音（点一下开始）
    _startListening();
  }

  Future<void> _startListening() async {
    setState(() {
      _draft = null;
      _parseError = null;
    });
    await _controller.start();
  }

  void _onVoiceChange() {
    if (!mounted) return;
    // 收音结束：把识别文本填进可编辑输入框，让用户过目修改
    if (_controller.phase == VoiceInputPhase.done && _draft == null) {
      _textCtrl.text = _controller.text;
      _textCtrl.selection = TextSelection.collapsed(
          offset: _textCtrl.text.length);
      _pulse.stop();
    }
    if (_controller.isListening && !_pulse.isAnimating) {
      _pulse.repeat(reverse: true);
    }
    if (!_controller.isListening && _pulse.isAnimating) {
      _pulse.stop();
      _pulse.value = 0;
    }
    setState(() {});
  }

  Future<void> _parse() async {
    final text = _textCtrl.text.trim();
    if (text.isEmpty || _parsing) return;
    setState(() {
      _parsing = true;
      _parseError = null;
    });
    try {
      final res = await _parser(text);
      if (!mounted) return;
      setState(() {
        _parsing = false;
        _draft = res.draft;
        _parseError = res.errorText;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _parsing = false;
        // ApiException.toString() 即后端话术（如「请先配置 AI 模型」），与 chat 页一致
        _parseError = e is ApiException ? e.message : '解析失败，请重试';
      });
    }
  }

  @override
  void dispose() {
    _controller.removeListener(_onVoiceChange);
    if (widget.controller == null) _controller.dispose();
    _pulse.dispose();
    _textCtrl.dispose();
    super.dispose();
  }

  // ── Build ────────────────────────────────────────────────────
  @override
  Widget build(BuildContext context) {
    return Padding(
      // 键盘弹出时顶起弹层
      padding: EdgeInsets.only(
          bottom: MediaQuery.of(context).viewInsets.bottom),
      child: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 12, 20, 20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              _header(),
              const SizedBox(height: 16),
              if (_draft != null)
                _draftView()
              else if (_parsing)
                _parsingView()
              else
                _voiceView(),
            ],
          ),
        ),
      ),
    );
  }

  Widget _header() {
    return Row(children: [
      Icon(Icons.graphic_eq_rounded, size: 18, color: AppColors.primary),
      const SizedBox(width: 6),
      Expanded(
        child: Text('语音记账',
            style: TextStyle(
                fontSize: 15,
                fontWeight: FontWeight.w600,
                color: AppColors.text1)),
      ),
      IconButton(
        icon: Icon(Icons.close_rounded, size: 20, color: AppColors.text3),
        onPressed: () => Navigator.pop(context, false),
      ),
    ]);
  }

  /// 草稿确认：复用对话记账同款卡片；确认入库后自动关弹层
  Widget _draftView() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text('请确认这笔账单',
            style: TextStyle(fontSize: 12.5, color: AppColors.text2)),
        BillDraftCard(
          data: _draft!,
          onDone: () {
            if (mounted) Navigator.pop(context, true);
          },
        ),
      ],
    );
  }

  Widget _parsingView() {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 28),
      child: Column(children: [
        SizedBox(
          width: 22,
          height: 22,
          child: CircularProgressIndicator(
              strokeWidth: 2.2, color: AppColors.primary),
        ),
        const SizedBox(height: 12),
        Text('正在解析…', style: TextStyle(fontSize: 13, color: AppColors.text2)),
      ]),
    );
  }

  /// 收音 / 文本确认 / 错误三态
  Widget _voiceView() {
    switch (_controller.phase) {
      case VoiceInputPhase.listening:
        return _listeningView();
      case VoiceInputPhase.done:
        return _confirmTextView();
      case VoiceInputPhase.error:
        return _errorView();
      case VoiceInputPhase.idle:
        return Padding(
          padding: const EdgeInsets.symmetric(vertical: 28),
          child: Center(
            child: Text('正在启动语音识别…',
                style: TextStyle(fontSize: 13, color: AppColors.text2)),
          ),
        );
    }
  }

  Widget _listeningView() {
    final partial = _controller.text.trim();
    return Column(children: [
      const SizedBox(height: 8),
      // 呼吸圈 + 麦克风
      AnimatedBuilder(
        animation: _pulse,
        builder: (_, child) {
          final scale = 1.0 + 0.12 * _pulse.value;
          final ringAlpha = 0.35 * (1.0 - _pulse.value);
          return SizedBox(
            width: 88,
            height: 88,
            child: Stack(alignment: Alignment.center, children: [
              Transform.scale(
                scale: scale,
                child: Container(
                  width: 76,
                  height: 76,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    border: Border.all(
                      color: AppColors.primary
                          .withValues(alpha: 0.1 + ringAlpha),
                      width: 2,
                    ),
                  ),
                ),
              ),
              child!,
            ]),
          );
        },
        child: Container(
          width: 64,
          height: 64,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: AppColors.primaryLight,
          ),
          child:
              Icon(Icons.mic_rounded, size: 30, color: AppColors.primary),
        ),
      ),
      const SizedBox(height: 14),
      Text(
        partial.isEmpty ? '正在听你说话…' : partial,
        textAlign: TextAlign.center,
        style: TextStyle(
          fontSize: 15,
          height: 1.5,
          color: partial.isEmpty ? AppColors.text3 : AppColors.text1,
        ),
      ),
      const SizedBox(height: 4),
      Text('说完点下方按钮结束',
          style: TextStyle(fontSize: 12, color: AppColors.text3)),
      const SizedBox(height: 16),
      FilledButton.icon(
        onPressed: _controller.stop,
        icon: const Icon(Icons.stop_rounded, size: 18),
        label: const Text('结束收音'),
      ),
      const SizedBox(height: 4),
    ]);
  }

  /// 识别完成：文本可编辑，用户过目后点「生成草稿」
  Widget _confirmTextView() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        TextField(
          controller: _textCtrl,
          minLines: 1,
          maxLines: 3,
          autofocus: false,
          decoration: const InputDecoration(
            labelText: '识别结果（可修改）',
            hintText: '比如：中午请客户吃饭 268',
            isDense: true,
          ),
        ),
        if (_parseError != null) ...[
          const SizedBox(height: 10),
          Text(_parseError!,
              style: TextStyle(fontSize: 12.5, color: AppColors.danger)),
        ],
        const SizedBox(height: 14),
        Row(children: [
          Expanded(
            child: FilledButton(
              onPressed: _parse,
              child: const Text('生成草稿'),
            ),
          ),
          const SizedBox(width: 8),
          TextButton(
            onPressed: () async {
              await _controller.reset();
              _textCtrl.clear();
              await _startListening();
            },
            child: const Text('重说'),
          ),
        ]),
      ],
    );
  }

  Widget _errorView() {
    return Column(children: [
      const SizedBox(height: 8),
      Container(
        width: 56,
        height: 56,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: AppColors.dangerLight,
        ),
        child: Icon(Icons.mic_off_rounded, size: 26, color: AppColors.danger),
      ),
      const SizedBox(height: 14),
      Text(
        _controller.errorMessage ?? '语音识别出错了，请再试一次',
        textAlign: TextAlign.center,
        style: TextStyle(fontSize: 14, height: 1.5, color: AppColors.text1),
      ),
      const SizedBox(height: 16),
      Row(mainAxisAlignment: MainAxisAlignment.center, children: [
        FilledButton(
          onPressed: () async {
            await _controller.reset();
            await _startListening();
          },
          child: const Text('重试'),
        ),
        const SizedBox(width: 8),
        TextButton(
          onPressed: () => Navigator.pop(context, false),
          child: const Text('手动记账'),
        ),
      ]),
      const SizedBox(height: 4),
    ]);
  }
}
