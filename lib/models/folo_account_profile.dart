class FoloAccountProfile {
  const FoloAccountProfile({this.userId, this.name, this.email, this.imageUrl});

  final String? userId;
  final String? name;
  final String? email;
  final String? imageUrl;

  String get displayName {
    final resolvedName = name?.trim();
    if (resolvedName != null && resolvedName.isNotEmpty) return resolvedName;
    final resolvedEmail = email?.trim();
    if (resolvedEmail != null && resolvedEmail.isNotEmpty) return resolvedEmail;
    return 'Folo 账号';
  }

  String get initials {
    final value = displayName.trim();
    if (value.isEmpty) return 'F';
    return String.fromCharCode(value.runes.first).toUpperCase();
  }

  Map<String, String> toJson() => {
    if (userId?.trim().isNotEmpty == true) 'userId': userId!.trim(),
    if (name?.trim().isNotEmpty == true) 'name': name!.trim(),
    if (email?.trim().isNotEmpty == true) 'email': email!.trim(),
    if (imageUrl?.trim().isNotEmpty == true) 'imageUrl': imageUrl!.trim(),
  };

  static FoloAccountProfile? fromJson(Object? value) {
    if (value is! Map) return null;
    String? read(String key) {
      final text = value[key]?.toString().trim();
      return text == null || text.isEmpty ? null : text;
    }

    final profile = FoloAccountProfile(
      userId: read('userId'),
      name: read('name'),
      email: read('email'),
      imageUrl: read('imageUrl'),
    );
    return profile.toJson().isEmpty ? null : profile;
  }
}
