class SavedNote {
  final String id;
  final String text;

  SavedNote({
    required this.id,
    required this.text,
  });

  Map<String, dynamic> toJson() => {
    'id': id,
    'text': text,
  };

  factory SavedNote.fromJson(Map<String, dynamic> json) {
    return SavedNote(
      id: json['id'],
      text: json['text'],
    );
  }
}
