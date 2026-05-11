import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:scheduler/app/scheduling_shell.dart';
import 'package:scheduler/auth/sign_in_screen.dart';

/// Routes signed-out users to [SignInScreen], signed-in users to [SchedulingShell].
class AuthGate extends StatelessWidget {
  const AuthGate({super.key});

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<User?>(
      stream: FirebaseAuth.instance.authStateChanges(),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Scaffold(
            body: Center(child: CircularProgressIndicator()),
          );
        }
        if (snapshot.hasData) {
          return const SchedulingShell();
        }
        return const SignInScreen();
      },
    );
  }
}
