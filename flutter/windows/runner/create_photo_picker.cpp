#include "create_photo_picker.h"

#include <dshow.h>
#include <d3d9.h>
#include <vmr9.h>
#include <shobjidl.h>
#include <winrt/Windows.Foundation.h>
#include <winrt/Windows.Graphics.Imaging.h>
#include <winrt/Windows.Storage.h>
#include <winrt/Windows.Storage.Streams.h>

#include <algorithm>
#include <cstring>
#include <cstdlib>
#include <memory>
#include <stdexcept>

namespace {
using namespace winrt;
using namespace winrt::Windows::Graphics::Imaging;
using namespace winrt::Windows::Storage;
using namespace winrt::Windows::Storage::Streams;
using Value = flutter::EncodableValue;
constexpr uint64_t kMaxBytes = 25ULL * 1024 * 1024;
constexpr uint64_t kMaxPixels = 80000000;
constexpr uint32_t kLongestEdge = 2000;
constexpr int kCameraDialog = 8800;

CreatePhotoSelection ChooseFiles(HWND owner, int limit) {
  com_ptr<IFileOpenDialog> dialog;
  check_hresult(CoCreateInstance(CLSID_FileOpenDialog, nullptr, CLSCTX_INPROC_SERVER,
                                IID_PPV_ARGS(dialog.put())));
  DWORD options{};
  check_hresult(dialog->GetOptions(&options));
  check_hresult(dialog->SetOptions(options | FOS_FORCEFILESYSTEM | FOS_FILEMUSTEXIST |
                                   FOS_ALLOWMULTISELECT | FOS_NOCHANGEDIR | FOS_DONTADDTORECENT));
  const COMDLG_FILTERSPEC filter{L"Photos", L"*.jpg;*.jpeg;*.png;*.heic;*.heif;*.webp;*.bmp;*.tif;*.tiff"};
  check_hresult(dialog->SetFileTypes(1, &filter));
  check_hresult(dialog->SetTitle(L"Choose kitchen photos"));
  const HRESULT shown = dialog->Show(owner);
  if (shown == HRESULT_FROM_WIN32(ERROR_CANCELLED)) return {};
  check_hresult(shown);
  com_ptr<IShellItemArray> items;
  check_hresult(dialog->GetResults(items.put()));
  DWORD count{};
  check_hresult(items->GetCount(&count));
  CreatePhotoSelection selected;
  const auto accepted = std::min(count, static_cast<DWORD>(limit));
  selected.skipped_extra = accepted < count;
  for (DWORD i = 0; i < accepted; ++i) {
    com_ptr<IShellItem> item;
    check_hresult(items->GetItemAt(i, item.put()));
    PWSTR raw{};
    check_hresult(item->GetDisplayName(SIGDN_FILESYSPATH, &raw));
    std::unique_ptr<wchar_t, decltype(&CoTaskMemFree)> path(raw, CoTaskMemFree);
    selected.paths.emplace_back(path.get());
  }
  return selected;
}

struct Camera {
  com_ptr<IGraphBuilder> graph;
  com_ptr<IMediaControl> playback;
  com_ptr<IVMRWindowlessControl9> preview;
  std::vector<uint8_t> photo;
  const char* error = nullptr;

  void Start(HWND window) {
    com_ptr<ICreateDevEnum> devices;
    check_hresult(CoCreateInstance(CLSID_SystemDeviceEnum, nullptr, CLSCTX_INPROC_SERVER,
                                  IID_PPV_ARGS(devices.put())));
    com_ptr<IEnumMoniker> cameras;
    const HRESULT enumerated = devices->CreateClassEnumerator(
        CLSID_VideoInputDeviceCategory, cameras.put(), 0);
    check_hresult(enumerated);
    com_ptr<IMoniker> device;
    if (enumerated != S_OK || cameras->Next(1, device.put(), nullptr) != S_OK) {
      error = "No Windows camera was found. Connect a webcam or choose Gallery.";
      throw hresult_error(E_FAIL);
    }
    com_ptr<IBaseFilter> source;
    check_hresult(device->BindToObject(nullptr, nullptr, IID_PPV_ARGS(source.put())));
    check_hresult(CoCreateInstance(CLSID_FilterGraph, nullptr, CLSCTX_INPROC_SERVER,
                                  IID_PPV_ARGS(graph.put())));
    check_hresult(graph->AddFilter(source.get(), L"Camera"));
    com_ptr<IBaseFilter> renderer;
    check_hresult(CoCreateInstance(CLSID_VideoMixingRenderer9, nullptr, CLSCTX_INPROC_SERVER,
                                  IID_PPV_ARGS(renderer.put())));
    check_hresult(graph->AddFilter(renderer.get(), L"Preview"));
    check_hresult(renderer.as<IVMRFilterConfig9>()->SetRenderingMode(VMR9Mode_Windowless));
    preview = renderer.as<IVMRWindowlessControl9>();
    check_hresult(preview->SetVideoClippingWindow(window));
    check_hresult(preview->SetAspectRatioMode(VMR9ARMode_LetterBox));
    com_ptr<ICaptureGraphBuilder2> builder;
    check_hresult(CoCreateInstance(CLSID_CaptureGraphBuilder2, nullptr, CLSCTX_INPROC_SERVER,
                                  IID_PPV_ARGS(builder.put())));
    check_hresult(builder->SetFiltergraph(graph.get()));
    check_hresult(builder->RenderStream(&PIN_CATEGORY_PREVIEW, &MEDIATYPE_Video, source.get(),
                                        nullptr, renderer.get()));
    RECT bounds{8, 7, 334, 225};
    MapDialogRect(window, &bounds);
    check_hresult(preview->SetVideoPosition(nullptr, &bounds));
    playback = graph.as<IMediaControl>();
    check_hresult(playback->Run());
  }

