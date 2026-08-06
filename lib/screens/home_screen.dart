import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import 'package:gal/gal.dart';

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

  /// Ids picked for a bulk save.
  ///
  /// Only offered on Images: bulk-saving text would mean nothing, and a
  /// checkbox on every row would be clutter the rest of the time.
  final _selected = <String>{};

  /// (done, total) while a bulk save runs.
  (int, int)? _saving;

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

  /// Saves every picked image to the device's photo library.
  Future<void> _saveSelected(List<ClipboardItem> images) async {
    final chosen = images.where((i) => _selected.contains(i.id)).toList();
    if (chosen.isEmpty) return;

    final controller = context.read<ClipboardController>();
    setState(() => _saving = (0, chosen.length));

    final fetched = await controller.fetchOriginals(
      chosen,
      onProgress: (done, total) {
        if (mounted) setState(() => _saving = (done, total));
      },
    );

    var written = 0;
    try {
      if (fetched.isNotEmpty && !await Gal.hasAccess()) {
        if (!await Gal.requestAccess()) {
          if (mounted) {
            setState(() => _saving = null);
            _toast('CopyOnce needs permission to save to your photos.');
          }
          return;
        }
      }

      for (final (item, bytes) in fetched) {
        try {
          await Gal.putImageBytes(bytes, name: _photoName(item.content));
          written++;
        } on GalException {
          // Keep going: one unsupported file should not abandon the rest.
        }
      }
    } finally {
      if (mounted) {
        setState(() {
          _saving = null;
          _selected.clear();
        });
      }
    }

    if (!mounted) return;
    _toast(
      written == chosen.length
          ? '$written saved to your photos'
          : '$written of ${chosen.length} saved',
    );
  }

  /// Gallery filename: the stored name without its extension, since the
  /// platform appends its own.
  static String _photoName(String content) {
    final dot = content.lastIndexOf('.');
    final base = dot > 0 ? content.substring(0, dot) : content;
    return base.isEmpty ? 'CopyOnce' : base;
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

  /// Picks one or more images and relays them to the account's other devices.
  Future<void> _uploadImage() async {
    final controller = context.read<ClipboardController>();

    final picked = await widget.picker.pickFromGallery();
    if (picked.isEmpty) return; // Backed out of the picker.

    final stored = await controller.uploadImages([
      for (final image in picked)
        (bytes: image.bytes, filename: image.filename),
    ]);

    if (!mounted) return;

    // A batch can half-succeed — the ten-image cap is the usual reason — and
    // saying so is more useful than either a bare error or a silent partial.
    if (stored == picked.length) {
      _toast(stored == 1 ? 'Sent to your devices' : '$stored images sent');
    } else if (stored == 0) {
      _toast(controller.errorMessage ?? 'Could not send those images');
    } else {
      _toast(
        '$stored of ${picked.length} sent — '
        '${controller.errorMessage ?? 'the rest could not be sent'}',
      );
    }
  }

  /// "Sending…" for one image, "3 of 8" for a batch — a count only helps when
  /// there is more than one thing to count.
  String _uploadLabel(ClipboardController controller) {
    if (!controller.isUploading) return 'Add images';
    final progress = controller.uploadProgress;
    if (progress == null) return 'Sending…';
    return '${progress.$1} of ${progress.$2}';
  }

  void _toast(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          message,
          style: TextStyle(color: context.colors.onPrimary),
        ),
        backgroundColor: context.colors.primary,
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
                    color: context.colors.surface,
                    borderRadius: BorderRadius.circular(AppRadius.full),
                    border: Border.all(color: context.colors.divider),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Container(
                        width: 6,
                        height: 6,
                        decoration: BoxDecoration(
                          color: context.colors.success,
                          shape: BoxShape.circle,
                        ),
                      ),
                      const SizedBox(width: 6),
                      Text(
                        '$deviceCount devices',
                        style: TextStyle(
                          fontSize: 12,
                          color: context.colors.textSecondary,
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
              backgroundColor: context.colors.primary,
              foregroundColor: context.colors.onPrimary,
              icon: controller.isUploading
                  ? SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: context.colors.onPrimary,
                      ),
                    )
                  : const Icon(Icons.add_photo_alternate_outlined),
              label: Text(_uploadLabel(controller)),
            )
          : FloatingActionButton.extended(
              onPressed: _captureNow,
              backgroundColor: context.colors.primary,
              foregroundColor: context.colors.onPrimary,
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
                  onSelected: (_) => setState(() {
                    _typeFilter = null;
                    _selected.clear();
                  }),
                ),
                const SizedBox(width: AppSpacing.s),
                _FilterChip(
                  label: 'Text',
                  count: all
                      .where((i) => i.type == ClipboardItemType.text)
                      .length,
                  selected: _typeFilter == ClipboardItemType.text,
                  onSelected: (_) => setState(() {
                    _typeFilter = ClipboardItemType.text;
                    _selected.clear();
                  }),
                ),
                const SizedBox(width: AppSpacing.s),
                _FilterChip(
                  label: 'Links',
                  count: all
                      .where((i) => i.type == ClipboardItemType.link)
                      .length,
                  selected: _typeFilter == ClipboardItemType.link,
                  onSelected: (_) => setState(() {
                    _typeFilter = ClipboardItemType.link;
                    _selected.clear();
                  }),
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

          // ── Bulk selection (Images only) ──────────────────────────────────
          if (_typeFilter == ClipboardItemType.image && items.isNotEmpty)
            _SelectionBar(
              selectedCount: _selected.length,
              totalCount: items.length,
              saving: _saving,
              onToggleAll: () => setState(() {
                if (_selected.length == items.length) {
                  _selected.clear();
                } else {
                  _selected
                    ..clear()
                    ..addAll(items.map((i) => i.id));
                }
              }),
              onSave: () => _saveSelected(items),
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
                      selectable: _typeFilter == ClipboardItemType.image,
                      selected: _selected.contains(items[index].id),
                      onToggleSelected: () => setState(() {
                        final id = items[index].id;
                        if (!_selected.add(id)) _selected.remove(id);
                      }),
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

/// Shown above the list on Images: pick several, save them together.
class _SelectionBar extends StatelessWidget {
  const _SelectionBar({
    required this.selectedCount,
    required this.totalCount,
    required this.saving,
    required this.onToggleAll,
    required this.onSave,
  });

  final int selectedCount;
  final int totalCount;
  final (int, int)? saving;
  final VoidCallback onToggleAll;
  final VoidCallback onSave;

  @override
  Widget build(BuildContext context) {
    final busy = saving != null;
    final allPicked = selectedCount == totalCount && totalCount > 0;

    return Padding(
      padding: const EdgeInsets.fromLTRB(
        AppSpacing.m,
        0,
        AppSpacing.m,
        AppSpacing.s,
      ),
      child: Container(
        padding: const EdgeInsets.symmetric(
          horizontal: AppSpacing.m,
          vertical: AppSpacing.s,
        ),
        decoration: BoxDecoration(
          color: context.colors.card,
          borderRadius: BorderRadius.circular(AppRadius.m),
          border: Border.all(color: context.colors.divider),
        ),
        child: Row(
          children: [
            Expanded(
              child: Text(
                selectedCount > 0
                    ? '\$selectedCount selected'
                    : 'Select images to save several',
                style: TextStyle(
                  fontSize: 13,
                  color: context.colors.textSecondary,
                ),
              ),
            ),
            TextButton(
              onPressed: busy ? null : onToggleAll,
              child: Text(allPicked ? 'Clear' : 'Select all'),
            ),
            const SizedBox(width: AppSpacing.xs),
            FilledButton.icon(
              onPressed: busy || selectedCount == 0 ? null : onSave,
              icon: busy
                  ? SizedBox(
                      width: 14,
                      height: 14,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: context.colors.onPrimary,
                      ),
                    )
                  : const Icon(Icons.download_rounded, size: 18),
              label: Text(busy ? '\${saving!.\$1} of \${saving!.\$2}' : 'Save'),
            ),
          ],
        ),
      ),
    );
  }
}

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
        color: context.colors.error.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(AppRadius.l),
      ),
      child: Icon(Icons.delete_outline_rounded, color: context.colors.error),
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
              decoration: BoxDecoration(
                color: context.colors.surface,
                shape: BoxShape.circle,
              ),
              child: Icon(
                Icons.cloud_off_rounded,
                size: 30,
                color: context.colors.textHint,
              ),
            ),
            const SizedBox(height: AppSpacing.l),
            Text(
              'Cannot reach your clipboard',
              style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.w600,
                color: context.colors.textPrimary,
              ),
            ),
            const SizedBox(height: AppSpacing.s),
            Text(
              message,
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 14,
                color: context.colors.textSecondary,
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
              decoration: BoxDecoration(
                color: context.colors.surface,
                shape: BoxShape.circle,
              ),
              child: Icon(icon, size: 32, color: context.colors.textHint),
            ),
            const SizedBox(height: AppSpacing.l),
            Text(
              title,
              style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.w600,
                color: context.colors.textPrimary,
              ),
            ),
            const SizedBox(height: AppSpacing.s),
            Text(
              body,
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 14,
                color: context.colors.textSecondary,
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
