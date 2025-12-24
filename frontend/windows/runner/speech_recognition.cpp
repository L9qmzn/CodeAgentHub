#include "speech_recognition.h"
#include <iostream>
#include <codecvt>
#include <locale>
#include <cstring>

SpeechRecognition::SpeechRecognition() {}

SpeechRecognition::~SpeechRecognition() {
    StopListening();

    if (grammar_) {
        grammar_->Release();
        grammar_ = nullptr;
    }
    if (context_) {
        context_->Release();
        context_ = nullptr;
    }
    if (recognizer_) {
        recognizer_->Release();
        recognizer_ = nullptr;
    }
    // Note: Don't CloseHandle on recognition_event_ - it's owned by the context
    recognition_event_ = nullptr;

    if (com_initialized_) {
        CoUninitialize();
        com_initialized_ = false;
    }
}

bool SpeechRecognition::Initialize() {
    if (is_initialized_) {
        return true;
    }

    HRESULT hr = CoInitializeEx(nullptr, COINIT_APARTMENTTHREADED);
    if (FAILED(hr) && hr != RPC_E_CHANGED_MODE) {
        if (error_callback_) {
            error_callback_("COM 初始化失败");
        }
        return false;
    }
    com_initialized_ = (hr != RPC_E_CHANGED_MODE);

    // 创建共享识别器（使用系统默认的语音识别引擎）
    hr = CoCreateInstance(CLSID_SpSharedRecognizer, nullptr, CLSCTX_ALL,
                          IID_ISpRecognizer, (void**)&recognizer_);
    if (FAILED(hr)) {
        if (error_callback_) {
            error_callback_("创建语音识别器失败，请确保 Windows 语音识别已启用");
        }
        Cleanup();
        return false;
    }

    // 创建识别上下文
    hr = recognizer_->CreateRecoContext(&context_);
    if (FAILED(hr)) {
        if (error_callback_) {
            error_callback_("创建识别上下文失败");
        }
        Cleanup();
        return false;
    }

    // 设置感兴趣的事件
    hr = context_->SetInterest(SPFEI(SPEI_RECOGNITION) | SPFEI(SPEI_FALSE_RECOGNITION),
                                SPFEI(SPEI_RECOGNITION) | SPFEI(SPEI_FALSE_RECOGNITION));
    if (FAILED(hr)) {
        if (error_callback_) {
            error_callback_("设置事件失败");
        }
        Cleanup();
        return false;
    }

    // 获取事件句柄 (owned by context, don't close it)
    recognition_event_ = context_->GetNotifyEventHandle();

    // 创建语法 - 使用听写模式
    hr = context_->CreateGrammar(0, &grammar_);
    if (FAILED(hr)) {
        if (error_callback_) {
            error_callback_("创建语法失败");
        }
        Cleanup();
        return false;
    }

    // 加载听写语法
    hr = grammar_->LoadDictation(nullptr, SPLO_STATIC);
    if (FAILED(hr)) {
        if (error_callback_) {
            error_callback_("加载听写语法失败，请确保已安装语音识别语言包");
        }
        Cleanup();
        return false;
    }

    is_initialized_ = true;
    if (status_callback_) {
        status_callback_("initialized");
    }
    return true;
}

void SpeechRecognition::Cleanup() {
    if (grammar_) {
        grammar_->Release();
        grammar_ = nullptr;
    }
    if (context_) {
        context_->Release();
        context_ = nullptr;
    }
    if (recognizer_) {
        recognizer_->Release();
        recognizer_ = nullptr;
    }
    recognition_event_ = nullptr;

    if (com_initialized_) {
        CoUninitialize();
        com_initialized_ = false;
    }
}

bool SpeechRecognition::StartListening() {
    if (!is_initialized_) {
        if (!Initialize()) {
            return false;
        }
    }

    if (is_listening_) {
        return true;
    }

    // 激活听写语法
    HRESULT hr = grammar_->SetDictationState(SPRS_ACTIVE);
    if (FAILED(hr)) {
        if (error_callback_) {
            error_callback_("激活听写失败");
        }
        return false;
    }

    is_listening_ = true;
    should_stop_ = false;

    // 启动识别线程
    recognition_thread_ = std::thread(&SpeechRecognition::RecognitionThread, this);

    if (status_callback_) {
        status_callback_("listening");
    }
    return true;
}

