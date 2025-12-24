#ifndef RUNNER_SPEECH_RECOGNITION_H_
#define RUNNER_SPEECH_RECOGNITION_H_

#include <flutter/flutter_engine.h>
#include <flutter/method_channel.h>
#include <flutter/standard_method_codec.h>
#include <flutter/event_channel.h>
#include <flutter/event_sink.h>
#include <flutter/event_stream_handler_functions.h>
#include <windows.h>
#include <sapi.h>
// Note: We don't include sphelper.h as it requires ATL
// Instead we use the low-level SAPI API directly
#include <string>
#include <memory>
#include <functional>
#include <thread>
#include <atomic>
#include <mutex>

#pragma comment(lib, "sapi.lib")

class SpeechRecognition {
public:
    SpeechRecognition();
    ~SpeechRecognition();

    // 初始化语音识别
    bool Initialize();

    // 开始监听
    bool StartListening();

    // 停止监听
    void StopListening();

    // 是否正在监听
    bool IsListening() const { return is_listening_; }

    // 是否已初始化
    bool IsInitialized() const { return is_initialized_; }

    // 设置结果回调 (thread-safe)
    void SetResultCallback(std::function<void(const std::string&, bool)> callback);

    // 设置错误回调 (thread-safe)
    void SetErrorCallback(std::function<void(const std::string&)> callback);

    // 设置状态回调 (thread-safe)
    void SetStatusCallback(std::function<void(const std::string&)> callback);

private:
    void RecognitionThread();
    void Cleanup();
    std::string WideToUtf8(const std::wstring& wstr);

    ISpRecognizer* recognizer_ = nullptr;
    ISpRecoContext* context_ = nullptr;
    ISpRecoGrammar* grammar_ = nullptr;
    HANDLE recognition_event_ = nullptr;  // Owned by context, don't close

    std::atomic<bool> is_initialized_{false};
    std::atomic<bool> is_listening_{false};
    std::atomic<bool> should_stop_{false};
    bool com_initialized_ = false;
    std::thread recognition_thread_;

    // Mutex for thread-safe callback access
    mutable std::mutex callback_mutex_;
    std::function<void(const std::string&, bool)> result_callback_;
    std::function<void(const std::string&)> error_callback_;
    std::function<void(const std::string&)> status_callback_;
};

// 注册 Method Channel
void RegisterSpeechRecognitionChannel(flutter::FlutterEngine* engine);

#endif  // RUNNER_SPEECH_RECOGNITION_H_
