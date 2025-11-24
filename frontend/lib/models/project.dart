class Project {
  final String id;
  final String name;
  final String path;
  final DateTime createdAt;
  final DateTime? lastActiveAt;
  final int sessionCount;

  Project({
    required this.id,
    required this.name,
    required this.path,
    required this.createdAt,
    this.lastActiveAt,
    this.sessionCount = 0,
  });

  Project copyWith({
    String? id,
    String? name,
    String? path,
    DateTime? createdAt,
    DateTime? lastActiveAt,
    int? sessionCount,
  }) {
    return Project(
      id: id ?? this.id,
      name: name ?? this.name,
      path: path ?? this.path,
      createdAt: createdAt ?? this.createdAt,
      lastActiveAt: lastActiveAt ?? this.lastActiveAt,
      sessionCount: sessionCount ?? this.sessionCount,
    );
  }
}
