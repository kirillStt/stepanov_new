class FileModel {
  final String id;
  final String name;
  final String path;
  final int size;
  final DateTime modifiedAt;
  final bool isFolder;
  final String? downloadUrl;  // новое поле для Firebase

  FileModel({
    required this.id,
    required this.name,
    required this.path,
    required this.size,
    required this.modifiedAt,
    this.isFolder = false,
    this.downloadUrl,
  });

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'name': name,
      'path': path,
      'size': size,
      'modifiedAt': modifiedAt.toIso8601String(),
      'isFolder': isFolder,
      'downloadUrl': downloadUrl,
    };
  }

  factory FileModel.fromJson(Map<String, dynamic> json) {
    return FileModel(
      id: json['id'],
      name: json['name'],
      path: json['path'],
      size: json['size'],
      modifiedAt: DateTime.parse(json['modifiedAt']),
      isFolder: json['isFolder'] ?? false,
      downloadUrl: json['downloadUrl'],
    );
  }

  String get readableSize {
    if (size < 1024) return '$size B';
    if (size < 1048576) return '${(size / 1024).toStringAsFixed(1)} KB';
    if (size < 1073741824) return '${(size / 1048576).toStringAsFixed(1)} MB';
    return '${(size / 1073741824).toStringAsFixed(1)} GB';
  }
}