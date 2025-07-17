import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import '../dialogs/add_student_dialog.dart';
import '../models/ocr_model.dart';
import '../models/student_model.dart';
import '../screens/student_screen.dart';
import '../models/grading_model.dart';

class StudentsTab extends StatefulWidget {
  final String classId;
  final String examId;
  const StudentsTab({super.key, required this.classId, required this.examId});

  @override
  State<StudentsTab> createState() => _StudentsTabState();
}

class _StudentsTabState extends State<StudentsTab> {
  final String userId = FirebaseAuth.instance.currentUser!.uid;
  final OcrService _ocrService = OcrService();
  final GradingService _gradingService = GradingService();
  bool _isGrading = false;



  // In tabs/students_tab.dart

  // In tabs/students_tab.dart

  Future<void> _gradeAllStudents() async {
    setState(() => _isGrading = true);

    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => const AlertDialog(
        content: Row(children: [CircularProgressIndicator(), SizedBox(width: 20), Text("Grading all students...")]),
      ),
    );

    try {
      // 1. Fetch all data, ensuring it's ordered correctly
      final questionsRef = FirebaseFirestore.instance.collection('users').doc(userId).collection('classes').doc(widget.classId).collection('exams').doc(widget.examId).collection('questions').orderBy('questionNumber');
      final studentsRef = FirebaseFirestore.instance.collection('users').doc(userId).collection('classes').doc(widget.classId).collection('exams').doc(widget.examId).collection('students');
      final results = await Future.wait([questionsRef.get(), studentsRef.get()]);
      final questionDocs = results[0].docs;
      final studentDocs = results[1].docs;

      if (questionDocs.isEmpty) throw Exception("No questions with key answers found.");
      if (studentDocs.isEmpty) throw Exception("No students to grade.");

      // --- NEW LOGIC: Prepare an ordered list of key questions and answers ---
      final List<ParsedQuestion> keyQuestionsAndAnswers = questionDocs.map((doc) {
        final data = doc.data();
        return ParsedQuestion(question: data['fullQuestion'], answer: data['text1']);
      }).toList();
      // --- END OF NEW LOGIC ---

      // 3. Process each student
      final batch = FirebaseFirestore.instance.batch();
      for (final studentDoc in studentDocs) {
        double totalMark = 0.0;
        final Map<String, double> gradedMarks = {};

        final studentData = studentDoc.data();
        final answerSheets = (studentData['answerSheets'] as List? ?? []).map((s) => AnswerSheet.fromMap(Map<String, dynamic>.from(s))).toList();

        // Get the student's answers in a correctly ordered list
        final studentAnswers = answerSheets
            .expand((sheet) => _ocrService.extractQuestionsFromText(sheet.ocrText))
            .toList();

        // --- NEW LOGIC: Loop by index, not by text matching ---
        // We find the smaller of the two list lengths to avoid errors
        final int loopCount = keyQuestionsAndAnswers.length < studentAnswers.length
            ? keyQuestionsAndAnswers.length
            : studentAnswers.length;

        print("👤 Grading Student: ${studentData['name']}. Found ${keyQuestionsAndAnswers.length} key answers and ${studentAnswers.length} student answers. Will grade $loopCount pairs.");

        for (int i = 0; i < loopCount; i++) {
          final keyQA = keyQuestionsAndAnswers[i];
          final studentQA = studentAnswers[i];

          // Use a try-catch for each API call for resilience
          try {
            final mark = await _gradingService.gradeAnswer(
              question: keyQA.question,       // Key Question
              keyAnswer: keyQA.answer,         // Key Answer
              studentAnswer: studentQA.answer, // Student's Answer
            );
            totalMark += mark;
            // We still use the full question text as the key for the marks map
            gradedMarks[keyQA.question] = mark;
            print("  ✅ Graded Q${i+1}: Mark = $mark");
          } catch (e) {
            print("  ❌ Failed to grade Q${i+1}. Error: $e");
          }
        }
        // --- END OF NEW LOGIC ---

        batch.update(studentDoc.reference, {
          'totalMark': totalMark,
          'gradedMarks': gradedMarks,
        });
      }

      // 4. Commit all updates at once
      await batch.commit();

      Navigator.pop(context); // Close loading dialog
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Grading complete! Check logs for any errors.')));

    } catch (e) {
      Navigator.pop(context);
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('A critical error occurred: $e'), backgroundColor: Colors.red));
    } finally {
      setState(() => _isGrading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(
        title: const Text('Students', style: TextStyle(color: Color(0xFF1A237E))),
        backgroundColor: Colors.white,
        elevation: 0,
        actions: [
          Padding(
            padding: const EdgeInsets.only(right: 8.0),
            child: IconButton(
              icon: Icon(Icons.auto_awesome, color: _isGrading ? Colors.grey : const Color(0xFF1A237E)),
              tooltip: 'Grade All Students',
              onPressed: _isGrading ? null : _gradeAllStudents,
            ),
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton(
        backgroundColor: const Color(0xFF1A237E),
        onPressed: () => showDialog(context: context, builder: (_) => AddStudentDialog(userId: userId, classId: widget.classId, examId: widget.examId)),
        child: const Icon(Icons.add, color: Colors.white),
      ),
      body: StreamBuilder<QuerySnapshot>(
        stream: FirebaseFirestore.instance.collection('users').doc(userId).collection('classes').doc(widget.classId).collection('exams').doc(widget.examId).collection('students').orderBy('name').snapshots(),
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) return const Center(child: CircularProgressIndicator());
          if (snapshot.hasError) return Center(child: Text('Error: ${snapshot.error}'));
          if (!snapshot.hasData || snapshot.data!.docs.isEmpty) return const Center(child: Text('No students found. Add one to get started.', style: TextStyle(fontSize: 16, color: Colors.grey)));
          final students = snapshot.data!.docs.map((doc) => Student.fromMap(doc.data() as Map<String, dynamic>, doc.id)).toList();
          return ListView.builder(
            padding: const EdgeInsets.all(8.0).copyWith(bottom: 80),
            itemCount: students.length,
            itemBuilder: (context, index) {
              final student = students[index];
              final studentData = snapshot.data!.docs[index].data() as Map<String, dynamic>;
              final totalMark = studentData['totalMark'] as num?;
              return Card(
                elevation: 2,
                margin: const EdgeInsets.symmetric(vertical: 8, horizontal: 8),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                child: ListTile(
                  leading: CircleAvatar(backgroundColor: const Color(0xFF1A237E), child: Text(student.name.substring(0, 1), style: const TextStyle(color: Colors.white))),
                  title: Text(student.name, style: const TextStyle(fontWeight: FontWeight.bold)),
                  subtitle: Text('ID: ${student.studentId}'),
                  trailing: totalMark != null ? Text('Mark: ${totalMark.toStringAsFixed(1)}', style: const TextStyle(color: Colors.teal, fontWeight: FontWeight.bold, fontSize: 15)) : const Icon(Icons.pending_outlined, color: Colors.grey, size: 20),
                  onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => StudentScreen(student: student, classId: widget.classId, examId: widget.examId))),
                ),
              );
            },
          );
        },
      ),
    );
  }
}

class AnswerSheet {
  final String imageUrl;
  final String ocrText;
  AnswerSheet({required this.imageUrl, required this.ocrText});
  factory AnswerSheet.fromMap(Map<String, dynamic> map) {
    return AnswerSheet(imageUrl: map['imageUrl'] as String, ocrText: map['ocrText'] as String? ?? '');
  }
}