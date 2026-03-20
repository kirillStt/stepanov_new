import 'dart:io';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:stepanov_new/core/models/file_model.dart';
import 'package:stepanov_new/services/storage_service.dart';

class SupabaseStorageService implements StorageService {
  final SupabaseClient _supabase = Supabase.instance.client;
  
  static const String _bucketName = 'stepanov-web';

  String _transliterate(String text) {
  const cyrillic = 'АБВГДЕЁЖЗИЙКЛМНОПРСТУФХЦЧШЩЪЫЬЭЮЯабвгдеёжзийклмнопрстуфхцчшщъыьэюя';
  const latin = 'ABVGDEEZHZIJKLMNOPRSTUFHTSCHSHSHHYYEYUYABVGDEEZHZIJKLMNOPRSTUFHTSCHSHSHHYYEYUY';
  
  final buffer = StringBuffer();
  for (int i = 0; i < text.length; i++) {
    final char = text[i];
    final index = cyrillic.indexOf(char);
    if (index != -1) {
      buffer.write(latin[index]);
    } else if (char == ' ' || char == '_' || char == '-') {
      buffer.write('_');
    } else if (char == '[' || char == ']' || char == '(' || char == ')' || char == '{' || char == '}') {
      // пропускаем квадратные скобки и другие спецсимволы
      continue;
    } else if (RegExp(r'[a-zA-Z0-9]').hasMatch(char)) {
      buffer.write(char);
    } else {
      buffer.write('_');
    }
  }
  // удаляем повторяющиеся подчёркивания
  return buffer.toString().replaceAll(RegExp(r'_+'), '_').replaceAll(RegExp(r'^_|_$'), '');
}

  @override
  Future<List<FileModel>> getUserFiles(String userId) async {
    try {
      final List<FileObject> files = await _supabase.storage
          .from(_bucketName)
          .list(path: userId);
      
      final List<FileModel> result = [];
      
      for (var file in files) {
        if (file.name != null && !file.name!.endsWith('/')) {
          final String filePath = '$userId/${file.name}';
          final String publicUrl = _supabase.storage
              .from(_bucketName)
              .getPublicUrl(filePath);
          
          int fileSize = 0;
          if (file.metadata != null && file.metadata!.containsKey('size')) {
            final sizeValue = file.metadata!['size'];
            if (sizeValue is int) {
              fileSize = sizeValue;
            }
          }
          
          DateTime modifiedAt = DateTime.now();
          if (file.updatedAt != null) {
            try {
              if (file.updatedAt is DateTime) {
                modifiedAt = file.updatedAt as DateTime;
              } else if (file.updatedAt is String) {
                modifiedAt = DateTime.parse(file.updatedAt as String);
              }
            } catch (e) {
              print('Ошибка парсинга даты: $e');
            }
          }
          
          result.add(FileModel(
            id: filePath,
            name: file.name!,
            path: filePath,
            size: fileSize,
            modifiedAt: modifiedAt,
            downloadUrl: publicUrl,
          ));
        }
      }
      
      return result;
    } catch (e) {
      print('Ошибка получения файлов из Supabase: $e');
      return [];
    }
  }

  @override
  Future<FileModel?> uploadFile(
    File file, 
    String fileName, 
    String userId, {
    String? mimeType,
  }) async {
    try {
      // Транслитерируем имя файла
      final safeFileName = _transliterate(fileName);
      final String filePath = '$userId/$safeFileName';
      final int fileSize = await file.length();
      
      print('Оригинальное имя: $fileName');
      print('Безопасное имя для Supabase: $safeFileName');
      
      final response = await _supabase.storage
          .from(_bucketName)
          .upload(
            filePath,
            file,
            fileOptions: FileOptions(
              cacheControl: '3600',
              contentType: mimeType,
            ),
          );
      
      if (response.isEmpty) {
        print('Ошибка: пустой ответ от Supabase');
        return null;
      }
      
      final String publicUrl = _supabase.storage
          .from(_bucketName)
          .getPublicUrl(filePath);
      
      print('Файл загружен: $safeFileName, размер: $fileSize байт');
      
      return FileModel(
        id: filePath,
        name: fileName, // Оригинальное имя для пользователя
        path: filePath,
        size: fileSize,
        modifiedAt: DateTime.now(),
        downloadUrl: publicUrl,
      );
    } catch (e) {
      print('Ошибка загрузки в Supabase: $e');
      return null;
    }
  }

  @override
  Future<bool> deleteFile(String filePath) async {
    try {
      await _supabase.storage
          .from(_bucketName)
          .remove([filePath]);
      return true;
    } catch (e) {
      print('Ошибка удаления из Supabase: $e');
      return false;
    }
  }

  @override
  Future<String?> getDownloadUrl(String filePath) async {
    try {
      return _supabase.storage
          .from(_bucketName)
          .getPublicUrl(filePath);
    } catch (e) {
      print('Ошибка получения URL: $e');
      return null;
    }
  }
}