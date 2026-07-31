import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../controllers/clipboard_controller.dart';
import '../models/clipboard_item.dart';
import '../services/media_picker.dart';
import '../theme/app_colors.dart';
import '../theme/app_theme.dart';
import '../widgets/clipboard_card.dart';

/// Main clipboard list screen: the account's synced items, searchable and
/// filterable by type.
///
/// Reads everything from [ClipboardController]; it holds no clipboard state of
/// its own beyond the search text and the selected filter.
class HomeScreen extends StatefulWidget {
  const HomeScreen({
    super.key,
    required this.onViewDevices,
    this.picker = const MediaPicker(),
  });

  /// Switches the nav shell to the Devices tab.
  final VoidCallback onViewDevices;

  /// Injectable so a widget test can supply a stand-in — the real picker opens
  /// system UI that a test cannot dismiss.
  final MediaPicker picker;

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

  List<ClipboardItem> _filtered(List<ClipboardItem> items) {
    final q = _query.trim().toLowerCase();
    return items.where((item) {
      final matchesType = _typeFilter == null || item.type == _typeFilter;
      final matchesQuery = q.isEmpty || item.content.toLowerCase().contains(q);
      return matchesType && matchesQuery;
    }).toList();
  }

  Future<void> _onCopy(ClipboardItem item) async {
    await context.read<ClipboardController>().copyToDevice(item);
    if (!mounted) return;
    _toast('Copied to clipboard');
  }

  Future<void> _onDelete(ClipboardItem item) async {
    final controller = context.read<ClipboardController>();
    final deleted = await controller.deleteItem(item);
    if (!mounted) return;
    _toast(deleted ? 'Deleted' : controller.errorMessage ?? 'Could not delete');
  }

  /// Captures whatever is on the device clipboard right now.
  ///
  /// Exists because Android forbids reading the clipboard unless this app has
  /// focus — so a deliberate tap is the one moment a read is guaranteed to work.
  Future<void> _captureNow() async {
    final controller = context.read<ClipboardController>();
    final saved = await controller.captureFromDevice();
    if (!mounted) return;
    _toast(
      saved != null
          ? 'Saved to CopyOnce'
          : controller.errorMessage ?? 'Nothing new on the clipboard',
    );
  }

  /// Picks an image and relays it to the account's other devices.
  Future<void> _uploadImage() async {
    final controller = context.read<ClipboardController>();

    final picked = await widget.picker.pickFromGallery();
    if (picked == null) return; // Backed out of the picker.

    final saved = await controller.uploadImage(
      bytes: picked.bytes,
      filename: picked.filename,
    );

    if (!mounted) return;
    _toast(
      saved != null
          ? 'Sent to your devices'
          : controller.errorMessage ?? 'Could not send that image',
    );
  }

