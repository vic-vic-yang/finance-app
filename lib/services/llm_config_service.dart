import 'dart:convert';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';

/// 个人 LLM 配置（BYOK）：Key 只存本机安全存储，**按账号隔离**。
/// 每个登录账号有自己的一套配置列表，退出登录只清内存不清存储，
/// 重新登录（AuthService.saveAuth → load(userId)）自动恢复该账号的配置。
/// 其中一套为「使用中」，所有 AI 请求自动带 X-LLM-* 请求头，服务端"过手不落库"。
class PersonalLlmConfig {
  final String id; // 本机生成的唯一 id
  final String provider; // deepseek / qwen / kimi / glm / custom
  final String baseUrl;
  final String apiKey;
  final String model;
  final String visionModel; // 可空：没有就不支持图片导入

  const PersonalLlmConfig({
    required this.id,
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

  /// 列表展示名：优先厂商预设名，自定义则显示模型 id
  String get displayName {
    for (final p in kLlmPresets) {
      if (p.id == provider) return p.name;
    }
    return model.isNotEmpty ? model : '自定义';
  }

  PersonalLlmConfig copyWith({
    String? provider,
    String? baseUrl,
    String? apiKey,
    String? model,
    String? visionModel,
  }) =>
      PersonalLlmConfig(
        id: id,
        provider: provider ?? this.provider,
        baseUrl: baseUrl ?? this.baseUrl,
        apiKey: apiKey ?? this.apiKey,
        model: model ?? this.model,
        visionModel: visionModel ?? this.visionModel,
      );

  Map<String, dynamic> toJson() => {
        'id': id,
        'provider': provider,
        'baseUrl': baseUrl,
        'apiKey': apiKey,
        'model': model,
        'visionModel': visionModel,
      };

  factory PersonalLlmConfig.fromJson(Map<String, dynamic> j) =>
      PersonalLlmConfig(
        id: (j['id'] as String?) ?? '',
        provider: (j['provider'] as String?) ?? 'custom',
        baseUrl: (j['baseUrl'] as String?) ?? '',
        apiKey: (j['apiKey'] as String?) ?? '',
        model: (j['model'] as String?) ?? '',
        visionModel: (j['visionModel'] as String?) ?? '',
      );
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
      'deepseek-v4-flash', '', 'platform.deepseek.com'),
  LlmProviderPreset('qwen', '通义千问', 'https://dashscope.aliyuncs.com/compatible-mode',
      'qwen-plus', 'qwen-vl-plus', 'bailian.console.aliyun.com'),
  LlmProviderPreset('kimi', 'Kimi', 'https://api.moonshot.ai/v1',
      'kimi-k3', 'kimi-k3', 'platform.moonshot.cn'),
  LlmProviderPreset('glm', '智谱 GLM', 'https://open.bigmodel.cn/api/paas/v4',
      'glm-4-flash', 'glm-4v-flash', 'open.bigmodel.cn'),
  LlmProviderPreset('custom', '自定义（OpenAI 兼容）', '', '', '', ''),
];

class LlmConfigService {
  LlmConfigService._();
  static final LlmConfigService instance = LlmConfigService._();

  static const _storage = FlutterSecureStorage();
  // 按账号隔离的存储键前缀（后缀是 userId）
  static const _kConfigsPrefix = 'llm_configs@'; // JSON 数组
  static const _kActivePrefix = 'llm_active@';

  // 上一版的全局多配置键（未按账号隔离），首次启动迁移到当前账号名下后删除
  static const _globalConfigs = 'llm_configs';
  static const _globalActiveId = 'llm_active_id';

  // 更早的单配置存储键（首次启动自动迁移后删除）
  static const _legacyProvider = 'llm_provider';
  static const _legacyBaseUrl = 'llm_base_url';
  static const _legacyApiKey = 'llm_api_key';
  static const _legacyModel = 'llm_model';
  static const _legacyVision = 'llm_vision_model';

  List<PersonalLlmConfig> _configs = [];
  String? _activeId;
  String? _userId;
  bool _loaded = false;

  String get _configsKey => '$_kConfigsPrefix$_userId';
  String get _activeKey => '$_kActivePrefix$_userId';

  /// 启动时（main）与登录成功时（AuthService.saveAuth）调用。
  /// [userId] 省略则沿用当前账号；传 null 表示未登录。
  Future<void> load([String? userId]) async {
    _userId = userId ?? _userId;
    _configs = [];
    _activeId = null;
    try {
      if (_userId != null) {
        var migrated = false;
        var raw = await _storage.read(key: _configsKey);
        if (raw == null) {
          // 迁移①：上一版的全局多配置（未按账号隔离）→ 当前账号
          raw = await _storage.read(key: _globalConfigs);
          if (raw != null) {
            _activeId = await _storage.read(key: _globalActiveId);
            await Future.wait([
              _storage.delete(key: _globalConfigs),
              _storage.delete(key: _globalActiveId),
            ]);
            migrated = true;
          } else {
            // 迁移②：更早的单配置版本
            migrated = await _migrateLegacy();
          }
        }
        if (raw != null) {
          _configs = _parseConfigs(raw);
          // 正常路径：读回该账号「使用中」的配置 id（迁移路径已在上面设置过）
          if (!migrated) _activeId = await _storage.read(key: _activeKey);
        }
        if (_activeId == null || !_configs.any((c) => c.id == _activeId)) {
          _activeId = _configs.isEmpty ? null : _configs.first.id;
        }
        if (migrated) await _persist();
      } else {
        // 未登录（或本地用户信息缺 id）：只读加载全局/旧配置到内存，
        // 保证 AI 功能可用；不落盘不删除，等登录拿到 userId 后正式迁移
        var raw = await _storage.read(key: _globalConfigs);
        if (raw != null) {
          _configs = _parseConfigs(raw);
          _activeId = await _storage.read(key: _globalActiveId);
        } else if (await _migrateLegacy(persist: false)) {
          // _migrateLegacy(persist:false) 已填好 _configs/_activeId，
          // 旧键保留不删，等登录拿到 userId 后走正式迁移
        }
      }
      if (_userId == null &&
          _activeId == null &&
          _configs.isNotEmpty) {
        _activeId = _configs.first.id;
      }
    } catch (_) {
      _configs = [];
      _activeId = null;
    }
    _loaded = true;
  }

