import 'dart:typed_data';

import 'package:flutter/material.dart';

import '../theme.dart';

/// 存图前的预览对话框：先看一眼，再决定要不要存相册 / 分享
class ExportPreviewDialog extends StatelessWidget {
  const ExportPreviewDialog({super.key, required this.png, this.preferShare = false});

  final Uint8List png;

  /// true = 用户点的是"分享"，把分享放在主按钮位置
  final bool preferShare;

  @override
  Widget build(BuildContext context) {
    return Dialog(
      insetPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 40),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(14, 14, 14, 10),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const Text(
              '图片预览',
              style: TextStyle(fontSize: 15, fontWeight: FontWeight.w700),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 4),
            const Text(
              '确认没问题再保存',
              style: TextStyle(fontSize: 11, color: AppColors.textSecondary),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 10),
            Flexible(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxHeight: 420),
                child: Container(
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: AppColors.divider),
                  ),
                  clipBehavior: Clip.antiAlias,
                  child: Image.memory(png, fit: BoxFit.contain),
                ),
              ),
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child: _buildSecondary(context, preferShare ? '保存到相册' : '分享', preferShare ? 'save' : 'share'),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: FilledButton(
                    onPressed: () => Navigator.pop(context, preferShare ? 'share' : 'save'),
                    style: FilledButton.styleFrom(
                      backgroundColor: AppColors.primary,
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                    ),
                    child: Text(preferShare ? '分享' : '保存到相册'),
                  ),
                ),
              ],
            ),
            TextButton(
              onPressed: () => Navigator.pop(context, 'cancel'),
              child: const Text('取消', style: TextStyle(fontSize: 13)),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildSecondary(BuildContext context, String label, String value) {
    return OutlinedButton(
      onPressed: () => Navigator.pop(context, value),
      style: OutlinedButton.styleFrom(
        side: const BorderSide(color: AppColors.divider),
        foregroundColor: AppColors.textPrimary,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
      ),
      child: Text(label),
    );
  }
}
