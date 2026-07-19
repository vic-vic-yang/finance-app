import 'package:flutter/material.dart';
import '../core/theme.dart';
import '../services/api_service.dart';
import '../services/llm_config_service.dart';
import '../widgets/glass.dart';

/// 新增 / 编辑一套 AI 模型配置。
/// 保存结果写回本机安全存储（服务端过手不落库），pop(true) 表示有变更。
class AiModelEditScreen extends StatefulWidget {
  /// null = 新增；传入则为编辑
  final PersonalLlmConfig? existing;
  const AiModelEditScreen({super.key, this.existing});

  @override
  State<AiModelEditScreen> createState() => _AiModelEditScreenState();
}

class _AiModelEditScreenState extends State<AiModelEditScreen> {
  late String _provider = widget.existing?.provider ?? 'deepseek';
  final _baseUrlCtrl = TextEditingController();
  final _keyCtrl = TextEditingController();
  final _modelCtrl = TextEditingController();
  final _visionCtrl = TextEditingController();
  bool _keyVisible = false;
  bool _busy = false;
  String? _testResult;
  bool? _testOk;

  LlmProviderPreset get _preset =>
      kLlmPresets.firstWhere((p) => p.id == _provider,
          orElse: () => kLlmPresets.last);

  @override
  void initState() {
    super.initState();
    final e = widget.existing;
    if (e != null) {
      _baseUrlCtrl.text = e.baseUrl;
      _keyCtrl.text = e.apiKey;
      _modelCtrl.text = e.model;
      _visionCtrl.text = e.visionModel;
    } else {
      // 新增：带上默认预设值，用户基本只需粘 Key
      _baseUrlCtrl.text = _preset.baseUrl;
      _modelCtrl.text = _preset.defaultModel;
      _visionCtrl.text = _preset.defaultVisionModel;
    }
  }

  @override
  void dispose() {
    _baseUrlCtrl.dispose();
    _keyCtrl.dispose();
    _modelCtrl.dispose();
    _visionCtrl.dispose();
    super.dispose();
  }

  /// 厂家切换时暂存当前输入（纯内存，不落盘）
  final _tempInputs = <String, Map<String, String>>{};

  void _applyPreset(String id) {
    if (id == _provider) return;
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
        _baseUrlCtrl.text = p.baseUrl;
        _modelCtrl.text = p.defaultModel;
        _visionCtrl.text = p.defaultVisionModel;
        // 换厂家必须清 Key，避免「新厂家 URL + 旧厂家 Key」的错配
        _keyCtrl.text = '';
      }
      _testResult = null;
      _testOk = null;
    });
  }

  PersonalLlmConfig _formConfig() => PersonalLlmConfig(
        id: widget.existing?.id ?? LlmConfigService.newId(),
        provider: _provider,
        baseUrl: _baseUrlCtrl.text.trim(),
        apiKey: _keyCtrl.text.trim(),
        model: _modelCtrl.text.trim(),
        visionModel: _visionCtrl.text.trim(),
      );

  Future<void> _test() async {
    final cfg = _formConfig();
    if (!cfg.isComplete) {
      _toast('Base URL / API Key / 模型 都要填');
      return;
    }
    setState(() {
      _busy = true;
      _testResult = null;
      _testOk = null;
    });
    try {
      // 直接用表单配置测（临时请求头），不改动已保存的配置
      final res = await ApiService.testLlm(override: cfg);
      final ok = res['ok'] as bool? ?? false;
      setState(() {
        _testOk = ok;
        _testResult = ok
            ? '连接成功 ✓ （${res['model']}）'
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

  Future<void> _save() async {
    final cfg = _formConfig();
    if (!cfg.isComplete) {
      _toast('Base URL / API Key / 模型 都要填');
      return;
    }
    setState(() => _busy = true);
    try {
      await LlmConfigService.instance.upsert(cfg);
      if (mounted) Navigator.pop(context, true);
    } catch (e) {
      _toast('保存失败：$e');
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
    final isEdit = widget.existing != null;
    return Scaffold(
      backgroundColor: AppColors.bg,
      appBar: AuraAppBar(title: isEdit ? '编辑模型' : '添加模型'),
      body: AuraBackground(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 40),
          children: [
            GlassCard(
              radius: 16,
              padding: const EdgeInsets.fromLTRB(16, 14, 16, 16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('服务商',
                      style: TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w600,
                          color: AppColors.text1)),
                  const SizedBox(height: 12),
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
                        style:
                            TextStyle(fontSize: 11, color: AppColors.text3)),
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
            ),
            const SizedBox(height: 14),
            Row(children: [
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
            ]),
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
          ],
        ),
      ),
    );
  }
}
