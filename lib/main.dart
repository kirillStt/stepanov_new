import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:file_picker/file_picker.dart';
import 'dart:io';
import 'dart:typed_data';
import 'dart:async';
import 'package:share_plus/share_plus.dart';
import 'package:cross_file/cross_file.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:dio/dio.dart' as dio;
import 'package:provider/provider.dart';
import 'core/models/file_model.dart';
import 'services/storage_service.dart';
import 'services/supabase_storage_service.dart';
import 'screens/email_confirmation_screen.dart';
import 'package:app_links/app_links.dart';
import 'package:flutter_desktop_updater/flutter_desktop_updater.dart';
import 'package:shared_preferences/shared_preferences.dart';

late StorageService storageService;
late SupabaseClient supabase;

// ========== КЛАСС ДЛЯ УПРАВЛЕНИЯ ТЕМОЙ ==========
class ThemeProvider extends ChangeNotifier {
  ThemeMode _themeMode = ThemeMode.system;
  
  ThemeMode get themeMode => _themeMode;
  
  bool get isDarkMode {
    if (_themeMode == ThemeMode.system) {
      return WidgetsBinding.instance.platformDispatcher.platformBrightness == Brightness.dark;
    }
    return _themeMode == ThemeMode.dark;
  }
  
  void setThemeMode(ThemeMode mode) {
    _themeMode = mode;
    notifyListeners();
    _saveThemePreference();
  }
  
  void toggleTheme() {
    if (_themeMode == ThemeMode.light) {
      setThemeMode(ThemeMode.dark);
    } else if (_themeMode == ThemeMode.dark) {
      setThemeMode(ThemeMode.light);
    } else {
      setThemeMode(ThemeMode.light);
    }
  }
  
  Future<void> _saveThemePreference() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('theme_mode', _themeMode.name);
  }
  
  Future<void> loadThemePreference() async {
    final prefs = await SharedPreferences.getInstance();
    final themeName = prefs.getString('theme_mode');
    if (themeName != null) {
      _themeMode = ThemeMode.values.firstWhere(
        (e) => e.name == themeName,
        orElse: () => ThemeMode.system,
      );
    }
  }
}

// ========== API КЛИЕНТ ДЛЯ BACKEND НА VERCEL ==========
class ApiClient {
  static const String baseUrl = 'https://stepanov-backend.vercel.app/api';
  
  final dio.Dio _dio = dio.Dio(dio.BaseOptions(
    baseUrl: baseUrl,
    connectTimeout: const Duration(seconds: 30),
    receiveTimeout: const Duration(seconds: 30),
  ));
  
  String? _token;
  
  void setToken(String token) {
    _token = token;
    _dio.options.headers['Authorization'] = 'Bearer $token';
  }
  
  Future<Map<String, dynamic>> getFiles() async {
    final response = await _dio.get('/files');
    return response.data;
  }
  
  Future<Map<String, dynamic>> uploadFile(File file, String fileName) async {
    final formData = dio.FormData.fromMap({
      'file': await dio.MultipartFile.fromFile(file.path),
      'originalName': fileName,
    });
    
    final response = await _dio.post(
      '/files/upload',
      data: formData,
      onSendProgress: (sent, total) {
        print('Прогресс: ${(sent / total * 100).toStringAsFixed(1)}%');
      },
    );
    
    return response.data;
  }
  
  Future<void> deleteFile(String fileId) async {
    await _dio.delete('/files/$fileId');
  }
  
  Future<String> getDownloadUrl(String fileId) async {
    final response = await _dio.get('/files/$fileId/download');
    return response.data['downloadUrl'];
  }
}

// ========== РЕАЛИЗАЦИЯ CloudStorageService ==========
class CloudStorageService implements StorageService {
  final ApiClient _apiClient = ApiClient();
  
  void init(String token) {
    _apiClient.setToken(token);
  }
  
  @override
  Future<List<FileModel>> getUserFiles(String userId) async {
    try {
      final data = await _apiClient.getFiles();
      final List<FileModel> files = [];
      for (var file in data['files']) {
        files.add(FileModel(
          id: file['id'],
          name: file['name'],
          path: file['path'],
          size: file['size'],
          modifiedAt: DateTime.parse(file['modifiedAt']),
          downloadUrl: file['downloadUrl'],
        ));
      }
      return files;
    } catch (e) {
      print('Ошибка получения файлов: $e');
      return [];
    }
  }
  
  @override
  Future<FileModel?> uploadFile(File file, String fileName, String userId, {String? mimeType}) async {
    try {
      final data = await _apiClient.uploadFile(file, fileName);
      
      if (data['success'] == true) {
        final fileData = data['file'];
        return FileModel(
          id: fileData['id'],
          name: fileData['name'],
          path: fileData['path'],
          size: fileData['size'],
          modifiedAt: DateTime.now(),
          downloadUrl: fileData['downloadUrl'],
        );
      }
      return null;
    } catch (e) {
      print('Ошибка загрузки: $e');
      return null;
    }
  }
  
  @override
  Future<bool> deleteFile(String filePath) async {
    try {
      final fileId = filePath.split('/').last;
      await _apiClient.deleteFile(fileId);
      return true;
    } catch (e) {
      print('Ошибка удаления: $e');
      return false;
    }
  }
  
  @override
  Future<String?> getDownloadUrl(String filePath) async {
    try {
      final fileId = filePath.split('/').last;
      return await _apiClient.getDownloadUrl(fileId);
    } catch (e) {
      print('Ошибка получения URL: $e');
      return null;
    }
  }
}

class WindowSizeManager {
  static const Size loginWindowSize = Size(400, 500);
  static const Size mainWindowSize = Size(900, 600);
  
  static void setWindowSize(Size size) {
    if (WidgetsBinding.instance.platformDispatcher.views.isNotEmpty) {
      final view = WidgetsBinding.instance.platformDispatcher.views.first;
    }
  }
}

