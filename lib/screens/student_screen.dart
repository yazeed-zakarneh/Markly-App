import 'dart:async';
import 'dart:io';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:markly/models/student_model.dart';
import 'package:markly/widgets/custom_drawer.dart';
import '../models/ocr_model.dart';

class _CombinedAnswerData {
  final String questionText;
  final String studentAnswer;
  final double baseMark;
  final double maxGrade;
  _CombinedAnswerData({ required this.questionText, required this.studentAnswer, required this.baseMark, required this.maxGrade });
  double get scaledMark => (baseMark * maxGrade) / 10.0;
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

  late Future<List<_CombinedAnswerData>> _combinedDataFuture;

  @override
  void initState() {
    super.initState();
    _combinedDataFuture = _loadCombinedData();
  }

  Future<List<_CombinedAnswerData>> _loadCombinedData() async {
    final questionsQuery = FirebaseFirestore.instance.collection('users').doc(userId).collection('classes').doc(widget.classId).collection('exams').doc(widget.examId).collection('questions').orderBy('questionNumber');
    final answersQuery = FirebaseFirestore.instance.collection('users').doc(userId).collection('classes').doc(widget.classId).collection('exams').doc(widget.examId).collection('students').doc(widget.student.id).collection('answers').orderBy('questionNumber');

    final results = await Future.wait([ questionsQuery.get(), answersQuery.get() ]);
    final questionDocs = results[0].docs;
    final answerDocs = results[1].docs;

    final List<_CombinedAnswerData> combinedList = [];
    final int loopCount = questionDocs.length < answerDocs.length ? questionDocs.length : answerDocs.length;

    for (int i = 0; i < loopCount; i++) {
      final questionData = questionDocs[i].data();
      final answerData = answerDocs[i].data();
      final double maxGrade = double.tryParse(questionData['text2'] ?? '10.0') ?? 10.0;
      final double baseMark = (answerData['mark'] as num?)?.toDouble() ?? 0.0;

      combinedList.add(_CombinedAnswerData(
        questionText: '${questionData['fullQuestion']}',
        studentAnswer: answerData['studentAnswer'] ?? '',
        baseMark: baseMark,
        maxGrade: maxGrade,
      ));
    }
    return combinedList;
  }

  Future<void> _addAndProcessSheet() async {
    if (_isProcessing) return;
    setState(() => _isProcessing = true);
    final picker = ImagePicker();
    final pickedFile = await picker.pickImage(source: ImageSource.gallery, maxWidth: 1800, imageQuality: 85);
    if (pickedFile == null) {
      setState(() => _isProcessing = false);
      return;
    }
    final imageFile = File(pickedFile.path);
    try {
      final rawText = await _ocrService.performOcr(imageFile);
      if (rawText == null) throw Exception("OCR failed.");
      final enhancedText = await _ocrService.enhanceOcrText(rawText);
      final parsedQuestions = _ocrService.extractQuestionsFromText(enhancedText);
      if (parsedQuestions.isEmpty) throw Exception("No questions parsed.");

      final answersCollection = FirebaseFirestore.instance.collection('users').doc(userId).collection('classes').doc(widget.classId).collection('exams').doc(widget.examId).collection('students').doc(widget.student.id).collection('answers');
      final existingAnswersCount = (await answersCollection.get()).size;

      final batch = FirebaseFirestore.instance.batch();
      for (int i = 0; i < parsedQuestions.length; i++) {
        final pq = parsedQuestions[i];
        final newAnswerNumber = existingAnswersCount + i + 1;
        final newAnswerDocRef = answersCollection.doc();
        batch.set(newAnswerDocRef, {
          'questionNumber': newAnswerNumber,
          'questionText': pq.question,
          'studentAnswer': pq.answer,
          'mark': null,
        });
      }
      await batch.commit();

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Successfully added ${parsedQuestions.length} answers!')));
        setState(() { _combinedDataFuture = _loadCombinedData(); });
      }
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Failed: $e'), backgroundColor: Colors.red));
    } finally {
      if (mounted) setState(() => _isProcessing = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      endDrawer: CustomDrawer(onClose: () => Navigator.pop(context)),
      appBar: AppBar(
        backgroundColor: Colors.white, elevation: 0,
        title: Image.asset('assets/images/logo_text.png', height: 40),
        centerTitle: true,
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
                icon: _isProcessing ? Container(width: 20, height: 20, margin: const EdgeInsets.only(right: 8), child: const CircularProgressIndicator(color: Colors.white, strokeWidth: 2)) : const Icon(Icons.add_a_photo_outlined, color: Colors.white,),
                label: Text(_isProcessing ? 'Processing...' : 'Add Answer Sheet'),
              ),
            ),
            const SizedBox(height: 16),
            const Divider(),
            Expanded(
              child: FutureBuilder<List<_CombinedAnswerData>>(
                future: _combinedDataFuture,
                builder: (context, snapshot) {
                  if (snapshot.connectionState == ConnectionState.waiting) return const Center(child: CircularProgressIndicator());
                  if (snapshot.hasError) return Center(child: Text("Error: ${snapshot.error}"));
                  if (!snapshot.hasData || snapshot.data!.isEmpty) return const Center(
                    child: Text("No answers found for this student.", textAlign: TextAlign.center, style: TextStyle(fontSize: 16, color: Colors.grey)),
                  );

                  final answerDataList = snapshot.data!;
                  final double totalScaledScore = answerDataList.fold(0.0, (sum, item) => sum + item.scaledMark);
                  final double totalMaxGrade = answerDataList.fold(0.0, (sum, item) => sum + item.maxGrade);

                  return Column(
                    children: [
                      Padding(
                        padding: const EdgeInsets.symmetric(vertical: 8.0),
                        child: Text(
                          'Total Mark: ${totalScaledScore.toStringAsFixed(1)} / ${totalMaxGrade.toStringAsFixed(1)}',
                          style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold, color: Colors.teal),
                        ),
                      ),
                      Expanded(
                        child: ListView.builder(
                          padding: const EdgeInsets.only(top: 8),
                          itemCount: answerDataList.length,
                          itemBuilder: (context, index) {
                            final data = answerDataList[index];
                            return _QaDisplayCard(question: data.questionText, answer: data.studentAnswer, mark: data.scaledMark, maxGrade: data.maxGrade);
                          },
                        ),
                      ),
                    ],
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

class _QaDisplayCard extends StatelessWidget {
  final String question;
  final String answer;
  final num? mark;
  final num? maxGrade;
  const _QaDisplayCard({required this.question, required this.answer, this.mark, this.maxGrade});

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
                    child: Text(question, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16, color: Color(0xFF1A237E)))),
                if (mark != null) ...[
                  const SizedBox(width: 16),
                  Text(
                    '${mark!.toStringAsFixed(1)} / ${maxGrade?.toStringAsFixed(1) ?? '10'}',
                    style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 18, color: Colors.teal),
                  ),
                ],
              ],
            ),
            const SizedBox(height: 8),
            const Divider(),
            const SizedBox(height: 8),
            Text(answer.isNotEmpty ? answer : "(No answer was provided)", style: TextStyle(fontSize: 15, color: Colors.grey[800], fontStyle: FontStyle.italic)),
          ],
        ),
      ),
    );
  }
}