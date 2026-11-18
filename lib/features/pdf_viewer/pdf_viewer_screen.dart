import 'dart:async';
import 'dart:math' as math;

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:material_ui/material_ui.dart';

import '../../core/errors/app_exception.dart';
import '../../core/routing/routes.dart';
import '../../core/theme/app_spacing.dart';
import '../../core/utils/formatters.dart';
import '../../domain/services/pdf_service.dart';
import '../../shared/providers/core_providers.dart';
import '../../shared/providers/pdf_providers.dart';
import '../../shared/providers/share_providers.dart';
import '../../shared/widgets/dialogs.dart';
import '../../shared/widgets/state_views.dart';
import '../settings/settings_controller.dart';
import 'pdf_actions.dart';
import 'pdf_export_sheet.dart';
import 'pdf_labels.dart';
import 'pdf_page_renderer.dart';

/// Shows a document's generated PDF, one page at a time, with sharing,
/// printing and export.
///
/// Pages are rasterized lazily: only the visible page and its neighbours are
/// rendered, at about the screen's resolution, and only a few are kept.
class PdfViewerScreen extends ConsumerStatefulWidget {
  const PdfViewerScreen({
    required this.documentId,
    this.initialPage,
    super.key,
  });

  final String documentId;

  /// One-based page to open at.
  final int? initialPage;

  @override
  ConsumerState<PdfViewerScreen> createState() => _PdfViewerScreenState();
}

/// Pages kept in memory besides the visible one.
const _cacheSize = 5;

/// Pages on each side of the visible one that are rendered ahead.
const _prefetch = 1;

class _PdfViewerScreenState extends ConsumerState<PdfViewerScreen> {
  /// Incremented on every (re)load so stale results are ignored.
  int _generation = 0;

  // Loading phase.
  bool _loading = true;
  TaskProgress? _progress;
  Object? _error;

  // Ready phase.
  String? _path;
  String _title = 'PDF';
  int _pageCount = 0;
  OpenedPdf? _pdf;
  bool _canRender = false;
  PageController? _controller;
  late int _index = math.max(0, (widget.initialPage ?? 1) - 1);

  // Lazy page rendering.
  // Map literals keep insertion order, which the eviction relies on.
  final _rendered = <int, RenderedPdfPage>{};
  final _pending = <int>{};
  final _failed = <int>{};
  Future<void> _renderQueue = Future.value();

  @override
  void initState() {
    super.initState();
    unawaited(_load());
  }

  @override
  void dispose() {
    _generation++;
    _controller?.dispose();
    _pdf?.dispose();
    super.dispose();
  }

  void _resetDocument() {
    _controller?.dispose();
    _controller = null;
    _pdf?.dispose();
    _pdf = null;
    _path = null;
    _rendered.clear();
    _pending.clear();
    _failed.clear();
  }

