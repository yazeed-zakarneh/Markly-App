import 'dart:math' as math;
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import '../dialogs/add_student_dialog.dart';
import '../models/student_model.dart';
import '../screens/student_screen.dart';
import '../models/grading_model.dart';

class _StudentScoreData {
  final Student student;
  final double finalScaledMark;
  final double examMaxGrade;

  _StudentScoreData({
    required this.student,
    required this.finalScaledMark,
    required this.examMaxGrade,
  });
}

class StudentsTab extends StatefulWidget {
  final String classId;
  final String examId;
  const StudentsTab({super.key, required this.classId, required this.examId});

  @override
  State<StudentsTab> createState() => _StudentsTabState();
}

class _StudentsTabState extends State<StudentsTab> {
  String _searchQuery = '';
  final _searchController = TextEditingController();

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  final String userId = FirebaseAuth.instance.currentUser!.uid;
  final GradingService _gradingService = GradingService();
  bool _isGrading = false;

  Future<void> _gradeAllStudents() async {
    setState(() => _isGrading = true);
    showDialog(context: context, barrierDismissible: false, builder: (_) => const AlertDialog(
        content: Row(children: [CircularProgressIndicator(), SizedBox(width: 20), Text("Grading & calculating...")]))
    );

    try {
      final examRef = FirebaseFirestore.instance.collection('users').doc(userId).collection('classes').doc(widget.classId).collection('exams').doc(widget.examId);
      final examDoc = await examRef.get();
      if (!examDoc.exists) throw Exception("Exam not found");

      // ⬇️ UPDATE: Read from the new 'scaleMaxGrade' field for calculations
      final double examMaxGradeForScaling = (examDoc.data()!['scaleMaxGrade'] as num).toDouble();

      final questionsRef = examRef.collection('questions').orderBy('questionNumber');
      final questionDocs = (await questionsRef.get()).docs;

      final studentsRef = examRef.collection('students');
      final studentDocs = (await studentsRef.get()).docs;

      if (questionDocs.isEmpty || studentDocs.isEmpty) throw Exception("Missing questions or students to grade.");

      // --- Part 1: Grade all answers ---
      final batch = FirebaseFirestore.instance.batch();
      for (final studentDoc in studentDocs) {
        final studentAnswersSnapshot = await studentDoc.reference.collection('answers').orderBy('questionNumber').get();
        final studentAnswerDocs = studentAnswersSnapshot.docs;
        if (studentAnswerDocs.isEmpty) continue;
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
          } catch (e) { print("Error grading Q${i+1} for ${studentDoc.data()['name']}: $e"); }
        }
      }
      await batch.commit();

      // --- Part 2: Calculate and update Min, Max, and Avg ---
      double questionsRawTotal = 0.0;
      for (final doc in questionDocs) {
        questionsRawTotal += double.tryParse(doc.data()['text2'] ?? '10.0') ?? 10.0;
      }
      if (questionsRawTotal == 0) questionsRawTotal = 1.0;

      List<double> finalScores = [];
      final updatedStudentDocs = (await studentsRef.get()).docs;

      for (final studentDoc in updatedStudentDocs) {
        double studentRawScore = 0.0;
        final answersSnapshot = await studentDoc.reference.collection('answers').get();
        for (final answerDoc in answersSnapshot.docs) {
          studentRawScore += (answerDoc.data()['mark'] as num?)?.toDouble() ?? 0.0;
        }
        final finalScaledMark = (studentRawScore / questionsRawTotal) * examMaxGradeForScaling;
        finalScores.add(finalScaledMark);
      }

      if (finalScores.isNotEmpty) {
        final double maxScore = finalScores.reduce(math.max);
        final double minScore = finalScores.reduce(math.min);
        final double avgScore = finalScores.reduce((a, b) => a + b) / finalScores.length;

        // ⬇️ UPDATE: Write the calculated results to the display fields ('min', 'max', 'avg')
        await examRef.update({
          'min': minScore,
          'max': maxScore,
          'avg': avgScore,
        });
      }

