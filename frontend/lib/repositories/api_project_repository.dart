import '../models/project.dart';
import '../models/session.dart';
import '../models/user_settings.dart';
import '../services/api_service.dart';
import 'project_repository.dart';

class ApiProjectRepository implements ProjectRepository {
  final ApiService _apiService;

  ApiProjectRepository(this._apiService);

  @override
  ApiService get apiService => _apiService;

  @override
  Future<List<Project>> getProjects() async {
    final sessions = await _apiService.getSessions();

    // Group sessions by cwd to create projects
    final Map<String, List<Map<String, dynamic>>> projectMap = {};
    for (var session in sessions) {
      final cwd = session['cwd'] as String;
      projectMap.putIfAbsent(cwd, () => []).add(session);
    }

    // Convert to Project list
    final projects = <Project>[];
    projectMap.forEach((cwd, sessions) {
      // Use the directory name as project name
      final name = cwd.split(RegExp(r'[/\\]')).last;

      // Find the earliest created_at and latest updated_at
      DateTime? earliest;
      DateTime? latest;
      int totalMessages = 0;

      for (var session in sessions) {
        final createdAt = DateTime.parse(session['created_at']);
        final updatedAt = DateTime.parse(session['updated_at']);
        totalMessages += (session['message_count'] as int?) ?? 0;

        if (earliest == null || createdAt.isBefore(earliest)) {
          earliest = createdAt;
        }
        if (latest == null || updatedAt.isAfter(latest)) {
          latest = updatedAt;
        }
      }

      projects.add(Project(
        id: cwd, // Use cwd as unique ID
        name: name,
        path: cwd,
        createdAt: earliest ?? DateTime.now(),
        lastActiveAt: latest,
        sessionCount: sessions.length,
      ));
    });

    // Sort by lastActiveAt descending
    projects.sort((a, b) {
      if (a.lastActiveAt == null && b.lastActiveAt == null) return 0;
      if (a.lastActiveAt == null) return 1;
      if (b.lastActiveAt == null) return -1;
      return b.lastActiveAt!.compareTo(a.lastActiveAt!);
    });

    return projects;
  }

  @override
  Future<Project> getProject(String id) async {
    final projects = await getProjects();
    return projects.firstWhere(
      (p) => p.id == id,
      orElse: () => throw Exception('Project not found'),
    );
  }

  @override
  Future<List<Session>> getProjectSessions(String projectId) async {
    final allSessions = await _apiService.getSessions();

    // Filter sessions by cwd (projectId is the cwd)
    final projectSessions = allSessions
        .where((s) => s['cwd'] == projectId)
        .map((s) => Session(
              id: s['session_id'],
              projectId: projectId,
              title: s['title'],
              name: s['title'], // Use title as name
              cwd: s['cwd'],
              createdAt: DateTime.parse(s['created_at']),
              updatedAt: DateTime.parse(s['updated_at']),
              messageCount: s['message_count'] ?? 0,
            ))
        .toList();

    // Sort by updatedAt descending
    projectSessions.sort((a, b) => b.updatedAt.compareTo(a.updatedAt));

    return projectSessions;
  }

  @override
  Future<Session> getSession(String sessionId) async {
    final data = await _apiService.getSession(sessionId);
    return Session(
      id: data['session_id'],
      projectId: data['cwd'],
      title: data['title'],
      name: data['title'],
      cwd: data['cwd'],
      createdAt: DateTime.parse(data['created_at']),
      updatedAt: DateTime.parse(data['updated_at']),
      messageCount: (data['messages'] as List).length,
    );
  }

  @override
  Future<Map<String, int>> reloadSessions({String? claudeDir}) async {
    final result = await _apiService.loadSessions(claudeDir: claudeDir);
    return {
      'sessions': result['sessions_loaded'] as int? ?? 0,
      'agentRuns': result['agent_runs_loaded'] as int? ?? 0,
    };
  }

  @override
  Future<ClaudeUserSettings> getUserSettings(String userId) async {
    try {
      final data = await _apiService.getUserSettings(userId);
      return ClaudeUserSettings.fromJson({
        'user_id': userId,
        ...data,
      });
    } catch (e) {
      return ClaudeUserSettings.defaults(userId);
    }
  }

  @override
  Future<void> updateUserSettings(String userId, ClaudeUserSettings settings) async {
    await _apiService.updateUserSettings(userId, settings.toJson());
  }
}
