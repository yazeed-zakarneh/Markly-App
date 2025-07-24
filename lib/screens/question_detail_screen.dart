import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import '../widgets/custom_drawer.dart';

class QuestionDetailScreen extends StatefulWidget {
  final String classId;
  final String examId;
  final String questionId;
  final String questionName;
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
  final TextEditingController _questionController = TextEditingController();
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
    _questionController.dispose();
    _answerController.dispose();
    _gradeController.dispose();
    super.dispose();
  }

  Future<void> _loadInitialData() async {
    try {
      final userId = FirebaseAuth.instance.currentUser!.uid;
      final docSnapshot = await FirebaseFirestore.instance
          .collection('users').doc(userId).collection('classes')
          .doc(widget.classId).collection('exams').doc(widget.examId)
          .collection('questions').doc(widget.questionId).get();

      if (docSnapshot.exists && mounted) {
        final data = docSnapshot.data();
        _questionController.text = data?['fullQuestion'] ?? 'Question not found.';
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
      endDrawer: CustomDrawer(onClose: () => Navigator.pop(context)),
      appBar: AppBar(
        backgroundColor: Colors.white,
        elevation: 0,
        title: Image.asset('assets/images/logo_text.png', height: 40),
        centerTitle: true,
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(48),
          child: Padding(
            padding: const EdgeInsets.only(left: 16, bottom: 12, right: 16),
            child: Align(
              alignment: Alignment.centerLeft,
              child: Text(
                '${widget.className} - ${widget.examTitle} - ${widget.questionName}',
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
            TextField(
              controller: _questionController,
              readOnly: true,
              decoration: const InputDecoration(
                labelText: "Question",
                border: OutlineInputBorder(),
                fillColor: Color(0xFFF5F5F5),
                filled: true,
              ),
              style: const TextStyle(fontWeight: FontWeight.bold),
              maxLines: null,
            ),
            const SizedBox(height: 16),

            TextField(
              readOnly: true,
              controller: _answerController,
              decoration: const InputDecoration(
                labelText: "Key Answer",
                border: OutlineInputBorder(),
              ),
              maxLines: null,
            ),
            const SizedBox(height: 16),

            TextField(
              controller: _gradeController,
              decoration: const InputDecoration(
                labelText: 'Max Grade',
                border: OutlineInputBorder(),
              ),
              keyboardType: TextInputType.number,
              maxLines: null,
            ),
            const SizedBox(height: 24),

            Center(
              child: ElevatedButton(
                onPressed: _isSaving ? null : _saveData,
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFF1A237E),
                  padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 14),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
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