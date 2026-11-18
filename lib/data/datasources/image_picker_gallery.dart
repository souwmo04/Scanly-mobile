import 'package:image_picker/image_picker.dart';

import '../../domain/services/document_scanner.dart';

/// Gallery import through the system photo picker. On Android 13+ this uses
/// the Photo Picker, which needs no storage permission.
class ImagePickerGallery implements GalleryPicker {
  ImagePickerGallery([ImagePicker? picker]) : _picker = picker ?? ImagePicker();

  final ImagePicker _picker;

  @override
  Future<List<String>> pickImages() async {
    // requestFullMetadata: false avoids asking for extra photo permissions
    // on iOS; Scanly doesn't need location or other EXIF metadata.
    final files = await _picker.pickMultiImage(requestFullMetadata: false);
    return files.map((f) => f.path).toList();
  }
}
