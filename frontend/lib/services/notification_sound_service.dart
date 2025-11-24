import 'package:audioplayers/audioplayers.dart';
import 'dart:typed_data';
import 'dart:math';
import 'package:flutter/scheduler.dart';

/// 通知音效服务
class NotificationSoundService {
  static final NotificationSoundService _instance = NotificationSoundService._internal();
  factory NotificationSoundService() => _instance;
  NotificationSoundService._internal();

  final AudioPlayer _player = AudioPlayer();
  double _volume = 0.5; // 默认音量50%

  double get volume => _volume;

  void setVolume(double volume) {
    _volume = volume.clamp(0.0, 1.0);
    _player.setVolume(_volume);
  }

  /// 播放通知提示音
  Future<void> playNotificationSound() async {
    try {
      // 确保在主线程上执行音频播放
      SchedulerBinding.instance.addPostFrameCallback((_) async {
        try {
          // 生成一个简单的提示音（440Hz，持续200ms）
          final bytes = _generateBeepSound(
            frequency: 800, // Hz
            duration: 0.15, // seconds
            sampleRate: 44100,
          );

          await _player.stop();
          await _player.setVolume(_volume);
          await _player.play(BytesSource(bytes));
        } catch (e) {
          print('播放提示音失败: $e');
        }
      });
    } catch (e) {
      print('播放提示音失败: $e');
    }
  }

  /// 生成beep音频数据（16-bit PCM WAV格式）
  Uint8List _generateBeepSound({
    required double frequency,
    required double duration,
    required int sampleRate,
  }) {
    final numSamples = (sampleRate * duration).toInt();
    final data = <int>[];

    // WAV文件头（44字节）
    final dataSize = numSamples * 2; // 16-bit = 2 bytes per sample
    final fileSize = 36 + dataSize;

    // RIFF header
    data.addAll('RIFF'.codeUnits);
    data.addAll(_int32ToBytes(fileSize));
    data.addAll('WAVE'.codeUnits);

    // fmt chunk
    data.addAll('fmt '.codeUnits);
    data.addAll(_int32ToBytes(16)); // Chunk size
    data.addAll(_int16ToBytes(1)); // Audio format (1 = PCM)
    data.addAll(_int16ToBytes(1)); // Number of channels (1 = mono)
    data.addAll(_int32ToBytes(sampleRate)); // Sample rate
    data.addAll(_int32ToBytes(sampleRate * 2)); // Byte rate
    data.addAll(_int16ToBytes(2)); // Block align
    data.addAll(_int16ToBytes(16)); // Bits per sample

    // data chunk
    data.addAll('data'.codeUnits);
    data.addAll(_int32ToBytes(dataSize));

    // Generate samples with envelope (fade in/out to avoid clicks)
    for (int i = 0; i < numSamples; i++) {
      final t = i / sampleRate;

      // Envelope: fade in/out
      double envelope = 1.0;
      final fadeTime = 0.01; // 10ms fade
      if (t < fadeTime) {
        envelope = t / fadeTime;
      } else if (t > duration - fadeTime) {
        envelope = (duration - t) / fadeTime;
      }

      // Generate sine wave
      final sample = (sin(2 * pi * frequency * t) * envelope * 32767 * 0.5).toInt();
      data.addAll(_int16ToBytes(sample));
    }

    return Uint8List.fromList(data);
  }

  List<int> _int16ToBytes(int value) {
    return [value & 0xFF, (value >> 8) & 0xFF];
  }

  List<int> _int32ToBytes(int value) {
    return [
      value & 0xFF,
      (value >> 8) & 0xFF,
      (value >> 16) & 0xFF,
      (value >> 24) & 0xFF,
    ];
  }

  void dispose() {
    _player.dispose();
  }
}
