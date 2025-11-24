import 'dart:async';
import 'package:flutter/foundation.dart';
import '../models/project.dart';
import '../models/session.dart';
import '../repositories/project_repository.dart';
import '../repositories/codex_repository.dart';

/// 共享项目数据服务（单例）
/// 用于在多个 HomeScreen 实例之间共享项目列表和最近对话数据
/// 避免重复请求，确保数据一致性
class SharedProjectDataService {
  // 单例模式
  static SharedProjectDataService? _instance;
  static SharedProjectDataService get instance {
    _instance ??= SharedProjectDataService._();
    return _instance!;
  }

  SharedProjectDataService._();

  // Repository 引用
  ProjectRepository? _claudeRepository;
  CodexRepository? _codexRepository;

  // 缓存数据 - 项目列表
  List<Project> _claudeProjects = [];
  List<Project> _codexProjects = [];

  // 缓存数据 - 最近对话
  List<Session> _claudeRecentSessions = [];
  List<Session> _codexRecentSessions = [];

  // 上次刷新时间 - 项目列表
  DateTime? _lastClaudeRefresh;
  DateTime? _lastCodexRefresh;

  // 上次刷新时间 - 最近对话
  DateTime? _lastClaudeSessionsRefresh;
  DateTime? _lastCodexSessionsRefresh;

  // 刷新间隔（默认30秒）
  Duration _refreshInterval = const Duration(seconds: 30);

  // 是否正在加载 - 项目列表
  bool _isLoadingClaude = false;
  bool _isLoadingCodex = false;

  // 是否正在加载 - 最近对话
  bool _isLoadingClaudeSessions = false;
  bool _isLoadingCodexSessions = false;

  // 数据变化通知器 - 项目列表
  final ValueNotifier<List<Project>> claudeProjectsNotifier = ValueNotifier([]);
  final ValueNotifier<List<Project>> codexProjectsNotifier = ValueNotifier([]);

  // 数据变化通知器 - 最近对话
  final ValueNotifier<List<Session>> claudeRecentSessionsNotifier = ValueNotifier([]);
  final ValueNotifier<List<Session>> codexRecentSessionsNotifier = ValueNotifier([]);

  // 加载状态通知器 - 项目列表
  final ValueNotifier<bool> claudeLoadingNotifier = ValueNotifier(false);
  final ValueNotifier<bool> codexLoadingNotifier = ValueNotifier(false);

  // 加载状态通知器 - 最近对话
  final ValueNotifier<bool> claudeSessionsLoadingNotifier = ValueNotifier(false);
  final ValueNotifier<bool> codexSessionsLoadingNotifier = ValueNotifier(false);

  // 错误通知器 - 项目列表
  final ValueNotifier<String?> claudeErrorNotifier = ValueNotifier(null);
  final ValueNotifier<String?> codexErrorNotifier = ValueNotifier(null);

  // 错误通知器 - 最近对话
  final ValueNotifier<String?> claudeSessionsErrorNotifier = ValueNotifier(null);
  final ValueNotifier<String?> codexSessionsErrorNotifier = ValueNotifier(null);

  // 定时刷新器
  Timer? _autoRefreshTimer;

  /// 初始化服务
  void initialize({
    required ProjectRepository claudeRepository,
    required CodexRepository codexRepository,
    Duration? refreshInterval,
  }) {
    _claudeRepository = claudeRepository;
    _codexRepository = codexRepository;
    if (refreshInterval != null) {
      _refreshInterval = refreshInterval;
    }

    // 启动自动刷新定时器
    _startAutoRefresh();
  }

  /// 启动自动刷新
  void _startAutoRefresh() {
    _autoRefreshTimer?.cancel();
    _autoRefreshTimer = Timer.periodic(_refreshInterval, (_) {
      // 自动刷新不强制，只有过期才刷新
      _checkAndRefresh(isCodex: false, force: false);
      _checkAndRefresh(isCodex: true, force: false);
    });
  }

  /// 检查并刷新数据
  Future<void> _checkAndRefresh({required bool isCodex, required bool force}) async {
    final lastRefresh = isCodex ? _lastCodexRefresh : _lastClaudeRefresh;
    final isExpired = lastRefresh == null ||
        DateTime.now().difference(lastRefresh) > _refreshInterval;

    if (force || isExpired) {
      await refresh(isCodex: isCodex, force: true);
    }
  }

