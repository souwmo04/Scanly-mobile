import 'dart:io';

import 'package:camera/camera.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';

import '../../core/theme/app_colors.dart';
import '../../core/theme/app_spacing.dart';
import '../../domain/entities/app_settings.dart';
import '../../shared/providers/scanner_providers.dart';
import '../../shared/widgets/dialogs.dart';
import '../settings/settings_controller.dart';

/// A page captured or picked in the camera screen.
class CapturedPage {
  const CapturedPage(
    this.path, {
    required this.isTemporary,
    this.autoCrop = true,
  });

  final String path;

  /// True for camera captures (temporary files we may delete after saving);
  /// false for gallery picks.
  final bool isTemporary;

  /// Detect and flatten the document when saving. False for pages that
  /// Google's scanner already cropped.
  final bool autoCrop;
}

/// Built-in camera with manual capture, flash, camera switching, gallery
/// import and a page counter.
///
/// Used on iOS and as the Android fallback when ML Kit's scanner is not
/// available. Automatic edge detection is layered on in Milestone 3.
class CameraCaptureView extends ConsumerStatefulWidget {
  const CameraCaptureView({
    required this.onFinished,
    required this.onClose,
    super.key,
  });

  /// Called with the captured pages when the user taps Done.
  final ValueChanged<List<CapturedPage>> onFinished;

  /// Called when the user leaves without saving.
  final VoidCallback onClose;

  @override
  ConsumerState<CameraCaptureView> createState() => _CameraCaptureViewState();
}

enum _CameraIssue { permissionDenied, noCamera, failed }

