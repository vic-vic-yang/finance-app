#!/usr/bin/env dart
// ignore_for_file: avoid_print // CLI 工具：stdout 即输出通道（含基线重定向）
/// ======================================================================
/// design_lint · 司库设计系统「防回潮」检查
/// ======================================================================
///
/// 用法（在 finance_app 目录下）：
///
///   # 日常检查：只报基线之外的新增违规；有新增 exit(1)，干净 exit(0)
///   dart run tool/design_lint.dart
///
///   # 首次 / 需要重置存量时：生成基线文件（全量违规清单）
///   dart run tool/design_lint.dart --baseline > tool/design_baseline.txt
///
/// 规则（扫描 [_scanRoots] 下全部 .dart 文件）：
///   1. 禁止硬编码色值 `Color(0x…)` —— 颜色一律走 AppColors / ChartPalette。
///   2. 禁止 Material 命名色 `Colors.white|black|grey|red|blue|green|…`
///      （`Colors.transparent` 放行）。
///
/// 豁免：
///   - 行豁免：行尾注释 `// design:ok` 或 `// design:ok 原因`，该行放行。
///   - 文件豁免：下方 [_exemptFiles] 常量（约定尽量保持为空；
///     chart_kit.dart 的色板锚点色已用行内 design:ok 处理）。
///
/// 基线比对：按「文件 + 行内容指纹」匹配（不含行号），行号漂移不影响；
/// 基线文件缺失时视为空基线（全部违规都算新增）。
library;

import 'dart:io';

/// 扫描根目录（相对包根）。
const _scanRoots = ['lib/screens', 'lib/widgets'];

/// 文件级豁免清单（相对包根，正斜杠）。尽量保持为空。
const _exemptFiles = <String>{
  // 设计系统色值定义本身；当前不在扫描根内，列出以防将来扩大扫描范围。
  'lib/core/theme.dart',
  // 主题色板（palette 种子色）定义，同属 token 定义处。
  'lib/core/theme_service.dart',
};

/// 基线文件（相对包根）。
const _baselinePath = 'tool/design_baseline.txt';

final _rule1 = RegExp(r'Color\(0x');
final _rule2 = RegExp(
    r'Colors\.(white|black|grey|red|blue|green|orange|purple|amber|teal|indigo|deepOrange|deepPurple|blueGrey|lightGreen|pink|cyan|lime|yellow|brown)');

class _Violation {
  _Violation(this.file, this.line, this.rule, this.content);

  /// 相对包根路径（正斜杠）。
  final String file;
  final int line;
  final int rule;

  /// 行内容（trim 后），即指纹本体。
  final String content;

  /// 基线指纹：文件 + 行内容（不含行号，容忍行号漂移）。
  String get fingerprint => '$file\t$content';
}

void main(List<String> args) {
  final root = _packageRoot();
  final baselineMode = args.contains('--baseline');
  final violations = _scan(root);

  if (baselineMode) {
    // 输出即基线文件内容（重定向到 tool/design_baseline.txt）。
    print('# design_lint baseline v1');
    print('# 重新生成：dart run tool/design_lint.dart --baseline > tool/design_baseline.txt');
    print('# 存量违规共 ${violations.length} 处');
    for (final v in violations) {
      print(v.fingerprint);
    }
    exit(0);
  }

  final remaining = _loadBaseline(root);
  final fresh = <_Violation>[];
  for (final v in violations) {
    final key = v.fingerprint;
    if ((remaining[key] ?? 0) > 0) {
      remaining[key] = remaining[key]! - 1; // 消耗一条基线配额（同行内容多次出现时逐条抵消）
    } else {
      fresh.add(v);
    }
  }

  if (fresh.isEmpty) {
    print('✅ 无新增设计违规（存量基线 ${violations.length} 处保持不变）');
    exit(0);
  }

  print('发现 ${fresh.length} 处新增设计违规（另 ${violations.length - fresh.length} 处存量已记入基线）：');
  for (final v in fresh) {
    print('  ${v.file}:${v.line}  [规则${v.rule}]  ${v.content}');
  }
  print('');
  print('规则1 = 硬编码 Color(0x…)；规则2 = Material 命名色 Colors.xxx。');
  print('修复：改用 AppColors / ChartPalette；确需豁免在行尾加 `// design:ok 原因`。');
  exit(1);
}

/// 包根目录：优先取脚本所在位置的上一级（tool/ 的父目录），兜底 cwd。
Directory _packageRoot() {
  try {
    final script = File.fromUri(Platform.script);
    return script.parent.parent.absolute;
  } catch (_) {
    return Directory.current.absolute;
  }
}

List<_Violation> _scan(Directory root) {
  final result = <_Violation>[];
  for (final rel in _scanRoots) {
    final dir = Directory('${root.path}/$rel');
    if (!dir.existsSync()) continue;
    for (final entity in dir.listSync(recursive: true)) {
      if (entity is! File || !entity.path.endsWith('.dart')) continue;
      final relPath = _relPath(root, entity);
      if (_exemptFiles.contains(relPath)) continue;
      final lines = entity.readAsLinesSync();
      for (var i = 0; i < lines.length; i++) {
        final line = lines[i];
        if (line.contains('// design:ok')) continue;
        final rule =
            _rule1.hasMatch(line) ? 1 : (_rule2.hasMatch(line) ? 2 : 0);
        if (rule == 0) continue;
        result.add(_Violation(relPath, i + 1, rule, line.trim()));
      }
    }
  }
  result.sort((a, b) {
    final c = a.file.compareTo(b.file);
    return c != 0 ? c : a.line.compareTo(b.line);
  });
  return result;
}

String _relPath(Directory root, File f) {
  final r = root.path.replaceAll('\\', '/');
  var p = f.path.replaceAll('\\', '/');
  if (p.startsWith('$r/')) p = p.substring(r.length + 1);
  return p;
}

/// 读取基线文件为「指纹 → 出现次数」；文件缺失视为空基线。
Map<String, int> _loadBaseline(Directory root) {
  final counts = <String, int>{};
  final f = File('${root.path}/$_baselinePath');
  if (!f.existsSync()) return counts;
  for (var line in f.readAsLinesSync()) {
    // dart run 会把构建信息（"Running build hooks..."）混进 stdout/基线文件，剔除
    line = line.replaceAll('Running build hooks...', '').trimRight();
    if (line.isEmpty || line.startsWith('#')) continue;
    if (!line.contains('\t')) continue; // 非指纹行（残余日志混入等）
    counts[line] = (counts[line] ?? 0) + 1;
  }
  return counts;
}
