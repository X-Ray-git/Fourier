import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../services/feed_silent_settings_service.dart';
import 'app_glass.dart';

class SilentGroupAssignment {
  const SilentGroupAssignment.group(this.groupId) : cancelSilent = false;
  const SilentGroupAssignment.cancel() : groupId = null, cancelSilent = true;

  final String? groupId;
  final bool cancelSilent;

  Future<void> applyTo(String feedId) => cancelSilent
      ? FeedSilentSettingsService.setSilent(feedId, false)
      : FeedSilentSettingsService.moveToGroup(feedId, groupId);
}

Future<SilentGroupAssignment?> showSilentGroupAssignmentDialog(
  BuildContext context, {
  required String feedId,
}) {
  return showDialog<SilentGroupAssignment>(
    context: context,
    builder: (_) => _SilentGroupAssignmentDialog(feedId: feedId),
  );
}

Future<String?> showSilentGroupNameDialog(
  BuildContext context, {
  String? initialValue,
}) {
  return showDialog<String>(
    context: context,
    builder: (_) => _SilentGroupNameDialog(initialValue: initialValue),
  );
}

Future<bool> showDeleteSilentGroupConfirmation(
  BuildContext context, {
  required SilentFeedGroup group,
  required int feedCount,
}) async {
  return await showDialog<bool>(
        context: context,
        builder: (dialogContext) => _SilentGroupDialog(
          title: const Text('删除静默分组？'),
          content: Text(
            feedCount == 0
                ? '“${group.name}”是空分组。'
                : '其中的 $feedCount 个订阅源将移至“未分组”，仍保持静默。',
          ),
          actions: [
            AppGlassButton(
              onPressed: () => Navigator.pop(dialogContext, false),
              label: '取消',
            ),
            AppGlassButton(
              onPressed: () => Navigator.pop(dialogContext, true),
              role: AppGlassButtonRole.destructive,
              label: '删除',
            ),
          ],
        ),
      ) ??
      false;
}

class _SilentGroupAssignmentDialog extends StatefulWidget {
  const _SilentGroupAssignmentDialog({required this.feedId});

  final String feedId;

  @override
  State<_SilentGroupAssignmentDialog> createState() =>
      _SilentGroupAssignmentDialogState();
}

class _SilentGroupAssignmentDialogState
    extends State<_SilentGroupAssignmentDialog> {
  Future<void> _create() async {
    final name = await showSilentGroupNameDialog(context);
    if (name == null || !mounted) return;
    try {
      final group = await FeedSilentSettingsService.createGroup(name);
      if (mounted) {
        Navigator.pop(context, SilentGroupAssignment.group(group.id));
      }
    } on FormatException catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(error.message)));
    }
  }

  @override
  Widget build(BuildContext context) {
    final current = FeedSilentSettingsService.groupIdFor(widget.feedId);
    final isSilent = FeedSilentSettingsService.isSilent(widget.feedId);
    final groups = FeedSilentSettingsService.groups;
    return _SilentGroupDialog(
      title: Text(isSilent ? '移动至静默分组' : '设为静默'),
      content: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 360),
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              ListTile(
                title: const Text('未分组'),
                trailing: isSilent && current == null
                    ? const Icon(Icons.check)
                    : null,
                onTap: () => Navigator.pop(
                  context,
                  const SilentGroupAssignment.group(null),
                ),
              ),
              for (final group in groups)
                ListTile(
                  title: Text(group.name),
                  trailing: current == group.id
                      ? const Icon(Icons.check)
                      : null,
                  onTap: () => Navigator.pop(
                    context,
                    SilentGroupAssignment.group(group.id),
                  ),
                ),
            ],
          ),
        ),
      ),
      actions: [
        if (isSilent)
          AppGlassButton(
            onPressed: () =>
                Navigator.pop(context, const SilentGroupAssignment.cancel()),
            label: '取消静默',
          ),
        AppGlassButton(onPressed: _create, label: '新建分组'),
        AppGlassButton(onPressed: () => Navigator.pop(context), label: '关闭'),
      ],
    );
  }
}

class _SilentGroupNameDialog extends StatefulWidget {
  const _SilentGroupNameDialog({this.initialValue});

  final String? initialValue;

  @override
  State<_SilentGroupNameDialog> createState() => _SilentGroupNameDialogState();
}

class _SilentGroupNameDialogState extends State<_SilentGroupNameDialog> {
  late final TextEditingController _controller;
  final FocusNode _focusNode = FocusNode();
  String? _error;

  @override
  void initState() {
    super.initState();
    _controller = TextEditingController(text: widget.initialValue);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _focusNode.requestFocus();
    });
  }

  @override
  void dispose() {
    _controller.dispose();
    _focusNode.dispose();
    super.dispose();
  }

  void _submit() {
    final value = _controller.text.trim();
    if (value.isEmpty ||
        value.length > 40 ||
        FeedSilentSettingsService.reservedGroupNames.contains(value)) {
      setState(() => _error = '请输入 1–40 个字符，不能使用“全部静默”或“未分组”');
      return;
    }
    if (value != widget.initialValue &&
        FeedSilentSettingsService.groups.any((group) => group.name == value)) {
      setState(() => _error = '分组名称不能重复');
      return;
    }
    Navigator.pop(context, value);
  }

  @override
  Widget build(BuildContext context) {
    return _SilentGroupDialog(
      title: Text(widget.initialValue == null ? '新建静默分组' : '重命名静默分组'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          AppGlassTextField(
            controller: _controller,
            focusNode: _focusNode,
            inputFormatters: [LengthLimitingTextInputFormatter(40)],
            textInputAction: TextInputAction.done,
            onFieldSubmitted: (_) => _submit(),
            label: '分组名称',
          ),
          if (_error != null) ...[
            const SizedBox(height: 8),
            Text(
              _error!,
              style: TextStyle(color: Theme.of(context).colorScheme.error),
            ),
          ],
        ],
      ),
      actions: [
        AppGlassButton(onPressed: () => Navigator.pop(context), label: '取消'),
        AppGlassButton(
          onPressed: _submit,
          label: '确定',
          role: AppGlassButtonRole.primary,
        ),
      ],
    );
  }
}

class _SilentGroupDialog extends StatelessWidget {
  const _SilentGroupDialog({
    required this.title,
    required this.content,
    required this.actions,
  });

  final Widget title;
  final Widget content;
  final List<Widget> actions;

  @override
  Widget build(BuildContext context) {
    if (!Platform.isMacOS) {
      return AlertDialog(title: title, content: content, actions: actions);
    }
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
              DefaultTextStyle.merge(
                style: const TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.w800,
                ),
                child: title,
              ),
              const SizedBox(height: 14),
              Flexible(child: SingleChildScrollView(child: content)),
              const SizedBox(height: 18),
              Wrap(
                alignment: WrapAlignment.end,
                spacing: 10,
                runSpacing: 8,
                children: actions,
              ),
            ],
          ),
        ),
      ),
    );
  }
}
