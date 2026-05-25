import 'dart:io';
import 'package:flutter/material.dart';
import 'package:google_mlkit_text_recognition/google_mlkit_text_recognition.dart';
import 'package:image_picker/image_picker.dart';
import 'package:permission_handler/permission_handler.dart';

import '../core/theme.dart';
import '../models/category.dart';
import '../services/bill_parser.dart';

/// OCR 图片识别记账。
/// 用户先选拍照 / 相册，识别完成后预览图片 + 识别文本 + 解析草稿，
/// 点"使用"返回 [BillDraft]。
class OcrInputSheet extends StatefulWidget {
  const OcrInputSheet({super.key, required this.categories});

  final List<Category> categories;

  @override
  State<OcrInputSheet> createState() => _OcrInputSheetState();
}

class _OcrInputSheetState extends State<OcrInputSheet> {
  final ImagePicker _picker = ImagePicker();

  XFile? _image;
  bool _busy = false;
  String _rawText = '';
  BillDraft? _draft;
  String? _err;

  /// ML Kit 中文识别器（同时识别 简体中文 + 英文 + 数字）
  late final TextRecognizer _recognizer =
      TextRecognizer(script: TextRecognitionScript.chinese);

  @override
  void dispose() {
    _recognizer.close();
    super.dispose();
  }

  Future<void> _pick(ImageSource src) async {
    // 拍照需要相机权限；相册不需要（image_picker 内部用系统选择器）
    if (src == ImageSource.camera) {
      var perm = await Permission.camera.status;
      if (!perm.isGranted) perm = await Permission.camera.request();
      if (!perm.isGranted) {
        setState(() => _err = '需要相机权限才能拍照识别');
        return;
      }
    }

    XFile? file;
    try {
      file = await _picker.pickImage(
        source: src,
        imageQuality: 88,
        maxWidth: 2400,
      );
    } catch (e) {
      setState(() => _err = '选择图片失败：$e');
      return;
    }
    if (file == null) return;

    setState(() {
      _image = file;
      _busy = true;
      _err = null;
      _rawText = '';
      _draft = null;
    });

    try {
      final input = InputImage.fromFilePath(file.path);
      final result = await _recognizer.processImage(input);
      final text = result.text;
      final draft = BillParser.parse(text, widget.categories);
      if (!mounted) return;
      setState(() {
        _rawText = text;
        _draft = draft;
        _busy = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _busy = false;
        _err = '识别失败：$e';
      });
    }
  }

  void _confirm() {
    if (_draft != null) Navigator.pop(context, _draft);
  }

