import 'dart:typed_data';

/// Web 平台不支持写本地临时文件（备份分享按钮在 Web 端不显示）
Future<String> writeTempFile(String name, Uint8List bytes) {
  throw UnsupportedError('当前平台不支持写临时文件');
}