final GlobalKey<NavigatorState> navigatorKey = GlobalKey<NavigatorState>();

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  
  const supabaseUrl = String.fromEnvironment('SUPABASE_URL');
  const supabaseAnonKey = String.fromEnvironment('SUPABASE_ANON_KEY');
  
  if (supabaseUrl.isEmpty || supabaseAnonKey.isEmpty) {
    throw Exception(
      'Missing environment variables!\n'
      'Please run with: flutter run --dart-define=SUPABASE_URL=... --dart-define=SUPABASE_ANON_KEY=...'
    );
  }
  
  print('Environment variables loaded');
  print('SUPABASE_URL: $supabaseUrl');
  print('SUPABASE_ANON_KEY: ${supabaseAnonKey.substring(0, 10)}...');
  
  await Supabase.initialize(
    url: supabaseUrl,
    anonKey: supabaseAnonKey,
  );
  
  supabase = Supabase.instance.client;
  
  // Используем прямую загрузку в Supabase
  storageService = SupabaseStorageService();
  
  _handleDeepLinks(); 

  UpdateConfig().configure(
    updateJsonUrl: 'https://raw.githubusercontent.com/kirillStt/stepanov_new/main/updates.json',
  );

  print('Используется прямая загрузка в Supabase Storage');
  runApp(const FileStorageApp());
}

void _handleDeepLinks() {
  final appLinks = AppLinks();

  appLinks.getInitialLink().then((Uri? initialUri) {
    if (initialUri != null && initialUri.toString().contains('code=')) {
      _showConfirmationDialog();
    }
  }).catchError((e) {
    print('Ошибка получения начальной ссылки: $e');
  });

  appLinks.uriLinkStream.listen((Uri? uri) {
    if (uri != null && uri.toString().contains('code=')) {
      _showConfirmationDialog();
    }
  }).onError((e) {
    print('Ошибка в потоке ссылок: $e');
  });
}

void _showConfirmationDialog() {
  WidgetsBinding.instance.addPostFrameCallback((_) {
    showDialog(
      context: navigatorKey.currentContext!,
      barrierDismissible: false,
      builder: (context) => AlertDialog(
        title: const Text('Email подтверждён! 🎉'),
        content: const Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.check_circle, color: Colors.green, size: 64),
            SizedBox(height: 16),
            Text(
              'Ваш email успешно подтверждён. Теперь вы можете войти в приложение.',
              textAlign: TextAlign.center,
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () {
              Navigator.pop(context);
              supabase.auth.signOut();
            },
            child: const Text('Войти'),
          ),
        ],
      ),
    );
  });
}

class FileStorageApp extends StatefulWidget {
  const FileStorageApp({super.key});

  @override
  State<FileStorageApp> createState() => _FileStorageAppState();
}

class _FileStorageAppState extends State<FileStorageApp> {
  late ThemeProvider _themeProvider;

  @override
  void initState() {
    super.initState();
    _themeProvider = ThemeProvider();
    _themeProvider.loadThemePreference();
    _setupWindowListener();
  }

  void _setupWindowListener() {}

  @override
  Widget build(BuildContext context) {
    return ChangeNotifierProvider.value(
      value: _themeProvider,
      child: Consumer<ThemeProvider>(
        builder: (context, provider, child) {
          return MaterialApp(
            navigatorKey: navigatorKey,
            title: 'Stepanov',
            theme: _lightTheme(),
            darkTheme: _darkTheme(),
            themeMode: provider.themeMode,
            home: StreamBuilder<AuthState>(
              stream: supabase.auth.onAuthStateChange,
              builder: (context, snapshot) {
                if (snapshot.connectionState == ConnectionState.waiting) {
                  return const Center(child: CircularProgressIndicator());
                }
                
                final session = supabase.auth.currentSession;
                if (session != null) {
                  if (storageService is CloudStorageService) {
                    (storageService as CloudStorageService).init(session.accessToken);
                  }
                  final user = supabase.auth.currentUser;
                  if (user != null && user.emailConfirmedAt == null) {
                    return const EmailConfirmationScreen();
                  }
                  return const FileManagerScreen();
                }
                return const AuthScreen();
              },
            ),
            debugShowCheckedModeBanner: false,
          );
        },
      ),
    );
  }
}

// ========== ТЕМЫ ==========
ThemeData _lightTheme() {
  return ThemeData(
    brightness: Brightness.light,
    primarySwatch: Colors.blue,
    colorScheme: ColorScheme.fromSeed(
      seedColor: Colors.blue,
      brightness: Brightness.light,
    ),
    appBarTheme: const AppBarTheme(
      elevation: 0,
      centerTitle: false,
    ),
    cardTheme: CardThemeData(
      elevation: 2,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
      ),
    ),
    inputDecorationTheme: InputDecorationTheme(
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
      ),
      filled: true,
      fillColor: Colors.grey.shade50,
    ),
    elevatedButtonTheme: ElevatedButtonThemeData(
      style: ElevatedButton.styleFrom(
        minimumSize: const Size(double.infinity, 50),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(12),
        ),
      ),
    ),
    useMaterial3: true,
  );
}

ThemeData _darkTheme() {
  return ThemeData(
    brightness: Brightness.dark,
    primarySwatch: Colors.blue,
    colorScheme: ColorScheme.fromSeed(
      seedColor: Colors.blue,
      brightness: Brightness.dark,
    ),
    appBarTheme: const AppBarTheme(
      elevation: 0,
      centerTitle: false,
    ),
    cardTheme: CardThemeData(
      elevation: 2,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
      ),
    ),
    inputDecorationTheme: InputDecorationTheme(
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
      ),
      filled: true,
      fillColor: Colors.grey.shade800,
    ),
    elevatedButtonTheme: ElevatedButtonThemeData(
      style: ElevatedButton.styleFrom(
        minimumSize: const Size(double.infinity, 50),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(12),
        ),
      ),
    ),
    useMaterial3: true,
  );
}

// ========== ЭКРАН АВТОРИЗАЦИИ ==========
class AuthScreen extends StatefulWidget {
  const AuthScreen({super.key});

  @override
  State<AuthScreen> createState() => _AuthScreenState();
}

class _AuthScreenState extends State<AuthScreen> {
  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();
  bool _isLogin = true;
  bool _isLoading = false;

