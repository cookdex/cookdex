#pragma once

#include <flutter/encodable_value.h>
#include <windows.h>
#include <cstdint>
#include <functional>
#include <string>
#include <vector>

struct CreatePhotoSelection {
  std::vector<std::wstring> paths;
  std::vector<uint8_t> camera_bmp;
  bool skipped_extra = false;
};

// The owned native dialogs run on the platform thread. Conversion runs on an MTA worker.
CreatePhotoSelection ChooseCreatePhotos(HWND owner, bool camera, int limit);
flutter::EncodableValue PrepareCreatePhotos(
    const CreatePhotoSelection& selection, const std::function<bool()>& cancelled);
