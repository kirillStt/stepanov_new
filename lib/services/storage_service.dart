import 'dart:io';
import 'package:stepanov_new/core/models/file_model.dart';

abstract class StorageService {
  Future<List<FileModel>> getUserFiles(String userId);
  Future<FileModel?> uploadFile(
    File file, 
    String fileName, 
    String userId, {
    String? mimeType, // Добавлен опциональный параметр
  });
  Future<bool> deleteFile(String filePath);
  Future<String?> getDownloadUrl(String filePath);
}