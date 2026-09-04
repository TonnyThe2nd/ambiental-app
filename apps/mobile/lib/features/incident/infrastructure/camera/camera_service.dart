import 'package:image_picker/image_picker.dart';

abstract class CameraService {
  Future<String?> capturePhoto();
}

class ImagePickerCameraService implements CameraService {
  final ImagePicker _picker = ImagePicker();
  @override
  Future<String?> capturePhoto() async {
    final photo = await _picker.pickImage(
      source: ImageSource.camera,
      imageQuality: 85,
      maxWidth: 1920,
    );
    return photo?.path;
  }
}
