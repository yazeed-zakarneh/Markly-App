import 'dart:io';
import 'dart:math' as math;
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:excel/excel.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';
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
  final String className;
  final String examTitle;
  const StudentsTab({
    super.key,
    required this.classId,
    required this.examId,
    required this.className,
    required this.examTitle,
  });

  @override
  State<StudentsTab> createState() => _StudentsTabState();
}

class _StudentsTabState extends State<StudentsTab> {
  String _searchQuery = '';
  final _searchController = TextEditingController();
  final String userId = FirebaseAuth.instance.currentUser!.uid;
  final GradingService _gradingService = GradingService();
  bool _isGrading = false;
  bool _isMenuOpen = false;
  // --- New state for export process ---
  bool _isExporting = false;

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  Future<List<_StudentScoreData>> _calculateAllStudentScores() async {
    final examDoc = await FirebaseFirestore.instance.collection('users').doc(userId).collection('classes').doc(widget.classId).collection('exams').doc(widget.examId).get();
    if (!examDoc.exists) throw Exception("Exam document not found!");
    final double examMaxGradeForScaling = (examDoc.data()!['scaleMaxGrade'] as num).toDouble();
    final questionDocs = (await examDoc.reference.collection('questions').orderBy('questionNumber').get()).docs;
    final studentDocs = (await examDoc.reference.collection('students').orderBy('name').get()).docs;
    final Map<int, double> questionNumberToMaxGradeMap = {};
    double totalExamWeight = 0.0;
    for (final doc in questionDocs) {
      final data = doc.data();
      final int qNum = data['questionNumber'];
      final double grade = double.tryParse(data['text2'] ?? '0.0') ?? 0.0;
      questionNumberToMaxGradeMap[qNum] = grade;
      totalExamWeight += grade;
    }
    final List<_StudentScoreData> results = [];
    for (final studentDoc in studentDocs) {
      final answerDocs = (await studentDoc.reference.collection('answers').get()).docs;
      double studentTotalWeightedScore = 0.0;
      for (final answerDoc in answerDocs) {
        final answerData = answerDoc.data();
        final baseMark = (answerData['mark'] as num?)?.toDouble() ?? 0.0;
        final qNum = answerData['questionNumber'] as int;
        final double questionMaxGrade = questionNumberToMaxGradeMap[qNum] ?? 0.0;
        final double weightedMarkForQuestion = (baseMark / 10.0) * questionMaxGrade;
        studentTotalWeightedScore += weightedMarkForQuestion;
      }
      final double finalScaledMark = (totalExamWeight > 0) ? (studentTotalWeightedScore / totalExamWeight) * examMaxGradeForScaling : 0.0;
      results.add(_StudentScoreData(student: Student.fromMap(studentDoc.data(), studentDoc.id), finalScaledMark: finalScaledMark, examMaxGrade: examMaxGradeForScaling));
    }
    return results;
  }