  void TakePhoto() {
    BYTE* raw{};
    check_hresult(preview->GetCurrentImage(&raw));
    std::unique_ptr<BYTE, decltype(&CoTaskMemFree)> dib(raw, CoTaskMemFree);
    if (!raw) throw hresult_error(E_FAIL);
    com_ptr<IMalloc> allocator;
    check_hresult(CoGetMalloc(1, allocator.put()));
    const auto allocation = allocator->GetSize(raw);
    if (allocation == static_cast<SIZE_T>(-1) || allocation < sizeof(BITMAPINFOHEADER))
      throw hresult_error(E_FAIL);
    const auto& header = *reinterpret_cast<const BITMAPINFOHEADER*>(raw);
    if (header.biSize != sizeof(BITMAPINFOHEADER) || header.biWidth <= 0 ||
        header.biHeight == 0 || header.biPlanes != 1 ||
        (header.biCompression != BI_RGB && header.biCompression != BI_BITFIELDS) ||
        (header.biBitCount != 24 && header.biBitCount != 32)) throw hresult_error(E_FAIL);
    const auto height = static_cast<uint64_t>(std::abs(static_cast<int64_t>(header.biHeight)));
    const auto width = static_cast<uint64_t>(header.biWidth);
    if (width * height > kMaxPixels) throw hresult_error(E_FAIL);
    const auto row_bytes = ((width * header.biBitCount + 31) / 32) * 4;
    const auto offset = sizeof(BITMAPINFOHEADER) +
        (header.biCompression == BI_BITFIELDS ? 12ULL : 0ULL) + 4ULL * header.biClrUsed;
    const auto dib_bytes = offset + row_bytes * height;
    const auto total = sizeof(BITMAPFILEHEADER) + dib_bytes;
    if (total > kMaxBytes || dib_bytes > allocation) throw hresult_error(E_FAIL);
    BITMAPFILEHEADER file{};
    file.bfType = 0x4d42;
    file.bfOffBits = static_cast<DWORD>(sizeof(file) + offset);
    file.bfSize = static_cast<DWORD>(total);
    photo.resize(file.bfSize);
    std::memcpy(photo.data(), &file, sizeof(file));
    std::memcpy(photo.data() + sizeof(file), raw, static_cast<size_t>(dib_bytes));
  }
};

INT_PTR CALLBACK CameraDialog(HWND window, UINT message, WPARAM wparam, LPARAM lparam) {
  auto* camera = reinterpret_cast<Camera*>(GetWindowLongPtrW(window, DWLP_USER));
  try {
    if (message == WM_INITDIALOG) {
      camera = reinterpret_cast<Camera*>(lparam);
      SetWindowLongPtrW(window, DWLP_USER, lparam);
      camera->Start(window);
      return TRUE;
    }
    if (!camera) return FALSE;
    if (message == WM_PAINT && camera->preview) {
      PAINTSTRUCT paint{};
      HDC dc = BeginPaint(window, &paint);
      camera->preview->RepaintVideo(window, dc);
      EndPaint(window, &paint);
      return TRUE;
    }
    if (message == WM_DISPLAYCHANGE && camera->preview) camera->preview->DisplayModeChanged();
    if (message == WM_COMMAND && LOWORD(wparam) == IDOK) {
      camera->TakePhoto();
      EndDialog(window, IDOK);
      return TRUE;
    }
    if (message == WM_CLOSE || (message == WM_COMMAND && LOWORD(wparam) == IDCANCEL)) {
      EndDialog(window, IDCANCEL);
      return TRUE;
    }
  } catch (...) {
    if (camera && !camera->error) camera->error =
        "Windows could not use this camera. Check camera access or choose Gallery.";
    EndDialog(window, -1);
    return TRUE;
  }
  return FALSE;
}

IRandomAccessStream CameraStream(const std::vector<uint8_t>& bmp) {
  InMemoryRandomAccessStream stream;
  DataWriter writer(stream);
  writer.WriteBytes(bmp);
  writer.StoreAsync().get();
  writer.DetachStream();
  stream.Seek(0);
  return stream;
}

std::vector<uint8_t> Prepare(const IRandomAccessStream& input) {
  if (!input.Size() || input.Size() > kMaxBytes) throw hresult_error(E_INVALIDARG);
  const auto decoder = BitmapDecoder::CreateAsync(input).get();
  const auto width = decoder.PixelWidth(), height = decoder.PixelHeight();
  if (!width || !height || static_cast<uint64_t>(width) * height > kMaxPixels)
    throw hresult_error(E_INVALIDARG);
  BitmapTransform transform;
  const auto longest = std::max(width, height);
  if (longest > kLongestEdge) {
    transform.ScaledWidth(std::max(1U, static_cast<uint32_t>(static_cast<uint64_t>(width) * kLongestEdge / longest)));
    transform.ScaledHeight(std::max(1U, static_cast<uint32_t>(static_cast<uint64_t>(height) * kLongestEdge / longest)));
  }
  const auto bitmap = decoder.GetSoftwareBitmapAsync(
      BitmapPixelFormat::Bgra8, BitmapAlphaMode::Ignore, transform,
      ExifOrientationMode::RespectExifOrientation, ColorManagementMode::ColorManageToSRgb).get();
  InMemoryRandomAccessStream output;
  const auto encoder = BitmapEncoder::CreateAsync(BitmapEncoder::JpegEncoderId(), output).get();
  // Encode fresh pixel data. Never transcode the input's metadata or embedded thumbnails.
  encoder.SetSoftwareBitmap(bitmap);
  encoder.FlushAsync().get();
  const auto length = output.Size();
  if (!length || length > kMaxBytes) throw hresult_error(E_INVALIDARG);
  DataReader reader(output.GetInputStreamAt(0));
  if (reader.LoadAsync(static_cast<uint32_t>(length)).get() != length) throw hresult_error(E_FAIL);
  std::vector<uint8_t> bytes(static_cast<size_t>(length));
  reader.ReadBytes(bytes);
  return bytes;
}
}  // namespace

