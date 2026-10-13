import 'package:flutter/material.dart';

import 'theme/app_theme.dart';

void main() => runApp(const QuranApp());

class QuranApp extends StatelessWidget {
  const QuranApp({super.key});

  @override
  Widget build(BuildContext context) => MaterialApp(
        title: 'Quran',
        theme: AppTheme.light(),
        darkTheme: AppTheme.dark(),
        home: const Scaffold(body: Center(child: Text('Quran'))),
      );
}
