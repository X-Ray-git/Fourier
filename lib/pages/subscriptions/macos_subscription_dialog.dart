import 'package:flutter/material.dart';

import '../../common/widgets/app_glass.dart';
import '../../common/widgets/app_glass_selection_button.dart';
import '../../common/widgets/feedback_toast.dart';
import '../../http/init.dart';
import '../../models/feed.dart';
import '../../services/subscription_management_service.dart';
import '../../utils/source_taxonomy.dart';

Future<FeedModel?> showMacSubscriptionEditor(
  BuildContext context, {
  FeedModel? feed,
  required List<String> categories,
}) {
  return showDialog<FeedModel>(
    context: context,
    barrierColor: Colors.black.withValues(alpha: 0.28),
    builder: (_) =>
        _MacSubscriptionEditorDialog(feed: feed, categories: categories),
  );
}

Future<String?> showMacCategoryRenameDialog(
  BuildContext context, {
  required String category,
}) {
  return showDialog<String>(
    context: context,
    barrierColor: Colors.black.withValues(alpha: 0.28),
    builder: (_) => _MacCategoryRenameDialog(category: category),
  );
}

Future<bool> showMacUnsubscribeConfirmation(
  BuildContext context, {
  required FeedModel feed,
}) async {
  final result = await showDialog<bool>(
    context: context,
    barrierColor: Colors.black.withValues(alpha: 0.28),
    builder: (_) => _MacConfirmationDialog(
      title: '取消订阅',
      message: '确定取消订阅《${feed.title}》吗？历史文章、本地缓存和订阅源偏好不会被删除。',
      confirmLabel: '取消订阅',
      destructive: true,
    ),
  );
  return result == true;
}

class _MacSubscriptionEditorDialog extends StatefulWidget {
  const _MacSubscriptionEditorDialog({
    required this.feed,
    required this.categories,
  });

  final FeedModel? feed;
  final List<String> categories;

  @override
  State<_MacSubscriptionEditorDialog> createState() =>
      _MacSubscriptionEditorDialogState();
}

