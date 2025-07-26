import 'package:flutter/material.dart';
import '../widgets/custom_drawer.dart';

class AboutUsScreen extends StatelessWidget {
  const AboutUsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(

      endDrawer: CustomDrawer(onClose: () => Navigator.pop(context)),
      backgroundColor: Colors.white,
      appBar: AppBar(
        backgroundColor: Colors.white,
        elevation: 0,
        title: Text(
          'About Us',
          style: TextStyle(
            color: Color(0xFF1A237E),
            fontWeight: FontWeight.bold,
            fontSize: 18,
          ),
        ),
        centerTitle: true,
      ),
      body: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 24.0, vertical: 20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: const [
            Text(
              'Welcome to Markly!',
              style: TextStyle(
                fontSize: 22,
                fontWeight: FontWeight.bold,
                color: Color(0xFF1A237E),
              ),
            ),
            SizedBox(height: 16),
            Text(
              'Markly is a smart exam grading assistant designed to simplify and speed up the process of evaluating paper-based exams. '
                  'We combine cutting-edge OCR technology with AI to help educators save time and ensure accurate and fair grading.',
              style: TextStyle(fontSize: 16, height: 1.5),
            ),
            SizedBox(height: 16),
            Text(
              'Our Mission:',
              style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
            ),
            Text(
              'To support teachers and schools by providing modern tools that reduce manual work and improve assessment quality.',
              style: TextStyle(fontSize: 16),
            ),
            SizedBox(height: 24),
            Text(
              'If you have questions or suggestions, feel free to reach out!',
              style: TextStyle(fontSize: 16),
            ),
          ],
        ),
      ),
    );
  }
}