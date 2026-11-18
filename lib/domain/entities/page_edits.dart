import '../../core/vision/quad.dart';
import 'scan_page.dart';

/// Every user-editable setting of a page. The processed image is always
/// re-rendered from the untouched original using these values, so edits
/// never degrade quality and can be changed or reverted at any time.
class PageEdits {
  const PageEdits({
    required this.corners,
    this.rotation = 0,
    this.filter = PageFilter.original,
    this.brightness = 0,
    this.contrast = 0,
    this.sharpness = 0,
  });

  /// No crop, no rotation, no adjustments.
  factory PageEdits.initial() => PageEdits(corners: Quad.fullFrame(1, 1));

  /// Reads the stored edits of [page].
  factory PageEdits.fromPage(ScanPage page) => PageEdits(
    corners: page.cropCorners ?? Quad.fullFrame(1, 1),
    rotation: page.rotation,
    filter: page.filter,
    brightness: page.brightness,
    contrast: page.contrast,
    sharpness: page.sharpness,
  );

  /// Crop outline, normalised 0–1 to the original image.
  final Quad corners;

  /// Clockwise rotation applied after cropping: 0, 90, 180 or 270.
  final int rotation;
  final PageFilter filter;

  /// −1 (darker) … +1 (brighter).
  final double brightness;

  /// −1 (flatter) … +1 (punchier).
  final double contrast;

  /// 0 (none) … 1 (strong).
  final double sharpness;

  bool get isFullFrame => corners == Quad.fullFrame(1, 1);

  /// True when rendering would reproduce the original image unchanged.
  bool get isIdentity =>
      isFullFrame &&
      rotation == 0 &&
      filter == PageFilter.original &&
      brightness == 0 &&
      contrast == 0 &&
      sharpness == 0;

  PageEdits copyWith({
    Quad? corners,
    int? rotation,
    PageFilter? filter,
    double? brightness,
    double? contrast,
    double? sharpness,
  }) => PageEdits(
    corners: corners ?? this.corners,
    rotation: rotation ?? this.rotation,
    filter: filter ?? this.filter,
    brightness: brightness ?? this.brightness,
    contrast: contrast ?? this.contrast,
    sharpness: sharpness ?? this.sharpness,
  );

  /// Rotates by a quarter turn; [clockwise] false turns left.
  PageEdits rotated({bool clockwise = true}) =>
      copyWith(rotation: (rotation + (clockwise ? 90 : 270)) % 360);

  @override
  bool operator ==(Object other) =>
      other is PageEdits &&
      other.corners == corners &&
      other.rotation == rotation &&
      other.filter == filter &&
      other.brightness == brightness &&
      other.contrast == contrast &&
      other.sharpness == sharpness;

  @override
  int get hashCode =>
      Object.hash(corners, rotation, filter, brightness, contrast, sharpness);
}

/// Linear undo/redo history.
class EditHistory<T> {
  EditHistory(this.initial, {this.limit = 50}) : _states = [initial];

  /// The state the history started with.
  final T initial;

  /// Maximum number of remembered states (oldest are dropped).
  final int limit;
  final List<T> _states;
  int _index = 0;

  T get current => _states[_index];
  bool get canUndo => _index > 0;
  bool get canRedo => _index < _states.length - 1;

  /// True if [current] differs from [initial].
  bool get isChanged => current != initial;

  /// Records a new state; discards any redo states. Ignores no-op pushes.
  void push(T state) {
    if (state == current) return;
    _states
      ..removeRange(_index + 1, _states.length)
      ..add(state);
    if (_states.length > limit) {
      _states.removeAt(0);
    }
    _index = _states.length - 1;
  }

  /// Replaces the current state without adding a history entry (e.g. while
  /// a slider is being dragged).
  void replace(T state) => _states[_index] = state;

  T undo() {
    if (canUndo) _index--;
    return current;
  }

  T redo() {
    if (canRedo) _index++;
    return current;
  }
}
