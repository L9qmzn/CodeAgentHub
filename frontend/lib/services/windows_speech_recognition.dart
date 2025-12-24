import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

/// Windows 原生语音识别服务（使用 SAPI）
/// 仅在 Windows 平台可用，离线可用
class WindowsSpeechRecognition {
  static WindowsSpeechRecognition? _instance;

  static const MethodChannel _channel = MethodChannel('com.codeagenthub/speech_recognition');
  static const EventChannel _eventChannel = EventChannel('com.codeagenthub/speech_recognition_events');

  bool _isInitialized = false;
  bool _isListening = false;

  // 回调函数
  Function(String text, bool isFinal)? onResult;
  Function(String error)? onError;
  Function(String status)? onStatus;

  WindowsSpeechRecognition._() {
    _setupEventChannel();
  }

  static WindowsSpeechRecognition getInstance() {
    _instance ??= WindowsSpeechRecognition._();
    return _instance!;
  }

  /// 是否支持（仅 Windows）
  bool get isPlatformSupported {
    if (kIsWeb) return false;
    return Platform.isWindows;
  }

  /// 是否已初始化
  bool get isInitialized => _isInitialized;

  /// 是否正在监听
  bool get isListening => _isListening;

  void _setupEventChannel() {
    if (!isPlatformSupported) return;

    _eventChannel.receiveBroadcastStream().listen((event) {
      if (event is Map) {
        final type = event['type'] as String?;

        if (type == 'result') {
          final text = event['text'] as String? ?? '';
          final isFinal = event['isFinal'] as bool? ?? true;
          if (text.isNotEmpty) {
            onResult?.call(text, isFinal);
          }
        } else if (type == 'error') {
          final error = event['error'] as String? ?? '未知错误';
          onError?.call(error);
        } else if (type == 'status') {
          final status = event['status'] as String? ?? '';
          onStatus?.call(status);

          if (status == 'listening') {
            _isListening = true;
          } else if (status == 'stopped') {
            _isListening = false;
          }
        }
      }
    }, onError: (error) {
      print('ERROR WindowsSpeechRecognition: Event channel error: $error');
      onError?.call('事件通道错误: $error');
    });
  }

  /// 初始化语音识别
  Future<bool> initialize() async {
    if (!isPlatformSupported) {
      print('DEBUG WindowsSpeechRecognition: Platform not supported');
      return false;
    }

    if (_isInitialized) {
      return true;
    }

    try {
      print('DEBUG WindowsSpeechRecognition: Initializing...');
      final result = await _channel.invokeMethod<bool>('initialize');
      _isInitialized = result ?? false;
      print('DEBUG WindowsSpeechRecognition: Initialized: $_isInitialized');
      return _isInitialized;
    } catch (e) {
      print('ERROR WindowsSpeechRecognition: Failed to initialize: $e');
      onError?.call('初始化失败: $e');
      return false;
    }
  }

  /// 开始监听
  Future<bool> startListening() async {
    if (!isPlatformSupported) {
      onError?.call('当前平台不支持');
      return false;
    }

    if (!_isInitialized) {
      final success = await initialize();
      if (!success) {
        onError?.call('语音识别初始化失败，请确保 Windows 语音识别已启用');
        return false;
      }
    }

    if (_isListening) {
      return true;
    }

    try {
      print('DEBUG WindowsSpeechRecognition: Starting to listen...');
      final result = await _channel.invokeMethod<bool>('startListening');
      _isListening = result ?? false;
      print('DEBUG WindowsSpeechRecognition: Listening: $_isListening');
      return _isListening;
    } catch (e) {
      print('ERROR WindowsSpeechRecognition: Failed to start listening: $e');
      onError?.call('开始监听失败: $e');
      return false;
    }
  }

  /// 停止监听
  Future<void> stopListening() async {
    if (!_isListening) return;

    try {
      print('DEBUG WindowsSpeechRecognition: Stopping...');
      await _channel.invokeMethod('stopListening');
      _isListening = false;
      print('DEBUG WindowsSpeechRecognition: Stopped');
    } catch (e) {
      print('ERROR WindowsSpeechRecognition: Failed to stop: $e');
    }
  }

  /// 释放资源
  void dispose() {
    stopListening();
    _isInitialized = false;
    _isListening = false;
  }
}