void SpeechRecognition::StopListening() {
    if (!is_listening_) {
        return;
    }

    should_stop_ = true;
    is_listening_ = false;

    // 停用听写语法
    if (grammar_) {
        grammar_->SetDictationState(SPRS_INACTIVE);
    }

    // 等待线程结束
    if (recognition_thread_.joinable()) {
        recognition_thread_.join();
    }

    if (status_callback_) {
        status_callback_("stopped");
    }
}

void SpeechRecognition::RecognitionThread() {
    while (!should_stop_) {
        DWORD result = WaitForSingleObject(recognition_event_, 100);

        if (result == WAIT_OBJECT_0) {
            // Use low-level SAPI API instead of CSpEvent (which requires ATL)
            SPEVENT event;
            memset(&event, 0, sizeof(SPEVENT));
            ULONG fetched = 0;

            while (context_->GetEvents(1, &event, &fetched) == S_OK && fetched > 0) {
                // Process recognition events
                if (event.eEventId == SPEI_RECOGNITION || event.eEventId == SPEI_FALSE_RECOGNITION) {
                    // For recognition events, lParam contains ISpRecoResult*
                    if (event.elParamType == SPET_LPARAM_IS_OBJECT && event.lParam) {
                        ISpRecoResult* reco_result = reinterpret_cast<ISpRecoResult*>(event.lParam);

                        if (event.eEventId == SPEI_RECOGNITION) {
                            // 获取识别的文本
                            LPWSTR text = nullptr;
                            // Cast SP_GETWHOLEPHRASE (-1) to ULONG to avoid signed/unsigned warning
                            HRESULT hr = reco_result->GetText(static_cast<ULONG>(SP_GETWHOLEPHRASE), static_cast<ULONG>(SP_GETWHOLEPHRASE), TRUE, &text, nullptr);
                            if (SUCCEEDED(hr) && text) {
                                std::wstring wtext(text);
                                std::string utf8_text = WideToUtf8(wtext);

                                // Thread-safe callback invocation
                                std::lock_guard<std::mutex> lock(callback_mutex_);
                                if (result_callback_ && !utf8_text.empty()) {
                                    result_callback_(utf8_text, true);
                                }

                                CoTaskMemFree(text);
                            }
                        }
                        // Release the result object for both RECOGNITION and FALSE_RECOGNITION
                        reco_result->Release();
                    }
                } else {
                    // For other events, release any COM object in lParam if applicable
                    if (event.elParamType == SPET_LPARAM_IS_OBJECT && event.lParam) {
                        IUnknown* obj = reinterpret_cast<IUnknown*>(event.lParam);
                        obj->Release();
                    }
                }

                // Reset for next iteration
                memset(&event, 0, sizeof(SPEVENT));
                fetched = 0;
            }
        }
    }
}

std::string SpeechRecognition::WideToUtf8(const std::wstring& wstr) {
    if (wstr.empty()) return std::string();

    int size_needed = WideCharToMultiByte(CP_UTF8, 0, wstr.c_str(), (int)wstr.size(), nullptr, 0, nullptr, nullptr);
    std::string result(size_needed, 0);
    WideCharToMultiByte(CP_UTF8, 0, wstr.c_str(), (int)wstr.size(), &result[0], size_needed, nullptr, nullptr);
    return result;
}

void SpeechRecognition::SetResultCallback(std::function<void(const std::string&, bool)> callback) {
    std::lock_guard<std::mutex> lock(callback_mutex_);
    result_callback_ = callback;
}

void SpeechRecognition::SetErrorCallback(std::function<void(const std::string&)> callback) {
    std::lock_guard<std::mutex> lock(callback_mutex_);
    error_callback_ = callback;
}

void SpeechRecognition::SetStatusCallback(std::function<void(const std::string&)> callback) {
    std::lock_guard<std::mutex> lock(callback_mutex_);
    status_callback_ = callback;
}

// 全局语音识别实例
static std::unique_ptr<SpeechRecognition> g_speech_recognition;
// 全局 EventSink，需要跟踪以便正确清理
static flutter::EventSink<flutter::EncodableValue>* g_event_sink = nullptr;

