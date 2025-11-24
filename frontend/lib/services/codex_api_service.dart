import 'dart:convert';
import 'package:http/http.dart' as http;
import '../models/session_settings.dart';
import 'auth_service.dart';

class CodexApiService {
  String baseUrl;
  final AuthService? authService;

  CodexApiService({
    this.baseUrl = 'http://127.0.0.1:8207',
    this.authService,
  });

  /// Update the base URL dynamically
  void updateBaseUrl(String newUrl) {
    baseUrl = newUrl;
    print('DEBUG: CodexApiService baseUrl updated to: $newUrl');
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
      Uri.parse('$baseUrl/codex/sessions'),
      headers: _getHeaders(),
    );

    if (response.statusCode == 200) {
      final List<dynamic> data = json.decode(response.body);
      return data.cast<Map<String, dynamic>>();
    } else {
      throw Exception('Failed to load codex sessions: ${response.statusCode}');
    }
  }

  Future<Map<String, dynamic>> getSession(String sessionId) async {
    final url = '$baseUrl/codex/sessions/$sessionId';
    print('DEBUG CodexApiService: GET $url');

    final response = await http.get(
      Uri.parse(url),
      headers: _getHeaders(),
    );

    print('DEBUG CodexApiService: Response status=${response.statusCode}');
    if (response.statusCode == 200) {
      final data = json.decode(response.body);
      print('DEBUG CodexApiService: Response body keys=${data.keys.toList()}');
      return data;
    } else {
      print('DEBUG CodexApiService: Error response body=${response.body}');
      throw Exception('Failed to load codex session: ${response.statusCode}');
    }
  }

  Stream<Map<String, dynamic>> chat({
    String? sessionId,
    required String message,
    String? cwd,
    SessionSettings? settings,
    // Codex-specific parameters
    String? approvalPolicy,
    String? sandboxMode,
    String? model,
    String? modelReasoningEffort,
    bool? networkAccessEnabled,
    bool? webSearchEnabled,
    bool? skipGitRepoCheck,
  }) async* {
    final body = <String, dynamic>{};

    if (sessionId != null) {
      body['session_id'] = sessionId;
    }
    body['message'] = message;

    if (cwd != null) {
      body['cwd'] = cwd;
    }

    // Add codex-specific settings
    if (approvalPolicy != null) {
      body['approval_policy'] = approvalPolicy;
    }
    if (sandboxMode != null) {
      body['sandbox_mode'] = sandboxMode;
    }
    if (model != null) {
      body['model'] = model;
    }
    if (modelReasoningEffort != null) {
      body['model_reasoning_effort'] = modelReasoningEffort;
    }
    if (networkAccessEnabled != null) {
      body['network_access_enabled'] = networkAccessEnabled;
    }
    if (webSearchEnabled != null) {
      body['web_search_enabled'] = webSearchEnabled;
    }
    if (skipGitRepoCheck != null) {
      body['skip_git_repo_check'] = skipGitRepoCheck;
    }

    // Also include permission_mode and system_prompt if provided in settings
    // (backend might use them if supported)
    if (settings != null) {
      body['permission_mode'] = settings.permissionMode.value;
      if (settings.systemPrompt != null) {
        body['system_prompt'] = settings.systemPrompt;
      }
      body['setting_sources'] = settings.settingSources;
    }

    final request = http.Request('POST', Uri.parse('$baseUrl/codex/chat'));
    request.headers.addAll(_getHeaders());
    request.body = json.encode(body);

    final streamedResponse = await request.send();

    if (streamedResponse.statusCode != 200) {
      throw Exception('Codex chat request failed: ${streamedResponse.statusCode}');
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

  Future<Map<String, dynamic>> loadSessions({String? codexDir}) async {
    final body = <String, dynamic>{};
    if (codexDir != null) {
      body['codex_dir'] = codexDir;
    }

    final response = await http.post(
      Uri.parse('$baseUrl/codex/sessions/load'),
      headers: _getHeaders(),
      body: json.encode(body),
    );

    if (response.statusCode == 200) {
      return json.decode(response.body);
    } else {
      throw Exception('Failed to load codex sessions: ${response.statusCode}');
    }
  }

  // Get user settings for Codex
  Future<Map<String, dynamic>> getUserSettings(String userId) async {
    final response = await http.get(
      Uri.parse('$baseUrl/codex/users/$userId/settings'),
      headers: _getHeaders(),
    );

    if (response.statusCode == 200) {
      return json.decode(response.body);
    } else {
      throw Exception('Failed to load codex user settings: ${response.statusCode}');
    }
  }

  // Update user settings for Codex
  Future<void> updateUserSettings(String userId, Map<String, dynamic> settings) async {
    final response = await http.put(
      Uri.parse('$baseUrl/codex/users/$userId/settings'),
      headers: _getHeaders(),
      body: json.encode(settings),
    );

    if (response.statusCode != 200) {
      throw Exception('Failed to update codex user settings: ${response.statusCode}');
    }
  }
}
