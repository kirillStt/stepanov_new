import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart'; // или используйте Navigator

class EmailConfirmationScreen extends StatefulWidget {
  const EmailConfirmationScreen({super.key});

  @override
  State<EmailConfirmationScreen> createState() => _EmailConfirmationScreenState();
}

class _EmailConfirmationScreenState extends State<EmailConfirmationScreen> {
  @override
  void initState() {
    super.initState();
    _handleConfirmation();
  }

  Future<void> _handleConfirmation() async {
    // Небольшая задержка для показа анимации
    await Future.delayed(const Duration(seconds: 2));
    
    if (mounted) {
      // Показываем диалог успеха
      showDialog(
        context: context,
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
                Navigator.pop(context); // закрыть диалог
                Navigator.pop(context); // вернуться на экран входа
              },
              child: const Text('Войти'),
            ),
          ],
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const CircularProgressIndicator(),
            const SizedBox(height: 24),
            Text(
              'Подтверждение email...',
              style: Theme.of(context).textTheme.titleMedium,
            ),
          ],
        ),
      ),
    );
  }
}