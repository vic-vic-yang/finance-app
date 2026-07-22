import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../core/theme.dart';
import '../services/health_service.dart';
import '../widgets/siku_ui.dart';

/// 财务健康评分页
///
/// 数据来自 GET /api/health/score（服务端纯 SQL 聚合 + 纯函数打分）：
///   1. 顶部大号评分仪表盘（弧形进度 + 分数 + 等级，CustomPaint 自绘）
///   2. 五个维度卡片（名称 / 分数条 / headline / advice）
///   3. 下拉刷新重新计算
class HealthScreen extends StatefulWidget {
  const HealthScreen({super.key});

  @override
  State<HealthScreen> createState() => _HealthScreenState();
}

class _HealthScreenState extends State<HealthScreen> {
  HealthScore? _data;
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    try {
      final data = await HealthService.getScore();
      if (!mounted) return;
      setState(() {
        _data = data;
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() => _loading = false);
      _toast('加载失败：$e');
    }
  }

  void _toast(String s) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(s)));
  }

  /// 分数段配色：≥80 好（sage 绿）/ 60-79 一般（沙色）/ <60 警示（红）
  Color _scoreColor(int score) {
    // 用主题主色而非收支语义色：换主题时跟随，且不与「支出绿」混淆
    if (score >= 80) return AppColors.primary;
    if (score >= 60) return AppColors.warning;
    return AppColors.danger;
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.bg,
      appBar: const AuraAppBar(title: '财务健康分'),
      body: AuraBackground(
        child: _loading && _data == null
            ? const Center(child: CircularProgressIndicator())
            : _data == null
                ? const EmptyState(
                    emoji: '🩺',
                    title: '暂时算不出健康分',
                    hint: '下拉重试，或先记几笔账。',
                  )
                : RefreshIndicator(
                    onRefresh: _load,
                    child: ListView(
                      padding: const EdgeInsets.fromLTRB(20, 12, 20, 40),
                      children: [
                        _gaugeCard(_data!),
                        const SizedBox(height: 10),
                        _methodologyNote(),
                        SectionHeader(
                          title: '五维明细',
                          horizontal: 0,
                          top: 20,
                        ),
                        for (final d in _data!.dimensions) ...[
                          _dimensionCard(d),
                          const SizedBox(height: 10),
                        ],
                      ],
                    ),
                  ),
      ),
    );
  }

  // ── 1) 评分仪表盘大卡 ────────────────────────────────────────
  Widget _gaugeCard(HealthScore data) {
    final color = _scoreColor(data.score);
    return GlassCard(
      radius: 18,
      padding: const EdgeInsets.fromLTRB(20, 24, 20, 20),
      child: Column(
        children: [
          SizedBox(
            width: 200,
            height: 200,
            child: CustomPaint(
              painter: _GaugePainter(
                progress: data.score / 100,
                trackColor: AppColors.surfaceAlt,
                progressColor: color,
              ),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Text(
                    '${data.score}',
                    style: TextStyle(
                      fontSize: 56,
                      fontWeight: FontWeight.w700,
                      height: 1,
                      color: AppColors.text1,
                    ),
                  ),
                  const SizedBox(height: 6),
                  Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                    decoration: BoxDecoration(
                      color: color.withValues(alpha: 0.14),
                      borderRadius: BorderRadius.circular(20),
                    ),
                    child: Text(
                      '等级 ${data.grade}',
                      style: TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w700,
                        color: color,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 8),
          Text(
            _gradeComment(data.grade),
            style: TextStyle(fontSize: 13, color: AppColors.text2),
          ),
          if (data.computedAt != null) ...[
            const SizedBox(height: 4),
            Text(
              '计算于 ${DateFormat('M月d日 HH:mm').format(data.computedAt!.toLocal())}',
              style: TextStyle(fontSize: 11, color: AppColors.text3),
            ),
          ],
        ],
      ),
    );
  }

  String _gradeComment(String grade) {
    switch (grade) {
      case 'S':
        return '财务状况非常健康，堪称教科书级别';
      case 'A':
        return '财务状况健康，继续保持';
      case 'B':
        return '整体不错，个别维度还有提升空间';
      case 'C':
        return '刚及格，看看下面哪个维度拖了后腿';
      default:
        return '亮起红灯了，从最低分的那项开始改善';
    }
  }

  /// 口径说明小字
  Widget _methodologyNote() {
    return Text(
      '评分口径：储蓄率 / 应急金按近 3 个完整月收支（不含转账与股票纸面盈亏）；预算纪律看当月月度预算；坚持度看近 30 天记账天数；负债压力看未还借款占资产比例。',
      style: TextStyle(fontSize: 11, height: 1.5, color: AppColors.text3),
    );
  }

  // ── 2) 维度卡片 ─────────────────────────────────────────────
  Widget _dimensionCard(HealthDimension d) {
    final color = _scoreColor(d.score);
    return GlassCard(
      radius: 14,
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  d.label,
                  style: TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w600,
                    color: AppColors.text1,
                  ),
                ),
              ),
              Text(
                '权重 ${d.weight}%',
                style: TextStyle(fontSize: 11, color: AppColors.text3),
              ),
              const SizedBox(width: 8),
              Text(
                '${d.score}',
                style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w700,
                  color: color,
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          ClipRRect(
            borderRadius: BorderRadius.circular(10),
            child: LinearProgressIndicator(
              value: (d.score / 100).clamp(0.0, 1.0),
              minHeight: 8,
              backgroundColor: AppColors.surfaceAlt,
              valueColor: AlwaysStoppedAnimation(color),
            ),
          ),
          const SizedBox(height: 10),
          Text(
            d.headline,
            style: TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w600,
              color: AppColors.text1,
            ),
          ),
          const SizedBox(height: 3),
          Text(
            d.advice,
            style: TextStyle(fontSize: 12, height: 1.4, color: AppColors.text3),
          ),
        ],
      ),
    );
  }
}

/// 弧形仪表盘画笔：270° 圆弧（从 135° 起），圆头进度条
class _GaugePainter extends CustomPainter {
  _GaugePainter({
    required this.progress,
    required this.trackColor,
    required this.progressColor,
  });

  final double progress;
  final Color trackColor;
  final Color progressColor;

  static const double _startAngle = math.pi * 0.75; // 135°
  static const double _sweepAngle = math.pi * 1.5; // 270°

  @override
  void paint(Canvas canvas, Size size) {
    const stroke = 14.0;
    final center = size.center(Offset.zero);
    final radius = math.min(size.width, size.height) / 2 - stroke;
    final rect = Rect.fromCircle(center: center, radius: radius);

    final trackPaint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = stroke
      ..strokeCap = StrokeCap.round
      ..color = trackColor;
    final progressPaint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = stroke
      ..strokeCap = StrokeCap.round
      ..color = progressColor;

    canvas.drawArc(rect, _startAngle, _sweepAngle, false, trackPaint);
    final p = progress.clamp(0.0, 1.0);
    if (p > 0) {
      canvas.drawArc(rect, _startAngle, _sweepAngle * p, false, progressPaint);
    }
  }

  @override
  bool shouldRepaint(_GaugePainter old) =>
      old.progress != progress ||
      old.trackColor != trackColor ||
      old.progressColor != progressColor;
}