class _MacSubscriptionEditorDialogState
    extends State<_MacSubscriptionEditorDialog> {
  late final TextEditingController _urlController;
  late final TextEditingController _titleController;
  late final TextEditingController _categoryController;
  late int _view;
  bool _submitting = false;
  String? _error;

  bool get _isEditing => widget.feed != null;

  @override
  void initState() {
    super.initState();
    final feed = widget.feed;
    _urlController = TextEditingController(text: feed?.url ?? '');
    _titleController = TextEditingController(text: feed?.customTitle ?? '');
    _categoryController = TextEditingController(text: feed?.category ?? '');
    _view = feed?.view == 1 ? 1 : 0;
  }

  @override
  void dispose() {
    _urlController.dispose();
    _titleController.dispose();
    _categoryController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final categoryOptions = widget.categories
        .where((category) => category != widget.feed?.category)
        .map(
          (category) => AppGlassSelectionOption(
            value: category,
            label: category,
            icon: Icons.folder_outlined,
          ),
        )
        .toList(growable: false);

    return Dialog(
      elevation: 0,
      backgroundColor: Colors.transparent,
      insetPadding: const EdgeInsets.symmetric(horizontal: 32, vertical: 24),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 500),
        child: AppGlassSurface(
          borderRadius: AppGlassRadii.prominentPanel,
          padding: const EdgeInsets.all(20),
          tone: AppGlassTone.panel,
          nativeBackdrop: true,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                _isEditing ? '编辑订阅' : '添加 RSS 订阅',
                style: TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.w800,
                  color: cs.onSurface,
                ),
              ),
              const SizedBox(height: 5),
              Text(
                _isEditing ? '修改订阅在 Folo 中的标题、分类和内容类型。' : '输入 RSS 地址并设置其显示方式。',
                style: TextStyle(
                  fontSize: 12,
                  height: 1.4,
                  color: cs.onSurfaceVariant,
                ),
              ),
              const SizedBox(height: 18),
              AppGlassTextField(
                controller: _urlController,
                label: 'RSS URL',
                hint: 'https://example.com/feed.xml',
                readOnly: _isEditing,
                helper: _isEditing ? 'RSS 地址不可编辑；如需更换，请取消后重新订阅。' : null,
                textInputAction: TextInputAction.next,
              ),
              const SizedBox(height: 12),
              AppGlassTextField(
                controller: _titleController,
                label: '自定义标题',
                hint: _isEditing ? widget.feed?.sourceTitle : '留空则使用订阅源标题',
                helper: _isEditing
                    ? '留空时显示源标题：${widget.feed?.sourceTitle ?? ''}'
                    : null,
                textInputAction: TextInputAction.next,
              ),
              const SizedBox(height: 12),
              AppGlassTextField(
                controller: _categoryController,
                label: '分类',
                hint: '留空则归入未分类',
                textInputAction: TextInputAction.done,
                onFieldSubmitted: (_) => _submit(),
                suffixIcon: categoryOptions.isEmpty
                    ? null
                    : categoryOptions.length == 1
                    ? AppGlassIconButton(
                        icon: Icons.expand_more_rounded,
                        tooltip: '选择已有分类',
                        size: 28,
                        iconSize: 16,
                        useOwnLayer: false,
                        onPressed: () =>
                            _selectCategory(categoryOptions.first.value),
                      )
                    : AppGlassMorphActionButton<String>(
                        actions: categoryOptions,
                        title: '已有分类',
                        titleIcon: Icons.folder_copy_outlined,
                        triggerIcon: Icons.expand_more_rounded,
                        tooltip: '选择已有分类',
                        panelWidth: 220,
                        onSelected: _selectCategory,
                      ),
              ),
              const SizedBox(height: 14),
              AppGlassSurface(
                borderRadius: 12,
                padding: const EdgeInsets.fromLTRB(12, 9, 9, 9),
                tone: AppGlassTone.control,
                staticMaterial: true,
                child: Row(
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            '内容类型',
                            style: TextStyle(
                              fontSize: 11,
                              fontWeight: FontWeight.w600,
                              color: cs.onSurfaceVariant,
                            ),
                          ),
                          const SizedBox(height: 3),
                          Text(
                            SourceTaxonomy.viewLabelFromInt(_view),
                            style: TextStyle(
                              fontSize: 14,
                              fontWeight: FontWeight.w600,
                              color: cs.onSurface,
                            ),
                          ),
                        ],
                      ),
                    ),
                    AppGlassMorphSelectionButton<int>(
                      value: _view,
                      options: const [
                        AppGlassSelectionOption(
                          value: 0,
                          label: 'Articles',
                          icon: Icons.article_outlined,
                        ),
                        AppGlassSelectionOption(
                          value: 1,
                          label: 'Social Media',
                          icon: Icons.people_outline_rounded,
                        ),
                      ],
                      title: '内容类型',
                      titleIcon: Icons.view_list_outlined,
                      tooltip: '内容类型',
                      useOwnLayer: false,
                      onChanged: (view) => setState(() => _view = view),
                    ),
                  ],
                ),
              ),
              if (_error != null) ...[
                const SizedBox(height: 10),
                Text(
                  _error!,
                  style: TextStyle(fontSize: 12, height: 1.35, color: cs.error),
                ),
              ],
              const SizedBox(height: 18),
              Row(
                children: [
                  const Spacer(),
                  AppGlassButton(
                    label: '取消',
                    onPressed: _submitting
                        ? null
                        : () => Navigator.of(context).pop(),
                  ),
                  const SizedBox(width: 10),
                  AppGlassButton(
                    label: _submitting
                        ? (_isEditing ? '保存中' : '添加中')
                        : (_isEditing ? '保存' : '添加'),
                    icon: _submitting ? null : Icons.check_rounded,
                    role: AppGlassButtonRole.primary,
                    onPressed: _submitting ? null : _submit,
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _submit() async {
    if (_submitting) return;
    final url = _urlController.text.trim();
    final uri = Uri.tryParse(url);
    if (uri == null ||
        !const {'http', 'https'}.contains(uri.scheme.toLowerCase()) ||
        uri.host.isEmpty) {
      setState(() => _error = '请输入有效的 http 或 https RSS 地址。');
      return;
    }

    final draft = SubscriptionDraft(
      url: url,
      view: _view,
      title: _titleController.text,
      category: _categoryController.text,
    );
    setState(() {
      _submitting = true;
      _error = null;
    });

    if (!_isEditing) {
      final existing = SubscriptionManagementService.findByUrl(url);
      if (existing != null) {
        if (!mounted) return;
        AppFeedback.info('已经订阅', existing.title);
        Navigator.of(context).pop(existing);
        return;
      }
    }

    final result = _isEditing
        ? await SubscriptionManagementService.update(widget.feed!, draft)
        : await SubscriptionManagementService.create(draft);
    if (!mounted) return;
    if (result is Success<FeedModel>) {
      AppFeedback.success(
        _isEditing ? '订阅已更新' : '订阅已添加',
        result.response.title,
      );
      Navigator.of(context).pop(result.response);
      return;
    }
    setState(() {
      _submitting = false;
      _error = result is LoadError<FeedModel>
          ? result.errMsg ?? '操作失败'
          : '操作失败';
    });
  }

  void _selectCategory(String category) {
    setState(() {
      _categoryController.text = category;
      _categoryController.selection = TextSelection.collapsed(
        offset: category.length,
      );
    });
  }
}

class _MacCategoryRenameDialog extends StatefulWidget {
  const _MacCategoryRenameDialog({required this.category});

  final String category;

  @override
  State<_MacCategoryRenameDialog> createState() =>
      _MacCategoryRenameDialogState();
}

class _MacCategoryRenameDialogState extends State<_MacCategoryRenameDialog> {
  late final TextEditingController _controller;

  @override
  void initState() {
    super.initState();
    _controller = TextEditingController(text: widget.category)
      ..selection = TextSelection(
        baseOffset: 0,
        extentOffset: widget.category.length,
      );
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Dialog(
      elevation: 0,
      backgroundColor: Colors.transparent,
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 400),
        child: AppGlassSurface(
          borderRadius: AppGlassRadii.panel,
          padding: const EdgeInsets.all(18),
          tone: AppGlassTone.panel,
          nativeBackdrop: true,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const Text(
                '重命名分类',
                style: TextStyle(fontSize: 18, fontWeight: FontWeight.w800),
              ),
              const SizedBox(height: 14),
              AppGlassTextField(
                controller: _controller,
                label: '分类名称',
                textInputAction: TextInputAction.done,
                onFieldSubmitted: (_) => _submit(),
              ),
              const SizedBox(height: 18),
              Row(
                children: [
                  const Spacer(),
                  AppGlassButton(
                    label: '取消',
                    onPressed: Navigator.of(context).pop,
                  ),
                  const SizedBox(width: 10),
                  AppGlassButton(
                    label: '保存',
                    role: AppGlassButtonRole.primary,
                    onPressed: _submit,
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  void _submit() {
    final value = _controller.text.trim();
    if (value.isEmpty || value == widget.category) return;
    Navigator.of(context).pop(value);
  }
}

class _MacConfirmationDialog extends StatelessWidget {
  const _MacConfirmationDialog({
    required this.title,
    required this.message,
    required this.confirmLabel,
    this.destructive = false,
  });

  final String title;
  final String message;
  final String confirmLabel;
  final bool destructive;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Dialog(
      elevation: 0,
      backgroundColor: Colors.transparent,
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 420),
        child: AppGlassSurface(
          borderRadius: AppGlassRadii.panel,
          padding: const EdgeInsets.all(18),
          tone: AppGlassTone.panel,
          nativeBackdrop: true,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                title,
                style: TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.w800,
                  color: cs.onSurface,
                ),
              ),
              const SizedBox(height: 10),
              Text(
                message,
                style: TextStyle(
                  fontSize: 13,
                  height: 1.5,
                  color: cs.onSurfaceVariant,
                ),
              ),
              const SizedBox(height: 18),
              Row(
                children: [
                  const Spacer(),
                  AppGlassButton(
                    label: '取消',
                    onPressed: () => Navigator.of(context).pop(false),
                  ),
                  const SizedBox(width: 10),
                  AppGlassButton(
                    label: confirmLabel,
                    role: destructive
                        ? AppGlassButtonRole.destructive
                        : AppGlassButtonRole.primary,
                    onPressed: () => Navigator.of(context).pop(true),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}