void RegisterSpeechRecognitionChannel(flutter::FlutterEngine* engine) {
    auto channel = std::make_unique<flutter::MethodChannel<flutter::EncodableValue>>(
        engine->messenger(), "com.codeagenthub/speech_recognition",
        &flutter::StandardMethodCodec::GetInstance());

    channel->SetMethodCallHandler(
        [](const flutter::MethodCall<flutter::EncodableValue>& call,
           std::unique_ptr<flutter::MethodResult<flutter::EncodableValue>> result) {

            if (call.method_name() == "initialize") {
                if (!g_speech_recognition) {
                    g_speech_recognition = std::make_unique<SpeechRecognition>();
                }

                bool success = g_speech_recognition->Initialize();
                result->Success(flutter::EncodableValue(success));

            } else if (call.method_name() == "startListening") {
                if (!g_speech_recognition) {
                    result->Error("NOT_INITIALIZED", "语音识别未初始化");
                    return;
                }

                bool success = g_speech_recognition->StartListening();
                result->Success(flutter::EncodableValue(success));

            } else if (call.method_name() == "stopListening") {
                if (g_speech_recognition) {
                    g_speech_recognition->StopListening();
                }
                result->Success(flutter::EncodableValue(true));

            } else if (call.method_name() == "isListening") {
                bool listening = g_speech_recognition ? g_speech_recognition->IsListening() : false;
                result->Success(flutter::EncodableValue(listening));

            } else if (call.method_name() == "isInitialized") {
                bool initialized = g_speech_recognition ? g_speech_recognition->IsInitialized() : false;
                result->Success(flutter::EncodableValue(initialized));

            } else {
                result->NotImplemented();
            }
        });

    // 注册事件通道用于接收识别结果
    auto event_channel = std::make_unique<flutter::EventChannel<flutter::EncodableValue>>(
        engine->messenger(), "com.codeagenthub/speech_recognition_events",
        &flutter::StandardMethodCodec::GetInstance());

    auto event_handler = std::make_unique<flutter::StreamHandlerFunctions<flutter::EncodableValue>>(
        [](const flutter::EncodableValue* arguments,
           std::unique_ptr<flutter::EventSink<flutter::EncodableValue>>&& events)
            -> std::unique_ptr<flutter::StreamHandlerError<flutter::EncodableValue>> {

            // Store the event sink globally
            g_event_sink = events.release();

            if (g_speech_recognition && g_event_sink) {
                g_speech_recognition->SetResultCallback(
                    [](const std::string& text, bool is_final) {
                        if (g_event_sink) {
                            flutter::EncodableMap result;
                            result[flutter::EncodableValue("text")] = flutter::EncodableValue(text);
                            result[flutter::EncodableValue("isFinal")] = flutter::EncodableValue(is_final);
                            result[flutter::EncodableValue("type")] = flutter::EncodableValue("result");
                            g_event_sink->Success(flutter::EncodableValue(result));
                        }
                    });

                g_speech_recognition->SetErrorCallback(
                    [](const std::string& error) {
                        if (g_event_sink) {
                            flutter::EncodableMap result;
                            result[flutter::EncodableValue("error")] = flutter::EncodableValue(error);
                            result[flutter::EncodableValue("type")] = flutter::EncodableValue("error");
                            g_event_sink->Success(flutter::EncodableValue(result));
                        }
                    });

                g_speech_recognition->SetStatusCallback(
                    [](const std::string& status) {
                        if (g_event_sink) {
                            flutter::EncodableMap result;
                            result[flutter::EncodableValue("status")] = flutter::EncodableValue(status);
                            result[flutter::EncodableValue("type")] = flutter::EncodableValue("status");
                            g_event_sink->Success(flutter::EncodableValue(result));
                        }
                    });
            }

            return nullptr;
        },
        [](const flutter::EncodableValue* arguments)
            -> std::unique_ptr<flutter::StreamHandlerError<flutter::EncodableValue>> {

            if (g_speech_recognition) {
                g_speech_recognition->SetResultCallback(nullptr);
                g_speech_recognition->SetErrorCallback(nullptr);
                g_speech_recognition->SetStatusCallback(nullptr);
            }

            // Clean up event sink
            if (g_event_sink) {
                delete g_event_sink;
                g_event_sink = nullptr;
            }

            return nullptr;
        });

    event_channel->SetStreamHandler(std::move(event_handler));
}