  Future<void> _submit() async {
    setState(() => _isLoading = true);
    
    try {
      if (_isLogin) {
        final response = await supabase.auth.signInWithPassword(
          email: _emailController.text.trim(),
          password: _passwordController.text.trim(),
        );
        
        if (response.user != null && response.user!.emailConfirmedAt == null) {
          await supabase.auth.signOut();
          setState(() => _isLoading = false);
          if (mounted) {
            showDialog(
              context: context,
              barrierDismissible: false,
              builder: (context) => AlertDialog(
                title: const Text('Email не подтверждён'),
                content: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Text(
                      'Пожалуйста, подтвердите ваш email, перейдя по ссылке в письме.',
                    ),
                    const SizedBox(height: 16),
                    Text(
                      _emailController.text.trim(),
                      style: const TextStyle(fontWeight: FontWeight.bold),
                    ),
                  ],
                ),
                actions: [
                  TextButton(
                    onPressed: () => Navigator.pop(context),
                    child: const Text('Ок'),
                  ),
                ],
              ),
            );
          }
          return;
        }
        setState(() => _isLoading = false);
      } else {
        final response = await supabase.auth.signUp(
          email: _emailController.text.trim(),
          password: _passwordController.text.trim(),
        );
        
        if (response.user != null && (response.user!.identities?.isEmpty ?? true)) {
          setState(() => _isLoading = false);
          _showMessage('Пользователь с таким email уже зарегистрирован', isError: true);
          return;
        }
        
        if (response.user != null && response.session == null) {
          setState(() => _isLoading = false);
          showDialog(
            context: context,
            barrierDismissible: false,
            builder: (context) => AlertDialog(
              title: const Text('Подтвердите email'),
              content: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'На указанный адрес отправлено письмо с кодом подтверждения.',
                    style: TextStyle(fontSize: 16),
                  ),
                  const SizedBox(height: 16),
                  Text(
                    _emailController.text.trim(),
                    style: const TextStyle(
                      fontWeight: FontWeight.bold,
                      fontSize: 16,
                    ),
                  ),
                  const SizedBox(height: 16),
                  const Text(
                    'Введите код из письма на следующем экране.',
                    style: TextStyle(fontSize: 14, color: Colors.grey),
                  ),
                ],
              ),
              actions: [
                TextButton(
                  onPressed: () {
                    Navigator.pop(context);
                    Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (context) => EmailVerificationScreen(
                          supabase: supabase,
                          email: _emailController.text.trim(),
                        ),
                      ),
                    );
                  },
                  child: const Text('Ввести код'),
                ),
              ],
            ),
          );
          return;
        }
        setState(() => _isLoading = false);
        _showMessage('Регистрация успешна!');
      }
    } on AuthException catch (e) {
      String message;
      
      if (e.message.contains('Invalid login credentials')) {
        message = 'Неверный email или пароль';
      } else if (e.message.contains('Email not confirmed')) {
        message = 'Email не подтверждён. Проверьте почту';
      } else if (e.message.contains('User already registered')) {
        message = 'Пользователь с таким email уже зарегистрирован';
      } else if (e.message.contains('Password should be at least 6 characters')) {
        message = 'Пароль должен быть не менее 6 символов';
      } else if (e.message.contains('rate limit')) {
        message = 'Слишком много попыток. Попробуйте позже';
      } else {
        message = 'Ошибка: ${e.message}';
      }
      
      setState(() => _isLoading = false);
      _showMessage(message, isError: true);
      
    } catch (e) {
      setState(() => _isLoading = false);
      _showMessage('Ошибка: $e', isError: true);
    }
  }

  Future<void> _resetPassword() async {
    final email = _emailController.text.trim();
    
    if (email.isEmpty) {
      _showMessage('Введите email для сброса пароля', isError: true);
      return;
    }
    
    setState(() => _isLoading = true);
    
    try {
      await supabase.auth.resetPasswordForEmail(email);
      setState(() => _isLoading = false);
      
      showDialog(
        context: context,
        builder: (context) => AlertDialog(
          title: const Text('Проверьте почту'),
          content: Text(
            'На адрес $email отправлен код для сброса пароля. '
            'Введите этот код на следующем экране.'
          ),
          actions: [
            TextButton(
              onPressed: () {
                Navigator.pop(context);
                Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (context) => ResetPasswordScreen(email: email),
                  ),
                );
              },
              child: const Text('Далее'),
            ),
          ],
        ),
      );
    } on AuthException catch (e) {
      setState(() => _isLoading = false);
      _showMessage('Ошибка: ${e.message}', isError: true);
    } catch (e) {
      setState(() => _isLoading = false);
      _showMessage('Ошибка при сбросе пароля', isError: true);
    }
  }

  void _showMessage(String message, {bool isError = false}) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: isError ? Colors.red : Colors.green,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
      ),
      body: Center(
        child: Container(
          constraints: const BoxConstraints(
            maxWidth: 400,
            minWidth: 380,
            maxHeight: 500,
            minHeight: 480,
          ),
          child: Padding(
            padding: const EdgeInsets.all(20),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Text(
                  _isLogin ? 'Вход' : 'Регистрация',
                  style: Theme.of(context).textTheme.headlineMedium?.copyWith(
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const SizedBox(height: 40),
                TextField(
                  controller: _emailController,
                  decoration: const InputDecoration(
                    labelText: 'Email',
                    prefixIcon: Icon(Icons.email),
                    border: OutlineInputBorder(),
                  ),
                ),
                const SizedBox(height: 16),
                TextField(
                  controller: _passwordController,
                  obscureText: true,
                  decoration: const InputDecoration(
                    labelText: 'Пароль',
                    prefixIcon: Icon(Icons.lock),
                    border: OutlineInputBorder(),
                  ),
                ),
                const SizedBox(height: 24),
                
                if (_isLoading)
                  const CircularProgressIndicator()
                else
                  ElevatedButton(
                    onPressed: _submit,
                    style: ElevatedButton.styleFrom(
                      minimumSize: const Size(double.infinity, 50),
                    ),
                    child: Text(_isLogin ? 'Войти' : 'Зарегистрироваться'),
                  ),
                
                const SizedBox(height: 16),
                
                if (_isLogin)
                  TextButton(
                    onPressed: _resetPassword,
                    child: const Text(
                      'Забыли пароль?',
                      style: TextStyle(color: Colors.blue),
                    ),
                  ),
                
                TextButton(
                  onPressed: () => setState(() => _isLogin = !_isLogin),
                  child: Text(_isLogin
                      ? 'Нет аккаунта? Зарегистрироваться'
                      : 'Уже есть аккаунт? Войти'),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

// ========== ЭКРАН ОЖИДАНИЯ ПОДТВЕРЖДЕНИЯ EMAIL ==========
class EmailConfirmationScreen extends StatelessWidget {
  const EmailConfirmationScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final user = supabase.auth.currentUser;
    
    return Scaffold(
      appBar: AppBar(
        title: const Text('Подтверждение email'),
      ),
      body: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(
              Icons.mark_email_unread,
              size: 80,
              color: Colors.orange,
            ),
            const SizedBox(height: 20),
            const Text(
              'Подтвердите ваш email',
              style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 16),
            Text(
              'Мы отправили письмо на адрес:',
              style: TextStyle(fontSize: 16, color: Colors.grey[600]),
            ),
            const SizedBox(height: 8),
            Text(
              user?.email ?? '',
              style: const TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 24),
            const Text(
              'Перейдите по ссылке в письме, чтобы активировать аккаунт. После подтверждения вы сможете пользоваться приложением.',
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 16, color: Colors.grey),
            ),
            const SizedBox(height: 32),
            ElevatedButton(
              onPressed: () async {
                await supabase.auth.signOut();
              },
              style: ElevatedButton.styleFrom(
                minimumSize: const Size(double.infinity, 50),
              ),
              child: const Text('Выйти'),
            ),
          ],
        ),
      ),
    );
  }
}

// ========== ЭКРАН ВВОДА КОДА ДЛЯ СБРОСА ПАРОЛЯ ==========
class ResetPasswordScreen extends StatefulWidget {
  final String email;
  
  const ResetPasswordScreen({super.key, required this.email});

  @override
  State<ResetPasswordScreen> createState() => _ResetPasswordScreenState();
}

class _ResetPasswordScreenState extends State<ResetPasswordScreen> {
  final _tokenController = TextEditingController();
  final _newPasswordController = TextEditingController();
  final _confirmPasswordController = TextEditingController();
  bool _isLoading = false;

  Future<void> _verifyAndReset() async {
    final token = _tokenController.text.trim();
    final newPassword = _newPasswordController.text.trim();
    final confirmPassword = _confirmPasswordController.text.trim();
    final email = widget.email;

    if (token.isEmpty) {
      _showMessage('Введите код из письма', isError: true);
      return;
    }

    if (newPassword.isEmpty || confirmPassword.isEmpty) {
      _showMessage('Заполните все поля', isError: true);
      return;
    }

    if (newPassword != confirmPassword) {
      _showMessage('Пароли не совпадают', isError: true);
      return;
    }

    if (newPassword.length < 6) {
      _showMessage('Пароль должен быть не менее 6 символов', isError: true);
      return;
    }

    setState(() => _isLoading = true);

    try {
      final response = await supabase.auth.verifyOTP(
        type: OtpType.recovery,
        token: token,
        email: email,
      );
      
      if (response.session != null) {
        await supabase.auth.updateUser(
          UserAttributes(password: newPassword),
        );
        
        await supabase.auth.signOut();
        
        _showMessage('Пароль успешно изменён!');
        Navigator.popUntil(context, (route) => route.isFirst);
      } else {
        _showMessage('Неверный или просроченный код', isError: true);
      }
    } on AuthException catch (e) {
      _showMessage('Ошибка: ${e.message}', isError: true);
    } catch (e) {
      _showMessage('Ошибка при сбросе пароля', isError: true);
    } finally {
      setState(() => _isLoading = false);
    }
  }

  void _showMessage(String message, {bool isError = false}) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: isError ? Colors.red : Colors.green,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Сброс пароля'),
      ),
      body: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Text(
              'Введите код из письма и новый пароль',
              style: TextStyle(fontSize: 16),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 24),
            TextField(
              controller: _tokenController,
              decoration: const InputDecoration(
                labelText: 'Код из письма',
                prefixIcon: Icon(Icons.vpn_key),
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 16),
            TextField(
              controller: _newPasswordController,
              obscureText: true,
              decoration: const InputDecoration(
                labelText: 'Новый пароль',
                prefixIcon: Icon(Icons.lock),
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 16),
            TextField(
              controller: _confirmPasswordController,
              obscureText: true,
              decoration: const InputDecoration(
                labelText: 'Подтвердите пароль',
                prefixIcon: Icon(Icons.lock_outline),
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 24),
            if (_isLoading)
              const CircularProgressIndicator()
            else
              ElevatedButton(
                onPressed: _verifyAndReset,
                style: ElevatedButton.styleFrom(
                  minimumSize: const Size(double.infinity, 50),
                ),
                child: const Text('Сменить пароль'),
              ),
          ],
        ),
      ),
    );
  }
}

