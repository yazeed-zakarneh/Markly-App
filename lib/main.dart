import 'package:flutter/material.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_auth/firebase_auth.dart';

// We do not need to import firebase_options.dart in this version.

// Import your screen files
import 'screens/welcome_screen.dart'; // Using WelcomePage as the entry point for new users
import 'screens/home_screen.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  // This is the initialization method that works with your project setup.
  await Firebase.initializeApp();
  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Markly',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        scaffoldBackgroundColor: Colors.white,
        primarySwatch: Colors.indigo,
        fontFamily: 'Roboto',

        // This theme will apply to all AppBars in your app.
        appBarTheme: const AppBarTheme(
          iconTheme: IconThemeData(
            color: Color(0xFF1A237E),
          ),
          // This targets icons on the right side of the AppBar (like the menu)
          actionsIconTheme: IconThemeData(
            color: Color(0xFF1A237E), // Your brand color
          ),
        ),
      ),
      home: const AuthGate(),
    );
  }
}

class AuthGate extends StatelessWidget {
  const AuthGate({super.key});

  @override
  Widget build(BuildContext context) {
    // This StreamBuilder automatically rebuilds when the user logs in or out.
    return StreamBuilder<User?>(
      stream: FirebaseAuth.instance.authStateChanges(),
      builder: (context, snapshot) {
        // If snapshot has data, it means user is logged in.
        if (snapshot.hasData) {
          return const HomeScreen();
        }

        // No user, so show the main welcome page.
        return const WelcomePage();
      },
    );
  }
}