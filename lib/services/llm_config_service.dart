import 'package:flutter_secure_storage/flutter_secure_storage.dart';

/// 个人 LLM 配置（BYOK）：Key 只存本机安全存储。
/// 配好后所有 AI 请求自动带 X-LLM-* 请求头，服务端"过手不落库"直连你的模型。
class PersonalLlmConfig {
  final String provider; // deepseek / qwen / kimi / glm / custom
  final String baseUrl;
  final String apiKey;
  final String model;
  final String visionModel; // 可空：没有就不支持图片导入

  const PersonalLlmConfig({
    required this.provider,
    required this.baseUrl,
    required this.apiKey,
    required this.model,
    this.visionModel = '',
  });

  bool get isComplete =>
      baseUrl.trim().isNotEmpty &&
      apiKey.trim().isNotEmpty &&
      model.trim().isNotEmpty;
}

/// 服务商预设：选中即自动填 baseUrl + 常用模型，用户基本只需要粘 Key
class LlmProviderPreset {
  final String id;
  final String name;
  final String baseUrl;
  final String defaultModel;
  final String defaultVisionModel;
  final String keyUrl; // 去哪申请 Key（展示用）
  const LlmProviderPreset(this.id, this.name, this.baseUrl, this.defaultModel,
      this.defaultVisionModel, this.keyUrl);
}

const kLlmPresets = <LlmProviderPreset>[
  LlmProviderPreset('deepseek', 'DeepSeek', 'https://api.deepseek.com',
      'deepseek-chat', '', 'platform.deepseek.com'),
  LlmProviderPreset('qwen', '通义千问', 'https://dashscope.aliyuncs.com/compatible-mode',
      'qwen-plus', 'qwen-vl-plus', 'bailian.console.aliyun.com'),
  LlmProviderPreset('kimi', 'Kimi', 'https://api.moonshot.cn',
      'moonshot-v1-8k', 'moonshot-v1-8k-vision-preview', 'platform.moonshot.cn'),
  LlmProviderPreset('glm', '智谱 GLM', 'https://open.bigmodel.cn/api/paas',
      'glm-4-flash', 'glm-4v-flash', 'open.bigmodel.cn'),
  LlmProviderPreset('custom', '自定义（OpenAI 兼容）', '', '', '', ''),
];

class LlmConfigService {
  LlmConfigService._();
  static final LlmConfigService instance = LlmConfigService._();

  static const _storage = FlutterSecureStorage();
  static const _kProvider = 'llm_provider';
  static const _kBaseUrl = 'llm_base_url';
  static const _kApiKey = 'llm_api_key';
  static const _kModel = 'llm_model';
  static const _kVision = 'llm_vision_model';

  PersonalLlmConfig? _cached;
  bool _loaded = false;

  /// 启动时调用一次（main 里），之后 headers() 同步可用
  Future<void> load() async {
    try {
      final vals = await Future.wait([
        _storage.read(key: _kProvider),
        _storage.read(key: _kBaseUrl),
        _storage.read(key: _kApiKey),
        _storage.read(key: _kModel),
        _storage.read(key: _kVision),
      ]);
      final cfg = PersonalLlmConfig(
        provider: vals[0] ?? 'deepseek',
        baseUrl: vals[1] ?? '',
        apiKey: vals[2] ?? '',
        model: vals[3] ?? '',
        visionModel: vals[4] ?? '',
      );
      _cached = cfg.isComplete ? cfg : null;
    } catch (_) {
      _cached = null;
    }
    _loaded = true;
  }

  PersonalLlmConfig? get config => _cached;
  bool get hasPersonal => _cached != null;

  Future<PersonalLlmConfig> loadRaw() async {
    if (!_loaded) await load();
    return PersonalLlmConfig(
      provider: await _storage.read(key: _kProvider) ?? 'deepseek',
      baseUrl: await _storage.read(key: _kBaseUrl) ?? '',
      apiKey: await _storage.read(key: _kApiKey) ?? '',
      model: await _storage.read(key: _kModel) ?? '',
      visionModel: await _storage.read(key: _kVision) ?? '',
    );
  }

  Future<void> save(PersonalLlmConfig cfg) async {
    await Future.wait([
      _storage.write(key: _kProvider, value: cfg.provider),
      _storage.write(key: _kBaseUrl, value: cfg.baseUrl.trim()),
      _storage.write(key: _kApiKey, value: cfg.apiKey.trim()),
      _storage.write(key: _kModel, value: cfg.model.trim()),
      _storage.write(key: _kVision, value: cfg.visionModel.trim()),
    ]);
    _cached = cfg.isComplete ? cfg : null;
  }

  Future<void> clear() async {
    await Future.wait([
      _storage.delete(key: _kBaseUrl),
      _storage.delete(key: _kApiKey),
      _storage.delete(key: _kModel),
      _storage.delete(key: _kVision),
    ]);
    _cached = null;
  }

  /// 附加到所有请求的 X-LLM 头（未配置返回空 map）
  Map<String, String> headers() {
    final c = _cached;
    if (c == null) return const {};
    return {
      'X-LLM-Base-Url': c.baseUrl.trim(),
      'X-LLM-Api-Key': c.apiKey.trim(),
      'X-LLM-Model': c.model.trim(),
      if (c.visionModel.trim().isNotEmpty)
        'X-LLM-Vision-Model': c.visionModel.trim(),
    };
  }
}