// ========== ГЛАВНЫЙ ЭКРАН ==========
class FileManagerScreen extends StatefulWidget {
  const FileManagerScreen({super.key});

  @override
  State<FileManagerScreen> createState() => _FileManagerScreenState();
}

class _FileManagerScreenState extends State<FileManagerScreen> {
  List<FileModel> files = [];
  List<FileModel> filteredFiles = [];
  bool isLoading = true;

  bool _isImageFile(String fileName) {
    final extension = fileName.split('.').last.toLowerCase();
    const imageExtensions = ['jpg', 'jpeg', 'png', 'gif', 'bmp', 'webp', 'svg'];
    return imageExtensions.contains(extension);
  }
  
  String searchQuery = '';
  String sizeFilter = 'all';
  String dateFilter = 'all';
  String typeFilter = 'all';
  bool isFilterVisible = false;

  @override
  void initState() {
    super.initState();
    _loadFiles();
  }

  String? get _userId => supabase.auth.currentUser?.id;

  Future<void> _loadFiles() async {
    // Не вызываем setState до загрузки
    try {
      final userId = _userId ?? '';
      if (userId.isNotEmpty) {
        // Обновляем токен если нужно
        final session = supabase.auth.currentSession;
        if (session != null && storageService is CloudStorageService) {
          (storageService as CloudStorageService).init(session.accessToken);
        }
        
        // Получаем файлы
        final newFiles = await storageService.getUserFiles(userId);
        
        print('Загружено файлов из Supabase: ${newFiles.length}');
        
        // Восстанавливаем имена (без изменения исходного списка)
        final prefs = await SharedPreferences.getInstance();
        final restoredFiles = <FileModel>[];
        
        for (final file in newFiles) {
          final savedName = prefs.getString('file_name_${file.id}');
          if (savedName != null && savedName.isNotEmpty) {
            print('   Восстанавливаем имя: ${file.name} -> $savedName');
            restoredFiles.add(FileModel(
              id: file.id,
              name: savedName,
              path: file.path,
              size: file.size,
              modifiedAt: file.modifiedAt,
              downloadUrl: file.downloadUrl,
            ));
          } else {
            print('   Имя из Supabase: ${file.name}');
            restoredFiles.add(file);
          }
        }
        
        // Один setState после всех операций
        if (mounted) {
          setState(() {
            files = restoredFiles;
            filteredFiles = List.from(restoredFiles);
            isLoading = true; // показываем загрузку
          });
        }
      }
    } catch (e) {
      print('Ошибка загрузки файлов: $e');
      if (mounted) {
        setState(() {
          isLoading = false;
        });
      }
    } finally {
      // Завершаем загрузку
      if (mounted) {
        setState(() {
          isLoading = false;
        });
      }
    }
  }