class _CameraCaptureViewState extends ConsumerState<CameraCaptureView>
    with WidgetsBindingObserver {
  List<CameraDescription> _cameras = const [];
  int _cameraIndex = 0;
  CameraController? _controller;
  bool _initializing = true;
  _CameraIssue? _issue;
  FlashMode _flash = FlashMode.off;
  bool _capturing = false;
  bool _shutterFlash = false;
  final List<CapturedPage> _pages = [];

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _openCamera();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _controller?.dispose();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    final controller = _controller;
    // Release the camera in the background so other apps can use it.
    if (state == AppLifecycleState.inactive) {
      if (controller != null && controller.value.isInitialized) {
        _controller = null;
        controller.dispose();
        if (mounted) setState(() => _initializing = true);
      }
    } else if (state == AppLifecycleState.resumed && _controller == null) {
      _openCamera();
    }
  }

  ResolutionPreset get _preset =>
      switch (ref.read(settingsControllerProvider).scanQuality) {
        ScanQuality.standard => ResolutionPreset.high,
        ScanQuality.high => ResolutionPreset.veryHigh,
        ScanQuality.maximum => ResolutionPreset.max,
      };

  Future<void> _openCamera() async {
    setState(() {
      _initializing = true;
      _issue = null;
    });
    try {
      if (_cameras.isEmpty) {
        _cameras = await ref.read(availableCamerasProvider)();
        final back = _cameras.indexWhere(
          (c) => c.lensDirection == CameraLensDirection.back,
        );
        _cameraIndex = back < 0 ? 0 : back;
      }
      if (_cameras.isEmpty) {
        if (mounted) {
          setState(() {
            _issue = _CameraIssue.noCamera;
            _initializing = false;
          });
        }
        return;
      }

      final controller = CameraController(
        _cameras[_cameraIndex],
        _preset,
        enableAudio: false,
        imageFormatGroup: ImageFormatGroup.jpeg,
      );
      await controller.initialize();
      await controller.lockCaptureOrientation(DeviceOrientation.portraitUp);
      try {
        await controller.setFlashMode(_flash);
      } on CameraException {
        // Front cameras often have no flash; keep going without it.
        _flash = FlashMode.off;
      }
      if (!mounted) {
        await controller.dispose();
        return;
      }
      setState(() {
        _controller = controller;
        _initializing = false;
      });
    } on CameraException catch (e) {
      if (!mounted) return;
      setState(() {
        _initializing = false;
        _issue = switch (e.code) {
          'CameraAccessDenied' ||
          'CameraAccessDeniedWithoutPrompt' ||
          'CameraAccessRestricted' => _CameraIssue.permissionDenied,
          _ => _CameraIssue.failed,
        };
      });
    } on Object {
      // Plugin missing or platform error: show the recoverable message.
      if (!mounted) return;
      setState(() {
        _initializing = false;
        _issue = _CameraIssue.failed;
      });
    }
  }

  Future<void> _switchCamera() async {
    if (_cameras.length < 2) return;
    final old = _controller;
    setState(() {
      _controller = null;
      _cameraIndex = (_cameraIndex + 1) % _cameras.length;
    });
    await old?.dispose();
    await _openCamera();
  }

  Future<void> _cycleFlash() async {
    final controller = _controller;
    if (controller == null) return;
    final next = switch (_flash) {
      FlashMode.off => FlashMode.auto,
      FlashMode.auto => FlashMode.always,
      _ => FlashMode.off,
    };
    try {
      await controller.setFlashMode(next);
      setState(() => _flash = next);
    } on CameraException {
      if (mounted) showMessage(context, 'Flash is not available.');
    }
  }

  Future<void> _capture() async {
    final controller = _controller;
    if (controller == null || _capturing || !controller.value.isInitialized) {
      return;
    }
    setState(() => _capturing = true);
    try {
      await HapticFeedback.lightImpact();
      final file = await controller.takePicture();
      if (!mounted) return;
      setState(() {
        _pages.add(CapturedPage(file.path, isTemporary: true));
        _shutterFlash = true;
      });
      await Future<void>.delayed(const Duration(milliseconds: 120));
      if (mounted) setState(() => _shutterFlash = false);
    } on CameraException {
      if (mounted) showMessage(context, 'Could not take the photo. Try again.');
    } finally {
      if (mounted) setState(() => _capturing = false);
    }
  }

  Future<void> _pickFromGallery() async {
    try {
      final paths = await ref.read(galleryPickerProvider).pickImages();
      if (paths.isEmpty || !mounted) return;
      setState(() {
        _pages.addAll(paths.map((p) => CapturedPage(p, isTemporary: false)));
      });
    } on PlatformException {
      if (mounted) showMessage(context, 'Could not open your photos.');
    }
  }

  Future<void> _removeLastPage() async {
    if (_pages.isEmpty) return;
    final removed = _pages.removeLast();
    setState(() {});
    if (removed.isTemporary) {
      try {
        final file = File(removed.path);
        if (file.existsSync()) file.deleteSync();
      } on FileSystemException {
        // Already gone.
      }
    }
  }

  Future<void> _close() async {
    if (_pages.isNotEmpty) {
      final discard = await showConfirmDialog(
        context,
        title: 'Discard ${_pages.length == 1 ? 'page' : 'pages'}?',
        message: 'The pages you captured have not been saved.',
        confirmLabel: 'Discard',
        destructive: true,
      );
      if (!discard) return;
      for (final page in _pages.where((p) => p.isTemporary)) {
        try {
          final file = File(page.path);
          if (file.existsSync()) file.deleteSync();
        } on FileSystemException {
          // Already gone.
        }
      }
    }
    widget.onClose();
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) _close();
      },
      child: Scaffold(
        backgroundColor: Colors.black,
        body: Stack(
          fit: StackFit.expand,
          children: [
            _buildPreview(),
            if (_controller != null) const _FrameGuide(),
            AnimatedOpacity(
              opacity: _shutterFlash ? 0.6 : 0,
              duration: const Duration(milliseconds: 80),
              child: const IgnorePointer(
                child: ColoredBox(color: Colors.white),
              ),
            ),
            SafeArea(
              child: Column(
                children: [
                  _TopBar(
                    pageCount: _pages.length,
                    flash: _flash,
                    canSwitch: _cameras.length > 1 && _controller != null,
                    hasCamera: _controller != null,
                    onClose: _close,
                    onFlash: _cycleFlash,
                    onSwitch: _switchCamera,
                  ),
                  const Spacer(),
                  if (_controller != null && _pages.isEmpty)
                    const _Hint('Fit the document inside the frame'),
                  _BottomBar(
                    pages: _pages,
                    capturing: _capturing,
                    canCapture: _controller != null,
                    onGallery: _pickFromGallery,
                    onCapture: _capture,
                    onUndo: _removeLastPage,
                    onDone: () => widget.onFinished(List.of(_pages)),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildPreview() {
    final controller = _controller;
    if (_issue != null) {
      return _CameraMessage(
        issue: _issue!,
        onRetry: _openCamera,
        onGallery: _pickFromGallery,
      );
    }
    if (_initializing || controller == null) {
      return const Center(
        child: CircularProgressIndicator(color: Colors.white),
      );
    }
    final previewSize = controller.value.previewSize;
    if (previewSize == null) return CameraPreview(controller);
    // previewSize is reported in landscape; fill the portrait screen.
    return ClipRect(
      child: SizedBox.expand(
        child: FittedBox(
          fit: BoxFit.cover,
          child: SizedBox(
            width: previewSize.height,
            height: previewSize.width,
            child: CameraPreview(controller),
          ),
        ),
      ),
    );
  }
}

class _TopBar extends StatelessWidget {
  const _TopBar({
    required this.pageCount,
    required this.flash,
    required this.canSwitch,
    required this.hasCamera,
    required this.onClose,
    required this.onFlash,
    required this.onSwitch,
  });

  final int pageCount;
  final FlashMode flash;
  final bool canSwitch;
  final bool hasCamera;
  final VoidCallback onClose;
  final VoidCallback onFlash;
  final VoidCallback onSwitch;

  @override
  Widget build(BuildContext context) {
    final flashIcon = switch (flash) {
      FlashMode.auto => Icons.flash_auto_rounded,
      FlashMode.always || FlashMode.torch => Icons.flash_on_rounded,
      FlashMode.off => Icons.flash_off_rounded,
    };
    final flashLabel = switch (flash) {
      FlashMode.auto => 'Flash: auto',
      FlashMode.always || FlashMode.torch => 'Flash: on',
      FlashMode.off => 'Flash: off',
    };
    return Padding(
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.sm,
        vertical: AppSpacing.xs,
      ),
      child: Row(
        children: [
          _RoundIconButton(
            icon: Icons.close_rounded,
            tooltip: 'Close scanner',
            onPressed: onClose,
          ),
          const Spacer(),
          if (pageCount > 0)
            Container(
              padding: const EdgeInsets.symmetric(
                horizontal: AppSpacing.md,
                vertical: AppSpacing.xs + 2,
              ),
              decoration: BoxDecoration(
                color: Colors.black.withValues(alpha: 0.55),
                borderRadius: BorderRadius.circular(AppRadius.pill),
              ),
              child: Text(
                pageCount == 1 ? '1 page' : '$pageCount pages',
                style: Theme.of(context).textTheme.labelMedium
                    ?.copyWith(color: Colors.white),
              ),
            ),
          const Spacer(),
          if (hasCamera)
            _RoundIconButton(
              icon: flashIcon,
              tooltip: flashLabel,
              onPressed: onFlash,
            ),
          if (canSwitch) ...[
            const SizedBox(width: AppSpacing.xs),
            _RoundIconButton(
              icon: Icons.cameraswitch_rounded,
              tooltip: 'Switch camera',
              onPressed: onSwitch,
            ),
          ],
        ],
      ),
    );
  }
}

class _BottomBar extends StatelessWidget {
  const _BottomBar({
    required this.pages,
    required this.capturing,
    required this.canCapture,
    required this.onGallery,
    required this.onCapture,
    required this.onUndo,
    required this.onDone,
  });

  final List<CapturedPage> pages;
  final bool capturing;
  final bool canCapture;
  final VoidCallback onGallery;
  final VoidCallback onCapture;
  final VoidCallback onUndo;
  final VoidCallback onDone;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(
        AppSpacing.xl,
        AppSpacing.lg,
        AppSpacing.xl,
        AppSpacing.xl,
      ),
      child: Row(
        children: [
          Expanded(
            child: Align(
              alignment: Alignment.centerLeft,
              child: _RoundIconButton(
                icon: Icons.photo_library_outlined,
                tooltip: 'Import from photos',
                onPressed: onGallery,
                size: 52,
              ),
            ),
          ),
          _ShutterButton(
            enabled: canCapture && !capturing,
            onPressed: onCapture,
          ),
          Expanded(
            child: Align(
              alignment: Alignment.centerRight,
              child: pages.isEmpty
                  ? const SizedBox(width: 52)
                  : _DoneButton(
                      lastPage: pages.last,
                      count: pages.length,
                      onDone: onDone,
                      onUndo: onUndo,
                    ),
            ),
          ),
        ],
      ),
    );
  }
}

class _ShutterButton extends StatelessWidget {
  const _ShutterButton({required this.enabled, required this.onPressed});

  final bool enabled;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      enabled: enabled,
      label: 'Capture page',
      excludeSemantics: true,
      child: GestureDetector(
        onTap: enabled ? onPressed : null,
        child: AnimatedOpacity(
          duration: AppDurations.fast,
          opacity: enabled ? 1 : 0.45,
          child: Container(
            width: 78,
            height: 78,
            padding: const EdgeInsets.all(5),
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              border: Border.all(color: Colors.white, width: 4),
            ),
            child: const DecoratedBox(
              decoration: BoxDecoration(
                color: Colors.white,
                shape: BoxShape.circle,
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _DoneButton extends StatelessWidget {
  const _DoneButton({
    required this.lastPage,
    required this.count,
    required this.onDone,
    required this.onUndo,
  });

  final CapturedPage lastPage;
  final int count;
  final VoidCallback onDone;
  final VoidCallback onUndo;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Semantics(
          button: true,
          label: 'Remove last page',
          excludeSemantics: true,
          child: GestureDetector(
            onTap: onUndo,
            child: Stack(
              clipBehavior: Clip.none,
              children: [
                ClipRRect(
                  borderRadius: AppRadius.smAll,
                  child: Image.file(
                    File(lastPage.path),
                    width: 40,
                    height: 52,
                    fit: BoxFit.cover,
                    cacheWidth: 120,
                    errorBuilder: (_, _, _) =>
                        const SizedBox(width: 40, height: 52),
                  ),
                ),
                Positioned(
                  top: -6,
                  right: -6,
                  child: Container(
                    padding: const EdgeInsets.all(2),
                    decoration: const BoxDecoration(
                      color: Colors.black87,
                      shape: BoxShape.circle,
                    ),
                    child: const Icon(
                      Icons.undo_rounded,
                      size: 14,
                      color: Colors.white,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
        const SizedBox(width: AppSpacing.md),
        FilledButton(
          style: FilledButton.styleFrom(
            backgroundColor: Colors.white,
            foregroundColor: AppColors.navy900,
            minimumSize: const Size(64, 48),
            padding: const EdgeInsets.symmetric(horizontal: AppSpacing.lg),
          ),
          onPressed: onDone,
          child: Text('Done ($count)'),
        ),
      ],
    );
  }
}

class _RoundIconButton extends StatelessWidget {
  const _RoundIconButton({
    required this.icon,
    required this.tooltip,
    required this.onPressed,
    this.size = 44,
  });

  final IconData icon;
  final String tooltip;
  final VoidCallback onPressed;
  final double size;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.black.withValues(alpha: 0.45),
      shape: const CircleBorder(),
      child: IconButton(
        tooltip: tooltip,
        constraints: BoxConstraints.tightFor(width: size, height: size),
        icon: Icon(icon, color: Colors.white),
        onPressed: onPressed,
      ),
    );
  }
}

class _Hint extends StatelessWidget {
  const _Hint(this.text);

  final String text;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.lg,
        vertical: AppSpacing.sm,
      ),
      decoration: BoxDecoration(
        color: Colors.black.withValues(alpha: 0.55),
        borderRadius: BorderRadius.circular(AppRadius.pill),
      ),
      child: Text(
        text,
        style: Theme.of(context).textTheme.labelMedium
            ?.copyWith(color: Colors.white),
      ),
    );
  }
}

/// Static A4-proportioned guide. Replaced by live edge detection in M3.
class _FrameGuide extends StatelessWidget {
  const _FrameGuide();

  @override
  Widget build(BuildContext context) {
    return const IgnorePointer(
      child: Center(
        child: FractionallySizedBox(
          widthFactor: 0.82,
          child: AspectRatio(
            aspectRatio: 1 / 1.414,
            child: CustomPaint(painter: _CornerPainter()),
          ),
        ),
      ),
    );
  }
}

class _CornerPainter extends CustomPainter {
  const _CornerPainter();

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = Colors.white.withValues(alpha: 0.9)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 3
      ..strokeCap = StrokeCap.round;
    const len = 28.0;
    final w = size.width;
    final h = size.height;
    for (final (x, y, dx, dy) in [
      (0.0, 0.0, 1.0, 1.0),
      (w, 0.0, -1.0, 1.0),
      (0.0, h, 1.0, -1.0),
      (w, h, -1.0, -1.0),
    ]) {
      canvas.drawPath(
        Path()
          ..moveTo(x, y + dy * len)
          ..lineTo(x, y)
          ..lineTo(x + dx * len, y),
        paint,
      );
    }
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}

class _CameraMessage extends StatelessWidget {
  const _CameraMessage({
    required this.issue,
    required this.onRetry,
    required this.onGallery,
  });

  final _CameraIssue issue;
  final VoidCallback onRetry;
  final VoidCallback onGallery;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final (title, message) = switch (issue) {
      _CameraIssue.permissionDenied => (
        'Camera access is off',
        'Scanly needs the camera to scan documents. Allow camera access for '
            'Scanly in your phone\'s Settings, then try again. You can also '
            'import photos instead.',
      ),
      _CameraIssue.noCamera => (
        'No camera found',
        'This device has no camera available. You can still import photos '
            'of documents.',
      ),
      _CameraIssue.failed => (
        'Camera could not start',
        'Another app may be using the camera. Close it and try again.',
      ),
    };
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.xxxl),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(
              Icons.no_photography_outlined,
              color: Colors.white70,
              size: 48,
            ),
            const SizedBox(height: AppSpacing.lg),
            Text(
              title,
              style: theme.textTheme.titleLarge?.copyWith(color: Colors.white),
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
            Wrap(
              spacing: AppSpacing.md,
              runSpacing: AppSpacing.md,
              alignment: WrapAlignment.center,
              children: [
                if (issue != _CameraIssue.noCamera)
                  FilledButton(
                    style: FilledButton.styleFrom(
                      backgroundColor: Colors.white,
                      foregroundColor: AppColors.navy900,
                    ),
                    onPressed: onRetry,
                    child: const Text('Try again'),
                  ),
                OutlinedButton(
                  style: OutlinedButton.styleFrom(
                    foregroundColor: Colors.white,
                    side: const BorderSide(color: Colors.white54),
                  ),
                  onPressed: onGallery,
                  child: const Text('Import photos'),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
