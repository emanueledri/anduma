// Transito Torino — client Flutter (M7: arrivi, mappa, preferiti, avvisi, push).
import 'package:flutter/material.dart';

import 'screens/home_shell.dart';
import 'theme/app_theme.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(const TransitoApp());
}

class TransitoApp extends StatelessWidget {
  const TransitoApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Transito Torino',
      debugShowCheckedModeBanner: false,
      theme: AppTheme.light(),
      darkTheme: AppTheme.dark(),
      themeMode: ThemeMode.system, // light-default, dark se di sistema
      home: const HomeShell(),
    );
  }
}