  static List<PersonalLlmConfig> _parseConfigs(String raw) =>
      (jsonDecode(raw) as List)
          .whereType<Map>()
          .map((e) => PersonalLlmConfig.fromJson(e.cast<String, dynamic>()))
          .where((c) => c.id.isNotEmpty && c.isComplete)
          .toList();

  /// 旧版（单配置）→ 当前账号的多配置列表；返回是否有迁移发生。
  /// [persist]=false 时只读到内存，不删除旧键（未登录兜底路径用）
  Future<bool> _migrateLegacy({bool persist = true}) async {
    final vals = await Future.wait([
      _storage.read(key: _legacyProvider),
      _storage.read(key: _legacyBaseUrl),
      _storage.read(key: _legacyApiKey),
      _storage.read(key: _legacyModel),
      _storage.read(key: _legacyVision),
    ]);
    final hasLegacy = vals.any((v) => v != null && v.isNotEmpty);
    if (!hasLegacy) return false;
    final legacy = PersonalLlmConfig(
      id: _newId(),
      provider: vals[0] ?? 'deepseek',
      baseUrl: vals[1] ?? '',
      apiKey: vals[2] ?? '',
      model: vals[3] ?? '',
      visionModel: vals[4] ?? '',
    );
    if (persist) {
      await Future.wait([
        _storage.delete(key: _legacyProvider),
        _storage.delete(key: _legacyBaseUrl),
        _storage.delete(key: _legacyApiKey),
        _storage.delete(key: _legacyModel),
        _storage.delete(key: _legacyVision),
      ]);
    }
    _configs = legacy.isComplete ? [legacy] : [];
    _activeId = _configs.isEmpty ? null : _configs.first.id;
    return true;
  }

  Future<void> _ensureLoaded() async {
    if (!_loaded) await load();
  }

  Future<void> _persist() async {
    final uid = _userId;
    if (uid == null) return; // 未登录不落盘
    await _storage.write(
      key: _configsKey,
      value: jsonEncode(_configs.map((c) => c.toJson()).toList()),
    );
    if (_activeId != null) {
      await _storage.write(key: _activeKey, value: _activeId);
    } else {
      await _storage.delete(key: _activeKey);
    }
  }

  static int _seq = 0;
  static String _newId() =>
      '${DateTime.now().millisecondsSinceEpoch}_${_seq++}';

  List<PersonalLlmConfig> get configs => List.unmodifiable(_configs);

  /// 「使用中」的配置；没有则为 null
  PersonalLlmConfig? get active {
    for (final c in _configs) {
      if (c.id == _activeId) return c;
    }
    return null;
  }

  bool get hasPersonal => active != null;

  /// 新增或更新一套配置；若当前没有使用中的配置，自动把它设为使用中
  Future<void> upsert(PersonalLlmConfig cfg) async {
    await _ensureLoaded();
    final i = _configs.indexWhere((c) => c.id == cfg.id);
    if (i >= 0) {
      _configs[i] = cfg;
    } else {
      _configs.add(cfg);
    }
    if (active == null && cfg.isComplete) _activeId = cfg.id;
    await _persist();
  }

  /// 删除一套配置；删掉使用中的则顺位第一个
  Future<void> remove(String id) async {
    await _ensureLoaded();
    _configs.removeWhere((c) => c.id == id);
    if (_activeId == id) {
      _activeId = _configs.isEmpty ? null : _configs.first.id;
    }
    await _persist();
  }

  Future<void> setActive(String id) async {
    await _ensureLoaded();
    if (!_configs.any((c) => c.id == id)) return;
    _activeId = id;
    await _persist();
  }

  /// 退出登录时调用：只清内存态（Key 仍按账号留在本机安全存储），
  /// 下次登录 saveAuth 会用该账号 id 重新 load 恢复
  Future<void> unload() async {
    _configs = [];
    _activeId = null;
    _userId = null;
    _loaded = false;
  }

  /// 给某套配置生成 X-LLM 请求头（配置不完整返回空 map）
  static Map<String, String> headersOf(PersonalLlmConfig c) {
    if (!c.isComplete) return const {};
    return {
      'X-LLM-Base-Url': c.baseUrl.trim(),
      'X-LLM-Api-Key': c.apiKey.trim(),
      'X-LLM-Model': c.model.trim(),
      if (c.visionModel.trim().isNotEmpty)
        'X-LLM-Vision-Model': c.visionModel.trim(),
    };
  }

  /// 附加到所有请求的 X-LLM 头（未配置返回空 map）
  Map<String, String> headers() {
    final c = active;
    if (c == null) return const {};
    return headersOf(c);
  }

  /// 生成一个新配置 id（编辑页新增时用）
  static String newId() => _newId();
}
