/// Route paths. Use the helpers to build parameterised locations.
abstract final class Routes {
  static const home = '/';
  static const files = '/files';
  static const search = '/search';
  static const settings = '/settings';
  static const privacy = '/settings/privacy';
  static const about = '/settings/about';
  static const scan = '/scan';

  /// Opens the scanner straight in Scanly's built-in camera.
  static const scanWithCamera = '/scan?camera=1';

  static String folder(String id) => '/files/folder/$id';

  /// Page organizer of a document.
  static String pages(String documentId) => '/document/$documentId/pages';

  /// Editor for one page.
  static String editPage(String documentId, String pageId) =>
      '/document/$documentId/page/$pageId/edit';

  /// PDF viewer of a document, optionally at a one-based [page].
  static String pdf(String documentId, {int? page}) => page == null
      ? '/document/$documentId/pdf'
      : '/document/$documentId/pdf?page=$page';

  /// Scanner that appends new pages to [documentId].
  static String scanAppend(String documentId) => '/scan?append=$documentId';

  /// Scanner that replaces the image of [pageId] (retake).
  static String scanRetake(String pageId) => '/scan?retake=$pageId';

  /// Opens a document, optionally at a one-based [page].
  static String document(String id, {int? page}) =>
      page == null ? '/document/$id' : '/document/$id?page=$page';
}
