import 'dart:io';
import 'dart:typed_data';

/// 把字节写入系统临时目录，返回文件路径（分享备份文件用）
Future<String> writeTempFile(String name, Uint8List bytes) async {
  final dir = await Directory.systemTemp.createTemp('siku_backup');
  final safe = name.replaceAll(RegExp(r'[\\/:*?"<>|]+'), '_');
  final f = File('${dir.path}/$safe');
  await f.writeAsBytes(bytes, flush: true);
  return f.path;
}
