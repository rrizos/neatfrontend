import 'package:flutter/material.dart';

import 'auth/auth_gate.dart';

class NeatApp extends StatelessWidget {
  const NeatApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'neat',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        useMaterial3: true,
        brightness: Brightness.dark,
        scaffoldBackgroundColor: const Color(0xff121212),
        colorScheme: const ColorScheme.dark(
          primary: Colors.white,
          secondary: Color(0xff4ea3ff),
          surface: Color(0xff121212),
        ),
        appBarTheme: const AppBarTheme(
          backgroundColor: Color(0xff121212),
          foregroundColor: Colors.white,
          elevation: 0,
          surfaceTintColor: Color(0xff121212),
        ),
        bottomNavigationBarTheme: const BottomNavigationBarThemeData(
          backgroundColor: Color(0xff121212),
          selectedItemColor: Colors.white,
          unselectedItemColor: Color(0xffa9a9a9),
        ),
      ),
      home: const AuthGate(),
    );
  }
}
