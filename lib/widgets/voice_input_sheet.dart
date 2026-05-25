import 'package:flutter/material.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:speech_to_text/speech_to_text.dart' as stt;
import 'package:speech_to_text/speech_recognition_error.dart';

import '../core/theme.dart';
import '../models/category.dart';
import '../services/bill_parser.dart';

/// 语音输入弹窗。返回 [BillDraft]（用户确认后），或 null（取消）。
///
/// 用法：
/// ```
/// final draft = await showModalBottomSheet<BillDraft>(
///   context: context,
///   isScrollControlled: true,
///   backgroundColor: AppColors.surface,
///   shape: const RoundedRectangleBorder(
///     borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
///   ),
///   builder: (_) => VoiceInputSheet(categories: cats),
/// );
/// ```
class VoiceInputSheet extends StatefulWidget {
  const VoiceInputSheet({super.key, required this.categories});

  final List<Category> categories;

  @override
  State<VoiceInputSheet> createState() => _VoiceInputSheetState();
}

class _VoiceInputSheetState extends State<VoiceInputSheet>
    with SingleTickerProviderStateMixin {
  final stt.SpeechToText _stt = stt.SpeechToText();
  late final AnimationController _pulse;

  /// 初始化状态：null=未开始 / true=成功 / false=失败
  bool? _available;
  String _statusMsg = '';
  bool _listening = false;
  String _text = '';
  double _sound = 0; // 实时音量
  bool _disposed = false;

  @override
  void initState() {
    super.initState();
    _pulse = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1100),
    )..repeat(reverse: true);
    _bootstrap();
  }

  @override
  void dispose() {
    _disposed = true;
    _pulse.dispose();
    _stt.stop();
    super.dispose();
  }

  Future<void> _bootstrap() async {
    // 1. 申请麦克风权限
    var perm = await Permission.microphone.status;
    if (!perm.isGranted) {
      perm = await Permission.microphone.request();
    }
    if (!perm.isGranted) {
      if (!mounted) return;
      setState(() {
        _available = false;
        _statusMsg = '需要麦克风权限才能使用语音记账';
      });
      return;
    }

    // 2. 初始化 STT
    final ok = await _stt.initialize(
      onStatus: _onStatus,
      onError: _onError,
    );
    if (_disposed) return;
    if (!ok) {
      setState(() {
        _available = false;
        _statusMsg = '当前设备不支持语音识别，或没有安装语音服务';
      });
      return;
    }

    setState(() {
      _available = true;
      _statusMsg = '点麦克风开始说话…';
    });
    // 自动开始监听，省一次点击
    _start();
  }

  void _onStatus(String s) {
    if (_disposed) return;
    // s 可能为：listening / notListening / done
    if (s == 'done' || s == 'notListening') {
      setState(() => _listening = false);
    }
  }

  void _onError(SpeechRecognitionError e) {
    if (_disposed) return;
    setState(() {
      _listening = false;
      _statusMsg = '识别出错：${e.errorMsg}';
    });
  }

  Future<void> _start() async {
    if (_listening) return;
    setState(() {
      _text = '';
      _statusMsg = '正在听…';
      _listening = true;
    });
    await _stt.listen(
      onResult: (r) {
        if (_disposed) return;
        setState(() => _text = r.recognizedWords);
      },
      onSoundLevelChange: (lvl) {
        if (_disposed) return;
        setState(() => _sound = lvl);
      },
      listenOptions: stt.SpeechListenOptions(
        partialResults: true,
        cancelOnError: true,
        listenMode: stt.ListenMode.dictation,
        localeId: 'zh_CN',
        listenFor: const Duration(seconds: 30),
        pauseFor: const Duration(seconds: 3),
      ),
    );
  }

  Future<void> _stop() async {
    await _stt.stop();
    if (!mounted) return;
    setState(() => _listening = false);
  }

  void _confirm() {
    final draft = BillParser.parse(_text, widget.categories);
    Navigator.pop(context, draft);
  }

  @override
  Widget build(BuildContext context) {
    final inset = MediaQuery.of(context).viewInsets.bottom;
    return Padding(
      padding: EdgeInsets.only(bottom: inset),
      child: SafeArea(
        top: false,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            _header(),
            const SizedBox(height: 8),
            _micCircle(),
            const SizedBox(height: 18),
            _transcript(),
            const SizedBox(height: 14),
            _statusLine(),
            const SizedBox(height: 18),
            _actions(),
            const SizedBox(height: 16),
          ],
        ),
      ),
    );
  }

  Widget _header() => Padding(
        padding: const EdgeInsets.fromLTRB(16, 14, 8, 6),
        child: Row(children: [
          Icon(Icons.mic_rounded, size: 20, color: AppColors.primary),
          const SizedBox(width: 8),
          Text('语音记账',
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
      );

  Widget _micCircle() {
    final disabled = _available == false;
    return GestureDetector(
      onTap: disabled
          ? null
          : () => _listening ? _stop() : _start(),
      child: AnimatedBuilder(
        animation: _pulse,
        builder: (_, __) {
          // 用音量 + pulse 动画一起决定光圈大小
          final double extra = _listening ? (24.0 + _sound * 4) : 0.0;
          return SizedBox(
            width: 160,
            height: 160,
            child: Stack(
              alignment: Alignment.center,
              children: [
                if (_listening)
                  Container(
                    width: 100 + extra,
                    height: 100 + extra,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: AppColors.primary.withOpacity(
                          0.10 + 0.06 * (1 - _pulse.value)),
                    ),
                  ),
                Container(
                  width: 96,
                  height: 96,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: disabled
                        ? AppColors.surfaceAlt
                        : (_listening
                            ? AppColors.primary
                            : AppColors.primaryLight),
                    boxShadow: _listening
                        ? [
                            BoxShadow(
                              color: AppColors.primary.withOpacity(0.35),
                              blurRadius: 18,
                              spreadRadius: 1,
                            )
                          ]
                        : null,
                  ),
                  child: Icon(
                    _listening
                        ? Icons.mic_rounded
                        : Icons.mic_none_rounded,
                    size: 44,
                    color: disabled
                        ? AppColors.text3
                        : (_listening
                            ? AppColors.onPrimary
                            : AppColors.primary),
                  ),
                ),
              ],
            ),
          );
        },
      ),
    );
  }

  Widget _transcript() {
    return ConstrainedBox(
      constraints: const BoxConstraints(minHeight: 56, maxHeight: 140),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 24),
        child: SingleChildScrollView(
          reverse: true,
          child: Text(
            _text.isEmpty
                ? '试试："午饭花了 35"、"打车 23"、"工资到账 12000"'
                : _text,
            textAlign: TextAlign.center,
            style: TextStyle(
              fontSize: _text.isEmpty ? 13 : 18,
              fontWeight:
                  _text.isEmpty ? FontWeight.normal : FontWeight.w600,
              color: _text.isEmpty ? AppColors.text3 : AppColors.text1,
              height: 1.4,
            ),
          ),
        ),
      ),
    );
  }

  Widget _statusLine() {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 24),
      child: Text(
        _statusMsg,
        textAlign: TextAlign.center,
        style: TextStyle(fontSize: 12, color: AppColors.text2),
      ),
    );
  }

  Widget _actions() {
    final canConfirm = _text.trim().isNotEmpty && !_listening;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: Row(children: [
        Expanded(
          child: OutlinedButton(
            onPressed: _text.isEmpty
                ? null
                : () => setState(() {
                      _text = '';
                      _statusMsg = '已清空，重新说一次';
                    }),
            style: OutlinedButton.styleFrom(
              foregroundColor: AppColors.text1,
              side: BorderSide(color: AppColors.border),
              padding: const EdgeInsets.symmetric(vertical: 14),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
              ),
            ),
            child: const Text('重说'),
          ),
        ),
        const SizedBox(width: 10),
        Expanded(
          flex: 2,
          child: ElevatedButton(
            onPressed: canConfirm ? _confirm : null,
            style: ElevatedButton.styleFrom(
              backgroundColor: AppColors.primary,
              foregroundColor: AppColors.onPrimary,
              minimumSize: const Size(double.infinity, 48),
              padding: const EdgeInsets.symmetric(vertical: 14),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
              ),
              disabledBackgroundColor: AppColors.surfaceAlt,
              disabledForegroundColor: AppColors.text3,
            ),
            child: const Text('使用这段话',
                style:
                    TextStyle(fontSize: 15, fontWeight: FontWeight.w600)),
          ),
        ),
      ]),
    );
  }
}
