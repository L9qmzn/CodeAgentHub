import 'dart:convert';
import 'package:http/http.dart' as http;
import '../models/session_settings.dart';
import 'auth_service.dart';

class ApiService {
  String baseUrl;
  final AuthService? authService;

  ApiService({
    this.baseUrl = 'http://127.0.0.1:8207',
    this.authService,
  });

  /// Update the base URL dynamically
  void updateBaseUrl(String newUrl) {
    baseUrl = newUrl;
    print('DEBUG: ApiService baseUrl updated to: $newUrl');
  }

  Map<String, String> _getHeaders() {
    final headers = <String, String>{
      'Content-Type': 'application/json',
    };

    // Add Basic Auth header if available
    final authHeader = authService?.basicAuthHeader;
    if (authHeader != null) {
      headers['Authorization'] = authHeader;
    }

    return headers;
  }

  Future<List<Map<String, dynamic>>> getSessions() async {
    final response = await http.get(
      Uri.parse('$baseUrl/sessions'),
      headers: _getHeaders(),
    );

    if (response.statusCode == 200) {
      final List<dynamic> data = json.decode(response.body);
      return data.cast<Map<String, dynamic>>();
    } else {
      throw Exception('Failed to load sessions: ${response.statusCode}');
    }
  }

  Future<Map<String, dynamic>> getSession(String sessionId) async {
    final response = await http.get(
      Uri.parse('$baseUrl/sessions/$sessionId'),
      headers: _getHeaders(),
    );

    if (response.statusCode == 200) {
      return json.decode(response.body);
    } else {
      throw Exception('Failed to load session: ${response.statusCode}');
    }
  }

  Stream<Map<String, dynamic>> chat({
    String? sessionId,
    dynamic message,  // 支持 String 或 Map (包含content数组)
    String? cwd,
    SessionSettings? settings,
  }) async* {
    final body = <String, dynamic>{};

    if (sessionId != null) {
      body['session_id'] = sessionId;
    }

    // message 可以是字符串或包含content的对象
    body['message'] = message;

    if (cwd != null) {
      body['cwd'] = cwd;
    }

    // Add settings if provided
    if (settings != null) {
      body['permission_mode'] = settings.permissionMode.value;
      if (settings.systemPrompt != null) {
        body['system_prompt'] = settings.systemPrompt;
      }
      body['setting_sources'] = settings.settingSources;
      // Add advanced_options if present (对话级高级设置)
      if (settings.advancedOptions != null && settings.advancedOptions!.isNotEmpty) {
        body['advanced_options'] = settings.advancedOptions;
      }
    }

    final request = http.Request('POST', Uri.parse('$baseUrl/chat'));
    request.headers.addAll(_getHeaders());
    request.body = json.encode(body);

    final streamedResponse = await request.send();

    if (streamedResponse.statusCode != 200) {
      throw Exception('Chat request failed: ${streamedResponse.statusCode}');
    }

    String? currentEvent;
    final buffer = StringBuffer();

    await for (var chunk in streamedResponse.stream.transform(utf8.decoder)) {
      buffer.write(chunk);
      final content = buffer.toString();
      final lines = content.split('\n');

      // Keep the last incomplete line in buffer
      buffer.clear();
      if (!content.endsWith('\n')) {
        buffer.write(lines.last);
        lines.removeLast();
      }

      for (var line in lines) {
        line = line.trim();
        if (line.isEmpty) {
          // Empty line marks end of event
          currentEvent = null;
          continue;
        }

        if (line.startsWith('event: ')) {
          currentEvent = line.substring(7);
        } else if (line.startsWith('data: ')) {
          final data = line.substring(6);
          if (data.trim().isNotEmpty && currentEvent != null) {
            try {
              final parsed = json.decode(data);
              // Yield event with type
              yield {
                'event_type': currentEvent,
                ...parsed,
              };
            } catch (e) {
              // Skip invalid JSON
            }
          }
        }
      }
    }
  }

  Future<Map<String, dynamic>> loadSessions({String? claudeDir}) async {
    final body = <String, dynamic>{};
    if (claudeDir != null) {
      body['claude_dir'] = claudeDir;
    }

    final response = await http.post(
      Uri.parse('$baseUrl/sessions/load'),
      headers: _getHeaders(),
      body: json.encode(body),
    );

    if (response.statusCode == 200) {
      return json.decode(response.body);
    } else {
      throw Exception('Failed to load sessions: ${response.statusCode}');
    }
  }

  // Get user settings for Claude Code
  Future<Map<String, dynamic>> getUserSettings(String userId) async {
    final response = await http.get(
      Uri.parse('$baseUrl/users/$userId/settings'),
      headers: _getHeaders(),
    );

    if (response.statusCode == 200) {
      return json.decode(response.body);
    } else {
      throw Exception('Failed to load user settings: ${response.statusCode}');
    }
  }

  // Update user settings for Claude Code
  Future<void> updateUserSettings(String userId, Map<String, dynamic> settings) async {
    final response = await http.put(
      Uri.parse('$baseUrl/users/$userId/settings'),
      headers: _getHeaders(),
      body: json.encode(settings),
    );

    if (response.statusCode != 200) {
      throw Exception('Failed to update user settings: ${response.statusCode}');
    }
  }

  // Stop a running chat task
  Future<void> stopChat(String runId) async {
    final response = await http.post(
      Uri.parse('$baseUrl/chat/stop'),
      headers: _getHeaders(),
      body: json.encode({'run_id': runId}),
    );

    if (response.statusCode != 200 && response.statusCode != 404) {
      throw Exception('Failed to stop chat: ${response.statusCode}');
    }
  }
}