  @override
  Widget build(BuildContext context) {
    final mq = MediaQuery.of(context);
    final maxH = mq.size.height * 0.85;
    return ConstrainedBox(
      constraints: BoxConstraints(maxHeight: maxH),
      child: Padding(
        padding: EdgeInsets.only(bottom: mq.viewInsets.bottom),
        child: SafeArea(
          top: false,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              _header(),
              if (_image == null)
                _pickerView()
              else
                Expanded(child: _resultView()),
              if (_image != null) _actions(),
              const SizedBox(height: 10),
            ],
          ),
        ),
      ),
    );
  }

  Widget _header() => Padding(
        padding: const EdgeInsets.fromLTRB(16, 14, 8, 6),
        child: Row(children: [
          Icon(Icons.document_scanner_outlined,
              size: 20, color: AppColors.primary),
          const SizedBox(width: 8),
          Text('拍照记账',
              style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w600,
                  color: AppColors.text1)),
          const Spacer(),
          if (_image != null)
            TextButton.icon(
              onPressed: _busy
                  ? null
                  : () => setState(() {
                        _image = null;
                        _rawText = '';
                        _draft = null;
                        _err = null;
                      }),
              icon: Icon(Icons.refresh_rounded,
                  size: 18, color: AppColors.text2),
              label: Text('换一张',
                  style:
                      TextStyle(fontSize: 13, color: AppColors.text2)),
            ),
          IconButton(
            onPressed: () => Navigator.pop(context),
            icon: Icon(Icons.close_rounded, color: AppColors.text2),
          ),
        ]),
      );

  Widget _pickerView() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 14, 20, 24),
      child: Column(
        children: [
          Text(
            '拍下小票/账单/转账截图，自动识别金额',
            textAlign: TextAlign.center,
            style: TextStyle(fontSize: 13, color: AppColors.text2),
          ),
          const SizedBox(height: 22),
          Row(children: [
            Expanded(child: _bigBtn(
              icon: Icons.photo_camera_rounded,
              label: '拍照',
              onTap: () => _pick(ImageSource.camera),
            )),
            const SizedBox(width: 12),
            Expanded(child: _bigBtn(
              icon: Icons.photo_library_rounded,
              label: '从相册',
              onTap: () => _pick(ImageSource.gallery),
            )),
          ]),
          if (_err != null) ...[
            const SizedBox(height: 12),
            Text(_err!,
                style: TextStyle(
                    fontSize: 12, color: AppColors.expense)),
          ],
        ],
      ),
    );
  }

  Widget _bigBtn({
    required IconData icon,
    required String label,
    required VoidCallback onTap,
  }) {
    return Material(
      color: AppColors.surface,
      borderRadius: BorderRadius.circular(16),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(16),
        child: Container(
          height: 110,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: AppColors.border),
          ),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(icon, size: 30, color: AppColors.primary),
              const SizedBox(height: 8),
              Text(label,
                  style: TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w600,
                      color: AppColors.text1)),
            ],
          ),
        ),
      ),
    );
  }

  Widget _resultView() {
    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(16, 6, 16, 10),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // 图片预览
          ClipRRect(
            borderRadius: BorderRadius.circular(12),
            child: Image.file(
              File(_image!.path),
              height: 160,
              width: double.infinity,
              fit: BoxFit.cover,
            ),
          ),
          const SizedBox(height: 12),
          if (_busy)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 24),
              child: Center(
                child: Column(children: [
                  CircularProgressIndicator(color: AppColors.primary),
                  const SizedBox(height: 10),
                  Text('正在识别…',
                      style: TextStyle(
                          fontSize: 13, color: AppColors.text2)),
                ]),
              ),
            )
          else if (_err != null)
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: AppColors.expenseLight,
                borderRadius: BorderRadius.circular(10),
              ),
              child: Text(_err!,
                  style: TextStyle(
                      fontSize: 13, color: AppColors.expense)),
            )
          else if (_draft != null) ...[
            // ── 解析结果摘要 ─────────────────────────────────
            _summary(_draft!),
            const SizedBox(height: 12),
            // 原始 OCR 文本，折叠展示
            Text('识别到的文本',
                style: TextStyle(
                    fontSize: 12,
                    color: AppColors.text2,
                    fontWeight: FontWeight.w500)),
            const SizedBox(height: 6),
            Container(
              constraints: const BoxConstraints(maxHeight: 160),
              padding:
                  const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
              decoration: BoxDecoration(
                color: AppColors.surfaceAlt,
                borderRadius: BorderRadius.circular(10),
              ),
              child: SingleChildScrollView(
                child: SelectableText(
                  _rawText.isEmpty ? '（没有识别到任何文字）' : _rawText,
                  style: TextStyle(
                      fontSize: 12,
                      color: AppColors.text2,
                      height: 1.5),
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _summary(BillDraft d) {
    final amount = d.amount;
    final cat = d.category;
    final isExp = d.type == 'expense';
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(children: [
            Container(
              padding: const EdgeInsets.symmetric(
                  horizontal: 8, vertical: 3),
              decoration: BoxDecoration(
                color: isExp
                    ? AppColors.expenseLight
                    : AppColors.incomeLight,
                borderRadius: BorderRadius.circular(6),
              ),
              child: Text(isExp ? '支出' : '收入',
                  style: TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w600,
                      color:
                          isExp ? AppColors.expense : AppColors.income)),
            ),
            const Spacer(),
            Text(
              amount != null
                  ? '¥${amount.toStringAsFixed(2)}'
                  : '— 未识别到金额',
              style: TextStyle(
                fontSize: amount != null ? 22 : 13,
                fontWeight: FontWeight.w700,
                color: amount != null
                    ? AppColors.text1
                    : AppColors.text3,
              ),
            ),
          ]),
          const SizedBox(height: 8),
          Row(children: [
            Text(cat?.displayIcon ?? '📂',
                style: const TextStyle(fontSize: 16)),
            const SizedBox(width: 6),
            Expanded(
              child: Text(
                cat?.fullName ?? '未自动识别分类（保存时手动选）',
                style: TextStyle(
                    fontSize: 13,
                    color: cat != null
                        ? AppColors.text1
                        : AppColors.text2),
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ]),
        ],
      ),
    );
  }

  Widget _actions() {
    final canUse = _draft != null && !_busy;
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 4, 16, 6),
      child: Row(children: [
        Expanded(
          child: OutlinedButton(
            onPressed: () => Navigator.pop(context),
            style: OutlinedButton.styleFrom(
              foregroundColor: AppColors.text1,
              side: BorderSide(color: AppColors.border),
              padding: const EdgeInsets.symmetric(vertical: 14),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
              ),
            ),
            child: const Text('取消'),
          ),
        ),
        const SizedBox(width: 10),
        Expanded(
          flex: 2,
          child: ElevatedButton(
            onPressed: canUse ? _confirm : null,
            style: ElevatedButton.styleFrom(
              backgroundColor: AppColors.primary,
              foregroundColor: AppColors.onPrimary,
              minimumSize: const Size(double.infinity, 48),
              padding: const EdgeInsets.symmetric(vertical: 14),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
              ),
              disabledBackgroundColor: AppColors.surfaceAlt,
              disabledForegroundColor: AppColors.text3,
            ),
            child: const Text('使用识别结果',
                style:
                    TextStyle(fontSize: 15, fontWeight: FontWeight.w600)),
          ),
        ),
      ]),
    );
  }
}