  void _toast(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
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
    final controller = context.watch<ClipboardController>();
    final all = controller.items;
    final items = _filtered(all);
    final deviceCount = controller.devices.length;

    // An item that arrived from another device announces itself once, if the
    // user has sync alerts on.
    final alert = controller.pendingAlert;
    if (alert != null) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        context.read<ClipboardController>().consumeAlert();
        _toast('New item from ${alert.deviceName}');
      });
    }

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
      // The action follows the filter: on Images the useful thing to do is add
      // one, everywhere else it is to capture what is on the clipboard.
      floatingActionButton: _typeFilter == ClipboardItemType.image
          ? FloatingActionButton.extended(
              onPressed: controller.isUploading ? null : _uploadImage,
              backgroundColor: AppColors.primary,
              foregroundColor: AppColors.white,
              icon: controller.isUploading
                  ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: AppColors.white,
                      ),
                    )
                  : const Icon(Icons.add_photo_alternate_outlined),
              label: Text(controller.isUploading ? 'Sending…' : 'Add image'),
            )
          : FloatingActionButton.extended(
              onPressed: _captureNow,
              backgroundColor: AppColors.primary,
              foregroundColor: AppColors.white,
              icon: const Icon(Icons.content_paste_go_rounded),
              label: const Text('Save clipboard'),
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
                  count: all.length,
                  selected: _typeFilter == null,
                  onSelected: (_) => setState(() => _typeFilter = null),
                ),
                const SizedBox(width: AppSpacing.s),
                _FilterChip(
                  label: 'Text',
                  count: all
                      .where((i) => i.type == ClipboardItemType.text)
                      .length,
                  selected: _typeFilter == ClipboardItemType.text,
                  onSelected: (_) =>
                      setState(() => _typeFilter = ClipboardItemType.text),
                ),
                const SizedBox(width: AppSpacing.s),
                _FilterChip(
                  label: 'Links',
                  count: all
                      .where((i) => i.type == ClipboardItemType.link)
                      .length,
                  selected: _typeFilter == ClipboardItemType.link,
                  onSelected: (_) =>
                      setState(() => _typeFilter = ClipboardItemType.link),
                ),
                const SizedBox(width: AppSpacing.s),
                _FilterChip(
                  label: 'Images',
                  count: all
                      .where((i) => i.type == ClipboardItemType.image)
                      .length,
                  selected: _typeFilter == ClipboardItemType.image,
                  onSelected: (_) =>
                      setState(() => _typeFilter = ClipboardItemType.image),
                ),
              ],
            ),
          ),

          // ── Loading / error / empty / list ────────────────────────────────
          Expanded(
            child: switch (controller.status) {
              ClipboardListStatus.initial || ClipboardListStatus.loading =>
                const Center(child: CircularProgressIndicator()),
              ClipboardListStatus.error => _ErrorState(
                message:
                    controller.errorMessage ?? 'Could not load your clipboard.',
                onRetry: () => context.read<ClipboardController>().refresh(),
              ),
              ClipboardListStatus.ready when items.isEmpty => _EmptyState(
                isFiltered: all.isNotEmpty,
                isImages: _typeFilter == ClipboardItemType.image,
                onAddImage: _uploadImage,
              ),
              ClipboardListStatus.ready => RefreshIndicator(
                onRefresh: () => context.read<ClipboardController>().refresh(),
                child: ListView.separated(
                  padding: const EdgeInsets.fromLTRB(
                    AppSpacing.m,
                    AppSpacing.s,
                    AppSpacing.m,
                    AppSpacing.xl,
                  ),
                  itemCount: items.length,
                  separatorBuilder: (_, _) =>
                      const SizedBox(height: AppSpacing.s),
                  itemBuilder: (_, index) => Dismissible(
                    key: ValueKey(items[index].id),
                    direction: DismissDirection.endToStart,
                    background: const _DeleteBackground(),
                    onDismissed: (_) => _onDelete(items[index]),
                    child: ClipboardCard(
                      item: items[index],
                      onCopy: () => _onCopy(items[index]),
                    ),
                  ),
                ),
              ),
            },
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

/// Swipe-to-delete backdrop.
class _DeleteBackground extends StatelessWidget {
  const _DeleteBackground();

  @override
  Widget build(BuildContext context) {
    return Container(
      alignment: Alignment.centerRight,
      padding: const EdgeInsets.only(right: AppSpacing.l),
      decoration: BoxDecoration(
        color: AppColors.error.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(AppRadius.l),
      ),
      child: const Icon(Icons.delete_outline_rounded, color: AppColors.error),
    );
  }
}

class _ErrorState extends StatelessWidget {
  const _ErrorState({required this.message, required this.onRetry});

  final String message;
  final VoidCallback onRetry;

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
              decoration: const BoxDecoration(
                color: AppColors.surface,
                shape: BoxShape.circle,
              ),
              child: const Icon(
                Icons.cloud_off_rounded,
                size: 30,
                color: AppColors.textHint,
              ),
            ),
            const SizedBox(height: AppSpacing.l),
            const Text(
              'Cannot reach your clipboard',
              style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.w600,
                color: AppColors.textPrimary,
              ),
            ),
            const SizedBox(height: AppSpacing.s),
            Text(
              message,
              textAlign: TextAlign.center,
              style: const TextStyle(
                fontSize: 14,
                color: AppColors.textSecondary,
                height: 1.5,
              ),
            ),
            const SizedBox(height: AppSpacing.l),
            ElevatedButton(onPressed: onRetry, child: const Text('Try again')),
          ],
        ),
      ),
    );
  }
}

class _EmptyState extends StatelessWidget {
  const _EmptyState({
    required this.isFiltered,
    this.isImages = false,
    this.onAddImage,
  });

  /// True when items exist but the search or filter hides them all — a
  /// different situation from having nothing synced at all.
  final bool isFiltered;

  /// True when the Images filter is on, which has its own empty state: images
  /// are expected to be absent most of the time, because they leave as soon as
  /// they have been delivered.
  final bool isImages;

  final Future<void> Function()? onAddImage;

  @override
  Widget build(BuildContext context) {
    final (icon, title, body) = switch ((isImages, isFiltered)) {
      (true, _) => (
        Icons.add_photo_alternate_outlined,
        'No images waiting',
        'Send an image and it appears on your other devices.\nIt clears once '
            'they have it, or after 24 hours.',
      ),
      (false, true) => (
        Icons.search_off_rounded,
        'No matches',
        'Try a different search or filter.',
      ),
      (false, false) => (
        Icons.content_paste_off_rounded,
        'Nothing here yet',
        'Copy something, then tap Save clipboard —\nor copy on another device '
            'and it lands here.',
      ),
    };

    return Center(
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.xl),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 72,
              height: 72,
              decoration: const BoxDecoration(
                color: AppColors.surface,
                shape: BoxShape.circle,
              ),
              child: Icon(icon, size: 32, color: AppColors.textHint),
            ),
            const SizedBox(height: AppSpacing.l),
            Text(
              title,
              style: const TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.w600,
                color: AppColors.textPrimary,
              ),
            ),
            const SizedBox(height: AppSpacing.s),
            Text(
              body,
              textAlign: TextAlign.center,
              style: const TextStyle(
                fontSize: 14,
                color: AppColors.textSecondary,
                height: 1.5,
              ),
            ),
            if (isImages && onAddImage != null) ...[
              const SizedBox(height: AppSpacing.l),
              ElevatedButton.icon(
                onPressed: onAddImage,
                icon: const Icon(Icons.add_photo_alternate_outlined, size: 18),
                label: const Text('Choose an image'),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