  /// 获取项目列表（优先返回缓存）
  List<Project> getProjects({required bool isCodex}) {
    return isCodex ? List.unmodifiable(_codexProjects) : List.unmodifiable(_claudeProjects);
  }

  /// 检查缓存是否有效
  bool isCacheValid({required bool isCodex}) {
    final lastRefresh = isCodex ? _lastCodexRefresh : _lastClaudeRefresh;
    if (lastRefresh == null) return false;
    return DateTime.now().difference(lastRefresh) <= _refreshInterval;
  }

  /// 刷新项目列表
  /// [force] - true: 强制刷新; false: 只在过期时刷新
  Future<List<Project>> refresh({required bool isCodex, bool force = false}) async {
    // 检查是否需要刷新
    if (!force && isCacheValid(isCodex: isCodex)) {
      return getProjects(isCodex: isCodex);
    }

    // 检查是否正在加载
    final isLoading = isCodex ? _isLoadingCodex : _isLoadingClaude;
    if (isLoading) {
      // 等待当前加载完成
      return getProjects(isCodex: isCodex);
    }

    // 设置加载状态
    if (isCodex) {
      _isLoadingCodex = true;
      codexLoadingNotifier.value = true;
      codexErrorNotifier.value = null;
    } else {
      _isLoadingClaude = true;
      claudeLoadingNotifier.value = true;
      claudeErrorNotifier.value = null;
    }

    try {
      final List<Project> projects;
      if (isCodex) {
        if (_codexRepository == null) {
          throw Exception('Codex repository not initialized');
        }
        projects = await _codexRepository!.getProjects();
      } else {
        if (_claudeRepository == null) {
          throw Exception('Claude repository not initialized');
        }
        projects = await _claudeRepository!.getProjects();
      }

      // 更新缓存
      if (isCodex) {
        _codexProjects = projects;
        _lastCodexRefresh = DateTime.now();
        codexProjectsNotifier.value = List.unmodifiable(projects);
      } else {
        _claudeProjects = projects;
        _lastClaudeRefresh = DateTime.now();
        claudeProjectsNotifier.value = List.unmodifiable(projects);
      }

      print('SharedProjectDataService: Refreshed ${isCodex ? "Codex" : "Claude"} projects, count: ${projects.length}');
      return projects;
    } catch (e) {
      print('SharedProjectDataService: Error refreshing ${isCodex ? "Codex" : "Claude"} projects: $e');
      if (isCodex) {
        codexErrorNotifier.value = e.toString();
      } else {
        claudeErrorNotifier.value = e.toString();
      }
      return getProjects(isCodex: isCodex);
    } finally {
      // 清除加载状态
      if (isCodex) {
        _isLoadingCodex = false;
        codexLoadingNotifier.value = false;
      } else {
        _isLoadingClaude = false;
        claudeLoadingNotifier.value = false;
      }
    }
  }

  /// 强制刷新所有数据
  Future<void> refreshAll({bool force = true}) async {
    await Future.wait([
      refresh(isCodex: false, force: force),
      refresh(isCodex: true, force: force),
    ]);
  }

  /// 清除缓存
  void clearCache({bool? isCodex}) {
    if (isCodex == null || !isCodex) {
      _claudeProjects = [];
      _lastClaudeRefresh = null;
      claudeProjectsNotifier.value = [];
    }
    if (isCodex == null || isCodex) {
      _codexProjects = [];
      _lastCodexRefresh = null;
      codexProjectsNotifier.value = [];
    }
  }

  /// 获取上次刷新时间
  DateTime? getLastRefreshTime({required bool isCodex}) {
    return isCodex ? _lastCodexRefresh : _lastClaudeRefresh;
  }

  /// 设置刷新间隔
  void setRefreshInterval(Duration interval) {
    _refreshInterval = interval;
    _startAutoRefresh(); // 重启定时器
  }

  /// 手动触发刷新（给 UI 调用）
  /// 这会强制刷新数据，所有监听者都会收到更新
  Future<void> manualRefresh({required bool isCodex}) async {
    await refresh(isCodex: isCodex, force: true);
  }

  // ==================== 最近对话相关方法 ====================

  /// 获取最近对话（从缓存）
  List<Session> getRecentSessions({required bool isCodex}) {
    return isCodex ? _codexRecentSessions : _claudeRecentSessions;
  }

