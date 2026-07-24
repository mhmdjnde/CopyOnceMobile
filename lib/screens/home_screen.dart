import 'package:flutter/material.dart';
import '../data/mock_data.dart';
import '../models/clipboard_item.dart';
import '../theme/app_colors.dart';
import '../theme/app_theme.dart';
import '../widgets/clipboard_card.dart';

/// Main clipboard list screen.
/// Supports search and type filtering over mock data.
class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key, required this.onViewDevices});

  /// Switches the nav shell to the Devices tab.
  final VoidCallback onViewDevices;

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  final _searchController = TextEditingController();
  String _query = '';

  /// null = show all types.
  ClipboardItemType? _typeFilter;

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  List<ClipboardItem> get _filtered {
    final q = _query.trim().toLowerCase();
    return MockData.clipboardItems.where((item) {
      final matchesType = _typeFilter == null || item.type == _typeFilter;
      final matchesQuery = q.isEmpty || item.content.toLowerCase().contains(q);
      return matchesType && matchesQuery;
    }).toList();
  }

  void _onCopy(ClipboardItem item) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: const Text('Copied to clipboard'),
        backgroundColor: AppColors.primary,
        duration: const Duration(seconds: 2),
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppRadius.m),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final items = _filtered;
    final deviceCount = MockData.devices.length;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Clipboard'),
        actions: [
          // Device indicator chip
          Padding(
            padding: const EdgeInsets.only(right: AppSpacing.m),
            child: Semantics(
              button: true,
              label: '$deviceCount connected devices',
              child: GestureDetector(
                onTap: widget.onViewDevices,
                child: Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: AppSpacing.m,
                    vertical: AppSpacing.xs + 2,
                  ),
                  decoration: BoxDecoration(
                    color: AppColors.surface,
                    borderRadius: BorderRadius.circular(AppRadius.full),
                    border: Border.all(color: AppColors.divider),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Container(
                        width: 6,
                        height: 6,
                        decoration: const BoxDecoration(
                          color: AppColors.success,
                          shape: BoxShape.circle,
                        ),
                      ),
                      const SizedBox(width: 6),
                      Text(
                        '$deviceCount devices',
                        style: const TextStyle(
                          fontSize: 12,
                          color: AppColors.textSecondary,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
      body: Column(
        children: [
          // ── Search bar ───────────────────────────────────────────────────
          Padding(
            padding: const EdgeInsets.fromLTRB(
              AppSpacing.m,
              AppSpacing.s,
              AppSpacing.m,
              0,
            ),
            child: TextField(
              controller: _searchController,
              onChanged: (v) => setState(() => _query = v),
              decoration: const InputDecoration(
                hintText: 'Search clipboard…',
                prefixIcon: Icon(Icons.search_rounded),
              ),
            ),
          ),

          // ── Filter chips ─────────────────────────────────────────────────
          SizedBox(
            height: 52,
            child: ListView(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.symmetric(
                horizontal: AppSpacing.m,
                vertical: AppSpacing.s,
              ),
              children: [
                _FilterChip(
                  label: 'All',
                  count: MockData.clipboardItems.length,
                  selected: _typeFilter == null,
                  onSelected: (_) => setState(() => _typeFilter = null),
                ),
                const SizedBox(width: AppSpacing.s),
                _FilterChip(
                  label: 'Text',
                  count: MockData.clipboardItems
                      .where((i) => i.type == ClipboardItemType.text)
                      .length,
                  selected: _typeFilter == ClipboardItemType.text,
                  onSelected: (_) =>
                      setState(() => _typeFilter = ClipboardItemType.text),
                ),
                const SizedBox(width: AppSpacing.s),
                _FilterChip(
                  label: 'Links',
                  count: MockData.clipboardItems
                      .where((i) => i.type == ClipboardItemType.link)
                      .length,
                  selected: _typeFilter == ClipboardItemType.link,
                  onSelected: (_) =>
                      setState(() => _typeFilter = ClipboardItemType.link),
                ),
                const SizedBox(width: AppSpacing.s),
                _FilterChip(
                  label: 'Images',
                  count: MockData.clipboardItems
                      .where((i) => i.type == ClipboardItemType.image)
                      .length,
                  selected: _typeFilter == ClipboardItemType.image,
                  onSelected: (_) =>
                      setState(() => _typeFilter = ClipboardItemType.image),
                ),
              ],
            ),
          ),

          // ── List / Empty state ────────────────────────────────────────────
          Expanded(
            child: items.isEmpty
                ? const _EmptyState()
                : ListView.separated(
                    padding: const EdgeInsets.fromLTRB(
                      AppSpacing.m,
                      AppSpacing.s,
                      AppSpacing.m,
                      AppSpacing.xl,
                    ),
                    itemCount: items.length,
                    separatorBuilder: (_, __) =>
                        const SizedBox(height: AppSpacing.s),
                    itemBuilder: (_, index) => ClipboardCard(
                      item: items[index],
                      onCopy: () => _onCopy(items[index]),
                    ),
                  ),
          ),
        ],
      ),
    );
  }
}

// ── Supporting widgets ─────────────────────────────────────────────────────────

class _FilterChip extends StatelessWidget {
  const _FilterChip({
    required this.label,
    required this.count,
    required this.selected,
    required this.onSelected,
  });

  final String label;
  final int count;
  final bool selected;
  final ValueChanged<bool> onSelected;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      selected: selected,
      child: FilterChip(
        label: Text('$label  $count'),
        selected: selected,
        onSelected: onSelected,
        showCheckmark: false,
      ),
    );
  }
}

class _EmptyState extends StatelessWidget {
  const _EmptyState();

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.xl),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 72,
              height: 72,
              decoration: BoxDecoration(
                color: AppColors.surface,
                shape: BoxShape.circle,
              ),
              child: const Icon(
                Icons.content_paste_off_rounded,
                size: 32,
                color: AppColors.textHint,
              ),
            ),
            const SizedBox(height: AppSpacing.l),
            const Text(
              'Nothing here',
              style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.w600,
                color: AppColors.textPrimary,
              ),
            ),
            const SizedBox(height: AppSpacing.s),
            const Text(
              'Copy something on any device\nand it will appear here.',
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 14,
                color: AppColors.textSecondary,
                height: 1.5,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