  void _applyFilters() {
    setState(() {
      filteredFiles = files.where((file) {
        if (searchQuery.isNotEmpty && 
            !file.name.toLowerCase().contains(searchQuery.toLowerCase())) {
          return false;
        }
        
        if (sizeFilter != 'all') {
          final sizeMB = file.size / (1024 * 1024);
          switch (sizeFilter) {
            case 'small':
              if (sizeMB > 1) return false;
              break;
            case 'medium':
              if (sizeMB < 1 || sizeMB > 10) return false;
              break;
            case 'large':
              if (sizeMB < 10) return false;
              break;
          }
        }
        
        if (dateFilter != 'all') {
          final now = DateTime.now();
          final fileDate = file.modifiedAt;
          final difference = now.difference(fileDate).inDays;
          
          switch (dateFilter) {
            case 'today':
              if (difference > 1) return false;
              break;
            case 'week':
              if (difference > 7) return false;
              break;
            case 'month':
              if (difference > 30) return false;
              break;
          }
        }
        
        if (typeFilter != 'all') {
          final extension = file.name.split('.').last.toLowerCase();
          final imageTypes = ['jpg', 'jpeg', 'png', 'gif', 'bmp', 'webp'];
          final documentTypes = ['txt', 'pdf', 'doc', 'docx', 'xls', 'xlsx', 'ppt', 'pptx'];
          final archiveTypes = ['zip', 'rar', '7z', 'tar', 'gz'];
          
          switch (typeFilter) {
            case 'image':
              if (!imageTypes.contains(extension)) return false;
              break;
            case 'document':
              if (!documentTypes.contains(extension)) return false;
              break;
            case 'archive':
              if (!archiveTypes.contains(extension)) return false;
              break;
            case 'other':
              if (imageTypes.contains(extension) || 
                  documentTypes.contains(extension) || 
                  archiveTypes.contains(extension)) return false;
              break;
          }
        }
        
        return true;
      }).toList();
    });
  }

  void _resetFilters() {
    setState(() {
      searchQuery = '';
      sizeFilter = 'all';
      dateFilter = 'all';
      typeFilter = 'all';
      filteredFiles = List.from(files);
      isFilterVisible = false;
    });
  }

