import 'package:flutter/material.dart';

import '../../common/constants/constants.dart';
import '../../common/widgets/app_glass.dart';
import '../../common/widgets/mobile_blur_app_bar.dart';
import '../../services/app_license_service.dart';
import '../../services/app_version_service.dart';
import 'widgets/mobile_settings_chrome.dart';

class AppLicensesDialog extends StatelessWidget {
  const AppLicensesDialog({super.key});

  @override
  Widget build(BuildContext context) {
    final viewport = MediaQuery.sizeOf(context);
    final width = (viewport.width - 64).clamp(360.0, 900.0);
    final height = (viewport.height - 48).clamp(420.0, 700.0);

    return Dialog(
      elevation: 0,
      backgroundColor: Colors.transparent,
      insetPadding: const EdgeInsets.symmetric(horizontal: 32, vertical: 24),
      child: SizedBox(
        width: width,
        height: height,
        child: AppGlassSurface(
          borderRadius: AppGlassRadii.prominentPanel,
          tone: AppGlassTone.panel,
          nativeBackdrop: true,
          child: _LicenseSurface(
            headerTrailing: AppGlassIconButton(
              icon: Icons.close_rounded,
              tooltip: '关闭',
              nativeBackdrop: true,
              onPressed: () => Navigator.of(context).pop(),
            ),
          ),
        ),
      ),
    );
  }
}

class AppLicensesPage extends StatelessWidget {
  const AppLicensesPage({super.key});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Scaffold(
      backgroundColor: cs.surface,
      appBar: const MobileBlurAppBar(
        title: Text(
          '开源许可证',
          style: TextStyle(fontSize: 17, fontWeight: FontWeight.bold),
        ),
      ),
      body: SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(12, 12, 12, 16),
          child: MobileSettingsPanel(
            child: _LicenseSurface(
              heading: AppConstants.appName,
              metadata: 'v${AppVersionService.version} · AGPL-3.0-only',
            ),
          ),
        ),
      ),
    );
  }
}

class _LicenseSurface extends StatefulWidget {
  const _LicenseSurface({
    this.heading = '开源许可证',
    this.metadata,
    this.headerTrailing,
  });

  final String heading;
  final String? metadata;
  final Widget? headerTrailing;

  @override
  State<_LicenseSurface> createState() => _LicenseSurfaceState();
}

class _LicenseSurfaceState extends State<_LicenseSurface> {
  late final Future<List<AppLicenseRecord>> _catalog;
  final _searchController = TextEditingController();
  final _detailScrollController = ScrollController();
  String _query = '';
  String? _selectedPackage;

  @override
  void initState() {
    super.initState();
    _catalog = AppLicenseService.loadCatalog();
  }

  @override
  void dispose() {
    _searchController.dispose();
    _detailScrollController.dispose();
    super.dispose();
  }

