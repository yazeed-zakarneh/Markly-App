import 'dart:io';
import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:image_picker/image_picker.dart';
import '../screens/question_detail_screen.dart';
import '../models/ocr_model.dart'; // Make sure this path is correct

class QuestionsTab extends StatefulWidget {
  final String classId;
  final String examId;
  final String className;
  final String examTitle;

  const QuestionsTab({
    super.key,
    required this.classId,
    required this.examId,
    required this.className,
    required this.examTitle,
  });

  @override
  State<QuestionsTab> createState() => _QuestionsTabState();
}

class _QuestionsTabState extends State<QuestionsTab> {
  final userId = FirebaseAuth.instance.currentUser!.uid;
  final OcrService _ocrService = OcrService();

  void _showAddQuestionsFromImageDialog() {
    bool isLoading = false;
    String statusMessage = 'Upload an exam sheet to extract questions.';

    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setDialogState) {

            Future<void> processImage() async {
              final picker = ImagePicker();
              final picked = await picker.pickImage(
                  source: ImageSource.gallery,
                  maxWidth: 1800,
                  imageQuality: 85);
              if (picked == null) return;

              setDialogState(() {
                isLoading = true;
                statusMessage = 'Processing image with OCR...';
              });

              try {
                final rawText = await _ocrService.performOcr(File(picked.path));
                if (rawText == null || rawText.isEmpty) {
                  throw Exception("OCR could not extract any text.");
                }

                final questionsToCreate = _ocrService.extractQuestionsFromText(rawText);
                if (questionsToCreate.isEmpty) {
                  throw Exception("No valid questions found in the format 'Q#) ... ?'");
                }

                setDialogState(() {
                  statusMessage = 'Found ${questionsToCreate.length} questions. Saving...';
                });

                final questionsCollection = FirebaseFirestore.instance
                    .collection('users').doc(userId).collection('classes')
                    .doc(widget.classId).collection('exams').doc(widget.examId)
                    .collection('questions');

                // Fetch the current number of questions to determine the starting index.
                final existingDocsSnapshot = await questionsCollection.get();
                final existingQuestionCount = existingDocsSnapshot.size;

                final batch = FirebaseFirestore.instance.batch();

                for (int i = 0; i < questionsToCreate.length; i++) {
                  final pq = questionsToCreate[i];

                  // Calculate the new number based on how many questions already exist.
                  final newQuestionNumber = existingQuestionCount + i + 1;
                  final simpleName = 'Q$newQuestionNumber';

                  final newQuestionRef = questionsCollection.doc();
                  batch.set(newQuestionRef, {
                    'name': simpleName,
                    'fullQuestion': pq.question,
                    'text1': pq.answer,
                    'text2': '',
                    'questionNumber': newQuestionNumber,
                    'createdAt': FieldValue.serverTimestamp(),
                  });
                }

                await batch.commit();

                Navigator.pop(context);
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(content: Text('Successfully added ${questionsToCreate.length} questions!')),
                );

              } catch (e) {
                setDialogState(() {
                  isLoading = false;
                  statusMessage = 'Error: $e\nPlease try again.';
                });
              }
            }

            return AlertDialog(
              title: const Text("Add Questions from Image"),
              content: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(statusMessage, textAlign: TextAlign.center),
                  if (isLoading)
                    const Padding(
                      padding: EdgeInsets.only(top: 20),
                      child: CircularProgressIndicator(),
                    ),
                ],
              ),
              actions: [
                TextButton(
                  onPressed: isLoading ? null : () => Navigator.pop(context),
                  child: const Text("Cancel"),
                ),
                ElevatedButton.icon(
                  onPressed: isLoading ? null : processImage,
                  icon: const Icon(Icons.upload_file),
                  label: const Text("Upload"),
                ),
              ],
            );
          },
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    // This query correctly sorts all questions, new and old, by their number.
    final questionsRef = FirebaseFirestore.instance
        .collection('users').doc(userId).collection('classes')
        .doc(widget.classId).collection('exams').doc(widget.examId)
        .collection('questions').orderBy('questionNumber', descending: false);

    return Stack(
      children: [
        StreamBuilder<QuerySnapshot>(
          stream: questionsRef.snapshots(),
          builder: (context, snapshot) {
            if (snapshot.connectionState == ConnectionState.waiting) {
              return const Center(child: CircularProgressIndicator());
            }

            final questions = snapshot.data?.docs ?? [];

            if (questions.isEmpty) {
              return const Center(
                child: Text(
                  'No questions yet. Tap the + button to add.',
                  style: TextStyle(fontSize: 16, color: Colors.grey),
                ),
              );
            }

            return ListView.builder(
              padding: const EdgeInsets.all(16.0).copyWith(bottom: 80),
              itemCount: questions.length,
              itemBuilder: (context, index) {
                final data = questions[index].data() as Map<String, dynamic>;
                final questionText = data['name'] ?? 'Unnamed Question';

                return Card(
                  margin: const EdgeInsets.only(bottom: 12),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                  child: ListTile(
                    leading: const Icon(Icons.help_outline, color: Color(0xFF1A237E)),
                    title: Text(
                      questionText,
                      style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                    ),
                    tileColor: const Color(0xFFF5F5F5),
                    onTap: () {
                      Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (_) => QuestionDetailScreen(
                            classId: widget.classId,
                            examId: widget.examId,
                            questionId: questions[index].id,
                            questionName: questionText,
                            className: widget.className,
                            examTitle: widget.examTitle,
                          ),
                        ),
                      );
                    },
                  ),
                );
              },
            );
          },
        ),
        Positioned(
          bottom: 20,
          right: 20,
          child: FloatingActionButton(
            onPressed: _showAddQuestionsFromImageDialog,
            backgroundColor: const Color(0xFF1A237E),
            child: const Icon(Icons.add_a_photo_outlined),
          ),
        ),
      ],
    );
  }
}