/// Route paths. Use the helpers to build parameterised locations.
abstract final class Routes {
  static const home = '/';
  static const files = '/files';
  static const search = '/search';
  static const settings = '/settings';
  static const privacy = '/settings/privacy';
  static const about = '/settings/about';
  static const scan = '/scan';

  static String folder(String id) => '/files/folder/$id';

  /// Opens a document, optionally at a one-based [page].
  static String document(String id, {int? page}) =>
      page == null ? '/document/$id' : '/document/$id?page=$page';
}