  /// 刷新最近对话
  Future<List<Session>> refreshRecentSessions({
    required bool isCodex,
    bool force = false,
    int limit = 50,
  }) async {
    // 检查是否需要刷新
    final lastRefresh = isCodex ? _lastCodexSessionsRefresh : _lastClaudeSessionsRefresh;
    if (!force && lastRefresh != null) {
      final timeSinceRefresh = DateTime.now().difference(lastRefresh);
      if (timeSinceRefresh < _refreshInterval) {
        // 未过期，返回缓存数据
        return getRecentSessions(isCodex: isCodex);
      }
    }

    // 防止重复加载
    final isLoading = isCodex ? _isLoadingCodexSessions : _isLoadingClaudeSessions;
    if (isLoading) {
      return getRecentSessions(isCodex: isCodex);
    }

    // 设置加载状态
    if (isCodex) {
      _isLoadingCodexSessions = true;
      codexSessionsLoadingNotifier.value = true;
      codexSessionsErrorNotifier.value = null;
    } else {
      _isLoadingClaudeSessions = true;
      claudeSessionsLoadingNotifier.value = true;
      claudeSessionsErrorNotifier.value = null;
    }

    try {
      final List<Session> sessions;
      if (isCodex) {
        if (_codexRepository == null) {
          throw Exception('Codex repository not initialized');
        }
        // 获取所有项目的最近对话
        final projects = await _codexRepository!.getProjects();
        final allSessions = <Session>[];
        for (final project in projects) {
          final projectSessions = await _codexRepository!.getProjectSessions(project.id);
          allSessions.addAll(projectSessions);
        }
        // 按更新时间排序并限制数量
        allSessions.sort((a, b) => b.updatedAt.compareTo(a.updatedAt));
        sessions = allSessions.take(limit).toList();
      } else {
        if (_claudeRepository == null) {
          throw Exception('Claude repository not initialized');
        }
        // 获取所有项目的最近对话
        final projects = await _claudeRepository!.getProjects();
        final allSessions = <Session>[];
        for (final project in projects) {
          final projectSessions = await _claudeRepository!.getProjectSessions(project.id);
          allSessions.addAll(projectSessions);
        }
        // 按更新时间排序并限制数量
        allSessions.sort((a, b) => b.updatedAt.compareTo(a.updatedAt));
        sessions = allSessions.take(limit).toList();
      }

      // 更新缓存
      if (isCodex) {
        _codexRecentSessions = sessions;
        _lastCodexSessionsRefresh = DateTime.now();
        codexRecentSessionsNotifier.value = List.unmodifiable(sessions);
      } else {
        _claudeRecentSessions = sessions;
        _lastClaudeSessionsRefresh = DateTime.now();
        claudeRecentSessionsNotifier.value = List.unmodifiable(sessions);
      }

      print('SharedProjectDataService: Refreshed ${isCodex ? "Codex" : "Claude"} recent sessions, count: ${sessions.length}');
      return sessions;
    } catch (e) {
      print('SharedProjectDataService: Error refreshing ${isCodex ? "Codex" : "Claude"} recent sessions: $e');
      if (isCodex) {
        codexSessionsErrorNotifier.value = e.toString();
      } else {
        claudeSessionsErrorNotifier.value = e.toString();
      }
      return getRecentSessions(isCodex: isCodex);
    } finally {
      // 清除加载状态
      if (isCodex) {
        _isLoadingCodexSessions = false;
        codexSessionsLoadingNotifier.value = false;
      } else {
        _isLoadingClaudeSessions = false;
        claudeSessionsLoadingNotifier.value = false;
      }
    }
  }

  /// 手动刷新最近对话
  Future<void> manualRefreshRecentSessions({required bool isCodex, int limit = 50}) async {
    await refreshRecentSessions(isCodex: isCodex, force: true, limit: limit);
  }

  /// 释放资源
  void dispose() {
    _autoRefreshTimer?.cancel();
    claudeProjectsNotifier.dispose();
    codexProjectsNotifier.dispose();
    claudeLoadingNotifier.dispose();
    codexLoadingNotifier.dispose();
    claudeErrorNotifier.dispose();
    codexErrorNotifier.dispose();
    claudeRecentSessionsNotifier.dispose();
    codexRecentSessionsNotifier.dispose();
    claudeSessionsLoadingNotifier.dispose();
    codexSessionsLoadingNotifier.dispose();
    claudeSessionsErrorNotifier.dispose();
    codexSessionsErrorNotifier.dispose();
    _instance = null;
  }

  /// 重置单例（用于测试或登出）
  static void reset() {
    _instance?.dispose();
    _instance = null;
  }
}
