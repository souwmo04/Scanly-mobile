import 'dart:async';
import 'dart:typed_data';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:material_ui/material_ui.dart';

import '../../core/errors/app_exception.dart';
import '../../core/theme/app_spacing.dart';
import '../../core/vision/quad.dart';
import '../../domain/entities/app_settings.dart';
import '../../domain/entities/page_edits.dart';
import '../../domain/entities/scan_page.dart';
import '../../shared/providers/core_providers.dart';
import '../../shared/providers/scanner_providers.dart';
import '../../shared/widgets/dialogs.dart';
import '../../shared/widgets/state_views.dart';
import '../ocr/ocr_queue.dart';
import '../settings/settings_controller.dart';
import 'crop_view.dart';

/// Loads a page and opens the editor for it.
class PageEditorScreen extends ConsumerWidget {
  const PageEditorScreen({required this.pageId, super.key});

  final String pageId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final page = ref.watch(_pageProvider(pageId));
    return page.when(
      loading: () => Scaffold(appBar: AppBar(), body: const LoadingState()),
      error: (e, _) => Scaffold(
        appBar: AppBar(),
        body: ErrorState(error: e),
      ),
      data: (page) {
        if (page == null) {
          return Scaffold(
            appBar: AppBar(),
            body: const EmptyState(
              icon: Icons.image_not_supported_outlined,
              title: 'Page not found',
              message: 'It may have been deleted.',
            ),
          );
        }
        final size = ref.watch(imageSizeProvider(page.originalPath));
        return size.when(
          loading: () => Scaffold(appBar: AppBar(), body: const LoadingState()),
          error: (e, _) => Scaffold(
            appBar: AppBar(),
            body: ErrorState(error: e),
          ),
          data: (s) => _PageEditor(
            page: page,
            originalWidth: s.width,
            originalHeight: s.height,
          ),
        );
      },
    );
  }
}

final _pageProvider = FutureProvider.autoDispose.family<ScanPage?, String>(
  (ref, id) => ref.watch(documentRepositoryProvider).getPage(id),
);

enum _Tool { crop, filters, adjust }

class _PageEditor extends ConsumerStatefulWidget {
  const _PageEditor({
    required this.page,
    required this.originalWidth,
    required this.originalHeight,
  });

  final ScanPage page;
  final int originalWidth;
  final int originalHeight;

  @override
  ConsumerState<_PageEditor> createState() => _PageEditorState();
}

class _PageEditorState extends ConsumerState<_PageEditor> {
  late final EditHistory<PageEdits> _history = EditHistory(
    PageEdits.fromPage(widget.page),
  );
  _Tool _tool = _Tool.crop;
  bool _saving = false;
  bool _detecting = false;

  /// True between the first change of a slider drag and its end, so one drag
  /// becomes one undo step.
  bool _sliderDragging = false;

  Uint8List? _preview;
  bool _rendering = false;
  int _renderGeneration = 0;
  Timer? _debounce;

  PageEdits get _edits => _history.current;

  @override
  void initState() {
    super.initState();
    _schedulePreview(immediate: true);
  }

  @override
  void dispose() {
    _debounce?.cancel();
    super.dispose();
  }

  void _push(PageEdits next) {
    setState(() => _history.push(next));
    _schedulePreview();
  }

  void _schedulePreview({bool immediate = false}) {
    _debounce?.cancel();
    _debounce = Timer(
      immediate ? Duration.zero : const Duration(milliseconds: 220),
      _renderPreview,
    );
  }

  Future<void> _renderPreview() async {
    final generation = ++_renderGeneration;
    final edits = _edits;
    if (!edits.corners.isConvex) return;
    setState(() => _rendering = true);
    try {
      final bytes = await ref
          .read(editPageProvider)
          .preview(widget.page, edits);
      if (!mounted || generation != _renderGeneration) return;
      setState(() => _preview = bytes);
    } on Object catch (e) {
      if (mounted) showMessage(context, describeError(e));
    } finally {
      if (mounted && generation == _renderGeneration) {
        setState(() => _rendering = false);
      }
    }
  }

  void _undo() {
    setState(_history.undo);
    _schedulePreview();
  }

  void _redo() {
    setState(_history.redo);
    _schedulePreview();
  }

  Future<void> _autoDetect() async {
    setState(() => _detecting = true);
    try {
      final quad = await ref.read(editPageProvider).detectCorners(widget.page);
      if (!mounted) return;
      if (quad == null) {
        showMessage(context, 'No document edges found. Drag the corners.');
      } else {
        _push(_edits.copyWith(corners: quad));
      }
    } on Object catch (e) {
      if (mounted) showMessage(context, describeError(e));
    } finally {
      if (mounted) setState(() => _detecting = false);
    }
  }