  void _select(AppLicenseRecord record) {
    setState(() => _selectedPackage = record.packageName);
    if (_detailScrollController.hasClients) {
      _detailScrollController.jumpTo(0);
    }
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.balance_rounded, size: 21, color: cs.primary),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      widget.heading,
                      style: TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.w800,
                        color: cs.onSurface,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      widget.metadata ??
                          '${AppConstants.appName} v${AppVersionService.version} · AGPL-3.0-only',
                      style: TextStyle(
                        fontSize: 12,
                        color: cs.onSurfaceVariant,
                      ),
                    ),
                  ],
                ),
              ),
              // ignore: use_null_aware_elements
              if (widget.headerTrailing != null) widget.headerTrailing!,
            ],
          ),
          const SizedBox(height: 14),
          TextField(
            controller: _searchController,
            onChanged: (value) => setState(() => _query = value.trim()),
            textInputAction: TextInputAction.search,
            decoration: InputDecoration(
              hintText: '搜索软件包或许可证内容',
              prefixIcon: const Icon(Icons.search_rounded, size: 19),
              suffixIcon: _query.isEmpty
                  ? null
                  : IconButton(
                      tooltip: '清除搜索',
                      onPressed: () {
                        _searchController.clear();
                        setState(() => _query = '');
                      },
                      icon: const Icon(Icons.close_rounded, size: 18),
                    ),
              filled: true,
              fillColor: cs.onSurface.withValues(alpha: 0.035),
              contentPadding: const EdgeInsets.symmetric(
                horizontal: 12,
                vertical: 11,
              ),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
                borderSide: BorderSide(
                  color: cs.outlineVariant.withValues(alpha: 0.4),
                  width: 0.8,
                ),
              ),
              enabledBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
                borderSide: BorderSide(
                  color: cs.outlineVariant.withValues(alpha: 0.4),
                  width: 0.8,
                ),
              ),
            ),
          ),
          const SizedBox(height: 12),
          Expanded(
            child: FutureBuilder<List<AppLicenseRecord>>(
              future: _catalog,
              builder: (context, snapshot) {
                if (snapshot.hasError) {
                  return _LicenseMessage(
                    icon: Icons.error_outline_rounded,
                    message: '无法读取许可证信息',
                    detail: snapshot.error.runtimeType.toString(),
                  );
                }
                if (!snapshot.hasData) {
                  return const Center(child: CircularProgressIndicator());
                }
                final query = _query.toLowerCase();
                final records = snapshot.data!
                    .where(
                      (record) =>
                          query.isEmpty ||
                          record.packageName.toLowerCase().contains(query) ||
                          record.text.toLowerCase().contains(query),
                    )
                    .toList(growable: false);
                if (records.isEmpty) {
                  return const _LicenseMessage(
                    icon: Icons.search_off_rounded,
                    message: '没有匹配的许可证',
                  );
                }
                final selected = records.cast<AppLicenseRecord?>().firstWhere(
                  (record) => record!.packageName == _selectedPackage,
                  orElse: () => records.first,
                )!;
                return LayoutBuilder(
                  builder: (context, constraints) {
                    if (constraints.maxWidth >= 620) {
                      return _buildWideCatalog(context, records, selected);
                    }
                    return _buildCompactCatalog(context, records, selected);
                  },
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildWideCatalog(
    BuildContext context,
    List<AppLicenseRecord> records,
    AppLicenseRecord selected,
  ) {
    final cs = Theme.of(context).colorScheme;
    return Row(
      children: [
        SizedBox(
          width: 245,
          child: _LicensePackageList(
            records: records,
            selectedPackage: selected.packageName,
            onSelected: _select,
          ),
        ),
        VerticalDivider(
          width: 25,
          thickness: 0.8,
          color: cs.outlineVariant.withValues(alpha: 0.35),
        ),
        Expanded(
          child: _LicenseDetail(
            key: ValueKey(selected.packageName),
            record: selected,
            controller: _detailScrollController,
          ),
        ),
      ],
    );
  }

  Widget _buildCompactCatalog(
    BuildContext context,
    List<AppLicenseRecord> records,
    AppLicenseRecord selected,
  ) {
    if (_selectedPackage == null ||
        !records.any((record) => record.packageName == _selectedPackage)) {
      return _LicensePackageList(
        records: records,
        selectedPackage: null,
        onSelected: _select,
      );
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        TextButton.icon(
          onPressed: () => setState(() => _selectedPackage = null),
          icon: const Icon(Icons.arrow_back_rounded, size: 18),
          label: const Text('全部软件包'),
        ),
        const SizedBox(height: 4),
        Expanded(
          child: _LicenseDetail(
            key: ValueKey(selected.packageName),
            record: selected,
            controller: _detailScrollController,
          ),
        ),
      ],
    );
  }
}

class _LicensePackageList extends StatelessWidget {
  const _LicensePackageList({
    required this.records,
    required this.selectedPackage,
    required this.onSelected,
  });

  final List<AppLicenseRecord> records;
  final String? selectedPackage;
  final ValueChanged<AppLicenseRecord> onSelected;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return ListView.separated(
      padding: EdgeInsets.zero,
      itemCount: records.length,
      separatorBuilder: (_, _) => const SizedBox(height: 3),
      itemBuilder: (context, index) {
        final record = records[index];
        final selected = record.packageName == selectedPackage;
        return Material(
          color: selected
              ? cs.primary.withValues(alpha: 0.11)
              : Colors.transparent,
          borderRadius: BorderRadius.circular(9),
          child: InkWell(
            borderRadius: BorderRadius.circular(9),
            onTap: () => onSelected(record),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 9),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      record.packageName,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 13,
                        fontWeight: selected
                            ? FontWeight.w700
                            : FontWeight.w500,
                        color: selected ? cs.primary : cs.onSurface,
                      ),
                    ),
                  ),
                  Icon(
                    Icons.chevron_right_rounded,
                    size: 18,
                    color: selected ? cs.primary : cs.onSurfaceVariant,
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }
}

class _LicenseDetail extends StatelessWidget {
  const _LicenseDetail({
    super.key,
    required this.record,
    required this.controller,
  });

  final AppLicenseRecord record;
  final ScrollController controller;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Scrollbar(
      controller: controller,
      thumbVisibility: false,
      child: SingleChildScrollView(
        controller: controller,
        padding: const EdgeInsets.only(right: 10, bottom: 12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              record.packageName,
              style: TextStyle(
                fontSize: 17,
                fontWeight: FontWeight.w800,
                color: cs.onSurface,
              ),
            ),
            const SizedBox(height: 12),
            SelectableText(
              record.text,
              style: TextStyle(
                fontSize: 12.5,
                height: 1.5,
                color: cs.onSurfaceVariant,
                fontFamily: 'monospace',
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _LicenseMessage extends StatelessWidget {
  const _LicenseMessage({
    required this.icon,
    required this.message,
    this.detail,
  });

  final IconData icon;
  final String message;
  final String? detail;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 30, color: cs.onSurfaceVariant),
          const SizedBox(height: 10),
          Text(message, style: TextStyle(color: cs.onSurfaceVariant)),
          if (detail case final value?) ...[
            const SizedBox(height: 4),
            Text(
              value,
              style: TextStyle(fontSize: 11, color: cs.onSurfaceVariant),
            ),
          ],
        ],
      ),
    );
  }
}
