import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:speech_to_text/speech_to_text.dart' as stt;

/// 语音识别状态机：空闲 / 收音中 / 识别完成 / 错误
enum VoiceInputPhase { idle, listening, done, error }

/// 把 speech_to_text 的错误码映射成对用户友好的中文提示。
/// 'not_available' 是本层自定义码：设备上没有可用的语音识别服务。
String mapSpeechError(String code) {
  switch (code) {
    case 'not_available':
      return '当前设备没有可用的语音识别服务';
    case 'error_permission':
      return '需要麦克风权限才能语音记账，请在系统设置中允许';
    case 'error_speech_timeout':
    case 'error_no_match':
      return '没听清，请再试一次';
    case 'error_network':
    case 'error_network_timeout':
      return '网络异常，语音识别需要联网';
    case 'error_busy':
      return '识别器正忙，请稍后再试';
    case 'error_too_many_requests':
      return '操作太频繁，请稍后再试';
    default:
      return '语音识别出错了，请再试一次';
  }
}

/// 识别器抽象：生产环境用 [SpeechToTextRecognizer]（speech_to_text 插件），
/// 测试注入假实现，避免依赖平台通道。
abstract class SpeechRecognizer {
  /// 初始化并请求麦克风权限；返回 false = 无可用识别服务。
  /// [onError] 回调错误码（见 speech_to_text 的 SpeechRecognitionError.errorMsg），
  /// [onStatus] 回调识别器状态（'listening' / 'notListening' / 'done'）。
  Future<bool> initialize({
    void Function(String errorCode)? onError,
    void Function(String status)? onStatus,
  });

  /// 开始收音。[onResult] 回传识别文本（部分结果 isFinal=false，最终 isFinal=true）。
  Future<void> start({
    required String localeId,
    required void Function(String text, bool isFinal) onResult,
  });

  Future<void> stop();
  Future<void> cancel();
}

/// 生产实现：speech_to_text 插件（Android 走系统识别器，中文 zh_CN）。
/// Web 端能力受限：initialize 直接返回 false（入口层已做降级提示）。
class SpeechToTextRecognizer implements SpeechRecognizer {
  SpeechToTextRecognizer([stt.SpeechToText? speech])
      : _speech = speech ?? stt.SpeechToText();

  final stt.SpeechToText _speech;

  @override
  Future<bool> initialize({
    void Function(String errorCode)? onError,
    void Function(String status)? onStatus,
  }) async {
    if (kIsWeb) return false;
    try {
      return await _speech.initialize(
        onError: (e) => onError?.call(e.errorMsg),
        onStatus: onStatus,
      );
    } catch (_) {
      return false;
    }
  }

  @override
  Future<void> start({
    required String localeId,
    required void Function(String text, bool isFinal) onResult,
  }) {
    return _speech.listen(
      onResult: (r) => onResult(r.recognizedWords, r.finalResult),
      listenOptions: stt.SpeechListenOptions(
        localeId: localeId,
        listenFor: const Duration(seconds: 30),
        pauseFor: const Duration(seconds: 4),
        partialResults: true,
        cancelOnError: false,
        listenMode: stt.ListenMode.dictation,
      ),
    );
  }

  @override
  Future<void> stop() => _speech.stop();

  @override
  Future<void> cancel() => _speech.cancel();
}

/// 语音输入控制器：驱动 [SpeechRecognizer]，对外暴露
/// idle / listening / done / error 四态与当前识别文本。
///
/// 交互约定：toggle() —— 空闲时点一下开始收音，收音中再点一下结束。
class VoiceInputController extends ChangeNotifier {
  VoiceInputController({
    SpeechRecognizer? recognizer,
    this.localeId = 'zh_CN',
    this.stopGrace = const Duration(milliseconds: 300),
  }) : _recognizer = recognizer ?? SpeechToTextRecognizer();

  final SpeechRecognizer _recognizer;

  /// 识别语言，默认中文（中国大陆）
  final String localeId;

  /// 手动 stop 后等待最终结果的宽限时间（多数设备 stop 后立即回 final result）；
  /// 测试里传 Duration.zero 走同步收尾。
  final Duration stopGrace;

  VoiceInputPhase phase = VoiceInputPhase.idle;

  /// 当前识别文本（收音中是部分结果，done 后是最终结果）
  String text = '';

  /// phase == error 时的用户可读提示
  String? errorMessage;

  bool get isListening => phase == VoiceInputPhase.listening;

  Future<void> toggle() =>
      phase == VoiceInputPhase.listening ? stop() : start();

  Future<void> start() async {
    if (phase == VoiceInputPhase.listening) return;
    text = '';
    errorMessage = null;

    final ok = await _recognizer.initialize(
      onError: _onError,
      onStatus: _onStatus,
    );
    if (!ok) {
      phase = VoiceInputPhase.error;
      errorMessage = mapSpeechError('not_available');
      notifyListeners();
      return;
    }

    phase = VoiceInputPhase.listening;
    notifyListeners();
    try {
      await _recognizer.start(
        localeId: localeId,
        onResult: (words, isFinal) {
          // 只关心收音期间回来的结果；stop 之后的迟到结果也收下（最终文本更准）
          if (phase != VoiceInputPhase.listening &&
              phase != VoiceInputPhase.done) {
            return;
          }
          text = words;
          if (isFinal) _finishWithText();
          notifyListeners();
        },
      );
    } catch (_) {
      phase = VoiceInputPhase.error;
      errorMessage = mapSpeechError('unknown');
      notifyListeners();
    }
  }

  Future<void> stop() async {
    if (phase != VoiceInputPhase.listening) return;
    try {
      await _recognizer.stop();
    } catch (_) {/* 识别器已自行结束，按当前文本收尾 */}
    // 给最终的 final result 一点宽限；没到就按已有文本收尾
    if (stopGrace > Duration.zero) await Future.delayed(stopGrace);
    if (phase == VoiceInputPhase.listening) {
      _finishWithText();
      notifyListeners();
    }
  }

  /// 重来一遍（清空文本与错误，回到空闲；若在收音先取消）
  Future<void> reset() async {
    if (phase == VoiceInputPhase.listening) {
      try {
        await _recognizer.cancel();
      } catch (_) {}
    }
    phase = VoiceInputPhase.idle;
    text = '';
    errorMessage = null;
    notifyListeners();
  }

  /// 按当前文本结束收音：有文本 → done；空文本 → error（没听清）
  void _finishWithText() {
    if (text.trim().isNotEmpty) {
      phase = VoiceInputPhase.done;
      errorMessage = null;
    } else {
      phase = VoiceInputPhase.error;
      errorMessage = mapSpeechError('error_no_match');
    }
  }

  void _onError(String code) {
    if (phase != VoiceInputPhase.listening) return;
    phase = VoiceInputPhase.error;
    errorMessage = mapSpeechError(code);
    notifyListeners();
  }

  void _onStatus(String status) {
    // 系统识别器可能因静音（pauseFor）自行结束 —— 按已有文本收尾
    if (phase == VoiceInputPhase.listening &&
        (status == 'done' || status == 'notListening')) {
      _finishWithText();
      notifyListeners();
    }
  }

  @override
  void dispose() {
    if (phase == VoiceInputPhase.listening) {
      unawaited(_recognizer.cancel().catchError((_) {}));
    }
    super.dispose();
  }
}