  Future<void> _save() async {
    if (!_edits.corners.isConvex) {
      showMessage(context, 'The crop corners cross over. Adjust them first.');
      return;
    }
    if (!_history.isChanged) {
      context.pop(false);
      return;
    }
    setState(() => _saving = true);
    try {
      final settings = ref.read(settingsControllerProvider);
      final ocrQueue = ref.read(ocrQueueProvider.notifier);
      await ref
          .read(editPageProvider)
          .save(
            widget.page,
            _edits,
            jpegQuality: settings.compression.jpegQuality,
          );
      // The image changed, so its text is recognised again.
      unawaited(
        ocrQueue.pageImageChanged(widget.page.id, autoOcr: settings.autoOcr),
      );
      if (mounted) context.pop(true);
    } on Object catch (e) {
      if (!mounted) return;
      setState(() => _saving = false);
      showMessage(context, describeError(e));
    }
  }

  Future<void> _close() async {
    if (_history.isChanged) {
      final discard = await showConfirmDialog(
        context,
        title: 'Discard changes?',
        message: 'Your edits to this page will be lost.',
        confirmLabel: 'Discard',
        destructive: true,
      );
      if (!discard || !mounted) return;
    }
    context.pop(false);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;

    return PopScope(
      canPop: !_history.isChanged && !_saving,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop && !_saving) _close();
      },
      child: Scaffold(
        appBar: AppBar(
          leading: IconButton(
            tooltip: 'Close editor',
            icon: const Icon(Icons.close_rounded),
            onPressed: _saving ? null : _close,
          ),
          title: const Text('Edit page'),
          actions: [
            IconButton(
              tooltip: 'Undo',
              icon: const Icon(Icons.undo_rounded),
              onPressed: _history.canUndo && !_saving ? _undo : null,
            ),
            IconButton(
              tooltip: 'Redo',
              icon: const Icon(Icons.redo_rounded),
              onPressed: _history.canRedo && !_saving ? _redo : null,
            ),
            Padding(
              padding: const EdgeInsets.only(right: AppSpacing.sm),
              child: FilledButton(
                style: FilledButton.styleFrom(minimumSize: const Size(72, 40)),
                onPressed: _saving ? null : _save,
                child: _saving
                    ? SizedBox.square(
                        dimension: 18,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: scheme.onPrimary,
                        ),
                      )
                    : const Text('Save'),
              ),
            ),
          ],
        ),
        body: Column(
          children: [
            Expanded(
              child: ColoredBox(
                color: scheme.surfaceContainerHigh,
                child: _tool == _Tool.crop
                    ? CropView(
                        imagePath: widget.page.originalPath,
                        imageWidth: widget.originalWidth,
                        imageHeight: widget.originalHeight,
                        corners: _edits.corners,
                        rotation: _edits.rotation,
                        onDragStart: () => _dragFresh = true,
                        onChanged: (quad) {
                          // First move of a drag adds one undo step; the
                          // rest of the drag updates it in place.
                          setState(() {
                            if (_history.current.corners == quad) return;
                            if (_dragFresh) {
                              _history.push(_edits.copyWith(corners: quad));
                              _dragFresh = false;
                            } else {
                              _history.replace(_edits.copyWith(corners: quad));
                            }
                          });
                          _schedulePreview();
                        },
                      )
                    : _PreviewPane(bytes: _preview, busy: _rendering),
              ),
            ),
            _ToolPanel(
              tool: _tool,
              edits: _edits,
              detecting: _detecting,
              onRotate: (clockwise) =>
                  _push(_edits.rotated(clockwise: clockwise)),
              onAutoDetect: _autoDetect,
              onFullPage: () =>
                  _push(_edits.copyWith(corners: Quad.fullFrame(1, 1))),
              onResetAll: () => _push(PageEdits.initial()),
              onFilter: (filter) => _push(_edits.copyWith(filter: filter)),
              onAdjust: (next) {
                setState(() {
                  if (_sliderDragging) {
                    _history.replace(next);
                  } else {
                    _history.push(next);
                    _sliderDragging = true;
                  }
                });
                _schedulePreview();
              },
              onAdjustEnd: () => _sliderDragging = false,
            ),
            SafeArea(
              top: false,
              child: Padding(
                padding: const EdgeInsets.fromLTRB(
                  AppSpacing.lg,
                  AppSpacing.xs,
                  AppSpacing.lg,
                  AppSpacing.sm,
                ),
                child: SegmentedButton<_Tool>(
                  showSelectedIcon: false,
                  segments: const [
                    ButtonSegment(
                      value: _Tool.crop,
                      icon: Icon(Icons.crop_rounded),
                      label: Text('Crop'),
                    ),
                    ButtonSegment(
                      value: _Tool.filters,
                      icon: Icon(Icons.filter_b_and_w_rounded),
                      label: Text('Filters'),
                    ),
                    ButtonSegment(
                      value: _Tool.adjust,
                      icon: Icon(Icons.tune_rounded),
                      label: Text('Adjust'),
                    ),
                  ],
                  selected: {_tool},
                  onSelectionChanged: (s) {
                    setState(() => _tool = s.first);
                    if (_tool != _Tool.crop) _schedulePreview(immediate: true);
                  },
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// Set when a corner drag starts; cleared after its first change.
  bool _dragFresh = false;
}

class _PreviewPane extends StatelessWidget {
  const _PreviewPane({required this.bytes, required this.busy});

  final Uint8List? bytes;
  final bool busy;

  @override
  Widget build(BuildContext context) {
    final data = bytes;
    return Stack(
      fit: StackFit.expand,
      children: [
        if (data == null)
          const LoadingState(message: 'Preparing preview…')
        else
          InteractiveViewer(
            maxScale: 5,
            child: Padding(
              padding: const EdgeInsets.all(AppSpacing.lg),
              child: Center(
                child: Image.memory(
                  data,
                  gaplessPlayback: true,
                  fit: BoxFit.contain,
                ),
              ),
            ),
          ),
        if (busy && data != null)
          const Positioned(
            top: AppSpacing.md,
            right: AppSpacing.md,
            child: SizedBox.square(
              dimension: 20,
              child: CircularProgressIndicator(strokeWidth: 2.4),
            ),
          ),
      ],
    );
  }
}

class _ToolPanel extends StatelessWidget {
  const _ToolPanel({
    required this.tool,
    required this.edits,
    required this.detecting,
    required this.onRotate,
    required this.onAutoDetect,
    required this.onFullPage,
    required this.onResetAll,
    required this.onFilter,
    required this.onAdjust,
    required this.onAdjustEnd,
  });

  final _Tool tool;
  final PageEdits edits;
  final bool detecting;
  final ValueChanged<bool> onRotate;
  final VoidCallback onAutoDetect;
  final VoidCallback onFullPage;
  final VoidCallback onResetAll;
  final ValueChanged<PageFilter> onFilter;
  final ValueChanged<PageEdits> onAdjust;
  final VoidCallback onAdjustEnd;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      // Three 48 px slider rows need more room than the button rows.
      height: tool == _Tool.adjust ? 152 : 120,
      child: switch (tool) {
        _Tool.crop => _CropTools(
          detecting: detecting,
          onRotate: onRotate,
          onAutoDetect: onAutoDetect,
          onFullPage: onFullPage,
          onResetAll: onResetAll,
        ),
        _Tool.filters => _FilterTools(
          selected: edits.filter,
          onSelected: onFilter,
        ),
        _Tool.adjust => _AdjustTools(
          edits: edits,
          onChanged: onAdjust,
          onChangeEnd: onAdjustEnd,
        ),
      },
    );
  }
}

class _CropTools extends StatelessWidget {
  const _CropTools({
    required this.detecting,
    required this.onRotate,
    required this.onAutoDetect,
    required this.onFullPage,
    required this.onResetAll,
  });

  final bool detecting;
  final ValueChanged<bool> onRotate;
  final VoidCallback onAutoDetect;
  final VoidCallback onFullPage;
  final VoidCallback onResetAll;

  @override
  Widget build(BuildContext context) {
    return ListView(
      scrollDirection: Axis.horizontal,
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.md,
        vertical: AppSpacing.lg,
      ),
      children: [
        _ToolButton(
          icon: Icons.rotate_left_rounded,
          label: 'Rotate left',
          onPressed: () => onRotate(false),
        ),
        _ToolButton(
          icon: Icons.rotate_right_rounded,
          label: 'Rotate right',
          onPressed: () => onRotate(true),
        ),
        _ToolButton(
          icon: Icons.auto_fix_high_rounded,
          label: 'Auto detect',
          busy: detecting,
          onPressed: detecting ? null : onAutoDetect,
        ),
        _ToolButton(
          icon: Icons.fullscreen_rounded,
          label: 'Full page',
          onPressed: onFullPage,
        ),
        _ToolButton(
          icon: Icons.restart_alt_rounded,
          label: 'Reset all',
          onPressed: onResetAll,
        ),
      ],
    );
  }
}

class _ToolButton extends StatelessWidget {
  const _ToolButton({
    required this.icon,
    required this.label,
    required this.onPressed,
    this.busy = false,
  });

  final IconData icon;
  final String label;
  final VoidCallback? onPressed;
  final bool busy;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: AppSpacing.xs),
      child: InkWell(
        borderRadius: AppRadius.mdAll,
        onTap: onPressed,
        child: SizedBox(
          width: 84,
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Container(
                width: 48,
                height: 48,
                decoration: BoxDecoration(
                  color: theme.colorScheme.surfaceContainer,
                  borderRadius: AppRadius.mdAll,
                ),
                child: busy
                    ? const Padding(
                        padding: EdgeInsets.all(14),
                        child: CircularProgressIndicator(strokeWidth: 2.2),
                      )
                    : Icon(icon),
              ),
              const SizedBox(height: AppSpacing.xs),
              Text(
                label,
                style: theme.textTheme.labelSmall,
                textAlign: TextAlign.center,
                maxLines: 2,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

String filterLabel(PageFilter f) => switch (f) {
  PageFilter.original => 'Original',
  PageFilter.grayscale => 'Grayscale',
  PageFilter.blackWhite => 'Black & white',
  PageFilter.enhanced => 'Enhanced',
  PageFilter.colorDocument => 'Color document',
};

class _FilterTools extends StatelessWidget {
  const _FilterTools({required this.selected, required this.onSelected});

  final PageFilter selected;
  final ValueChanged<PageFilter> onSelected;

  @override
  Widget build(BuildContext context) {
    final icons = {
      PageFilter.original: Icons.image_outlined,
      PageFilter.grayscale: Icons.gradient_rounded,
      PageFilter.blackWhite: Icons.contrast_rounded,
      PageFilter.enhanced: Icons.auto_awesome_rounded,
      PageFilter.colorDocument: Icons.palette_outlined,
    };
    return ListView(
      scrollDirection: Axis.horizontal,
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.lg,
        vertical: AppSpacing.xl,
      ),
      children: [
        for (final f in PageFilter.values)
          Padding(
            padding: const EdgeInsets.only(right: AppSpacing.sm),
            child: ChoiceChip(
              avatar: Icon(icons[f], size: 18),
              label: Text(filterLabel(f)),
              selected: f == selected,
              onSelected: (_) => onSelected(f),
            ),
          ),
      ],
    );
  }
}

class _AdjustTools extends StatelessWidget {
  const _AdjustTools({
    required this.edits,
    required this.onChanged,
    required this.onChangeEnd,
  });

  final PageEdits edits;
  final ValueChanged<PageEdits> onChanged;
  final VoidCallback onChangeEnd;

  @override
  Widget build(BuildContext context) {
    Widget slider({
      required IconData icon,
      required String label,
      required double value,
      required double min,
      required PageEdits Function(double v) apply,
    }) {
      return Row(
        children: [
          const SizedBox(width: AppSpacing.lg),
          Icon(icon, size: 20),
          const SizedBox(width: AppSpacing.sm),
          SizedBox(
            width: 82,
            child: Text(label, style: Theme.of(context).textTheme.labelMedium),
          ),
          Expanded(
            child: Slider(
              value: value,
              min: min,
              divisions: min < 0 ? 40 : 20,
              label: (value * 100).round().toString(),
              semanticFormatterCallback: (v) => '$label ${(v * 100).round()}',
              onChanged: (v) => onChanged(apply(v)),
              onChangeEnd: (_) => onChangeEnd(),
            ),
          ),
        ],
      );
    }

    return Column(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        slider(
          icon: Icons.brightness_6_outlined,
          label: 'Brightness',
          value: edits.brightness,
          min: -1,
          apply: (v) => edits.copyWith(brightness: v),
        ),
        slider(
          icon: Icons.contrast_rounded,
          label: 'Contrast',
          value: edits.contrast,
          min: -1,
          apply: (v) => edits.copyWith(contrast: v),
        ),
        slider(
          icon: Icons.deblur_rounded,
          label: 'Sharpness',
          value: edits.sharpness,
          min: 0,
          apply: (v) => edits.copyWith(sharpness: v),
        ),
      ],
    );
  }
}
