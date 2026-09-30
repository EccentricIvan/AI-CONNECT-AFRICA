#include "ocr_channel.h"

#include <flutter/standard_method_codec.h>
#include <winrt/Windows.Foundation.Collections.h>
#include <winrt/Windows.Foundation.h>
#include <winrt/Windows.Globalization.h>
#include <winrt/Windows.Graphics.Imaging.h>
#include <winrt/Windows.Media.Ocr.h>
#include <winrt/Windows.Storage.Streams.h>

#include <algorithm>
#include <cstring>
#include <string>
#include <thread>
#include <vector>

namespace {

using flutter::EncodableList;
using flutter::EncodableMap;
using flutter::EncodableValue;
using winrt::Windows::Graphics::Imaging::BitmapAlphaMode;
using winrt::Windows::Graphics::Imaging::BitmapPixelFormat;
using winrt::Windows::Graphics::Imaging::SoftwareBitmap;
using winrt::Windows::Media::Ocr::OcrEngine;

struct Job {
  std::unique_ptr<flutter::MethodResult<EncodableValue>> result;
  bool info = false;
  std::vector<uint8_t> bgra;
  int width = 0;
  int height = 0;
  EncodableValue value;
  std::string error;
};

// The profile's language, else English, else none (no OCR pack installed).
OcrEngine CreateEngine() {
  OcrEngine engine = OcrEngine::TryCreateFromUserProfileLanguages();
  if (engine) return engine;
  winrt::Windows::Globalization::Language english(L"en-US");
  if (OcrEngine::IsLanguageSupported(english)) {
    return OcrEngine::TryCreateFromLanguage(english);
  }
  return nullptr;
}

void Run(Job* job) {
  winrt::init_apartment(winrt::apartment_type::multi_threaded);
  try {
    OcrEngine engine = CreateEngine();
    if (job->info) {
      EncodableMap info;
      info[EncodableValue("maxDimension")] =
          EncodableValue(static_cast<int32_t>(OcrEngine::MaxImageDimension()));
      info[EncodableValue("language")] =
          engine ? EncodableValue(winrt::to_string(
                       engine.RecognizerLanguage().LanguageTag()))
                 : EncodableValue();
      job->value = EncodableValue(info);
    } else if (!engine) {
      job->error = "No Windows OCR language is installed.";
    } else {
      const uint32_t size = static_cast<uint32_t>(job->bgra.size());
      winrt::Windows::Storage::Streams::Buffer buffer(size);
      std::memcpy(buffer.data(), job->bgra.data(), size);
      buffer.Length(size);
      SoftwareBitmap bitmap(BitmapPixelFormat::Bgra8, job->width, job->height,
                            BitmapAlphaMode::Premultiplied);
      bitmap.CopyFromBuffer(buffer);

      auto recognized = engine.RecognizeAsync(bitmap).get();
      EncodableList lines;
      for (auto const& line : recognized.Lines()) {
        float left = 1e9f, top = 1e9f, right = 0, bottom = 0;
        for (auto const& word : line.Words()) {
          auto r = word.BoundingRect();
          left = std::min(left, r.X);
          top = std::min(top, r.Y);
          right = std::max(right, r.X + r.Width);
          bottom = std::max(bottom, r.Y + r.Height);
        }
        if (right <= left) continue;
        EncodableMap item;
        item[EncodableValue("text")] =
            EncodableValue(winrt::to_string(line.Text()));
        item[EncodableValue("left")] = EncodableValue(static_cast<double>(left));
        item[EncodableValue("top")] = EncodableValue(static_cast<double>(top));
        item[EncodableValue("width")] =
            EncodableValue(static_cast<double>(right - left));
        item[EncodableValue("height")] =
            EncodableValue(static_cast<double>(bottom - top));
        lines.push_back(EncodableValue(item));
      }
      job->value = EncodableValue(lines);
    }
  } catch (winrt::hresult_error const& e) {
    job->error = winrt::to_string(e.message());
  } catch (...) {
    job->error = "Windows OCR failed.";
  }
  winrt::uninit_apartment();
}

}  // namespace

OcrChannel::OcrChannel(flutter::BinaryMessenger* messenger, HWND window)
    : window_(window) {
  channel_ = std::make_unique<flutter::MethodChannel<EncodableValue>>(
      messenger, "otic/ocr", &flutter::StandardMethodCodec::GetInstance());
  channel_->SetMethodCallHandler([this](const auto& call, auto result) {
    auto job = std::make_unique<Job>();
    job->result = std::move(result);
    if (call.method_name() == "info") {
      job->info = true;
    } else if (call.method_name() == "recognize") {
      const auto* args = std::get_if<EncodableMap>(call.arguments());
      if (!args) {
        job->result->Error("bad_args", "Expected a map.");
        return;
      }
      auto get = [args](const char* key) -> const EncodableValue* {
        auto it = args->find(EncodableValue(key));
        return it == args->end() ? nullptr : &it->second;
      };
      const auto* bgra = get("bgra");
      const auto* width = get("width");
      const auto* height = get("height");
      if (!bgra || !width || !height ||
          !std::holds_alternative<std::vector<uint8_t>>(*bgra)) {
        job->result->Error("bad_args", "Expected bgra, width and height.");
        return;
      }
      job->bgra = std::get<std::vector<uint8_t>>(*bgra);
      job->width = static_cast<int>(width->LongValue());
      job->height = static_cast<int>(height->LongValue());
      if (job->bgra.size() !=
          static_cast<size_t>(job->width) * job->height * 4) {
        job->result->Error("bad_args", "Pixel data doesn't match the size.");
        return;
      }
    } else {
      job->result->NotImplemented();
      return;
    }

    HWND window = window_;
    std::thread([raw = job.release(), window]() {
      Run(raw);
      if (!::PostMessage(window, kOcrDoneMessage, 0,
                         reinterpret_cast<LPARAM>(raw))) {
        delete raw;  // The window is gone; nobody is waiting for the reply.
      }
    }).detach();
  });
}

void OcrChannel::Discard(LPARAM raw) { delete reinterpret_cast<Job*>(raw); }

void OcrChannel::Complete(LPARAM raw) {
  std::unique_ptr<Job> job(reinterpret_cast<Job*>(raw));
  if (!job->error.empty()) {
    job->result->Error("ocr_failed", job->error);
  } else {
    job->result->Success(job->value);
  }
}
