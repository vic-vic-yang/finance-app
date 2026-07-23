import 'package:flutter_test/flutter_test.dart';
import 'package:finance_app/services/voice_input_service.dart';

/// 假识别器：脚本化 initialize/start/stop，测试手动触发回调
class FakeSpeechRecognizer implements SpeechRecognizer {
  bool initializeResult = true;
  bool throwOnStart = false;
  int initializeCalls = 0;
  int startCalls = 0;
  int stopCalls = 0;
  int cancelCalls = 0;
  String? lastLocaleId;

  void Function(String)? _errorCb;
  void Function(String)? _statusCb;
  void Function(String, bool)? _resultCb;

  @override
  Future<bool> initialize({
    void Function(String errorCode)? onError,
    void Function(String status)? onStatus,
  }) async {
    initializeCalls++;
    _errorCb = onError;
    _statusCb = onStatus;
    return initializeResult;
  }

  @override
  Future<void> start({
    required String localeId,
    required void Function(String text, bool isFinal) onResult,
  }) async {
    startCalls++;
    lastLocaleId = localeId;
    _resultCb = onResult;
    if (throwOnStart) throw Exception('recognizer boom');
  }

  @override
  Future<void> stop() async {
    stopCalls++;
  }

  @override
  Future<void> cancel() async {
    cancelCalls++;
  }

  void emit(String text, {bool isFinal = false}) =>
      _resultCb?.call(text, isFinal);
  void emitError(String code) => _errorCb?.call(code);
  void emitStatus(String status) => _statusCb?.call(status);
}

VoiceInputController makeController(FakeSpeechRecognizer fake) =>
    VoiceInputController(recognizer: fake, stopGrace: Duration.zero);

void main() {
  group('mapSpeechError', () {
    test('常见错误码映射成中文提示', () {
      expect(mapSpeechError('not_available'), contains('语音识别服务'));
      expect(mapSpeechError('error_permission'), contains('麦克风权限'));
      expect(mapSpeechError('error_speech_timeout'), contains('没听清'));
      expect(mapSpeechError('error_no_match'), contains('没听清'));
      expect(mapSpeechError('error_network'), contains('网络'));
      expect(mapSpeechError('error_busy'), contains('正忙'));
      expect(mapSpeechError('whatever'), contains('出错了'));
    });
  });

  group('VoiceInputController 状态机', () {
    test('初始为空闲', () {
      final c = makeController(FakeSpeechRecognizer());
      expect(c.phase, VoiceInputPhase.idle);
      expect(c.text, isEmpty);
      expect(c.errorMessage, isNull);
    });

    test('start → 收音中 → 部分结果上屏 → 最终结果 → 完成', () async {
      final fake = FakeSpeechRecognizer();
      final c = makeController(fake);

      await c.start();
      expect(c.phase, VoiceInputPhase.listening);
      expect(fake.lastLocaleId, 'zh_CN');

      fake.emit('中午请客户吃饭');
      expect(c.phase, VoiceInputPhase.listening); // 部分结果不改状态
      expect(c.text, '中午请客户吃饭');

      fake.emit('中午请客户吃饭 268', isFinal: true);
      expect(c.phase, VoiceInputPhase.done);
      expect(c.text, '中午请客户吃饭 268');
      expect(c.errorMessage, isNull);
    });

    test('无识别服务（initialize=false）→ 错误态 + 中文提示', () async {
      final fake = FakeSpeechRecognizer()..initializeResult = false;
      final c = makeController(fake);

      await c.start();
      expect(c.phase, VoiceInputPhase.error);
      expect(c.errorMessage, contains('语音识别服务'));
    });

    test('权限被拒 → 错误态 + 权限提示', () async {
      final fake = FakeSpeechRecognizer();
      final c = makeController(fake);

      await c.start();
      fake.emitError('error_permission');
      expect(c.phase, VoiceInputPhase.error);
      expect(c.errorMessage, contains('麦克风权限'));
    });

    test('识别超时 → 错误态 + 没听清', () async {
      final fake = FakeSpeechRecognizer();
      final c = makeController(fake);

      await c.start();
      fake.emitError('error_speech_timeout');
      expect(c.phase, VoiceInputPhase.error);
      expect(c.errorMessage, contains('没听清'));
    });

    test('start 抛异常 → 错误态不崩溃', () async {
      final fake = FakeSpeechRecognizer()..throwOnStart = true;
      final c = makeController(fake);

      await c.start();
      expect(c.phase, VoiceInputPhase.error);
      expect(c.errorMessage, isNotNull);
    });

    test('手动 stop：有部分文本 → 完成；无文本 → 没听清', () async {
      final fake = FakeSpeechRecognizer();
      final c = makeController(fake);

      await c.start();
      fake.emit('晚饭 58');
      await c.stop();
      expect(c.phase, VoiceInputPhase.done);
      expect(c.text, '晚饭 58');

      final fake2 = FakeSpeechRecognizer();
      final c2 = makeController(fake2);
      await c2.start();
      await c2.stop();
      expect(c2.phase, VoiceInputPhase.error);
      expect(c2.errorMessage, contains('没听清'));
    });

    test('识别器因静音自行结束（status=done）→ 按已有文本收尾', () async {
      final fake = FakeSpeechRecognizer();
      final c = makeController(fake);

      await c.start();
      fake.emit('打车 32');
      fake.emitStatus('done');
      expect(c.phase, VoiceInputPhase.done);
      expect(c.text, '打车 32');
    });

    test('toggle：空闲→收音，收音→stop', () async {
      final fake = FakeSpeechRecognizer();
      final c = makeController(fake);

      await c.toggle();
      expect(c.phase, VoiceInputPhase.listening);
      await c.toggle();
      expect(fake.stopCalls, 1);
    });

    test('reset：清空文本与错误，回到空闲', () async {
      final fake = FakeSpeechRecognizer();
      final c = makeController(fake);

      await c.start();
      fake.emit('午饭', isFinal: true);
      expect(c.phase, VoiceInputPhase.done);

      await c.reset();
      expect(c.phase, VoiceInputPhase.idle);
      expect(c.text, isEmpty);
      expect(c.errorMessage, isNull);
    });

    test('收音中 reset 会 cancel 识别器', () async {
      final fake = FakeSpeechRecognizer();
      final c = makeController(fake);

      await c.start();
      await c.reset();
      expect(fake.cancelCalls, 1);
      expect(c.phase, VoiceInputPhase.idle);
    });
  });
}