  /// Creates (or reuses) the PDF and opens it. With [shareAfter], the share
  /// sheet opens once the file is ready.
  Future<void> _load({
    PdfExportOptions? options,
    bool force = false,
    bool shareAfter = false,
  }) async {
    final generation = ++_generation;
    bool isCurrent() => mounted && generation == _generation;

    void reset() {
      _resetDocument();
      _loading = true;
      _progress = null;
      _error = null;
    }

    // The first load starts from initState, where setState is not allowed.
    generation == 1 ? reset() : setState(reset);

    final service = ref.read(documentPdfServiceProvider);
    final repo = ref.read(documentRepositoryProvider);
    final renderer = ref.read(pdfPageRendererProvider);
    try {
      final path = await service.ensurePdf(
        widget.documentId,
        options: options,
        force: force,
        onProgress: (done, total) {
          if (isCurrent()) {
            setState(() => _progress = (done: done, total: total));
          }
        },
      );
      final document = await repo.getDocument(widget.documentId);
      if (document == null) {
        throw const NotFoundException('This document no longer exists.');
      }
      final canRender = await renderer.isAvailable();
      final pdf = await renderer.open(path);
      if (!isCurrent()) {
        pdf.dispose();
        return;
      }
      final pageCount = document.pageCount;
      setState(() {
        _loading = false;
        _path = path;
        _title = document.title;
        _pageCount = pageCount;
        _pdf = pdf;
        _canRender = canRender;
        _index = pageCount == 0 ? 0 : _index.clamp(0, pageCount - 1);
        _controller = PageController(initialPage: _index);
      });
      if (canRender) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (isCurrent()) _requestAround(_index);
        });
      }
      if (shareAfter && mounted) await _share();
    } on Object catch (error) {
      if (isCurrent()) {
        setState(() {
          _loading = false;
          _error = error;
        });
      }
    }
  }

  // ---------------------------------------------------------------------------
  // Rendering

  int get _targetWidth {
    final media = MediaQuery.of(context);
    // 1.5x the screen width leaves some headroom for zooming in.
    return (media.size.width * media.devicePixelRatio * 1.5).round().clamp(
      400,
      2400,
    );
  }

  void _requestAround(int index) {
    if (!_canRender || _pdf == null) return;
    final width = _targetWidth;
    _render(index, width);
    for (var d = 1; d <= _prefetch; d++) {
      _render(index + d, width);
      _render(index - d, width);
    }
  }

  void _render(int index, int width) {
    final pdf = _pdf;
    if (pdf == null || index < 0 || index >= _pageCount) return;
    if (_rendered.containsKey(index) || _pending.contains(index)) return;
    _pending.add(index);
    _failed.remove(index);
    // One page at a time: the platform renderers are not built for parallel
    // work and every page holds a full bitmap.
    _renderQueue = _renderQueue.then((_) async {
      if (!mounted || _pdf != pdf) return;
      if ((index - _index).abs() > _prefetch) {
        _pending.remove(index);
        return;
      }
      try {
        final page = await pdf.renderPage(index, targetWidth: width);
        if (!mounted || _pdf != pdf) return;
        setState(() {
          _pending.remove(index);
          _rendered[index] = page;
          _evict();
        });
      } on Object {
        if (!mounted || _pdf != pdf) return;
        setState(() {
          _pending.remove(index);
          _failed.add(index);
        });
      }
    });
  }

  /// Drops the least recently rendered pages, keeping the visible one.
  void _evict() {
    while (_rendered.length > _cacheSize) {
      final victim = _rendered.keys.firstWhere(
        (i) => (i - _index).abs() > _prefetch,
        orElse: () => -1,
      );
      if (victim < 0) return;
      _rendered.remove(victim);
    }
  }

  void _onPageChanged(int index) {
    setState(() => _index = index);
    _requestAround(index);
  }

  // ---------------------------------------------------------------------------
  // Navigation

  void _goTo(int index) {
    final controller = _controller;
    if (controller == null || index < 0 || index >= _pageCount) return;
    if ((index - _index).abs() > 1) {
      controller.jumpToPage(index);
    } else {
      unawaited(
        controller.animateToPage(
          index,
          duration: AppDurations.medium,
          curve: Curves.easeOut,
        ),
      );
    }
  }

  /// Searches the document's recognised text and shows the chosen page.
  Future<void> _searchText() async {
    final index = await context.push<int>(
      Routes.documentSearch(widget.documentId),
    );
    if (index != null && mounted) _goTo(index);
  }

  Future<void> _jumpToPage() async {
    final page = await showDialog<int>(
      context: context,
      builder: (context) =>
          _JumpToPageDialog(pageCount: _pageCount, current: _index + 1),
    );
    if (page != null) _goTo(page - 1);
  }

  // ---------------------------------------------------------------------------
  // Actions

  Future<void> _share() async {
    final path = _path;
    if (path == null) return;
    await shareFileSafely(
      context,
      ref.read(shareServiceProvider),
      path,
      _title,
    );
  }

  Future<void> _print() async {
    final path = _path;
    if (path == null) return;
    await printFileSafely(
      context,
      ref.read(shareServiceProvider),
      path,
      _title,
    );
  }

  Future<void> _export() async {
    final defaults = PdfExportOptions.fromSettings(
      ref.read(settingsControllerProvider),
    );
    final options = await showPdfExportSheet(context, initial: defaults);
    if (options == null || !mounted) return;
    await _load(options: options, force: true, shareAfter: true);
    if (mounted && _error != null) {
      showMessage(context, 'Export failed. ${describeError(_error!)}');
    }
  }

  // ---------------------------------------------------------------------------
  // UI

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final ready = !_loading && _error == null && _path != null;
    final pdf = _pdf;

    return Scaffold(
      appBar: AppBar(
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(_title, maxLines: 1, overflow: TextOverflow.ellipsis),
            if (ready && pdf != null)
              Text(
                '${pluralPages(_pageCount)} · PDF ${formatBytes(pdf.sizeBytes)}',
                style: theme.textTheme.bodySmall,
              ),
          ],
        ),
        actions: [
          IconButton(
            tooltip: 'Search text',
            icon: const Icon(Icons.search_rounded),
            onPressed: ready && _pageCount > 0 ? _searchText : null,
          ),
          IconButton(
            tooltip: 'Share',
            icon: const Icon(Icons.ios_share_rounded),
            onPressed: ready ? _share : null,
          ),
          IconButton(
            tooltip: 'Print',
            icon: const Icon(Icons.print_outlined),
            onPressed: ready ? _print : null,
          ),
          IconButton(
            tooltip: 'Export',
            icon: const Icon(Icons.save_alt_rounded),
            onPressed: ready ? _export : null,
          ),
        ],
      ),
      body: _buildBody(theme),
    );
  }

  Widget _buildBody(ThemeData theme) {
    if (_loading) return _CreatingPdf(progress: _progress);
    final error = _error;
    if (error != null) {
      return ErrorState(error: error, onRetry: () => unawaited(_load()));
    }
    final pdf = _pdf;
    if (pdf == null) return const LoadingState();
    if (_pageCount == 0) {
      return const EmptyState(
        icon: Icons.picture_as_pdf_outlined,
        title: 'No pages',
        message: 'This document has no pages to show.',
      );
    }
    if (!_canRender) {
      return EmptyState(
        icon: Icons.picture_as_pdf_outlined,
        title: 'Preview not available',
        message:
            'This device cannot display PDF pages here. The PDF is ready '
            '(${formatBytes(pdf.sizeBytes)}) and you can still share, print '
            'or export it.',
        actionLabel: 'Share PDF',
        onAction: _share,
      );
    }

    return Column(
      children: [
        Expanded(
          child: PageView.builder(
            controller: _controller,
            itemCount: _pageCount,
            onPageChanged: _onPageChanged,
            itemBuilder: (context, i) => _PdfPageView(
              number: i + 1,
              page: _rendered[i],
              failed: _failed.contains(i),
              onRetry: () => _render(i, _targetWidth),
            ),
          ),
        ),
        SafeArea(
          top: false,
          child: Padding(
            padding: const EdgeInsets.symmetric(
              horizontal: AppSpacing.sm,
              vertical: AppSpacing.xs,
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                IconButton(
                  tooltip: 'Previous page',
                  icon: const Icon(Icons.chevron_left_rounded),
                  onPressed: _index > 0 ? () => _goTo(_index - 1) : null,
                ),
                Tooltip(
                  message: 'Go to page',
                  child: TextButton(
                    onPressed: _pageCount > 1 ? _jumpToPage : null,
                    child: Text('Page ${_index + 1} of $_pageCount'),
                  ),
                ),
                IconButton(
                  tooltip: 'Next page',
                  icon: const Icon(Icons.chevron_right_rounded),
                  onPressed: _index < _pageCount - 1
                      ? () => _goTo(_index + 1)
                      : null,
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}

class _CreatingPdf extends StatelessWidget {
  const _CreatingPdf({required this.progress});

  final TaskProgress? progress;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final value = progress;
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.xxxl),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 280),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              LinearProgressIndicator(
                value: value == null || value.total <= 0
                    ? null
                    : value.done / value.total,
                borderRadius: AppRadius.smAll,
              ),
              const SizedBox(height: AppSpacing.lg),
              Text(
                value == null
                    ? 'Creating PDF…'
                    : pdfProgressLabel(value.done, value.total),
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
                textAlign: TextAlign.center,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _PdfPageView extends StatelessWidget {
  const _PdfPageView({
    required this.number,
    required this.page,
    required this.failed,
    required this.onRetry,
  });

  final int number;
  final RenderedPdfPage? page;
  final bool failed;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final rendered = page;

    final Widget content;
    if (rendered != null) {
      content = Image(
        image: rendered.image,
        fit: BoxFit.contain,
        gaplessPlayback: true,
        filterQuality: FilterQuality.medium,
      );
    } else if (failed) {
      content = Center(
        child: TextButton.icon(
          onPressed: onRetry,
          icon: const Icon(Icons.refresh_rounded),
          label: const Text('Page could not be shown. Retry'),
        ),
      );
    } else {
      content = const Center(
        child: SizedBox.square(
          dimension: 24,
          child: CircularProgressIndicator(strokeWidth: 2.4),
        ),
      );
    }

    return Semantics(
      label: 'Page $number',
      child: InteractiveViewer(
        maxScale: 5,
        child: Padding(
          padding: const EdgeInsets.all(AppSpacing.lg),
          child: Center(
            child: AspectRatio(
              // A4 until the real page size is known.
              aspectRatio: rendered?.aspectRatio ?? 1 / math.sqrt2,
              child: DecoratedBox(
                decoration: BoxDecoration(
                  color: Colors.white,
                  boxShadow: [
                    BoxShadow(
                      color: scheme.shadow.withValues(alpha: 0.12),
                      blurRadius: 16,
                      offset: const Offset(0, 4),
                    ),
                  ],
                ),
                child: content,
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _JumpToPageDialog extends StatefulWidget {
  const _JumpToPageDialog({required this.pageCount, required this.current});

  final int pageCount;
  final int current;

  @override
  State<_JumpToPageDialog> createState() => _JumpToPageDialogState();
}

class _JumpToPageDialogState extends State<_JumpToPageDialog> {
  late final _controller = TextEditingController(text: '${widget.current}')
    ..selection = TextSelection(
      baseOffset: 0,
      extentOffset: '${widget.current}'.length,
    );

  int? get _value {
    final page = int.tryParse(_controller.text.trim());
    if (page == null || page < 1 || page > widget.pageCount) return null;
    return page;
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _submit() {
    final page = _value;
    if (page != null) Navigator.of(context).pop(page);
  }

  @override
  Widget build(BuildContext context) {
    final invalid = _controller.text.trim().isNotEmpty && _value == null;
    return AlertDialog(
      title: const Text('Go to page'),
      content: TextField(
        controller: _controller,
        autofocus: true,
        keyboardType: TextInputType.number,
        textInputAction: TextInputAction.go,
        decoration: InputDecoration(
          hintText: '1–${widget.pageCount}',
          errorText: invalid
              ? 'Enter a page from 1 to ${widget.pageCount}'
              : null,
        ),
        onChanged: (_) => setState(() {}),
        onSubmitted: (_) => _submit(),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: _value == null ? null : _submit,
          child: const Text('Go'),
        ),
      ],
    );
  }
}
