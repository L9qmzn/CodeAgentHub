import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:speech_to_text/speech_recognition_result.dart';
import 'package:speech_to_text/speech_to_text.dart';
import 'package:permission_handler/permission_handler.dart';
import 'windows_speech_recognition.dart';

/// 语音转文字服务
/// Windows: 使用原生 SAPI（离线可用）
/// Android/iOS/macOS: 使用 speech_to_text 插件
class SpeechToTextService {
  static SpeechToTextService? _instance;

  // speech_to_text 插件（非 Windows 平台）
  final SpeechToText _speech = SpeechToText();

  // Windows 原生语音识别
  WindowsSpeechRecognition? _windowsSpeech;

  bool _isInitialized = false;
  bool _isListening = false;
  String _lastRecognizedWords = '';
  String _currentLocaleId = 'zh_CN'; // 默认中文

  // 回调函数
  Function(String text, bool isFinal)? onResult;
  Function(String error)? onError;
  Function()? onListeningStarted;
  Function()? onListeningStopped;

  SpeechToTextService._();

  static SpeechToTextService getInstance() {
    _instance ??= SpeechToTextService._();
    return _instance!;
  }

  /// 是否已初始化
  bool get isInitialized => _isInitialized;

  /// 是否正在监听
  bool get isListening => _isListening;

  /// 最后识别的文字
  String get lastRecognizedWords => _lastRecognizedWords;

  /// 检查平台是否支持语音输入
  bool get isPlatformSupported {
    if (kIsWeb) return false;
    return Platform.isWindows || Platform.isMacOS || Platform.isAndroid || Platform.isIOS;
  }

  /// 是否使用 Windows 原生 API
  bool get _useWindowsNative {
    if (kIsWeb) return false;
    return Platform.isWindows;
  }

  /// 请求麦克风权限（Android/iOS）
  Future<bool> _requestMicrophonePermission() async {
    if (Platform.isAndroid || Platform.isIOS) {
      final status = await Permission.microphone.request();
      print('DEBUG SpeechToTextService: Microphone permission status: $status');
      if (status.isDenied || status.isPermanentlyDenied) {
        return false;
      }

      // iOS 还需要语音识别权限
      if (Platform.isIOS) {
        final speechStatus = await Permission.speech.request();
        print('DEBUG SpeechToTextService: Speech permission status: $speechStatus');
        if (speechStatus.isDenied || speechStatus.isPermanentlyDenied) {
          return false;
        }
      }
    }
    return true;
  }

  /// 初始化语音识别
  Future<bool> initialize() async {
    if (!isPlatformSupported) {
      print('DEBUG SpeechToTextService: Platform not supported');
      return false;
    }

    if (_isInitialized) {
      return true;
    }

    try {
      if (_useWindowsNative) {
        // Windows: 使用原生 SAPI
        return await _initializeWindows();
      } else {
        // 其他平台: 使用 speech_to_text 插件
        return await _initializePlugin();
      }
    } catch (e) {
      print('ERROR SpeechToTextService: Failed to initialize: $e');
      _isInitialized = false;
      return false;
    }
  }

  /// Windows 原生初始化
  Future<bool> _initializeWindows() async {
    print('DEBUG SpeechToTextService: Initializing Windows SAPI...');

    _windowsSpeech = WindowsSpeechRecognition.getInstance();

    // 设置回调
    _windowsSpeech!.onResult = (text, isFinal) {
      _lastRecognizedWords = text;
      print('DEBUG SpeechToTextService: Windows result: $text (final: $isFinal)');
      onResult?.call(text, isFinal);
    };

    _windowsSpeech!.onError = (error) {
      print('ERROR SpeechToTextService: Windows error: $error');
      onError?.call(error);
    };

    _windowsSpeech!.onStatus = (status) {
      print('DEBUG SpeechToTextService: Windows status: $status');
      if (status == 'listening') {
        _isListening = true;
        onListeningStarted?.call();
      } else if (status == 'stopped') {
        _isListening = false;
        onListeningStopped?.call();
      }
    };

    _isInitialized = await _windowsSpeech!.initialize();
    print('DEBUG SpeechToTextService: Windows SAPI initialized: $_isInitialized');
    return _isInitialized;
  }

  /// 插件初始化（Android/iOS/macOS）
  Future<bool> _initializePlugin() async {
    // 先请求权限
    final hasPermission = await _requestMicrophonePermission();
    if (!hasPermission) {
      print('DEBUG SpeechToTextService: Microphone permission denied');
      return false;
    }

    print('DEBUG SpeechToTextService: Initializing speech_to_text plugin...');
    _isInitialized = await _speech.initialize(
      onStatus: _onStatus,
      onError: _onSpeechError,
      debugLogging: true,
    );

    if (_isInitialized) {
      // 获取可用的语言列表
      final locales = await _speech.locales();
      print('DEBUG SpeechToTextService: Available locales: ${locales.map((l) => l.localeId).toList()}');

      // 尝试找到中文语言
      final chineseLocale = locales.firstWhere(
        (locale) => locale.localeId.startsWith('zh'),
        orElse: () => locales.isNotEmpty ? locales.first : LocaleName('en_US', 'English'),
      );
      _currentLocaleId = chineseLocale.localeId;
      print('DEBUG SpeechToTextService: Using locale: $_currentLocaleId');
    }

    print('DEBUG SpeechToTextService: Plugin initialized: $_isInitialized');
    return _isInitialized;
  }