  Future<void> _gradeAllStudents() async {
    setState(() => _isGrading = true);
    showDialog(context: context, barrierDismissible: false, builder: (_) => const AlertDialog(
        content: Row(children: [CircularProgressIndicator(), SizedBox(width: 20), Text("Grading & calculating...")]))
    );
    try {
      final examRef = FirebaseFirestore.instance.collection('users').doc(userId).collection('classes').doc(widget.classId).collection('exams').doc(widget.examId);
      final questionDocs = (await examRef.collection('questions').orderBy('questionNumber').get()).docs;
      final studentDocs = (await examRef.collection('students').get()).docs;
      if (questionDocs.isEmpty || studentDocs.isEmpty) throw Exception("Missing questions or students to grade.");

      final batch = FirebaseFirestore.instance.batch();
      for (final studentDoc in studentDocs) {
        final answersSnapshot = await studentDoc.reference.collection('answers').get();
        for (final studentAnswerDoc in answersSnapshot.docs) {
          final answerData = studentAnswerDoc.data();
          final int? questionNumber = answerData['questionNumber'];
          if (questionNumber == null) continue;
          final questionDocList = questionDocs.where((doc) => doc.data()['questionNumber'] == questionNumber).toList();
          if (questionDocList.isEmpty) continue;
          final questionData = questionDocList.first.data();
          try {
            final double baseMark = await _gradingService.gradeAnswer(
              question: questionData['fullQuestion'],
              keyAnswer: questionData['text1'],
              studentAnswer: answerData['studentAnswer'],
            );
            batch.update(studentAnswerDoc.reference, {'mark': baseMark});
          } catch (e) { print("Error grading Q$questionNumber for ${studentDoc.data()['name']}: $e"); }
        }
      }
      await batch.commit();

      final List<_StudentScoreData> finalScoresData = await _calculateAllStudentScores();
      if (finalScoresData.isNotEmpty) {
        final List<double> finalScores = finalScoresData.map((data) => data.finalScaledMark).toList();
        final double maxScore = finalScores.reduce(math.max);
        final double minScore = finalScores.reduce(math.min);
        final double avgScore = finalScores.reduce((a, b) => a + b) / finalScores.length;
        await examRef.update({'min': minScore, 'max': maxScore, 'avg': avgScore});
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

  Future<List<_StudentScoreData>> _calculateDisplayScores() {
    return _calculateAllStudentScores();
  }

  void _onAddButtonPressed() {
    setState(() => _isMenuOpen = false);
    showDialog(context: context, builder: (_) => AddStudentDialog(userId: userId, classId: widget.classId, examId: widget.examId)).then((_) => setState(() {}));
  }

  // --- New Export Function ---
  Future<void> _exportToExcel() async {
    if (_isExporting || _isGrading) return;
    setState(() { _isExporting = true; _isMenuOpen = false; });
    ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Generating Excel sheet...')));
    try {
      final studentScores = await _calculateAllStudentScores();
      if (studentScores.isEmpty) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('No student data to export.')));
        return;
      }
      final excel = Excel.createExcel();
      final String defaultSheetName = excel.sheets.keys.first;
      final Sheet sheetObject = excel[defaultSheetName];
      final headerRow = [ TextCellValue('Name'), TextCellValue('ID'),  TextCellValue('Mark')];
      sheetObject.appendRow(headerRow);
      for (final scoreData in studentScores) {
        final studentRow = [
          TextCellValue(scoreData.student.name),
          TextCellValue(scoreData.student.studentId),
          DoubleCellValue(double.parse(scoreData.finalScaledMark.toStringAsFixed(2))),
        ];
        sheetObject.appendRow(studentRow);
      }
      final directory = await getTemporaryDirectory();
      final sanitizedExamName = widget.examTitle.replaceAll(RegExp(r'[\\/:*?"<>|]'), '_');
      final sanitizedClassName = widget.className.replaceAll(RegExp(r'[\\/:*?"<>|]'), '_');
      final fileName = '$sanitizedExamName - $sanitizedClassName.xlsx';
      final path = '${directory.path}/$fileName';
      final fileBytes = excel.save();
      if (fileBytes != null) {
        final file = File(path)..writeAsBytesSync(fileBytes);
        await Share.shareXFiles([XFile(file.path)], text: 'Here are the exam grades.');
      } else {
        throw Exception("Failed to save Excel data.");
      }
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Error exporting data: $e'), backgroundColor: Colors.red));
    } finally {
      setState(() => _isExporting = false);
      ScaffoldMessenger.of(context).hideCurrentSnackBar();
    }
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

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Student deleted.')));
        setState(() {});
      }
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
    if (mounted) {
      setState(() {});
    }
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
          style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFF1A237E), shape: RoundedRectangleBorder(borderRadius: BorderRadius.all(Radius.circular(10)))),
          onPressed: _isGrading ? null : _gradeAllStudents,
          icon: Icon(Icons.check_circle_outline, color: _isGrading ? Colors.grey : Colors.white),
          label: const Text("Start grading", style: TextStyle(color: Colors.white)),
        ),
        centerTitle: true,
        automaticallyImplyLeading: false,
        backgroundColor: Colors.white,
        elevation: 0,
      ),
      body: Stack(
        children: [
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16.0),
            child: Column(
              children: [
                Container(
                  margin: const EdgeInsets.only(top: 8),
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  decoration: BoxDecoration(borderRadius: BorderRadius.circular(30), color: Colors.grey[200]),
                  child: TextField(
                    controller: _searchController,
                    onChanged: (value) => setState(() => _searchQuery = value.toLowerCase()),
                    decoration: InputDecoration(
                      hintText: "Search students...",
                      border: InputBorder.none,
                      icon: const Icon(Icons.search),
                      suffixIcon: _searchQuery.isNotEmpty ? IconButton(icon: const Icon(Icons.clear), onPressed: () {
                        _searchController.clear();
                        setState(() => _searchQuery = '');
                      }) : null,
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
                      final filteredStudentScores = allStudentScores.where((scoreData) {
                        final studentName = scoreData.student.name.toLowerCase();
                        final studentId = scoreData.student.studentId;
                        return studentName.contains(_searchQuery) || studentId.contains(_searchQuery);
                      }).toList();
                      if (filteredStudentScores.isEmpty) return const Center(child: Text("No matching students found."));
                      return ListView.builder(
                        padding: const EdgeInsets.only(bottom: 80),
                        itemCount: filteredStudentScores.length,
                        itemBuilder: (context, index) {
                          final scoreData = filteredStudentScores[index];
                          final student = scoreData.student;
                          return GestureDetector(
                            onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => StudentScreen(student: student, classId: widget.classId, examId: widget.examId))).then((_) => setState(() {})),
                            onLongPressStart: (details) => _showStudentContextMenu(context, details.globalPosition, student),
                            child: Card(
                              elevation: 2,
                              margin: const EdgeInsets.symmetric(vertical: 6, horizontal: 0),
                              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                              child: ListTile(
                                leading: CircleAvatar(backgroundColor: const Color(0xFF1A237E), child: Text(student.name.substring(0, 1), style: const TextStyle(color: Colors.white))),
                                title: Text(student.name, style: const TextStyle(fontWeight: FontWeight.bold)),
                                subtitle: Text('ID: ${student.studentId}'),
                                trailing: Text('${scoreData.finalScaledMark.toStringAsFixed(1)} / ${scoreData.examMaxGrade.toStringAsFixed(1)}', style: const TextStyle(color: Color(0xFF1A237E), fontWeight: FontWeight.bold, fontSize: 15)),
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
          Positioned(
            bottom: 20,
            right: 20,
            child: _buildFloatingMenu(),
          ),
        ],
      ),
    );
  }

  Widget _buildFloatingMenu() {
    final closedMenu = FloatingActionButton(
      onPressed: () => setState(() => _isMenuOpen = true),
      backgroundColor: const Color(0xFF1A237E),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      heroTag: 'menu_button',
      child: const Icon(Icons.more_horiz, color: Colors.white),
    );
    final openMenu = Container(
      padding: const EdgeInsets.symmetric(vertical: 8),
      decoration: BoxDecoration(color: const Color(0xFF1A237E), borderRadius: BorderRadius.circular(24), boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.2), spreadRadius: 2, blurRadius: 8)]),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          IconButton(
            tooltip: 'Export Data',
            // --- Logic connected here ---
            onPressed: (_isGrading || _isExporting) ? null : _exportToExcel,
            icon: const Icon(Icons.ios_share, color: Colors.white),
          ),
          IconButton(
            tooltip: 'Add Student',
            onPressed: _onAddButtonPressed,
            icon: const Icon(Icons.add, color: Colors.white, size: 28),
          ),
          IconButton(
            tooltip: 'Close Menu',
            onPressed: () => setState(() => _isMenuOpen = false),
            icon: const Icon(Icons.more_horiz, color: Colors.white),
          ),
        ],
      ),
    );
    return AnimatedSwitcher(
      duration: const Duration(milliseconds: 250),
      transitionBuilder: (Widget child, Animation<double> animation) => ScaleTransition(scale: animation, child: child),
      child: _isMenuOpen ? openMenu : closedMenu,
    );
  }
}