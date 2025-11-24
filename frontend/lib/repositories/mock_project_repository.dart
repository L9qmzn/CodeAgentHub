import '../models/project.dart';
import '../models/session.dart';
import '../models/user_settings.dart';
import 'project_repository.dart';

class MockProjectRepository implements ProjectRepository {
  @override
  dynamic get apiService => null;

  @override
  Future<Session> getSession(String sessionId) async {
    await Future.delayed(const Duration(milliseconds: 300));
    return Session(
      id: sessionId,
      projectId: 'project-1',
      title: 'Test Session',
      name: 'Test Session',
      cwd: '/projects/test',
      createdAt: DateTime.now(),
      updatedAt: DateTime.now(),
      messageCount: 0,
    );
  }

  @override
  Future<List<Project>> getProjects() async {
    await Future.delayed(const Duration(milliseconds: 500));
    return [
      Project(
        id: 'project-1',
        name: 'Claude Code Mobile',
        path: '/projects/cc_mobile',
        createdAt: DateTime.now().subtract(const Duration(days: 5)),
        lastActiveAt: DateTime.now(),
        sessionCount: 3,
      ),
      Project(
        id: 'project-2',
        name: 'Flutter Demo',
        path: '/projects/flutter_demo',
        createdAt: DateTime.now().subtract(const Duration(days: 10)),
        lastActiveAt: DateTime.now().subtract(const Duration(days: 2)),
        sessionCount: 5,
      ),
      Project(
        id: 'project-3',
        name: 'Backend API',
        path: '/projects/backend',
        createdAt: DateTime.now().subtract(const Duration(days: 15)),
        lastActiveAt: DateTime.now().subtract(const Duration(days: 5)),
        sessionCount: 2,
      ),
    ];
  }

  @override
  Future<Project> getProject(String id) async {
    await Future.delayed(const Duration(milliseconds: 300));
    return Project(
      id: id,
      name: 'Test Project',
      path: '/projects/test',
      createdAt: DateTime.now(),
      lastActiveAt: DateTime.now(),
      sessionCount: 0,
    );
  }

  @override
  Future<List<Session>> getProjectSessions(String projectId) async {
    await Future.delayed(const Duration(milliseconds: 500));
    return [
      Session(
        id: 'session-1',
        projectId: projectId,
        title: 'Initial Setup',
        name: 'Initial Setup',
        cwd: '/projects/test',
        createdAt: DateTime.now().subtract(const Duration(days: 2)),
        updatedAt: DateTime.now(),
        messageCount: 15,
      ),
      Session(
        id: 'session-2',
        projectId: projectId,
        title: 'Feature Development',
        name: 'Feature Development',
        cwd: '/projects/test',
        createdAt: DateTime.now().subtract(const Duration(days: 1)),
        updatedAt: DateTime.now().subtract(const Duration(hours: 5)),
        messageCount: 23,
      ),
      Session(
        id: 'session-3',
        projectId: projectId,
        title: 'Bug Fixes',
        name: 'Bug Fixes',
        cwd: '/projects/test',
        createdAt: DateTime.now().subtract(const Duration(hours: 12)),
        updatedAt: DateTime.now().subtract(const Duration(hours: 2)),
        messageCount: 8,
      ),
    ];
  }

  @override
  Future<Map<String, int>> reloadSessions({String? claudeDir}) async {
    await Future.delayed(const Duration(seconds: 1));
    return {
      'sessions': 10,
      'agentRuns': 4,
    };
  }

  @override
  Future<ClaudeUserSettings> getUserSettings(String userId) async {
    await Future.delayed(const Duration(milliseconds: 300));
    return ClaudeUserSettings.defaults(userId);
  }

  @override
  Future<void> updateUserSettings(String userId, ClaudeUserSettings settings) async {
    await Future.delayed(const Duration(milliseconds: 300));
    // Mock implementation - do nothing
  }
}
