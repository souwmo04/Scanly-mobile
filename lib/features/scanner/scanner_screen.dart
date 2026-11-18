import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:material_ui/material_ui.dart';

import '../../core/errors/app_exception.dart';
import '../../core/routing/routes.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/app_spacing.dart';
import '../../core/utils/formatters.dart';
import '../../domain/entities/app_settings.dart';
import '../../domain/services/document_scanner.dart';
import '../../shared/providers/scanner_providers.dart';
import '../../shared/widgets/dialogs.dart';
import '../settings/settings_controller.dart';
import 'camera_capture_view.dart';

enum _Phase { launching, camera, saving, failed }

/// Full-screen scanning flow.
///
/// 1. On Android, opens Google's ML Kit Document Scanner (edge detection,
///    auto-capture, crop, multi-page and gallery import built in).
/// 2. If ML Kit is unavailable, or on iOS, shows Scanly's own camera.
/// 3. Saves the pages as a new document and opens it.
class ScannerScreen extends ConsumerStatefulWidget {
  const ScannerScreen({this.forceCamera = false, super.key});

  /// Skip ML Kit and open the built-in camera directly.
  final bool forceCamera;

  @override
  ConsumerState<ScannerScreen> createState() => _ScannerScreenState();
}

class _ScannerScreenState extends ConsumerState<ScannerScreen> {
  _Phase _phase = _Phase.launching;
  int _saved = 0;
  int _total = 0;
  Object? _error;
  List<CapturedPage> _pending = const [];

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _start());
  }

  Future<void> _start() async {
    final scanner = ref.read(documentScannerProvider);
    final engine = ref.read(settingsControllerProvider).scannerEngine;
    if (widget.forceCamera ||
        engine == ScannerEngine.builtInCamera ||
        !scanner.isSupported) {
      setState(() => _phase = _Phase.camera);
      return;
    }
    final result = await scanner.scan(
      pageLimit: maxPagesPerScan,
      allowGalleryImport: true,
    );
    if (!mounted) return;
    switch (result.status) {
      case ScanStatus.completed:
        await _save([
          for (final path in result.imagePaths)
            CapturedPage(path, isTemporary: true),
        ]);
      case ScanStatus.cancelled:
        // Google's scanner reports a failed first-time module download the
        // same way as a normal cancel, so always offer a way forward.
        final messenger = ScaffoldMessenger.of(context);
        final router = GoRouter.of(context);
        context.pop();
        messenger
          ..hideCurrentSnackBar()
          ..showSnackBar(
            SnackBar(
              content: const Text('Scan cancelled'),
              action: SnackBarAction(
                label: 'Use camera',
                onPressed: () => router.push(Routes.scanWithCamera),
              ),
            ),
          );
      case ScanStatus.unavailable:
        setState(() => _phase = _Phase.camera);
        showMessage(
          context,
          'Google\'s scanner is not available on this device. '
          'Using the built-in camera.',
        );
    }
  }

  Future<void> _save(List<CapturedPage> pages) async {
    if (pages.isEmpty) {
      context.pop();
      return;
    }
    setState(() {
      _phase = _Phase.saving;
      _pending = pages;
      _saved = 0;
      _total = pages.length;
      _error = null;
    });
    try {
      final id = await ref
          .read(importPagesProvider)
          .call(
            pages.map((p) => p.path).toList(),
            title: defaultScanTitle(DateTime.now()),
            onProgress: (done, total) {
              if (mounted) setState(() => _saved = done);
            },
          );
      _deleteTemporary(pages);
      if (!mounted) return;
      context.pushReplacement(Routes.document(id));
    } on Object catch (error) {
      if (!mounted) return;
      setState(() {
        _phase = _Phase.failed;
        _error = error;
      });
    }
  }

  /// Removes scanner/camera temp files once they are no longer needed.
  /// Synchronous on purpose: a few small cache files, and the result must not
  /// depend on the app staying alive for another async hop.
  void _deleteTemporary(List<CapturedPage> pages) {
    for (final page in pages.where((p) => p.isTemporary)) {
      try {
        final file = File(page.path);
        if (file.existsSync()) file.deleteSync();
      } on FileSystemException {
        // Locked or already removed; the OS clears the cache eventually.
      }
    }
  }

  void _discardAndClose() {
    _deleteTemporary(_pending);
    if (mounted) context.pop();
  }

  @override
  Widget build(BuildContext context) {
    return switch (_phase) {
      _Phase.camera => CameraCaptureView(
        onFinished: _save,
        onClose: () => context.pop(),
      ),
      _Phase.launching => const _DarkStatus(
        message: 'Opening scanner…',
        showSpinner: true,
      ),
      _Phase.saving => _DarkStatus(
        message: _total <= 1
            ? 'Saving page…'
            : 'Saving page ${(_saved + 1).clamp(1, _total)} of $_total…',
        progress: _total == 0 ? null : _saved / _total,
      ),
      _Phase.failed => _SaveFailed(
        message: describeError(_error ?? 'Unknown error'),
        onRetry: () => _save(_pending),
        onDiscard: _discardAndClose,
      ),
    };
  }
}

class _DarkStatus extends StatelessWidget {
  const _DarkStatus({
    required this.message,
    this.progress,
    this.showSpinner = false,
  });

  final String message;
  final double? progress;
  final bool showSpinner;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return PopScope(
      canPop: false,
      child: Scaffold(
        backgroundColor: AppColors.navy950,
        body: Center(
          child: Padding(
            padding: const EdgeInsets.all(AppSpacing.xxxl),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (showSpinner || progress == null)
                  const CircularProgressIndicator(color: Colors.white)
                else
                  SizedBox(
                    width: 200,
                    child: LinearProgressIndicator(
                      value: progress,
                      color: Colors.white,
                      backgroundColor: Colors.white24,
                      borderRadius: BorderRadius.circular(AppRadius.pill),
                    ),
                  ),
                const SizedBox(height: AppSpacing.xl),
                Text(
                  message,
                  style: theme.textTheme.titleMedium?.copyWith(
                    color: Colors.white,
                  ),
                  textAlign: TextAlign.center,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _SaveFailed extends StatelessWidget {
  const _SaveFailed({
    required this.message,
    required this.onRetry,
    required this.onDiscard,
  });

  final String message;
  final VoidCallback onRetry;
  final VoidCallback onDiscard;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      backgroundColor: AppColors.navy950,
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(AppSpacing.xxxl),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(
                Icons.error_outline_rounded,
                color: Colors.white70,
                size: 48,
              ),
              const SizedBox(height: AppSpacing.lg),
              Text(
                'The scan could not be saved',
                style: theme.textTheme.titleLarge?.copyWith(
                  color: Colors.white,
                ),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: AppSpacing.sm),
              Text(
                message,
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: Colors.white70,
                ),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: AppSpacing.xl),
              FilledButton(
                style: FilledButton.styleFrom(
                  backgroundColor: Colors.white,
                  foregroundColor: AppColors.navy900,
                ),
                onPressed: onRetry,
                child: const Text('Try again'),
              ),
              const SizedBox(height: AppSpacing.sm),
              TextButton(
                style: TextButton.styleFrom(foregroundColor: Colors.white70),
                onPressed: onDiscard,
                child: const Text('Discard scan'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
