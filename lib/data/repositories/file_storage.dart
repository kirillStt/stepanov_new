import 'dart:io';
import 'dart:convert';
import 'package:path_provider/path_provider.dart';
import 'package:stepanov_new/core/models/file_model.dart';

class FileStorage {
  static final FileStorage _instance = FileStorage._internal();
  factory FileStorage() => _instance;
  FileStorage._internal();

  late Directory _appDir;
  late File _metadataFile;

  // Инициализация хранилища
  Future<void> init() async {
    _appDir = await getApplicationDocumentsDirectory();
    _metadataFile = File('${_appDir.path}/files_metadata.json');
    await _ensureFileExists();
  }

  // Проверка существования файла
  Future<void> _ensureFileExists() async {
    if (!await _metadataFile.exists()) {
      await _metadataFile.create(recursive: true);
      await _metadataFile.writeAsString('[]');
    }
  }

 // Сохранение списка файлов (теперь принимает List<FileModel>)
Future<void> saveFiles(List<FileModel> files) async {
  try {
    List<Map<String, dynamic>> filesJson = files.map((f) => f.toJson()).toList();
    String jsonData = jsonEncode(filesJson);
    await _metadataFile.writeAsString(jsonData);
  } catch (e) {
    print('Ошибка сохранения: $e');
  }
}

// Загрузка списка файлов (теперь возвращает List<FileModel>)
Future<List<FileModel>> loadFiles() async {
  try {
    await _ensureFileExists();
    String jsonData = await _metadataFile.readAsString();
    List<dynamic> jsonList = jsonDecode(jsonData);
    return jsonList.map((json) => FileModel.fromJson(json)).toList();
  } catch (e) {
    print('Ошибка загрузки: $e');
    return [];
  }
}

  // Копирование файла в хранилище приложения
  Future<File?> copyFileToStorage(File sourceFile, String fileName) async {
    try {
      // Создаем папку для файлов если её нет
      Directory filesDir = Directory('${_appDir.path}/files');
      if (!await filesDir.exists()) {
        await filesDir.create(recursive: true);
      }

      // Генерируем уникальное имя
      String timestamp = DateTime.now().millisecondsSinceEpoch.toString();
      String newFileName = '$timestamp${_getExtension(fileName)}';
      File destFile = File('${filesDir.path}/$newFileName');

      // Копируем файл
      return await sourceFile.copy(destFile.path);
    } catch (e) {
      print('Ошибка копирования: $e');
      return null;
    }
  }

  // Получение расширения файла
  String _getExtension(String fileName) {
    int lastDot = fileName.lastIndexOf('.');
    if (lastDot != -1) {
      return fileName.substring(lastDot);
    }
    return '';
  }

  // Удаление файла из хранилища
  Future<bool> deleteFile(String filePath) async {
    try {
      File file = File(filePath);
      if (await file.exists()) {
        await file.delete();
        return true;
      }
    } catch (e) {
      print('Ошибка удаления: $e');
    }
    return false;
  }
}