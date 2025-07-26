import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:google_sign_in/google_sign_in.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'signin_screen.dart';
import 'home_screen.dart';

class SignUpScreen extends StatefulWidget {
  const SignUpScreen({super.key});

  @override
  State<SignUpScreen> createState() => _SignUpScreenState();
}

class _SignUpScreenState extends State<SignUpScreen> {
  final firstNameController = TextEditingController();
  final lastNameController = TextEditingController();
  final emailController = TextEditingController();
  final passwordController = TextEditingController();
  final confirmPasswordController = TextEditingController();

  bool isLoading = false;

  @override
  void dispose() {
    firstNameController.dispose();
    lastNameController.dispose();
    emailController.dispose();
    passwordController.dispose();
    confirmPasswordController.dispose();
    super.dispose();
  }


  Future<void> handleSignUp() async {
    if (!mounted) return;
    if (passwordController.text != confirmPasswordController.text) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text("Passwords do not match")),
      );
      return;
    }

    final scaffoldMessenger = ScaffoldMessenger.of(context);
    final navigator = Navigator.of(context);

    try {
      setState(() => isLoading = true);


      final credential = await FirebaseAuth.instance.createUserWithEmailAndPassword(
        email: emailController.text.trim(),
        password: passwordController.text.trim(),
      );

      final user = credential.user;
      if (user == null) {
        throw FirebaseAuthException(code: 'user-not-found');
      }


      final fullName = '${firstNameController.text.trim()} ${lastNameController.text.trim()}';
      await user.updateDisplayName(fullName);


      await FirebaseFirestore.instance.collection('users').doc(user.uid).set({
        'name': fullName,
        'email': user.email,
        'photoUrl': user.photoURL,
        'createdAt': FieldValue.serverTimestamp(),
      });


      await user.sendEmailVerification();

      scaffoldMessenger.showSnackBar(
        const SnackBar(content: Text("Verification email sent. Please check your inbox.")),
      );

      navigator.pushReplacement(
        MaterialPageRoute(builder: (_) => const SignInScreen()),
      );
    } on FirebaseAuthException catch (e) {
      scaffoldMessenger.showSnackBar(
        SnackBar(content: Text(e.message ?? "Sign up failed")),
      );
    } finally {
      if (mounted) {
        setState(() => isLoading = false);
      }
    }
  }


  Future<void> handleGoogleSignIn() async {
    if (!mounted) return;
    final navigator = Navigator.of(context);
    final scaffoldMessenger = ScaffoldMessenger.of(context);

    try {
      setState(() => isLoading = true);

      final googleSignIn = GoogleSignIn(scopes: ['email']);
      await googleSignIn.signOut();
      final googleUser = await googleSignIn.signIn();
      if (googleUser == null) {
        if (mounted) setState(() => isLoading = false);
        return;
      }

      final googleAuth = await googleUser.authentication;
      final credential = GoogleAuthProvider.credential(
        accessToken: googleAuth.accessToken,
        idToken: googleAuth.idToken,
      );


      final userCredential = await FirebaseAuth.instance.signInWithCredential(credential);
      final user = userCredential.user;

      if (user == null) {
        throw FirebaseAuthException(code: 'user-not-found');
      }


      await FirebaseFirestore.instance.collection('users').doc(user.uid).set({
        'name': user.displayName,
        'email': user.email,
        'photoUrl': user.photoURL,
        'createdAt': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));

      navigator.pushReplacement(
        MaterialPageRoute(builder: (_) => const HomeScreen()),
      );
    } on FirebaseAuthException catch (e) {
      scaffoldMessenger.showSnackBar(
        SnackBar(content: Text(e.message ?? "Google sign-in failed")),
      );
    } finally {
      if (mounted) {
        setState(() => isLoading = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: [
        Scaffold(
          body: SafeArea(
            child: Center(
              child: SingleChildScrollView(
                padding: const EdgeInsets.symmetric(horizontal: 24.0),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Container(
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        border: Border.all(
                          color: const Color(0xFF1A237E),
                          width: 2.0,
                        ),
                      ),
                      child: const CircleAvatar(
                        radius: 60,
                        backgroundImage: AssetImage('assets/images/logo.png'),
                        backgroundColor: Colors.transparent,
                      ),
                    ),
                    const SizedBox(height: 32),
                    Row(
                      children: [
                        Expanded(
                          child: TextField(
                            controller: firstNameController,
                            decoration: const InputDecoration(
                              labelText: 'First Name',
                              border: OutlineInputBorder(borderRadius: BorderRadius.all(Radius.circular(10))),
                            ),
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: TextField(
                            controller: lastNameController,
                            decoration: const InputDecoration(
                              labelText: 'Last Name',
                              border: OutlineInputBorder(borderRadius: BorderRadius.all(Radius.circular(10))),
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 16),
                    TextField(
                      controller: emailController,
                      decoration: const InputDecoration(
                        labelText: 'Email',
                        border: OutlineInputBorder(borderRadius: BorderRadius.all(Radius.circular(10))),
                      ),
                    ),
                    const SizedBox(height: 16),
                    TextField(
                      controller: passwordController,
                      obscureText: true,
                      decoration: const InputDecoration(
                        labelText: 'Password',
                        border: OutlineInputBorder(borderRadius: BorderRadius.all(Radius.circular(10))),
                      ),
                    ),
                    const SizedBox(height: 16),
                    TextField(
                      controller: confirmPasswordController,
                      obscureText: true,
                      decoration: const InputDecoration(
                        labelText: 'Confirm Password',
                        border: OutlineInputBorder(borderRadius: BorderRadius.all(Radius.circular(10))),
                      ),
                    ),
                    const SizedBox(height: 24),
                    ElevatedButton(
                      onPressed: isLoading ? null : handleSignUp,
                      style: ElevatedButton.styleFrom(
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.all(Radius.circular(10))),
                        backgroundColor: const Color(0xFF1A237E),
                        minimumSize: const Size.fromHeight(50),
                      ),
                      child: const Text('Sign up', style: TextStyle(fontSize: 16, color: Colors.white)),
                    ),
                    const SizedBox(height: 12),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        const Text("Already have an account? "),
                        GestureDetector(
                          onTap: () {
                            Navigator.push(
                              context,
                              MaterialPageRoute(builder: (context) => const SignInScreen()),
                            );
                          },
                          child: const Text(
                            "Sign in",
                            style: TextStyle(
                              fontWeight: FontWeight.bold,
                              decoration: TextDecoration.underline,
                            ),
                          ),
                        )
                      ],
                    ),
                    const SizedBox(height: 20),
                    Row(
                      children: const [
                        Expanded(child: Divider(thickness: 1)),
                        Padding(
                          padding: EdgeInsets.symmetric(horizontal: 8.0),
                          child: Text("or"),
                        ),
                        Expanded(child: Divider(thickness: 1)),
                      ],
                    ),
                    const SizedBox(height: 16),
                    OutlinedButton.icon(
                      onPressed: isLoading ? null : handleGoogleSignIn,
                      icon: Image.asset('assets/images/google_logo.png', height: 24),
                      label: const Text(
                        'Continue with Google',
                        style: TextStyle(fontSize: 16, color: Colors.black87),
                      ),
                      style: OutlinedButton.styleFrom(
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.all(Radius.circular(10))),
                        minimumSize: const Size.fromHeight(50),
                        side: const BorderSide(color: Colors.grey),
                      ),
                    ),
                    const SizedBox(height: 24),
                  ],
                ),
              ),
            ),
          ),
        ),
        if (isLoading)
          Container(
            color: Colors.black.withOpacity(0.4),
            child: const Center(
              child: CircularProgressIndicator(color: Colors.white),
            ),
          ),
      ],
    );
  }
}