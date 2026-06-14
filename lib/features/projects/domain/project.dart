class Project {
  final String id;
  final String name;
  final int createdAtMs;
  final int updatedAtMs;

  const Project({
    required this.id,
    required this.name,
    required this.createdAtMs,
    required this.updatedAtMs,
  });

  factory Project.fromJson(Map<String, dynamic> json) {
    return Project(
      id: json['id'] as String? ?? '',
      name: json['name'] as String? ?? '',
      createdAtMs: json['createdAtMs'] as int? ?? 0,
      updatedAtMs: json['updatedAtMs'] as int? ?? 0,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'name': name,
      'createdAtMs': createdAtMs,
      'updatedAtMs': updatedAtMs,
    };
  }

  Project copyWith({
    String? name,
    int? updatedAtMs,
  }) {
    return Project(
      id: id,
      name: name ?? this.name,
      createdAtMs: createdAtMs,
      updatedAtMs: updatedAtMs ?? this.updatedAtMs,
    );
  }
}
