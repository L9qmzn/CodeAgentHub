class Session {
  final String id;
  final String projectId;
  final String title;
  final String name;
  final String cwd;
  final DateTime createdAt;
  final DateTime updatedAt;
  final int messageCount;

  Session({
    required this.id,
    required this.projectId,
    required this.title,
    required this.name,
    required this.cwd,
    required this.createdAt,
    required this.updatedAt,
    this.messageCount = 0,
  });

  Session copyWith({
    String? id,
    String? projectId,
    String? title,
    String? name,
    String? cwd,
    DateTime? createdAt,
    DateTime? updatedAt,
    int? messageCount,
  }) {
    return Session(
      id: id ?? this.id,
      projectId: projectId ?? this.projectId,
      title: title ?? this.title,
      name: name ?? this.name,
      cwd: cwd ?? this.cwd,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
      messageCount: messageCount ?? this.messageCount,
    );
  }
}
