#ifndef RUNNER_OCR_CHANNEL_H_
#define RUNNER_OCR_CHANNEL_H_

#include <flutter/binary_messenger.h>
#include <flutter/encodable_value.h>
#include <flutter/method_channel.h>
#include <windows.h>

#include <memory>

// Posted to the Flutter window when a background OCR job finishes, so the
// reply is sent on the platform thread.
constexpr UINT kOcrDoneMessage = WM_APP + 0x0C8;

// "otic/ocr": Windows.Media.Ocr for scanned PDF pages. Offline, built into
// Windows 10+. Work runs on a worker thread: the platform thread is a COM
// single-threaded apartment, where blocking on a WinRT async call asserts.
class OcrChannel {
 public:
  OcrChannel(flutter::BinaryMessenger* messenger, HWND window);

  // Sends the reply for a job posted with kOcrDoneMessage, and frees it.
  static void Complete(LPARAM job);

  // Frees a finished job without replying, once the engine is gone.
  static void Discard(LPARAM job);

 private:
  HWND window_;
  std::unique_ptr<flutter::MethodChannel<flutter::EncodableValue>> channel_;
};

#endif  // RUNNER_OCR_CHANNEL_H_