  /// 开始监听
  Future<bool> startListening() async {
    if (!_isInitialized) {
      final success = await initialize();
      if (!success) {
        String errorMsg = '语音识别初始化失败';
        if (Platform.isWindows) {
          errorMsg += '，请确保 Windows 语音识别已启用并安装了语音语言包';
        } else if (Platform.isAndroid) {
          errorMsg += '，请授予麦克风权限并确保已安装 Google 应用';
        } else if (Platform.isIOS) {
          errorMsg += '，请授予麦克风和语音识别权限';
        }
        onError?.call(errorMsg);
        return false;
      }
    }

    if (_isListening) {
      print('DEBUG SpeechToTextService: Already listening');
      return true;
    }

    try {
      if (_useWindowsNative && _windowsSpeech != null) {
        // Windows: 使用原生 SAPI
        return await _windowsSpeech!.startListening();
      } else {
        // 其他平台: 使用插件
        return await _startListeningPlugin();
      }
    } catch (e) {
      print('ERROR SpeechToTextService: Failed to start listening: $e');
      onError?.call('开始监听失败: $e');
      return false;
    }
  }

  Future<bool> _startListeningPlugin() async {
    print('DEBUG SpeechToTextService: Starting to listen (plugin)...');
    _lastRecognizedWords = '';

    await _speech.listen(
      onResult: _onSpeechResult,
      localeId: _currentLocaleId,
      listenFor: const Duration(seconds: 30), // 最长监听 30 秒
      pauseFor: const Duration(seconds: 3), // 暂停 3 秒后停止
      partialResults: true, // 返回部分结果
      cancelOnError: true,
      listenMode: ListenMode.dictation, // 听写模式
    );

    _isListening = true;
    onListeningStarted?.call();
    print('DEBUG SpeechToTextService: Listening started (plugin)');
    return true;
  }

  /// 停止监听
  Future<void> stopListening() async {
    if (!_isListening) return;

    try {
      print('DEBUG SpeechToTextService: Stopping listening...');

      if (_useWindowsNative && _windowsSpeech != null) {
        await _windowsSpeech!.stopListening();
      } else {
        await _speech.stop();
        _isListening = false;
        onListeningStopped?.call();
      }

      print('DEBUG SpeechToTextService: Listening stopped');
    } catch (e) {
      print('ERROR SpeechToTextService: Failed to stop listening: $e');
    }
  }

  /// 取消监听
  Future<void> cancelListening() async {
    if (!_isListening) return;

    try {
      print('DEBUG SpeechToTextService: Canceling listening...');

      if (_useWindowsNative && _windowsSpeech != null) {
        await _windowsSpeech!.stopListening();
      } else {
        await _speech.cancel();
        _isListening = false;
        _lastRecognizedWords = '';
        onListeningStopped?.call();
      }

      print('DEBUG SpeechToTextService: Listening canceled');
    } catch (e) {
      print('ERROR SpeechToTextService: Failed to cancel listening: $e');
    }
  }

  /// 切换语言（仅对非 Windows 平台有效）
  Future<void> setLocale(String localeId) async {
    _currentLocaleId = localeId;
    print('DEBUG SpeechToTextService: Locale set to: $localeId');
  }

  /// 获取可用语言列表（仅对非 Windows 平台有效）
  Future<List<LocaleName>> getAvailableLocales() async {
    if (_useWindowsNative) {
      // Windows SAPI 语言由系统管理
      return [];
    }
    if (!_isInitialized) {
      await initialize();
    }
    return await _speech.locales();
  }

  void _onSpeechResult(SpeechRecognitionResult result) {
    _lastRecognizedWords = result.recognizedWords;
    print('DEBUG SpeechToTextService: Result: ${result.recognizedWords} (final: ${result.finalResult})');
    onResult?.call(result.recognizedWords, result.finalResult);
  }

  void _onStatus(String status) {
    print('DEBUG SpeechToTextService: Status: $status');
    if (status == 'done' || status == 'notListening') {
      _isListening = false;
      onListeningStopped?.call();
    }
  }

  void _onSpeechError(dynamic error) {
    print('ERROR SpeechToTextService: Speech error: $error');
    _isListening = false;
    onListeningStopped?.call();

    String errorMessage = '语音识别错误';
    if (error.errorMsg != null) {
      if (error.errorMsg.contains('no_match')) {
        errorMessage = '未能识别语音，请重试';
      } else if (error.errorMsg.contains('audio')) {
        errorMessage = '音频错误，请检查麦克风';
      } else if (error.errorMsg.contains('network')) {
        errorMessage = '网络错误，请检查网络连接';
      } else if (error.errorMsg.contains('permission')) {
        errorMessage = '没有麦克风权限';
      } else {
        errorMessage = error.errorMsg;
      }
    }
    onError?.call(errorMessage);
  }

  /// 释放资源
  void dispose() {
    if (_useWindowsNative && _windowsSpeech != null) {
      _windowsSpeech!.dispose();
    } else if (_isListening) {
      _speech.cancel();
    }
    _isInitialized = false;
    _isListening = false;
  }
}
