import 'package:flutter/material.dart';

import '../../services/android_haptics_service.dart';
import 'app_glass.dart';

class MobileArticleRangeButton extends StatelessWidget {
  final bool unreadOnly;
  final ValueChanged<bool> onChanged;
  final double size;

  const MobileArticleRangeButton({
    super.key,
    required this.unreadOnly,
    required this.onChanged,
    this.size = 36,
  });

  Future<void> _showPicker(BuildContext context) async {
    final selected = await showModalBottomSheet<bool>(
      context: context,
      useSafeArea: true,
      backgroundColor: Colors.transparent,
      barrierColor: Colors.black.withValues(alpha: 0.30),
      builder: (sheetContext) => AppMobileGlassSheet(
        padding: const EdgeInsets.fromLTRB(12, 10, 12, 12),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 36,
              height: 4,
              margin: const EdgeInsets.only(bottom: 6),
              decoration: BoxDecoration(
                color: Theme.of(
                  sheetContext,
                ).colorScheme.onSurfaceVariant.withValues(alpha: 0.28),
                borderRadius: BorderRadius.circular(999),
              ),
            ),
            const ListTile(
              leading: Icon(Icons.filter_alt_rounded),
              title: Text(
                '文章范围',
                style: TextStyle(fontWeight: FontWeight.w700),
              ),
            ),
            _MobileArticleRangeOption(
              icon: Icons.filter_alt_rounded,
              label: '未读',
              description: '仅显示未读文章',
              selected: unreadOnly,
              onTap: () => Navigator.of(sheetContext).pop(true),
            ),
            _MobileArticleRangeOption(
              icon: Icons.filter_alt_off_rounded,
              label: '全部',
              description: '显示未读和已读文章',
              selected: !unreadOnly,
              onTap: () => Navigator.of(sheetContext).pop(false),
            ),
          ],
        ),
      ),
    );
    if (selected != null && selected != unreadOnly) onChanged(selected);
  }

  @override
  Widget build(BuildContext context) {
    return AppGlassIconButton(
      icon: unreadOnly
          ? Icons.filter_alt_rounded
          : Icons.filter_alt_off_rounded,
      tooltip: unreadOnly ? '范围：未读' : '范围：全部',
      size: size,
      iconSize: 19,
      onPressed: () => _showPicker(context),
    );
  }
}

class _MobileArticleRangeOption extends StatelessWidget {
  final IconData icon;
  final String label;
  final String description;
  final bool selected;
  final VoidCallback onTap;

  const _MobileArticleRangeOption({
    required this.icon,
    required this.label,
    required this.description,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.only(top: 4),
      child: Material(
        color: selected
            ? cs.primary.withValues(alpha: 0.11)
            : Colors.transparent,
        borderRadius: BorderRadius.circular(16),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: () {
            // 筛选选择：确认选择时提供轻微反馈。
            AndroidHapticsService.selectionClick();
            onTap();
          },
          child: ConstrainedBox(
            constraints: const BoxConstraints(minHeight: 58),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 9),
              child: Row(
                children: [
                  Icon(icon, size: 21, color: selected ? cs.primary : null),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Text(
                          label,
                          style: TextStyle(
                            fontSize: 15,
                            fontWeight: selected
                                ? FontWeight.w700
                                : FontWeight.w500,
                            color: selected ? cs.primary : cs.onSurface,
                          ),
                        ),
                        Text(
                          description,
                          style: TextStyle(
                            fontSize: 12,
                            color: cs.onSurfaceVariant,
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 12),
                  AnimatedOpacity(
                    duration: const Duration(milliseconds: 140),
                    opacity: selected ? 1 : 0,
                    child: Icon(
                      Icons.check_rounded,
                      size: 21,
                      color: cs.primary,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