  void _showMessage(String message, {bool isError = false}) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: isError ? Colors.red : Colors.green,
        duration: const Duration(seconds: 3),
      ),
    );
  }

  Future<bool> _showOverwriteDialog(String fileName) async {
    final result = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Файл уже существует'),
        content: Text(
          'Файл "$fileName" уже загружен.\n\nХотите заменить его?',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Отмена'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            style: TextButton.styleFrom(
              foregroundColor: Colors.orange,
            ),
            child: const Text('Заменить'),
          ),
        ],
      ),
    );
    return result ?? false;
  }

  Future<void> pickAndUploadFile() async {
    if (mounted) setState(() => isLoading = true);
    
    try {
      FilePickerResult? result = await FilePicker.platform.pickFiles(
        withData: false,
      );
      
      if (result != null) {
        final platformFile = result.files.single;
        final String fileName = platformFile.name;
        final String? filePath = platformFile.path;
        
        if (filePath == null) {
          _showMessage('Не удалось получить путь к файлу', isError: true);
          if (mounted) setState(() => isLoading = false);
          return;
        }
        
        final String userId = _userId ?? '';
        
        if (userId.isEmpty) {
          _showMessage('Пользователь не авторизован', isError: true);
          if (mounted) setState(() => isLoading = false);
          return;
        }
        
        // Проверка на дубликат
        final bool fileExists = files.any((file) => file.name == fileName);
        if (fileExists) {
          final bool overwrite = await _showOverwriteDialog(fileName);
          if (!overwrite) {
            if (mounted) setState(() => isLoading = false);
            _showMessage('Загрузка отменена', isError: false);
            return;
          }
        }
        
        print('Загрузка файла: $fileName');
        
        final File file = File(filePath);
        
        String? mimeType;
        final extension = fileName.split('.').last.toLowerCase();
        
        switch (extension) {
          case 'png':
            mimeType = 'image/png';
            break;
          case 'jpg':
          case 'jpeg':
            mimeType = 'image/jpeg';
            break;
          case 'gif':
            mimeType = 'image/gif';
            break;
          case 'pdf':
            mimeType = 'application/pdf';
            break;
          case 'txt':
            mimeType = 'text/plain';
            break;
          case 'torrent':
            mimeType = 'application/x-bittorrent';
            break;
          case 'pptx':
            mimeType = 'application/vnd.openxmlformats-officedocument.presentationml.presentation';
            break;
          default:
            mimeType = 'application/octet-stream';
        }
        
        final uploaded = await storageService.uploadFile(
          file, 
          fileName, 
          userId,
          mimeType: mimeType,
        );
        
        if (uploaded != null) {
          final prefs = await SharedPreferences.getInstance();
          await prefs.setString('file_name_${uploaded.id}', uploaded.name);
          print('📝 Сохранено имя: ${uploaded.name} для файла ${uploaded.id}');
          
          setState(() {
            if (fileExists) {
              files.removeWhere((f) => f.name == fileName);
              filteredFiles.removeWhere((f) => f.name == fileName);
            }
            files.insert(0, uploaded);
            filteredFiles.insert(0, uploaded);
          });
          _showMessage('Файл "${uploaded.name}" загружен');
        } else {
          _showMessage('Не удалось загрузить файл', isError: true);
        }
      }
    } catch (e) {
      print('Ошибка загрузки: $e');
      _showMessage('Ошибка: ${e.toString()}', isError: true);
    } finally {
      if (mounted) setState(() => isLoading = false);
    }
  }

  Future<void> _downloadFile(FileModel file) async {
    try {
      String? downloadUrl = file.downloadUrl;
      if (downloadUrl == null) {
        downloadUrl = await storageService.getDownloadUrl(file.path);
      }
      
      if (downloadUrl == null || downloadUrl.isEmpty) {
        _showMessage('Не удалось получить ссылку для скачивания', isError: true);
        return;
      }
      
      String? outputPath = await FilePicker.platform.saveFile(
        dialogTitle: 'Сохранить файл',
        fileName: file.name,
      );

      if (outputPath != null) {
        _showMessage('Скачивание началось...');
        
        final Uri uri = Uri.parse(downloadUrl);
        final request = await HttpClient().getUrl(uri);
        final response = await request.close();
        
        if (response.statusCode == 200) {
          final fileBytes = await consolidateHttpClientResponseBytes(response);
          await File(outputPath).writeAsBytes(fileBytes);
          if (mounted) {
            _showMessage('Файл сохранён');
          }
        } else {
          if (mounted) {
            _showMessage('Ошибка скачивания: ${response.statusCode}', isError: true);
          }
        }
      }
    } catch (e) {
      if (mounted) {
        _showMessage('Ошибка при сохранении: $e', isError: true);
      }
    }
  }

  Future<void> _shareFile(FileModel file) async {
    try {
      String? downloadUrl = file.downloadUrl;
      if (downloadUrl == null) {
        downloadUrl = await storageService.getDownloadUrl(file.path);
      }
      
      if (downloadUrl != null) {
        final downloadLink = downloadUrl.contains('?')
            ? '$downloadUrl&download' 
            : '$downloadUrl?download'; 
            
        await Clipboard.setData(ClipboardData(text: downloadLink));
        _showMessage('Ссылка для скачивания скопирована в буфер обмена');
        
        showDialog(
          context: context,
          builder: (context) => AlertDialog(
            title: const Text('Ссылка готова'),
            content: const Text('Ссылка для скачивания скопирована. Теперь вы можете отправить её другу в любом мессенджере.'),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context),
                child: const Text('Ок'),
              ),
            ],
          ),
        );
      } else {
        _showMessage('Не удалось получить ссылку', isError: true);
      }
    } catch (e) {
      _showMessage('Ошибка: $e', isError: true);
    }
  }

  Future<void> _deleteFile(int index) async {
    final file = filteredFiles[index];
    final originalIndex = files.indexWhere((f) => f.id == file.id);
    
    final confirm = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Удаление'),
        content: Text('Удалить "${file.name}"?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Отмена'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            style: TextButton.styleFrom(foregroundColor: Colors.red),
            child: const Text('Удалить'),
          ),
        ],
      ),
    );
    
    if (confirm == true) {
      final success = await storageService.deleteFile(file.path);
      if (success) {
        final prefs = await SharedPreferences.getInstance();
        await prefs.remove('file_name_${file.id}');
        
        setState(() {
          filteredFiles.removeAt(index);
          if (originalIndex != -1) {
            files.removeAt(originalIndex);
          }
        });
        _showMessage('Файл удален');
      } else {
        _showMessage('Не удалось удалить файл', isError: true);
      }
    }
  }

  Future<void> _logout() async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Выход'),
        content: const Text('Вы уверены, что хотите выйти?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Отмена'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Выйти'),
          ),
        ],
      ),
    );
    
    if (confirm == true) {
      await supabase.auth.signOut();
    }
  }

  void _navigateToChangePassword() {
    Navigator.push(
      context,
      MaterialPageRoute(builder: (context) => const ChangePasswordScreen()),
    );
  }

  @override
  Widget build(BuildContext context) {
    final themeProvider = Provider.of<ThemeProvider>(context);
    
    return Scaffold(
      appBar: AppBar(
        title: const Text('Stepanov'),
        actions: [
          PopupMenuButton<String>(
            icon: const Icon(Icons.more_vert),
            tooltip: 'Меню',
            onSelected: (value) {
              if (value == 'refresh') {
                _loadFiles();
              } else if (value == 'filter') {
                setState(() {
                  isFilterVisible = !isFilterVisible;
                });
              } else if (value == 'theme') {
                themeProvider.toggleTheme();
              } else if (value == 'password') {
                _navigateToChangePassword();
              } else if (value == 'logout') {
                _logout();
              }
            },
            itemBuilder: (context) => [
              const PopupMenuItem(
                value: 'filter',
                child: Row(
                  children: [
                    Icon(Icons.filter_alt, color: Colors.blue, size: 20),
                    SizedBox(width: 8),
                    Text('Фильтры'),
                  ],
                ),
              ),
              const PopupMenuItem(
                value: 'refresh',
                child: Row(
                  children: [
                    Icon(Icons.refresh, color: Colors.green, size: 20),
                    SizedBox(width: 8),
                    Text('Обновить'),
                  ],
                ),
              ),
              const PopupMenuItem(
                value: 'theme',
                child: Row(
                  children: [
                    Icon(Icons.brightness_6, color: Colors.purple, size: 20),
                    SizedBox(width: 8),
                    Text('Тема'),
                  ],
                ),
              ),
              const PopupMenuItem(
                value: 'password',
                child: Row(
                  children: [
                    Icon(Icons.password, color: Colors.orange, size: 20),
                    SizedBox(width: 8),
                    Text('Сменить пароль'),
                  ],
                ),
              ),
              const PopupMenuItem(
                value: 'logout',
                child: Row(
                  children: [
                    Icon(Icons.logout, color: Colors.red, size: 20),
                    SizedBox(width: 8),
                    Text('Выйти', style: TextStyle(color: Colors.red)),
                  ],
                ),
              ),
            ],
          ),
        ],
      ),
      body: Column(
        children: [
          if (isFilterVisible)
            Container(
              color: Theme.of(context).brightness == Brightness.dark 
                  ? Colors.grey.shade900 
                  : Colors.grey[100],
              padding: const EdgeInsets.all(12),
              child: Column(
                children: [
                  TextField(
                    decoration: const InputDecoration(
                      labelText: 'Поиск по имени',
                      prefixIcon: Icon(Icons.search),
                      border: OutlineInputBorder(),
                    ),
                    onChanged: (value) {
                      searchQuery = value;
                      _applyFilters();
                    },
                  ),
                  const SizedBox(height: 12),
                  Row(
                    children: [
                      const Text('Размер:', style: TextStyle(fontWeight: FontWeight.bold)),
                      const SizedBox(width: 12),
                      Expanded(
                        child: DropdownButton<String>(
                          value: sizeFilter,
                          isExpanded: true,
                          items: const [
                            DropdownMenuItem(value: 'all', child: Text('Все')),
                            DropdownMenuItem(value: 'small', child: Text('До 1 МБ')),
                            DropdownMenuItem(value: 'medium', child: Text('1-10 МБ')),
                            DropdownMenuItem(value: 'large', child: Text('Больше 10 МБ')),
                          ],
                          onChanged: (value) {
                            setState(() {
                              sizeFilter = value!;
                              _applyFilters();
                            });
                          },
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  Row(
                    children: [
                      const Text('Дата:', style: TextStyle(fontWeight: FontWeight.bold)),
                      const SizedBox(width: 12),
                      Expanded(
                        child: DropdownButton<String>(
                          value: dateFilter,
                          isExpanded: true,
                          items: const [
                            DropdownMenuItem(value: 'all', child: Text('За всё время')),
                            DropdownMenuItem(value: 'today', child: Text('Сегодня')),
                            DropdownMenuItem(value: 'week', child: Text('Последние 7 дней')),
                            DropdownMenuItem(value: 'month', child: Text('Последние 30 дней')),
                          ],
                          onChanged: (value) {
                            setState(() {
                              dateFilter = value!;
                              _applyFilters();
                            });
                          },
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  Row(
                    children: [
                      const Text('Тип:', style: TextStyle(fontWeight: FontWeight.bold)),
                      const SizedBox(width: 12),
                      Expanded(
                        child: DropdownButton<String>(
                          value: typeFilter,
                          isExpanded: true,
                          items: const [
                            DropdownMenuItem(value: 'all', child: Text('Все')),
                            DropdownMenuItem(value: 'image', child: Text('Изображения')),
                            DropdownMenuItem(value: 'document', child: Text('Документы')),
                            DropdownMenuItem(value: 'archive', child: Text('Архивы')),
                            DropdownMenuItem(value: 'other', child: Text('Другое')),
                          ],
                          onChanged: (value) {
                            setState(() {
                              typeFilter = value!;
                              _applyFilters();
                            });
                          },
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  TextButton.icon(
                    onPressed: _resetFilters,
                    icon: const Icon(Icons.clear),
                    label: const Text('Сбросить фильтры'),
                  ),
                ],
              ),
            ),
          Expanded(
            child: isLoading
                ? const Center(child: CircularProgressIndicator())
                : filteredFiles.isEmpty
                    ? Center(
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            const Icon(Icons.cloud_upload, size: 80, color: Colors.grey),
                            const SizedBox(height: 20),
                            Text(
                              files.isEmpty ? 'Нет файлов' : 'Нет файлов по выбранным фильтрам',
                              style: const TextStyle(fontSize: 18, color: Colors.grey),
                            ),
                            const SizedBox(height: 10),
                            ElevatedButton(
                              onPressed: files.isEmpty ? pickAndUploadFile : _resetFilters,
                              child: Text(files.isEmpty ? 'Загрузить файл' : 'Сбросить фильтры'),
                            ),
                          ],
                        ),
                      )
                    : ListView.builder(
                        itemCount: filteredFiles.length,
                        itemExtent: 72, // ← фиксированная высота элемента
                        itemBuilder: (context, index) {
                          final file = filteredFiles[index];
                          return Card(
                            margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                            child: ListTile(
                              leading: const Icon(Icons.insert_drive_file, color: Colors.blue),
                              title: Text(
                                file.name,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                              ),
                              subtitle: Text('${file.readableSize} • ${_formatDate(file.modifiedAt)}'),
                              onTap: _isImageFile(file.name) 
                                ? () async {
                                    String? imageUrl = file.downloadUrl;
                                    if (imageUrl == null) {
                                      imageUrl = await storageService.getDownloadUrl(file.path);
                                    }
                                    
                                    if (imageUrl != null && imageUrl.isNotEmpty) {
                                      final String validUrl = imageUrl;
                                      
                                      if (context.mounted) {
                                        Navigator.push(
                                          context,
                                          MaterialPageRoute(
                                            builder: (context) => ImagePreviewScreen(
                                              file: file,
                                              imageUrl: validUrl,
                                            ),
                                          ),
                                        );
                                      }
                                    } else {
                                      _showMessage('Не удалось загрузить изображение', isError: true);
                                    }
                                  }
                                : null,
                              trailing: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  IconButton(
                                    icon: const Icon(Icons.download, color: Colors.green),
                                    onPressed: () => _downloadFile(file),
                                    tooltip: 'Скачать',
                                  ),
                                  IconButton(
                                    icon: const Icon(Icons.share, color: Colors.blue),
                                    onPressed: () => _shareFile(file),
                                    tooltip: 'Поделиться',
                                  ),
                                  IconButton(
                                    icon: const Icon(Icons.delete, color: Colors.red),
                                    onPressed: () => _deleteFile(index),
                                    tooltip: 'Удалить',
                                  ),
                                ],
                              ),
                            ),
                          );
                        },
                      ),
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: pickAndUploadFile,
        tooltip: 'Загрузить файл',
        child: const Icon(Icons.add),
      ),
    );
  }

  String _formatDate(DateTime date) {
    return '${date.day.toString().padLeft(2, '0')}.${date.month.toString().padLeft(2, '0')}.${date.year} ${date.hour.toString().padLeft(2, '0')}:${date.minute.toString().padLeft(2, '0')}';
  }
}

// ========== ЭКРАН ПРЕДПРОСМОТРА ИЗОБРАЖЕНИЙ ==========
class ImagePreviewScreen extends StatefulWidget {
  final FileModel file;
  final String imageUrl;

  const ImagePreviewScreen({
    super.key,
    required this.file,
    required this.imageUrl,
  });

  @override
  State<ImagePreviewScreen> createState() => _ImagePreviewScreenState();
}

class _ImagePreviewScreenState extends State<ImagePreviewScreen> {
  late String _imageUrl;

  @override
  void initState() {
    super.initState();
    _imageUrl = widget.imageUrl;
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(
          widget.file.name,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.share),
            onPressed: _shareImage,
          ),
          IconButton(
            icon: const Icon(Icons.download),
            onPressed: _downloadImage,
          ),
        ],
      ),
      body: Center(
        child: InteractiveViewer(
          panEnabled: true,
          minScale: 0.5,
          maxScale: 4.0,
          child: Image.network(
            _imageUrl,
            fit: BoxFit.contain,
            loadingBuilder: (context, child, loadingProgress) {
              if (loadingProgress == null) return child;
              return Center(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    CircularProgressIndicator(
                      value: loadingProgress.expectedTotalBytes != null
                          ? loadingProgress.cumulativeBytesLoaded /
                              loadingProgress.expectedTotalBytes!
                          : null,
                    ),
                    const SizedBox(height: 16),
                    Text(
                      'Загрузка изображения...',
                      style: Theme.of(context).textTheme.bodyMedium,
                    ),
                  ],
                ),
              );
            },
            errorBuilder: (context, error, stackTrace) {
              return Center(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    const Icon(
                      Icons.broken_image,
                      size: 64,
                      color: Colors.grey,
                    ),
                    const SizedBox(height: 16),
                    Text(
                      'Не удалось загрузить изображение',
                      style: Theme.of(context).textTheme.bodyMedium,
                    ),
                    const SizedBox(height: 8),
                    ElevatedButton(
                      onPressed: () => Navigator.pop(context),
                      child: const Text('Назад'),
                    ),
                  ],
                ),
              );
            },
          ),
        ),
      ),
    );
  }

  void _shareImage() async {
    try {
      await Clipboard.setData(ClipboardData(text: _imageUrl));
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Ссылка на изображение скопирована'),
            backgroundColor: Colors.green,
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Ошибка: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  void _downloadImage() {
    Navigator.pop(context);
  }
}

// ========== ЭКРАН СМЕНЫ ПАРОЛЯ ==========
class ChangePasswordScreen extends StatefulWidget {
  const ChangePasswordScreen({super.key});

  @override
  State<ChangePasswordScreen> createState() => _ChangePasswordScreenState();
}

// ========== ЭКРАН ПОДТВЕРЖДЕНИЯ EMAIL ==========
class EmailVerificationScreen extends StatefulWidget {
  final SupabaseClient supabase;
  final String email;
  
  const EmailVerificationScreen({
    super.key, 
    required this.supabase,
    required this.email,
  });

  @override
  State<EmailVerificationScreen> createState() => _EmailVerificationScreenState();
}

class _EmailVerificationScreenState extends State<EmailVerificationScreen> {
  final _tokenController = TextEditingController();
  bool _isLoading = false;

  Future<void> _verifyEmail() async {
    final token = _tokenController.text.trim();
    
    if (token.isEmpty) {
      _showMessage('Введите код из письма', isError: true);
      return;
    }

    setState(() => _isLoading = true);

    try {
      final response = await widget.supabase.auth.verifyOTP(
        type: OtpType.email,
        token: token,
        email: widget.email,
      );

      if (response.user != null) {
        _showMessage('Email успешно подтверждён!');
        Navigator.popUntil(context, (route) => route.isFirst);
      } else {
        _showMessage('Неверный код подтверждения', isError: true);
      }
    } on AuthException catch (e) {
      _showMessage('Ошибка: ${e.message}', isError: true);
    } catch (e) {
      _showMessage('Ошибка при подтверждении', isError: true);
    } finally {
      setState(() => _isLoading = false);
    }
  }

  void _showMessage(String message, {bool isError = false}) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: isError ? Colors.red : Colors.green,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Подтверждение email'),
      ),
      body: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(
              Icons.mark_email_unread,
              size: 80,
              color: Colors.blue,
            ),
            const SizedBox(height: 20),
            const Text(
              'Введите код из письма',
              style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 16),
            Text(
              'Код отправлен на: ${widget.email}',
              textAlign: TextAlign.center,
              style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w500),
            ),
            const SizedBox(height: 16),
            const Text(
              'Мы отправили код на ваш email. Введите его ниже:',
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 16, color: Colors.grey),
            ),
            const SizedBox(height: 24),
            TextField(
              controller: _tokenController,
              decoration: const InputDecoration(
                labelText: 'Код подтверждения',
                prefixIcon: Icon(Icons.vpn_key),
                border: OutlineInputBorder(),
              ),
              textAlign: TextAlign.center,
              style: const TextStyle(fontSize: 24, letterSpacing: 4),
            ),
            const SizedBox(height: 24),
            if (_isLoading)
              const CircularProgressIndicator()
            else
              ElevatedButton(
                onPressed: _verifyEmail,
                style: ElevatedButton.styleFrom(
                  minimumSize: const Size(double.infinity, 50),
                ),
                child: const Text('Подтвердить'),
              ),
          ],
        ),
      ),
    );
  }
}

