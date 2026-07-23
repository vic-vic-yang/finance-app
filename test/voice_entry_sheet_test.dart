import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:finance_app/services/voice_input_service.dart';
import 'package:finance_app/widgets/voice_entry_sheet.dart';

/// 假识别器：脚本化行为，测试手动触发回调
class FakeSpeechRecognizer implements SpeechRecognizer {
  bool initializeResult = true;
  int stopCalls = 0;

  void Function(String)? _errorCb;
  void Function(String, bool)? _resultCb;

  @override
  Future<bool> initialize({
    void Function(String errorCode)? onError,
    void Function(String status)? onStatus,
  }) async {
    _errorCb = onError;
    return initializeResult;
  }

  @override
  Future<void> start({
    required String localeId,
    required void Function(String text, bool isFinal) onResult,
  }) async {
    _resultCb = onResult;
  }

  @override
  Future<void> stop() async {
    stopCalls++;
  }

  @override
  Future<void> cancel() async {}

  void emit(String text, {bool isFinal = false}) =>
      _resultCb?.call(text, isFinal);
  void emitError(String code) => _errorCb?.call(code);
}

const _draft = <String, dynamic>{
  'amount': 268.0,
  'categoryId': 'c1',
  'categoryName': '餐饮',
  'accountName': '招行',
  'note': '中午请客户吃饭',
  'billType': 'expense',
};

Widget wrap(Widget child) => MaterialApp(home: Scaffold(body: child));

void main() {
  testWidgets('收音中：实时上屏部分结果，结束收音后识别文本进入可编辑框',
      (tester) async {
    final fake = FakeSpeechRecognizer();
    final controller =
        VoiceInputController(recognizer: fake, stopGrace: Duration.zero);
    var parsedText = '';

    await tester.pumpWidget(wrap(VoiceEntrySheet(
      controller: controller,
      parser: (text) async {
        parsedText = text;
        return const VoiceParseResult.draft(_draft);
      },
    )));
    await tester.pump();
    expect(controller.phase, VoiceInputPhase.listening);
    expect(find.text('正在听你说话…'), findsOneWidget);
    expect(find.text('结束收音'), findsOneWidget);

    // 部分结果实时上屏
    fake.emit('中午请客户吃饭');
    await tester.pump();
    expect(find.text('中午请客户吃饭'), findsOneWidget);

    // 点「结束收音」，随后识别器回最终结果 → 进入文本确认态
    await tester.tap(find.text('结束收音'));
    fake.emit('中午请客户吃饭 268', isFinal: true);
    await tester.pump();
    await tester.pump();

    expect(controller.phase, VoiceInputPhase.done);
    final field = tester.widget<TextField>(find.byType(TextField));
    expect(field.controller!.text, '中午请客户吃饭 268');
    expect(find.text('生成草稿'), findsOneWidget);

    // 模拟用户改掉识别错字后确认解析
    await tester.enterText(find.byType(TextField), '中午请客户吃饭 268 元');
    await tester.tap(find.text('生成草稿'));
    await tester.pump();
    await tester.pump();

    expect(parsedText, '中午请客户吃饭 268 元');
    // 草稿卡渲染：金额 / 分类 / 账户 / 备注
    expect(find.textContaining('记一笔'), findsOneWidget);
    expect(find.textContaining('¥268'), findsOneWidget);
    expect(find.textContaining('餐饮'), findsOneWidget);
    expect(find.textContaining('招行'), findsOneWidget);
    expect(find.textContaining('中午请客户吃饭'), findsWidgets);
    expect(find.text('确认'), findsOneWidget);
    expect(find.text('取消'), findsOneWidget);
  });

  testWidgets('解析失败：显示失败原因，可改文案重试', (tester) async {
    final fake = FakeSpeechRecognizer();
    final controller =
        VoiceInputController(recognizer: fake, stopGrace: Duration.zero);

    await tester.pumpWidget(wrap(VoiceEntrySheet(
      controller: controller,
      parser: (text) async =>
          const VoiceParseResult.error('没听明白，请换个说法，比如「午饭 35」'),
    )));
    await tester.pump();
    fake.emit('巴拉巴拉', isFinal: true);
    await tester.pump();
    await tester.pump();

    await tester.tap(find.text('生成草稿'));
    await tester.pump();
    await tester.pump();

    expect(find.text('没听明白，请换个说法，比如「午饭 35」'), findsOneWidget);
    // 仍在文本确认态，可继续编辑重试
    expect(find.text('生成草稿'), findsOneWidget);
  });

  testWidgets('解析抛错（如 BYOK 未配置）：显示后端话术', (tester) async {
    final fake = FakeSpeechRecognizer();
    final controller =
        VoiceInputController(recognizer: fake, stopGrace: Duration.zero);

    await tester.pumpWidget(wrap(VoiceEntrySheet(
      controller: controller,
      parser: (text) async => throw Exception('请先配置 AI 模型'),
    )));
    await tester.pump();
    fake.emit('午饭 35', isFinal: true);
    await tester.pump();
    await tester.pump();

    await tester.tap(find.text('生成草稿'));
    await tester.pump();
    await tester.pump();

    expect(find.text('解析失败，请重试'), findsOneWidget);
  });

  testWidgets('无识别服务：错误态 + 重试 / 手动记账出口', (tester) async {
    final fake = FakeSpeechRecognizer()..initializeResult = false;
    final controller =
        VoiceInputController(recognizer: fake, stopGrace: Duration.zero);

    await tester.pumpWidget(wrap(VoiceEntrySheet(
      controller: controller,
      parser: (text) async => const VoiceParseResult.draft(_draft),
    )));
    await tester.pump();
    await tester.pump();

    expect(controller.phase, VoiceInputPhase.error);
    expect(find.text('当前设备没有可用的语音识别服务'), findsOneWidget);
    expect(find.text('重试'), findsOneWidget);
    expect(find.text('手动记账'), findsOneWidget);
  });

  testWidgets('权限被拒：错误态给权限提示', (tester) async {
    final fake = FakeSpeechRecognizer();
    final controller =
        VoiceInputController(recognizer: fake, stopGrace: Duration.zero);

    await tester.pumpWidget(wrap(VoiceEntrySheet(
      controller: controller,
      parser: (text) async => const VoiceParseResult.draft(_draft),
    )));
    await tester.pump();
    fake.emitError('error_permission');
    await tester.pump();

    expect(find.text('需要麦克风权限才能语音记账，请在系统设置中允许'), findsOneWidget);
    expect(find.text('重试'), findsOneWidget);
  });

  testWidgets('没听清（空文本结束）：错误提示 + 可重说', (tester) async {
    final fake = FakeSpeechRecognizer();
    final controller =
        VoiceInputController(recognizer: fake, stopGrace: Duration.zero);

    await tester.pumpWidget(wrap(VoiceEntrySheet(
      controller: controller,
      parser: (text) async => const VoiceParseResult.draft(_draft),
    )));
    await tester.pump();

    // 直接结束，没说出任何内容
    await tester.tap(find.text('结束收音'));
    await tester.pump();
    await tester.pump();

    expect(find.text('没听清，请再试一次'), findsOneWidget);
    expect(find.text('重试'), findsOneWidget);
  });
}
