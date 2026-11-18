import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/services/system_share_service.dart';
import '../../domain/services/pdf_service.dart';

/// System share sheet and print dialog.
final shareServiceProvider = Provider<ShareService>(
  (ref) => const SystemShareService(),
);
