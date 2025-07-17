import 'dart:io';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
// We do not need firebase_storage in this version as per your request
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:markly/models/student_model.dart';
import 'package:markly/widgets/custom_drawer.dart';
import '../models/ocr_model.dart';

// The QaDisplayCard widget remains the same and is correct.
class _QaDisplayCard extends StatelessWidget {
  final String question;
  final String answer;
  final num? mark;

  const _QaDisplayCard({required this.question, required this.answer, this.mark});

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: const EdgeInsets.only(bottom: 16),
      elevation: 2,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: Text(
                    question,
                    style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16, color: Color(0xFF1A237E)),
                  ),
                ),
                if (mark != null) ...[
                  const SizedBox(width: 16),
                  Text(
                    mark!.toStringAsFixed(1),
                    style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 18, color: Colors.teal),
                  ),
                ],
              ],
            ),
            const SizedBox(height: 8),
            const Divider(),
            const SizedBox(height: 8),
            Text(
              answer.isNotEmpty ? answer : "(No answer was provided)",
              style: TextStyle(fontSize: 15, color: Colors.grey[800], fontStyle: FontStyle.italic),
            ),
          ],
        ),
      ),
    );
  }
}

class StudentScreen extends StatefulWidget {
  final Student student;
  final String classId;
  final String examId;
  const StudentScreen({super.key, required this.student, required this.classId, required this.examId});

  @override
  State<StudentScreen> createState() => _StudentPageState();
}

class _StudentPageState extends State<StudentScreen> {
  bool _isProcessing = false;
  final String userId = FirebaseAuth.instance.currentUser!.uid;
  final OcrService _ocrService = OcrService();

  late final CollectionReference _answersCollection;

  @override
  void initState() {
    super.initState();
    _answersCollection = FirebaseFirestore.instance
        .collection('users').doc(userId).collection('classes')
        .doc(widget.classId).collection('exams').doc(widget.examId)
        .collection('students').doc(widget.student.id).collection('answers');
  }

  /// UPDATED: This function now uses the Regex-based parser directly.
  Future<void> _addAndProcessSheet() async {
    if (_isProcessing) return;
    final picker = ImagePicker();
    final pickedFile = await picker.pickImage(source: ImageSource.gallery, maxWidth: 1800, imageQuality: 85);
    if (pickedFile == null) return;

    setState(() => _isProcessing = true);
    final imageFile = File(pickedFile.path);

    try {
      // Step 1: Perform OCR to get raw text
      final rawText = await _ocrService.performOcr(imageFile);
      if (rawText == null || rawText.isEmpty) throw Exception("OCR failed to extract text.");

      // Step 2: Parse the raw text directly using the Regex-based method.
      // NO second API call is made.
      final parsedQuestions = _ocrService.extractQuestionsFromText(rawText);
      if (parsedQuestions.isEmpty) throw Exception("No questions could be parsed from the sheet using the format Q#)...?");

      // Step 3: Get the current number of answers to continue numbering
      final existingAnswersSnapshot = await _answersCollection.get();
      final existingAnswersCount = existingAnswersSnapshot.size;

      // Step 4: Save each parsed answer as a new document in Firestore
      final batch = FirebaseFirestore.instance.batch();
      for (int i = 0; i < parsedQuestions.length; i++) {
        final pq = parsedQuestions[i];
        final newAnswerNumber = existingAnswersCount + i + 1;

        final newAnswerDocRef = _answersCollection.doc();

        batch.set(newAnswerDocRef, {
          'questionNumber': newAnswerNumber,
          'questionText': pq.question,
          'studentAnswer': pq.answer,
          'mark': null, // No image URL is saved
        });
      }

      await batch.commit();

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Successfully added ${parsedQuestions.length} answers!')));
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Failed to process sheet: $e'), backgroundColor: Colors.red));
      }
    } finally {
      if (mounted) {
        setState(() => _isProcessing = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      drawer: CustomDrawer(onClose: () => Navigator.pop(context)),
      appBar: AppBar(
        backgroundColor: Colors.white, elevation: 0, automaticallyImplyLeading: false,
        title: Row(children: [
          IconButton(icon: const Icon(Icons.arrow_back, color: Color(0xFF1A237E)), onPressed: () => Navigator.pop(context)),
          const Spacer(), Image.asset('assets/images/logo_text.png', height: 40), const Spacer(),
          Builder(builder: (context) => IconButton(icon: const Icon(Icons.menu, color: Color(0xFF1A237E)), onPressed: () => Scaffold.of(context).openDrawer())),
        ]),
      ),
      body: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 8.0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(widget.student.name, style: const TextStyle(fontSize: 22, fontWeight: FontWeight.bold, color: Color(0xFF1A237E))),
                  Text('ID: ${widget.student.studentId}', style: TextStyle(fontSize: 16, color: Colors.grey[700])),
                ],
              ),
            ),
            const SizedBox(height: 16),
            Center(
              child: ElevatedButton.icon(
                style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFF1A237E), foregroundColor: Colors.white, padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12)),
                onPressed: _isProcessing ? null : _addAndProcessSheet,
                icon: _isProcessing ? Container(width: 20, height: 20, margin: const EdgeInsets.only(right: 8), child: const CircularProgressIndicator(color: Colors.white, strokeWidth: 2)) : const Icon(Icons.add_a_photo_outlined),
                label: Text(_isProcessing ? 'Processing...' : 'Add Answer Sheet'),
              ),
            ),
            const SizedBox(height: 16),
            const Divider(),
            Expanded(
              child: StreamBuilder<QuerySnapshot>(
                stream: _answersCollection.orderBy('questionNumber').snapshots(),
                builder: (context, snapshot) {
                  if (snapshot.connectionState == ConnectionState.waiting) {
                    return const Center(child: CircularProgressIndicator());
                  }
                  if (snapshot.hasError) {
                    return Center(child: Text("Error: ${snapshot.error}"));
                  }
                  if (!snapshot.hasData || snapshot.data!.docs.isEmpty) {
                    return const Center(
                      child: Text("No answers found for this student.\nScan an answer sheet to begin.", textAlign: TextAlign.center, style: TextStyle(fontSize: 16, color: Colors.grey)),
                    );
                  }

                  final answerDocs = snapshot.data!.docs;

                  return ListView.builder(
                    padding: const EdgeInsets.only(top: 8),
                    itemCount: answerDocs.length,
                    itemBuilder: (context, index) {
                      final data = answerDocs[index].data() as Map<String, dynamic>;

                      return Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Padding(
                            padding: const EdgeInsets.only(left: 4.0, bottom: 4.0),
                            child: Text(
                              'Question ${data['questionNumber']}',
                              style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: Colors.black87),
                            ),
                          ),
                          _QaDisplayCard(
                            question: data['questionText'] ?? '',
                            answer: data['studentAnswer'] ?? '',
                            mark: data['mark'] as num?,
                          ),
                        ],
                      );
                    },
                  );
                },
              ),
            )
          ],
        ),
      ),
    );
  }
}