      Navigator.pop(context);
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Grading and calculations complete!')));
      setState(() {});

    } catch (e) {
      Navigator.pop(context);
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('A critical error occurred: $e'), backgroundColor: Colors.red));
    } finally {
      if(mounted) setState(() => _isGrading = false);
    }
  }

  Future<List<_StudentScoreData>> _calculateDisplayScores() async {
    final examDoc = await FirebaseFirestore.instance
        .collection('users').doc(userId)
        .collection('classes').doc(widget.classId)
        .collection('exams').doc(widget.examId)
        .get();

    if (!examDoc.exists) throw Exception("Exam document not found!");

    // ⬇️ UPDATE: Read from 'scaleMaxGrade' for displaying student scores correctly
    final double examMaxGradeForDisplay = (examDoc.data()!['scaleMaxGrade'] as num).toDouble();

    final questionsQuery = FirebaseFirestore.instance
        .collection('users').doc(userId).collection('classes')
        .doc(widget.classId).collection('exams').doc(widget.examId).collection('questions');
    final questionDocs = (await questionsQuery.get()).docs;

    double questionsRawTotal = 0.0;
    for (final doc in questionDocs) {
      questionsRawTotal += double.tryParse(doc.data()['text2'] ?? '10.0') ?? 10.0;
    }
    if (questionsRawTotal == 0) questionsRawTotal = 1.0;

    final studentsQuery = FirebaseFirestore.instance
        .collection('users').doc(userId).collection('classes')
        .doc(widget.classId).collection('exams').doc(widget.examId).collection('students').orderBy('name');
    final studentDocs = (await studentsQuery.get()).docs;

    final List<_StudentScoreData> results = [];

    for (final studentDoc in studentDocs) {
      double studentRawScore = 0.0;
      final answersQuery = studentDoc.reference.collection('answers');
      final answerDocs = (await answersQuery.get()).docs;

      for (final answerDoc in answerDocs) {
        studentRawScore += (answerDoc.data()['mark'] as num?)?.toDouble() ?? 0.0;
      }

      final double finalScaledMark = (studentRawScore / questionsRawTotal) * examMaxGradeForDisplay;

      results.add(_StudentScoreData(
        student: Student.fromMap(studentDoc.data(), studentDoc.id),
        finalScaledMark: finalScaledMark,
        examMaxGrade: examMaxGradeForDisplay,
      ));
    }
    return results;
  }


  Future<void> _deleteStudent(String studentId) async {
    final shouldDelete = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Delete Student',style: TextStyle(color: Color(0xFF1A237E)),),
        content: const Text(style: TextStyle(color: Colors.red),'Are you sure you want to delete this student and all their answers? You won\'t be able to restore them!'),
        actions: [
          OutlinedButton(
              style: OutlinedButton.styleFrom(
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.all(Radius.circular(10))),
                side: BorderSide(color: Color(0xFF1A237E)),
              ),
              onPressed: () => Navigator.pop(context, false),
              child: const Text('Cancel', style: TextStyle(color: Color(0xFF1A237E)))
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFF1A237E),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.all(Radius.circular(10))),
            ),
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Delete',style: TextStyle(color: Colors.white)),
          ),
        ],
      ),
    );

    if (shouldDelete == true) {
      await FirebaseFirestore.instance
          .collection('users').doc(userId).collection('classes')
          .doc(widget.classId).collection('exams').doc(widget.examId)
          .collection('students').doc(studentId).delete();

      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Student deleted.')));
      setState(() {});
    }
  }

  Future<void> _editStudent(Student student) async {
    await showDialog(
      context: context,
      builder: (_) => AddStudentDialog(
        userId: userId,
        classId: widget.classId,
        examId: widget.examId,
        existingStudent: student,
      ),
    );
    setState(() {});
  }

  void _showStudentContextMenu(BuildContext context, Offset position, Student student) async {
    final selected = await showMenu<String>(
      context: context,
      position: RelativeRect.fromLTRB(position.dx, position.dy, position.dx, position.dy),
      items: [
        const PopupMenuItem(
          value: 'edit',
          child: Text('Edit Info'),
        ),
        const PopupMenuItem(
          value: 'delete',
          child: Text('Delete', style: TextStyle(color: Colors.red)),
        ),
      ],
    );

    if (selected == 'edit') {
      _editStudent(student);
    } else if (selected == 'delete') {
      _deleteStudent(student.id);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(
        title: ElevatedButton.icon(
          style: ElevatedButton.styleFrom(
            backgroundColor: const Color(0xFF1A237E),
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.all(Radius.circular(10))),
          ),
          onPressed: _isGrading ? null : _gradeAllStudents,
          icon: Icon(Icons.check_circle_outline, color: _isGrading ? Colors.grey : Colors.white),
          label: const Text("Start grading", style: TextStyle(color: Colors.white),),
        ),
        centerTitle: true,
        automaticallyImplyLeading: false,
        backgroundColor: Colors.white,
        elevation: 0,
      ),
      floatingActionButton: FloatingActionButton(
        backgroundColor: const Color(0xFF1A237E),
        onPressed: () async {
          await showDialog(context: context, builder: (_) => AddStudentDialog(userId: userId, classId: widget.classId, examId: widget.examId));
          setState(() {});
        },
        child: const Icon(Icons.add, color: Colors.white),
      ),
      body: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16.0),
        child: Column(
          children: [
            Container(
              margin: const EdgeInsets.only(top: 8),
              padding: const EdgeInsets.symmetric(horizontal: 16),
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(30),
                color: Colors.grey[200],
              ),
              child: TextField(
                controller: _searchController,
                onChanged: (value) {
                  setState(() {
                    _searchQuery = value.toLowerCase();
                  });
                },
                decoration: InputDecoration(
                  hintText: "Search students...",
                  border: InputBorder.none,
                  icon: const Icon(Icons.search),
                  suffixIcon: _searchQuery.isNotEmpty
                      ? IconButton(
                    icon: const Icon(Icons.clear),
                    onPressed: () {
                      _searchController.clear();
                      setState(() { _searchQuery = ''; });
                    },
                  )
                      : null,
                ),
              ),
            ),
            const SizedBox(height: 20),
            Expanded(
              child: FutureBuilder<List<_StudentScoreData>>(
                future: _calculateDisplayScores(),
                builder: (context, snapshot) {
                  if (snapshot.connectionState == ConnectionState.waiting) return const Center(child: CircularProgressIndicator());
                  if (snapshot.hasError) return Center(child: Text('Error: ${snapshot.error}'));
                  if (!snapshot.hasData || snapshot.data!.isEmpty) return const Center(child: Text('No students found.', style: TextStyle(fontSize: 16, color: Colors.grey)));

                  final allStudentScores = snapshot.data!;

                  // Filtering logic
                  final filteredStudentScores = allStudentScores.where((scoreData) {
                    final studentName = scoreData.student.name.toLowerCase();
                    final studentId = scoreData.student.studentId;
                    return studentName.contains(_searchQuery) || studentId.contains(_searchQuery);
                  }).toList();

                  if (filteredStudentScores.isEmpty) {
                    return const Center(child: Text("No matching students found."));
                  }

                  // ListView with filtered data
                  return ListView.builder(
                    padding: const EdgeInsets.only(bottom: 80),
                    itemCount: filteredStudentScores.length,
                    itemBuilder: (context, index) {
                      final scoreData = filteredStudentScores[index];
                      final student = scoreData.student;

                      return GestureDetector(
                        onTap: () => Navigator.push(
                            context,
                            MaterialPageRoute(builder: (_) => StudentScreen(
                              student: student,
                              classId: widget.classId,
                              examId: widget.examId,
                            ))
                        ).then((_) => setState(() {})),
                        onLongPressStart: (details) {
                          _showStudentContextMenu(context, details.globalPosition, student);
                        },
                        child: Card(
                          elevation: 2,
                          // Use horizontal: 0 to align with home screen cards
                          margin: const EdgeInsets.symmetric(vertical: 6, horizontal: 0),
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                          child: ListTile(
                            leading: CircleAvatar(backgroundColor: const Color(0xFF1A237E), child: Text(student.name.substring(0, 1), style: const TextStyle(color: Colors.white))),
                            title: Text(student.name, style: const TextStyle(fontWeight: FontWeight.bold)),
                            subtitle: Text('ID: ${student.studentId}'),
                            trailing: Text(
                              '${scoreData.finalScaledMark.toStringAsFixed(1)} / ${scoreData.examMaxGrade.toStringAsFixed(1)}',
                              style: const TextStyle(
                                  color: Color(0xFF1A237E),
                                  fontWeight: FontWeight.bold,
                                  fontSize: 15
                              ),
                            ),
                          ),
                        ),
                      );
                    },
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }
}