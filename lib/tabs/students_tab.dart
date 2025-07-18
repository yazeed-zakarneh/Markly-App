import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import '../dialogs/add_student_dialog.dart';
import '../models/student_model.dart';
import '../screens/student_screen.dart';
import '../models/grading_model.dart';

// Helper class to hold the dynamically calculated data
class _StudentScoreData {
  final Student student;
  final double totalScaledMark;
  final double totalMaxGrade;
  _StudentScoreData({ required this.student, required this.totalScaledMark, required this.totalMaxGrade });
}

class StudentsTab extends StatefulWidget {
  final String classId;
  final String examId;
  const StudentsTab({super.key, required this.classId, required this.examId});

  @override
  State<StudentsTab> createState() => _StudentsTabState();
}

class _StudentsTabState extends State<StudentsTab> {
  final String userId = FirebaseAuth.instance.currentUser!.uid;
  final GradingService _gradingService = GradingService();
  bool _isGrading = false;

  // This is the function that does the API call and saves the RAW score
  Future<void> _gradeAllStudents() async {
    setState(() => _isGrading = true);
    showDialog(context: context, barrierDismissible: false, builder: (_) => const AlertDialog(
        content: Row(children: [CircularProgressIndicator(), SizedBox(width: 20), Text("Grading all students...")]))
    );

    try {
      final questionsRef = FirebaseFirestore.instance.collection('users').doc(userId).collection('classes').doc(widget.classId).collection('exams').doc(widget.examId).collection('questions').orderBy('questionNumber');
      final questionDocs = (await questionsRef.get()).docs;

      final studentsRef = FirebaseFirestore.instance.collection('users').doc(userId).collection('classes').doc(widget.classId).collection('exams').doc(widget.examId).collection('students');
      final studentDocs = (await studentsRef.get()).docs;

      if (questionDocs.isEmpty || studentDocs.isEmpty) throw Exception("Missing questions or students to grade.");

      final batch = FirebaseFirestore.instance.batch();

      for (final studentDoc in studentDocs) {
        final studentAnswersSnapshot = await studentDoc.reference.collection('answers').orderBy('questionNumber').get();
        final studentAnswerDocs = studentAnswersSnapshot.docs;

        if (studentAnswerDocs.isEmpty) {
          print("Skipping ${studentDoc.data()['name']}: No answers found.");
          continue;
        }

        final int loopCount = questionDocs.length < studentAnswerDocs.length ? questionDocs.length : studentAnswerDocs.length;

        for (int i = 0; i < loopCount; i++) {
          final questionData = questionDocs[i].data();
          final studentAnswerDoc = studentAnswerDocs[i];

          try {
            final double baseMark = await _gradingService.gradeAnswer(
              question: questionData['fullQuestion'],
              keyAnswer: questionData['text1'],
              studentAnswer: studentAnswerDoc.data()['studentAnswer'],
            );
            batch.update(studentAnswerDoc.reference, {'mark': baseMark});
          } catch (e) {
            print("Error grading Q${i+1} for ${studentDoc.data()['name']}: $e");
          }
        }
      }

      await batch.commit();
      Navigator.pop(context);
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Grading complete!')));

      setState(() {});

    } catch (e) {
      Navigator.pop(context);
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('A critical error occurred: $e'), backgroundColor: Colors.red));
    } finally {
      if(mounted) setState(() => _isGrading = false);
    }
  }

  // This function dynamically calculates scores for display, without calling the API
  Future<List<_StudentScoreData>> _calculateDisplayScores() async {
    final questionsQuery = FirebaseFirestore.instance.collection('users').doc(userId).collection('classes').doc(widget.classId).collection('exams').doc(widget.examId).collection('questions').orderBy('questionNumber');
    final questionDocs = (await questionsQuery.get()).docs;

    double totalMaxGrade = 0.0;
    for (final doc in questionDocs) {
      totalMaxGrade += double.tryParse(doc.data()['text2'] ?? '10.0') ?? 10.0;
    }

    final studentsQuery = FirebaseFirestore.instance.collection('users').doc(userId).collection('classes').doc(widget.classId).collection('exams').doc(widget.examId).collection('students').orderBy('name');
    final studentDocs = (await studentsQuery.get()).docs;

    final List<_StudentScoreData> results = [];

    for (final studentDoc in studentDocs) {
      double studentTotalScaledMark = 0.0;
      final answersQuery = studentDoc.reference.collection('answers').orderBy('questionNumber');
      final answerDocs = (await answersQuery.get()).docs;

      final int loopCount = questionDocs.length < answerDocs.length ? questionDocs.length : answerDocs.length;

      for (int i = 0; i < loopCount; i++) {
        final questionData = questionDocs[i].data();
        final answerData = answerDocs[i].data();
        final double baseMark = (answerData['mark'] as num?)?.toDouble() ?? 0.0;
        final double maxGradeForQuestion = double.tryParse(questionData['text2'] ?? '10.0') ?? 10.0;
        studentTotalScaledMark += (baseMark * maxGradeForQuestion) / 10.0;
      }

      results.add(_StudentScoreData(
        student: Student.fromMap(studentDoc.data() as Map<String, dynamic>, studentDoc.id),
        totalScaledMark: studentTotalScaledMark,
        totalMaxGrade: totalMaxGrade,
      ));
    }
    return results;
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(
        automaticallyImplyLeading: false,
        title: const Text('Students', style: TextStyle(color: Color(0xFF1A237E))),
        backgroundColor: Colors.white,
        elevation: 0,
        actions: [
          Padding(
            padding: const EdgeInsets.only(right: 8.0),
            child: IconButton(
              icon: Icon(Icons.auto_awesome, color: _isGrading ? Colors.grey : const Color(0xFF1A237E)),
              tooltip: 'Grade All Students (Calls API)',
              onPressed: _isGrading ? null : _gradeAllStudents,
            ),
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton(
        backgroundColor: const Color(0xFF1A237E),
        onPressed: () async {
          await showDialog(context: context, builder: (_) => AddStudentDialog(userId: userId, classId: widget.classId, examId: widget.examId));
          setState(() {});
        },
        child: const Icon(Icons.add, color: Colors.white),
      ),
      body: FutureBuilder<List<_StudentScoreData>>(
        future: _calculateDisplayScores(),
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) return const Center(child: CircularProgressIndicator());
          if (snapshot.hasError) return Center(child: Text('Error: ${snapshot.error}'));
          if (!snapshot.hasData || snapshot.data!.isEmpty) return const Center(child: Text('No students found.', style: TextStyle(fontSize: 16, color: Colors.grey)));

          final studentScores = snapshot.data!;

          return ListView.builder(
            padding: const EdgeInsets.all(8.0).copyWith(bottom: 80),
            itemCount: studentScores.length,
            itemBuilder: (context, index) {
              final scoreData = studentScores[index];
              return Card(
                elevation: 2,
                margin: const EdgeInsets.symmetric(vertical: 8, horizontal: 8),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                child: ListTile(
                  leading: CircleAvatar(backgroundColor: const Color(0xFF1A237E), child: Text(scoreData.student.name.substring(0, 1), style: const TextStyle(color: Colors.white))),
                  title: Text(scoreData.student.name, style: const TextStyle(fontWeight: FontWeight.bold)),
                  subtitle: Text('ID: ${scoreData.student.studentId}'),
                  trailing: Text(
                      '${scoreData.totalScaledMark.toStringAsFixed(1)} / ${scoreData.totalMaxGrade.toStringAsFixed(1)}',
                      style: const TextStyle(color: Colors.teal, fontWeight: FontWeight.bold, fontSize: 15)
                  ),
                  onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => StudentScreen(student: scoreData.student, classId: widget.classId, examId: widget.examId)))
                      .then((_) => setState(() {})), // Refresh when returning from detail screen
                ),
              );
            },
          );
        },
      ),
    );
  }
}