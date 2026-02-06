class SavedNote {
  final String id;
  final String text;
  final int lastUsedAt; // 👈 NEW

  SavedNote({
    required this.id,
    required this.text,
    required this.lastUsedAt,
  });

  Map<String, dynamic> toJson() => {
    'id': id,
    'text': text,
    'lastUsedAt': lastUsedAt,
  };

  factory SavedNote.fromJson(Map<String, dynamic> json) {
    return SavedNote(
      id: json['id'],
      text: json['text'],
      lastUsedAt: json['lastUsedAt'],
    );
  }

  SavedNote copyWith({int? lastUsedAt}) {
    return SavedNote(
      id: id,
      text: text,
      lastUsedAt: lastUsedAt ?? this.lastUsedAt,
    );
  }
}
