import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import '../widgets/custom_drawer.dart';

class QuestionDetailScreen extends StatefulWidget {
  final String classId;
  final String examId;
  final String questionId;
  final String questionName; // This is the "Q#) ... ?" text
  final String className;
  final String examTitle;

  const QuestionDetailScreen({
    super.key,
    required this.classId,
    required this.examId,
    required this.questionId,
    required this.questionName,
    required this.className,
    required this.examTitle,
  });

  @override
  State<QuestionDetailScreen> createState() => _QuestionDetailScreenState();
}

class _QuestionDetailScreenState extends State<QuestionDetailScreen> {
  // We only need controllers and loading/saving state. No more OCR state.
  final TextEditingController _answerController = TextEditingController();
  final TextEditingController _gradeController = TextEditingController();
  bool _isSaving = false;
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _loadInitialData();
  }

  @override
  void dispose() {
    _answerController.dispose();
    _gradeController.dispose();
    super.dispose();
  }

  /// Loads the saved answer and grade from Firestore.
  Future<void> _loadInitialData() async {
    try {
      final userId = FirebaseAuth.instance.currentUser!.uid;
      final docSnapshot = await FirebaseFirestore.instance
          .collection('users').doc(userId).collection('classes')
          .doc(widget.classId).collection('exams').doc(widget.examId)
          .collection('questions').doc(widget.questionId).get();

      if (docSnapshot.exists && mounted) {
        final data = docSnapshot.data();
        // 'text1' holds the answer, 'text2' holds the grade/notes.
        _answerController.text = data?['text1'] ?? '';
        _gradeController.text = data?['text2'] ?? '';
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed to load existing data: $e')),
        );
      }
    } finally {
      if (mounted) {
        setState(() => _isLoading = false);
      }
    }
  }

  /// Saves any changes to the answer or grade.
  Future<void> _saveData() async {
    setState(() => _isSaving = true);
    final userId = FirebaseAuth.instance.currentUser!.uid;
    try {
      await FirebaseFirestore.instance
          .collection('users').doc(userId).collection('classes')
          .doc(widget.classId).collection('exams').doc(widget.examId)
          .collection('questions').doc(widget.questionId).update({
        'text1': _answerController.text,
        'text2': _gradeController.text,
        'updatedAt': FieldValue.serverTimestamp(),
      });

      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(const SnackBar(content: Text('Saved successfully')));
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('Failed to save: $e')));
      }
    } finally {
      if (mounted) {
        setState(() => _isSaving = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      drawer: CustomDrawer(onClose: () => Navigator.pop(context)),
      appBar: AppBar(
        // ... your AppBar code is fine ...
        backgroundColor: Colors.white,
        elevation: 0,
        automaticallyImplyLeading: false,
        title: Row(
          children: [
            IconButton(
              icon: const Icon(Icons.arrow_back, color: Color(0xFF1A237E)),
              onPressed: () => Navigator.pop(context),
            ),
            const Spacer(),
            Image.asset('assets/images/logo_text.png', height: 40),
            const Spacer(),
            Builder(
              builder: (context) => IconButton(
                icon: const Icon(Icons.menu, color: Color(0xFF1A237E)),
                onPressed: () => Scaffold.of(context).openDrawer(),
              ),
            ),
          ],
        ),
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(48),
          child: Padding(
            padding: const EdgeInsets.only(left: 16, bottom: 12, right: 16),
            child: Align(
              alignment: Alignment.centerLeft,
              child: Text(
                '${widget.className} > ${widget.examTitle}',
                style: const TextStyle(
                  fontWeight: FontWeight.bold,
                  color: Color(0xFF1A237E),
                  fontSize: 16,
                ),
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ),
        ),
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator(color: Color(0xFF1A237E)))
          : SingleChildScrollView(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Display the question text clearly.
            Text(
              widget.questionName,
              style: const TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                  color: Colors.black87
              ),
            ),
            const SizedBox(height: 24),

            // Text field for the student's answer.
            TextField(
              controller: _answerController,
              decoration: const InputDecoration(
                labelText: "Student's Answer",
                border: OutlineInputBorder(),
              ),
              maxLines: null, // Allows multiline
            ),
            const SizedBox(height: 16),

            // Text field for your grade or notes.
            TextField(
              controller: _gradeController,
              decoration: const InputDecoration(
                labelText: 'Grade / Notes',
                border: OutlineInputBorder(),
              ),
              maxLines: null,
            ),
            const SizedBox(height: 24),

            // Center the save button
            Center(
              child: ElevatedButton(
                onPressed: _isSaving ? null : _saveData,
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFF1A237E),
                  padding: const EdgeInsets.symmetric(
                      horizontal: 32, vertical: 14),
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12)),
                ),
                child: _isSaving
                    ? const SizedBox(
                    height: 20,
                    width: 20,
                    child: CircularProgressIndicator(
                        strokeWidth: 2, color: Colors.white))
                    : const Text('Save',
                    style:
                    TextStyle(fontSize: 16, color: Colors.white)),
              ),
            ),
          ],
        ),
      ),
    );
  }
}