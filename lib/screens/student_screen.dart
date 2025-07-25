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
  final String answerId;
  final int questionNumber;
  final String questionText;
  final String studentAnswer;
  final double baseMark;
  final double maxGrade;
  _CombinedAnswerData({
    required this.answerId,
    required this.questionText,
    required this.studentAnswer,
    required this.baseMark,
    required this.maxGrade,
    required this.questionNumber,
  });
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
    // Queries remain the same
    final questionsQuery = FirebaseFirestore.instance.collection('users').doc(userId).collection('classes').doc(widget.classId).collection('exams').doc(widget.examId).collection('questions');
    final answersQuery = FirebaseFirestore.instance.collection('users').doc(userId).collection('classes').doc(widget.classId).collection('exams').doc(widget.examId).collection('students').doc(widget.student.id).collection('answers');

    final results = await Future.wait([questionsQuery.get(), answersQuery.get()]);
    final questionDocs = results[0].docs;
    final answerDocs = results[1].docs;

    // Create a map for quick lookup of questions by their number
    final Map<int, DocumentSnapshot> questionMap = {
      for (var doc in questionDocs) (doc.data()['questionNumber'] as int): doc
    };

    final List<_CombinedAnswerData> combinedList = [];
    for (final answerDoc in answerDocs) {
      final answerData = answerDoc.data() as Map<String, dynamic>;
      // Get the question number directly from the answer document
      final int? questionNum = answerData['questionNumber'];

      if (questionNum != null && questionMap.containsKey(questionNum)) {
        final questionData = questionMap[questionNum]!.data() as Map<String, dynamic>;
        final double maxGrade = double.tryParse(questionData['text2'] ?? '10.0') ?? 10.0;
        final double baseMark = (answerData['mark'] as num?)?.toDouble() ?? 0.0;

        combinedList.add(_CombinedAnswerData(
          answerId: answerDoc.id,
          questionNumber: questionNum, // <-- PASS THE RELIABLE NUMBER HERE
          questionText: '${questionData['fullQuestion']}',
          studentAnswer: answerData['studentAnswer'] ?? '',
          baseMark: baseMark,
          maxGrade: maxGrade,
        ));
      }
    }

    // --- THIS IS THE CORRECTED SORTING LOGIC ---
    // Sort the list based on the reliable `questionNumber` field.
    combinedList.sort((a, b) => a.questionNumber.compareTo(b.questionNumber));

    return combinedList;
  }

  void _showAddAnswerSheetDialog() {
    if (_isProcessing) return;
    setState(() => _isProcessing = true);

    bool isDialogLoading = false;
    String statusMessage = "Upload a student's answer sheet.";
    bool isMultipleChoice = false;

    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setDialogState) {
            Future<void> processSheet() async {
              final picker = ImagePicker();
              final pickedFile = await picker.pickImage(source: ImageSource.gallery, maxWidth: 1800, imageQuality: 85);
              if (pickedFile == null) return;

              setDialogState(() { isDialogLoading = true; statusMessage = 'Processing image with OCR...'; });

              try {
                final rawText = await _ocrService.performOcr(File(pickedFile.path));
                if (rawText == null) throw Exception("OCR failed to extract text.");

                final answersCollection = FirebaseFirestore.instance.collection('users').doc(userId).collection('classes').doc(widget.classId).collection('exams').doc(widget.examId).collection('students').doc(widget.student.id).collection('answers');
                final batch = FirebaseFirestore.instance.batch();

                if (isMultipleChoice) {
                  setDialogState(() => statusMessage = 'Processing multiple-choice answers...');

                  // --- ADDED: Print raw student text before local cleanup ---
                  print("--- [Student Answer] Raw MCQ Text (Before Cleanup) ---\n$rawText\n------------------------------------------------------");
                  final cleanedMcqString = _ocrService.processRawMultipleChoiceText(rawText);

                  // --- ADDED: Print cleaned student text after local cleanup ---
                  print("--- [Student Answer] Cleaned MCQ Text (After Cleanup) ---\n$cleanedMcqString\n-----------------------------------------------------");

                  if (cleanedMcqString.isEmpty) throw Exception("No multiple-choice answers could be processed from the sheet.");

                  final questionsCollection = FirebaseFirestore.instance.collection('users').doc(userId).collection('classes').doc(widget.classId).collection('exams').doc(widget.examId).collection('questions');
                  final mcqQuery = await questionsCollection.where('isMultipleChoice', isEqualTo: true).limit(1).get();
                  if (mcqQuery.docs.isEmpty) throw Exception("The MCQ answer key has not been added. Please add it in the Questions tab first.");

                  final questionKeyDoc = mcqQuery.docs.first;
                  final int targetQuestionNumber = questionKeyDoc.data()['questionNumber'];
                  final newAnswerDocRef = answersCollection.doc();
                  batch.set(newAnswerDocRef, {'questionNumber': targetQuestionNumber, 'questionText': "Multiple Choice Question", 'studentAnswer': cleanedMcqString, 'mark': null});

                } else {
                  setDialogState(() => statusMessage = 'Enhancing extracted text...');
                  print("--- [Student Answer] Raw Text (Before API) ---\n$rawText\n--------------------------------------------");
                  final enhancedText = await _ocrService.enhanceOcrText(rawText);
                  print("--- [Student Answer] Enhanced Text (After API) ---\n$enhancedText\n----------------------------------------------");

                  final List<ParsedQuestion> parsedAnswers = _ocrService.extractQuestionsFromText(enhancedText);
                  if (parsedAnswers.isEmpty) throw Exception("No answers could be parsed from the sheet.");

                  final existingAnswersCount = (await answersCollection.get()).size;
                  for (int i = 0; i < parsedAnswers.length; i++) {
                    final pa = parsedAnswers[i];
                    final newAnswerNumber = existingAnswersCount + i + 1;
                    final newAnswerDocRef = answersCollection.doc();
                    batch.set(newAnswerDocRef, {'questionNumber': newAnswerNumber, 'questionText': pa.question, 'studentAnswer': pa.answer, 'mark': null});
                  }
                }

                setDialogState(() => statusMessage = 'Saving answers...');
                await batch.commit();
                Navigator.pop(context);
                if (mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Answers added successfully!')));
                  setState(() => _combinedDataFuture = _loadCombinedData());
                }
              } catch (e) {
                setDialogState(() { isDialogLoading = false; statusMessage = 'Error: $e'; });
              }
            }

            return AlertDialog(
              title: const Text("Add Answer Sheet", style: TextStyle(color: Color(0xFF1A237E))),
              content: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(statusMessage, textAlign: TextAlign.center),
                  if (!isDialogLoading)
                    Padding(
                      padding: const EdgeInsets.only(top: 16.0),
                      child: CheckboxListTile(
                        title: const Text("Multiple choice question", style: TextStyle(fontSize: 14),),
                        value: isMultipleChoice,
                        onChanged: (bool? value) => setDialogState(() => isMultipleChoice = value ?? false),
                        controlAffinity: ListTileControlAffinity.leading,
                        contentPadding: EdgeInsets.zero,
                        activeColor: const Color(0xFF1A237E),
                      ),
                    ),
                  if (isDialogLoading)
                    const Padding(
                      padding: EdgeInsets.only(top: 20),
                      child: CircularProgressIndicator(),
                    ),
                ],
              ),
              actions: [
                OutlinedButton(
                  style: OutlinedButton.styleFrom(shape: const RoundedRectangleBorder(borderRadius: BorderRadius.all(Radius.circular(10))), side: const BorderSide(color: Color(0xFF1A237E))),
                  onPressed: isDialogLoading ? null : () => Navigator.pop(context),
                  child: const Text("Cancel", style: TextStyle(color: Color(0xFF1A237E))),
                ),
                ElevatedButton.icon(
                  style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFF1A237E), shape: const RoundedRectangleBorder(borderRadius: BorderRadius.all(Radius.circular(10)))),
                  onPressed: isDialogLoading ? null : processSheet,
                  icon: const Icon(Icons.upload_file, color: Colors.white),
                  label: const Text("Upload", style: TextStyle(color: Colors.white)),
                ),
              ],
            );
          },
        );
      },
    ).whenComplete(() => { if (mounted) setState(() => _isProcessing = false) });
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
            const SizedBox(height: 8),
            Center(
              child: ElevatedButton.icon(
                style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFF1A237E), foregroundColor: Colors.white, padding: const EdgeInsets.all(12), shape: const RoundedRectangleBorder(borderRadius: BorderRadius.all(Radius.circular(10)))),
                onPressed: _isProcessing ? null : _showAddAnswerSheetDialog,
                icon: _isProcessing ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2)) : const Icon(Icons.add_a_photo_outlined, color: Colors.white,),
                label: Text(_isProcessing ? 'Processing...' : 'Add Answer Sheet', style: const TextStyle(fontSize: 15),),
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
                  if (!snapshot.hasData || snapshot.data!.isEmpty) return const Center(child: Text("No answers found for this student.", textAlign: TextAlign.center, style: TextStyle(fontSize: 16, color: Colors.grey)));
                  final answerDataList = (snapshot.data!);
                  final double totalScaledScore = answerDataList.fold(0.0, (sum, item) => sum + item.scaledMark);
                  final double totalMaxGrade = answerDataList.fold(0.0, (sum, item) => sum + item.maxGrade);
                  return Column(
                    children: [
                      Padding(
                        padding: const EdgeInsets.symmetric(vertical: 8.0),
                        child: Text('Total Mark: ${totalScaledScore.toStringAsFixed(1)} / ${totalMaxGrade.toStringAsFixed(1)}', style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: Color(0xFF1A237E))),
                      ),
                      Expanded(
                        child: ListView.builder(
                          padding: const EdgeInsets.only(top: 8, bottom: 16),
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
    final cardSurfaceColor = Theme.of(context).colorScheme.surface;
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
                Expanded(child: Text(question, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16, color: Color(0xFF1A237E)))),
                if (mark != null) ...[
                  const SizedBox(width: 16),
                  Container(
                    padding: const EdgeInsets.symmetric(vertical: 5, horizontal: 8),
                    decoration: BoxDecoration(border: Border.all(color: const Color(0xFF1A237E)), borderRadius: BorderRadius.circular(10), color: const Color(0xFF1A237E)),
                    child: Text('${mark!.toStringAsFixed(1)} / ${maxGrade?.toStringAsFixed(1) ?? '10'}', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16, color: cardSurfaceColor)),
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