class _ChangePasswordScreenState extends State<ChangePasswordScreen> {
  final _newPasswordController = TextEditingController();
  final _confirmPasswordController = TextEditingController();
  bool _isLoading = false;

  Future<void> _updatePassword() async {
    final newPassword = _newPasswordController.text.trim();
    final confirmPassword = _confirmPasswordController.text.trim();
    
    if (newPassword.isEmpty || confirmPassword.isEmpty) {
      _showMessage('Заполните все поля', isError: true);
      return;
    }
    
    if (newPassword != confirmPassword) {
      _showMessage('Пароли не совпадают', isError: true);
      return;
    }
    
    if (newPassword.length < 6) {
      _showMessage('Пароль должен быть не менее 6 символов', isError: true);
      return;
    }
    
    setState(() => _isLoading = true);
    
    try {
      await supabase.auth.updateUser(
        UserAttributes(password: newPassword),
      );
      
      _showMessage('Пароль успешно изменён');
      Navigator.pop(context);
    } on AuthException catch (e) {
      _showMessage('Ошибка: ${e.message}', isError: true);
    } catch (e) {
      _showMessage('Ошибка при смене пароля', isError: true);
    } finally {
      setState(() => _isLoading = false);
    }
  }

  void _showMessage(String message, {bool isError = false}) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: isError ? Colors.red : Colors.green,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Смена пароля'),
      ),
      body: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            TextField(
              controller: _newPasswordController,
              obscureText: true,
              decoration: const InputDecoration(
                labelText: 'Новый пароль',
                prefixIcon: Icon(Icons.lock),
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 16),
            TextField(
              controller: _confirmPasswordController,
              obscureText: true,
              decoration: const InputDecoration(
                labelText: 'Подтвердите пароль',
                prefixIcon: Icon(Icons.lock_outline),
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 24),
            if (_isLoading)
              const CircularProgressIndicator()
            else
              ElevatedButton(
                onPressed: _updatePassword,
                style: ElevatedButton.styleFrom(
                  minimumSize: const Size(double.infinity, 50),
                ),
                child: const Text('Изменить пароль'),
              ),
          ],
        ),
      ),
    );
  }
}

Future<Uint8List> consolidateHttpClientResponseBytes(HttpClientResponse response) async {
  final completer = Completer<Uint8List>();
  final chunks = <Uint8List>[];
  
  response.listen(
    (List<int> chunk) {
      chunks.add(Uint8List.fromList(chunk));
    },
    onDone: () {
      final totalLength = chunks.fold<int>(0, (prev, element) => prev + element.length);
      final bytes = Uint8List(totalLength);
      int offset = 0;
      for (final chunk in chunks) {
        bytes.setRange(offset, offset + chunk.length, chunk);
        offset += chunk.length;
      }
      completer.complete(bytes);
    },
    onError: (error) => completer.completeError(error),
  );
  
  return completer.future;
}