CreatePhotoSelection ChooseCreatePhotos(HWND owner, bool camera, int limit) {
  if (!camera) return ChooseFiles(owner, limit);
  Camera capture;
  const auto result = DialogBoxParamW(GetModuleHandleW(nullptr), MAKEINTRESOURCEW(kCameraDialog),
                                      owner, CameraDialog, reinterpret_cast<LPARAM>(&capture));
  if (capture.playback) capture.playback->Stop();
  if (result == IDCANCEL) return {};
  if (result != IDOK) throw std::runtime_error(capture.error ? capture.error :
      "Could not open the camera. Choose Gallery to add an existing photo.");
  CreatePhotoSelection selection;
  selection.camera_bmp = std::move(capture.photo);
  return selection;
}

flutter::EncodableValue PrepareCreatePhotos(
    const CreatePhotoSelection& selected, const std::function<bool()>& cancelled) {
  init_apartment(apartment_type::multi_threaded);
  struct Apartment { ~Apartment() { uninit_apartment(); } } apartment;
  flutter::EncodableList photos, errors;
  if (selected.skipped_extra) errors.emplace_back("Extra selections exceeded the photo limit and were skipped.");
  const bool camera = !selected.camera_bmp.empty();
  const size_t count = camera ? 1 : selected.paths.size();
  for (size_t i = 0; i < count && !cancelled(); ++i) {
    try {
      auto input = camera ? CameraStream(selected.camera_bmp) :
          StorageFile::GetFileFromPathAsync(selected.paths[i]).get().OpenAsync(FileAccessMode::Read).get();
      photos.emplace_back(Prepare(input));
    } catch (...) {
      errors.emplace_back("Photo " + std::to_string(i + 1) +
                          " could not be read (25 MiB / 80 MP maximum).");
    }
  }
  return Value(flutter::EncodableMap{{Value("photos"), Value(std::move(photos))},
                                    {Value("errors"), Value(std::move(errors))}});
}
