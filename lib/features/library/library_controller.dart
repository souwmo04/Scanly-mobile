import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../domain/repositories/document_repository.dart';
import '../../shared/providers/core_providers.dart';

enum LibraryLayout { grid, list }

/// How the library is displayed. Persisted so it survives restarts.
class LibraryViewState {
  const LibraryViewState({
    this.layout = LibraryLayout.grid,
    this.sort = DocumentSort.updatedNewest,
  });

  final LibraryLayout layout;
  final DocumentSort sort;

  LibraryViewState copyWith({LibraryLayout? layout, DocumentSort? sort}) =>
      LibraryViewState(layout: layout ?? this.layout, sort: sort ?? this.sort);
}

class LibraryViewController extends Notifier<LibraryViewState> {
  static const _layoutKey = 'library.layout';
  static const _sortKey = 'library.sort';

  @override
  LibraryViewState build() {
    final prefs = ref.watch(sharedPreferencesProvider);
    return LibraryViewState(
      layout:
          LibraryLayout.values.asNameMap()[prefs.getString(_layoutKey)] ??
          LibraryLayout.grid,
      sort:
          DocumentSort.values.asNameMap()[prefs.getString(_sortKey)] ??
          DocumentSort.updatedNewest,
    );
  }

  Future<void> setLayout(LibraryLayout layout) async {
    state = state.copyWith(layout: layout);
    await ref
        .read(sharedPreferencesProvider)
        .setString(_layoutKey, layout.name);
  }

  Future<void> setSort(DocumentSort sort) async {
    state = state.copyWith(sort: sort);
    await ref.read(sharedPreferencesProvider).setString(_sortKey, sort.name);
  }
}

final libraryViewProvider =
    NotifierProvider<LibraryViewController, LibraryViewState>(
      LibraryViewController.new,
    );

String sortLabel(DocumentSort sort) => switch (sort) {
  DocumentSort.updatedNewest => 'Last modified',
  DocumentSort.createdNewest => 'Newest first',
  DocumentSort.createdOldest => 'Oldest first',
  DocumentSort.titleAZ => 'Name (A–Z)',
  DocumentSort.sizeLargest => 'Largest first',
};
