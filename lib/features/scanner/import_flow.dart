import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:material_ui/material_ui.dart';

import '../../core/errors/app_exception.dart';
import '../../core/routing/routes.dart';
import '../../core/theme/app_spacing.dart';
import '../../core/utils/formatters.dart';
import '../../shared/providers/scanner_providers.dart';
import '../../shared/widgets/dialogs.dart';

/// Lets the user pick images from their photo library, saves them as one
/// document and opens it.
Future<void> importImagesFromGallery(
  BuildContext context,
  WidgetRef ref, {
  String? folderId,
}) async {
  final List<String> paths;
  try {
    paths = await ref.read(galleryPickerProvider).pickImages();
  } on PlatformException {
    if (context.mounted) showMessage(context, 'Could not open your photos.');
    return;
  }
  if (paths.isEmpty || !context.mounted) return;

  final progress = ValueNotifier<int>(0);
  final navigator = Navigator.of(context, rootNavigator: true);
  _showProgressDialog(context, progress, paths.length);

  try {
    final id = await ref
        .read(importPagesProvider)
        .call(
          paths,
          title: defaultImportTitle(DateTime.now()),
          folderId: folderId,
          onProgress: (done, _) => progress.value = done,
        );
    navigator.pop();
    if (context.mounted) await context.push(Routes.document(id));
  } on Object catch (error) {
    navigator.pop();
    if (context.mounted) showMessage(context, describeError(error));
  } finally {
    progress.dispose();
  }
}

/// Shows a non-dismissible progress dialog without awaiting it. The caller
/// closes it with the root navigator.
void _showProgressDialog(
  BuildContext context,
  ValueNotifier<int> progress,
  int total,
) {
  showDialog<void>(
    context: context,
    barrierDismissible: false,
    useRootNavigator: true,
    builder: (context) => PopScope(
      canPop: false,
      child: AlertDialog(
        content: ValueListenableBuilder<int>(
          valueListenable: progress,
          builder: (context, done, _) => Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              LinearProgressIndicator(value: total == 0 ? null : done / total),
              const SizedBox(height: AppSpacing.lg),
              Text(
                total == 1
                    ? 'Importing image…'
                    : 'Importing ${(done + 1).clamp(1, total)} of $total…',
              ),
            ],
          ),
        ),
      ),
    ),
  );
}
