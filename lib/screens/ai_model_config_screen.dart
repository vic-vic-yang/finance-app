import 'package:flutter/material.dart';
import '../core/theme.dart';
import '../services/api_service.dart';
import '../services/llm_config_service.dart';
import '../widgets/glass.dart';

/// AI 模型配置（BYOK）：
/// - Key 默认只存本机（服务端过手不落库）
/// - 打开「共享给账本成员」则加密上传，账本所有成员共用
class AiModelConfigScreen extends StatefulWidget {
  const AiModelConfigScreen({super.key});

  @override
  State<AiModelConfigScreen> createState() => _AiModelConfigScreenState();
}

class _AiModelConfigScreenState extends State<AiModelConfigScreen> {
  String _provider = 'deepseek';
  final _baseUrlCtrl = TextEditingController();
  final _keyCtrl = TextEditingController();
  final _modelCtrl = TextEditingController();
  final _visionCtrl = TextEditingController();
  bool _keyVisible = false;
  bool _share = false;
  bool _loading = true;
  bool _busy = false;
  String? _testResult; // 连通性测试结果文案
  bool? _testOk;

  // 账本共享现状（他人配置时展示）
  Map<String, dynamic>? _sharedInfo;
  bool _serverDefaultAllowed = false;

  LlmProviderPreset get _preset =>
      kLlmPresets.firstWhere((p) => p.id == _provider,
          orElse: () => kLlmPresets.last);

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _baseUrlCtrl.dispose();
    _keyCtrl.dispose();
    _modelCtrl.dispose();
    _visionCtrl.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    // 本机个人配置
    final cfg = await LlmConfigService.instance.loadRaw();
    _provider = cfg.provider;
    _baseUrlCtrl.text = cfg.baseUrl;
    _keyCtrl.text = cfg.apiKey;
    _modelCtrl.text = cfg.model;
    _visionCtrl.text = cfg.visionModel;
    // 账本共享现状
    try {
      final res = await ApiService.getLlmConfig();
      _sharedInfo = res['shared'] as Map<String, dynamic>?;
      _serverDefaultAllowed = res['serverDefaultAllowed'] as bool? ?? false;
      if (_sharedInfo != null && (_sharedInfo!['isOwner'] as bool? ?? false)) {
        _share = true;
      }
    } catch (_) {}
    if (mounted) setState(() => _loading = false);
  }

  /// 厂家切换时暂存当前输入（纯内存，不落盘）
  final _tempInputs = <String, Map<String, String>>{};

  void _applyPreset(String id) {
    // 离开当前厂家前暂存输入
    _tempInputs[_provider] = {
      'baseUrl': _baseUrlCtrl.text,
      'apiKey': _keyCtrl.text,
      'model': _modelCtrl.text,
      'vision': _visionCtrl.text,
    };
    setState(() {
      _provider = id;
      final p = _preset;
      // 切到的厂家如果有之前填过的输入，恢复之；否则用预设值
      final prev = _tempInputs[id];
      if (prev != null && (prev['baseUrl'] ?? '').isNotEmpty) {
        _baseUrlCtrl.text = prev['baseUrl'] ?? '';
        _keyCtrl.text = prev['apiKey'] ?? '';
        _modelCtrl.text = prev['model'] ?? '';
        _visionCtrl.text = prev['vision'] ?? '';
      } else {
        if (p.baseUrl.isNotEmpty) _baseUrlCtrl.text = p.baseUrl;
        if (p.defaultModel.isNotEmpty) _modelCtrl.text = p.defaultModel;
        _visionCtrl.text = p.defaultVisionModel;
      }
    });
  }

  Future<void> _save() async {
    final cfg = PersonalLlmConfig(
      provider: _provider,
      baseUrl: _baseUrlCtrl.text.trim(),
      apiKey: _keyCtrl.text.trim(),
      model: _modelCtrl.text.trim(),
      visionModel: _visionCtrl.text.trim(),
    );
    if (!cfg.isComplete) {
      _toast('Base URL / API Key / 模型 都要填');
      return;
    }
    setState(() => _busy = true);
    try {
      await LlmConfigService.instance.save(cfg);
      if (_share) {
        await ApiService.putLlmConfig(
          provider: cfg.provider,
          baseUrl: cfg.baseUrl,
          modelId: cfg.model,
          visionModelId:
              cfg.visionModel.isEmpty ? null : cfg.visionModel,
          apiKey: cfg.apiKey,
        );
      } else if (_sharedInfo != null &&
          (_sharedInfo!['isOwner'] as bool? ?? false)) {
        // 之前共享过、现在关掉 → 删除服务器上的
        await ApiService.deleteLlmConfig();
      }
      _toast(_share ? '已保存并共享给账本成员' : '已保存（仅本机）');
      await _load();
    } catch (e) {
      _toast('保存失败：$e');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _test() async {
    setState(() {
      _busy = true;
      _testResult = null;
      _testOk = null;
    });
    try {
      // 先把当前表单存到本机，让请求头带上最新配置再测
      final cfg = PersonalLlmConfig(
        provider: _provider,
        baseUrl: _baseUrlCtrl.text.trim(),
        apiKey: _keyCtrl.text.trim(),
        model: _modelCtrl.text.trim(),
        visionModel: _visionCtrl.text.trim(),
      );
      if (cfg.isComplete) await LlmConfigService.instance.save(cfg);
      final res = await ApiService.testLlm();
      final ok = res['ok'] as bool? ?? false;
      final src = switch (res['source'] as String? ?? '') {
        'personal' => '个人配置',
        'ledger' => '账本共享',
        'server' => '服务端默认',
        _ => '',
      };
      setState(() {
        _testOk = ok;
        _testResult = ok
            ? '连接成功 ✓ （$src · ${res['model']}）'
            : '连接失败：${res['error'] ?? '未知错误'}';
      });
    } catch (e) {
      setState(() {
        _testOk = false;
        _testResult = '测试失败：$e';
      });
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  void _toast(String msg) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(msg),
      behavior: SnackBarBehavior.floating,
    ));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.bg,
      appBar: const AuraAppBar(title: 'AI 模型'),
      body: AuraBackground(
        child: _loading
            ? const Center(child: CircularProgressIndicator())
            : ListView(
                padding: const EdgeInsets.fromLTRB(16, 12, 16, 40),
                children: [
                  if (_sharedInfo != null &&
                      !(_sharedInfo!['isOwner'] as bool? ?? false))
                    _sharedByOthersBanner(),
                  _formCard(),
                  const SizedBox(height: 14),
                  _shareCard(),
                  const SizedBox(height: 14),
                  _actions(),
                  if (_testResult != null) ...[
                    const SizedBox(height: 12),
                    Text(_testResult!,
                        style: TextStyle(
                            fontSize: 13,
                            height: 1.5,
                            color: _testOk == true
                                ? AppColors.expense
                                : AppColors.danger)),
                  ],
                  const SizedBox(height: 18),
                  _privacyNote(),
                ],
              ),
      ),
    );
  }

  Widget _sharedByOthersBanner() => Container(
        margin: const EdgeInsets.only(bottom: 14),
        padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
        decoration: BoxDecoration(
          color: AppColors.primaryLight,
          borderRadius: BorderRadius.circular(14),
        ),
        child: Row(children: [
          Icon(Icons.diversity_3_rounded,
              size: 18, color: AppColors.primary),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              '当前账本已由 @${_sharedInfo!['ownerName']} 提供共享模型'
              '（${_sharedInfo!['modelId']}），你无需配置即可使用 AI；'
              '也可以在下方配置自己的进行覆盖。',
              style: TextStyle(
                  fontSize: 12.5, color: AppColors.text2, height: 1.5),
            ),
          ),
        ]),
      );

  Widget _formCard() => GlassCard(
        radius: 16,
        padding: const EdgeInsets.fromLTRB(16, 14, 16, 16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('模型配置',
                style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                    color: AppColors.text1)),
            const SizedBox(height: 12),
            // 服务商预设
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                for (final p in kLlmPresets)
                  ChoiceChip(
                    label: Text(p.name,
                        style: const TextStyle(fontSize: 12.5)),
                    selected: _provider == p.id,
                    onSelected: (_) => _applyPreset(p.id),
                  ),
              ],
            ),
            if (_preset.keyUrl.isNotEmpty) ...[
              const SizedBox(height: 6),
              Text('Key 申请：${_preset.keyUrl}',
                  style: TextStyle(fontSize: 11, color: AppColors.text3)),
            ],
            const SizedBox(height: 12),
            TextField(
              controller: _baseUrlCtrl,
              decoration: const InputDecoration(
                labelText: 'Base URL',
                hintText: 'https://api.deepseek.com',
              ),
            ),
            const SizedBox(height: 10),
            TextField(
              controller: _keyCtrl,
              obscureText: !_keyVisible,
              decoration: InputDecoration(
                labelText: 'API Key',
                hintText: 'sk-…',
                suffixIcon: IconButton(
                  icon: Icon(
                      _keyVisible
                          ? Icons.visibility_off_outlined
                          : Icons.visibility_outlined,
                      size: 18),
                  onPressed: () =>
                      setState(() => _keyVisible = !_keyVisible),
                ),
              ),
            ),
            const SizedBox(height: 10),
            TextField(
              controller: _modelCtrl,
              decoration: const InputDecoration(
                labelText: '文本模型',
                hintText: 'deepseek-chat',
              ),
            ),
            const SizedBox(height: 10),
            TextField(
              controller: _visionCtrl,
              decoration: const InputDecoration(
                labelText: '视觉模型（可选，图片导入用）',
                hintText: '留空则不支持截图/图片导入',
              ),
            ),
          ],
        ),
      );

  Widget _shareCard() => GlassCard(
        radius: 16,
        padding: const EdgeInsets.fromLTRB(16, 6, 8, 6),
        child: SwitchListTile(
          contentPadding: EdgeInsets.zero,
          title: Text('共享给账本成员',
              style: TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
                  color: AppColors.text1)),
          subtitle: Text(
            _share
                ? 'Key 将加密上传到服务器，本账本所有成员的 AI 功能共用这份配置'
                : 'Key 仅保存在本机，只有你自己能用',
            style: TextStyle(
                fontSize: 11.5, color: AppColors.text3, height: 1.4),
          ),
          value: _share,
          onChanged: (v) => setState(() => _share = v),
        ),
      );

  Widget _actions() => Row(children: [
        Expanded(
          child: OutlinedButton(
            onPressed: _busy ? null : _test,
            child: Text(_busy ? '请稍候…' : '测试连接'),
          ),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: ElevatedButton(
            onPressed: _busy ? null : _save,
            child: const Text('保存'),
          ),
        ),
      ]);

  Widget _privacyNote() => Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            '隐私说明\n'
            '· 仅本机模式：Key 存手机安全存储，随请求转发给服务器直连模型，服务器不存储。\n'
            '· 共享模式：Key 用服务端密钥 AES-256-GCM 加密后落库，供账本成员共用；'
            '关闭共享即从服务器删除。\n'
            '${_serverDefaultAllowed ? '· 你在服务端白名单内：不配置也可使用内置默认模型。' : '· 未配置时 AI 功能不可用（记账等核心功能不受影响）。'}',
            style: TextStyle(fontSize: 11.5, color: AppColors.text3, height: 1.7),
          ),
          const SizedBox(height: 12),
          _vipStatusBanner(),
        ],
      );

  Widget _vipStatusBanner() {
    return FutureBuilder<Map<String, dynamic>>(
      future: ApiService.getVipStatus().catchError((_) => <String, dynamic>{'isVip': false}),
      builder: (_, snap) {
        final data = snap.data;
        if (data == null || data['isVip'] != true) {
          return const SizedBox.shrink();
        }
        final tier = data['vipTier'] as String? ?? '';
        final days = data['remainingDays'] as int? ?? 0;
        return Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: AppColors.primaryLight,
            borderRadius: BorderRadius.circular(12),
          ),
          child: Row(children: [
            const Text('👑', style: TextStyle(fontSize: 18)),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('VIP 会员 · $tier',
                      style: TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w600,
                          color: AppColors.text1)),
                  if (days > 0)
                    Text('剩余 $days 天',
                        style: TextStyle(
                            fontSize: 11.5, color: AppColors.text2)),
                ],
              ),
            ),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
              decoration: BoxDecoration(
                color: AppColors.primary,
                borderRadius: BorderRadius.circular(6),
              ),
              child: Text('VIP',
                  style: TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.bold,
                      color: AppColors.onPrimary)),
            ),
          ]),
        );
      },
    );
  }
}
