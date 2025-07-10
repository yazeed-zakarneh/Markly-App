import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import '../dialogs/add_student_dialog.dart';
import '../models/student_model.dart';
import '../screens/student_screen.dart';

class StudentsTab extends StatefulWidget {
  final String classId;
  final String examId;
  const StudentsTab({required this.classId, required this.examId});

  @override
  State<StudentsTab> createState() => _StudentsTabState();
}

class _StudentsTabState extends State<StudentsTab> {
  @override
  Widget build(BuildContext context) {
    final userId = FirebaseAuth.instance.currentUser!.uid;
    return Scaffold(
      backgroundColor: Colors.white,
      floatingActionButton: FloatingActionButton(
        backgroundColor: const Color(0xFF1A237E),
        onPressed: () {
          showDialog(
            context: context,
            builder: (_) => AddStudentDialog(
              userId: userId,
              classId: widget.classId,
              examId: widget.examId,
            ),
          );
        },
        child: const Icon(Icons.add, color: Colors.white),
      ),
      body: StreamBuilder<QuerySnapshot>(
        stream: FirebaseFirestore.instance
            .collection('users')
            .doc(userId)
            .collection('classes')
            .doc(widget.classId)
            .collection('exams')
            .doc(widget.examId)
            .collection('students')
            .snapshots(),
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }
          if (snapshot.hasError) {
            return Center(child: Text('Error: ${snapshot.error}'));
          }
          if (!snapshot.hasData || snapshot.data!.docs.isEmpty) {
            return const Center(
              child: Text(
                'No students found. Add one to get started.',
                style: TextStyle(fontSize: 16, color: Colors.grey),
              ),
            );
          }

          final students = snapshot.data!.docs.map((doc) {
            return Student.fromMap(doc.data() as Map<String, dynamic>, doc.id);
          }).toList();

          return ListView.builder(
            padding: const EdgeInsets.all(8.0),
            itemCount: students.length,
            itemBuilder: (context, index) {
              final student = students[index];
              return Card(
                elevation: 2,
                margin: const EdgeInsets.symmetric(vertical: 8, horizontal: 8),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
                child: ListTile(
                  title: Text(student.name,
                      style: const TextStyle(fontWeight: FontWeight.bold)),
                  subtitle: Text('ID: ${student.studentId}'),
                  onTap: () {
                    Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (_) => StudentScreen(
                          student: student,
                          classId: widget.classId,
                          examId: widget.examId,
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
    );
  }
}
