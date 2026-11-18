/// Base class for errors Scanly shows to users.
///
/// [message] is user-facing; [cause] keeps the original error for debugging.
sealed class AppException implements Exception {
  const AppException(this.message, [this.cause]);

  final String message;
  final Object? cause;

  @override
  String toString() => cause == null ? message : '$message (caused by: $cause)';
}

class StorageException extends AppException {
  const StorageException(super.message, [super.cause]);
}

class DatabaseException extends AppException {
  const DatabaseException(super.message, [super.cause]);
}

class NotFoundException extends AppException {
  const NotFoundException(super.message, [super.cause]);
}

class ValidationException extends AppException {
  const ValidationException(super.message, [super.cause]);
}

/// Converts any error into a short message safe to show in the UI.
String describeError(Object error) {
  if (error is AppException) return error.message;
  return 'Something went wrong. Please try again.';
}
