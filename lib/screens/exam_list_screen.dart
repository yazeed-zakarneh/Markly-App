import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import '../widgets/exam_card.dart';
import '../dialogs/add_exam_dialog.dart';
import '../screens/questions_screen.dart';
import '../widgets/custom_drawer.dart';

class ExamListScreen extends StatelessWidget {
  final String classId;
  final String className;

  const ExamListScreen({
    super.key,
    required this.classId,
    required this.className,
  });

  @override
  Widget build(BuildContext context) {
    final userId = FirebaseAuth.instance.currentUser!.uid;

    return Scaffold(
      backgroundColor: Colors.white,
      endDrawer: CustomDrawer(onClose: () => Navigator.pop(context)),
      floatingActionButton: FloatingActionButton(
        backgroundColor: const Color(0xFF1A237E),
        onPressed: () {
          showDialog(
            context: context,
            builder: (_) => AddExamDialog(userId: userId, classId: classId),
          );
        },
        child: const Icon(Icons.add, color: Colors.white),
      ),
      appBar: AppBar(
        backgroundColor: Colors.white,
        elevation: 0,
        title: Image.asset(
          'assets/images/logo_text.png',
          height: 40,
        ),
        centerTitle: true,
      ),
      body: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const SizedBox(height: 8),
            /// Class Name
            Text(
              className,
              style: const TextStyle(
                fontWeight: FontWeight.bold,
                fontSize: 18,
                color: Color(0xFF1A237E),
              ),
            ),

            /// Search
            Container(
              margin: const EdgeInsets.only(top: 8),
              padding: const EdgeInsets.symmetric(horizontal: 16),
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(30),
                color: Colors.grey[200],
              ),
              child: const TextField(
                decoration: InputDecoration(
                  hintText: "Search",
                  border: InputBorder.none,
                  icon: Icon(Icons.search),
                ),
              ),
            ),
            const SizedBox(height: 12),

            /// Exams List
            Expanded(
              child: StreamBuilder<QuerySnapshot>(
                stream: FirebaseFirestore.instance
                    .collection('users')
                    .doc(userId)
                    .collection('classes')
                    .doc(classId)
                    .collection('exams')
                    .orderBy('section')
                    .snapshots(),
                builder: (context, snapshot) {
                  if (!snapshot.hasData) {
                    return const Center(child: CircularProgressIndicator());
                  }

                  final docs = snapshot.data!.docs;

                  if (docs.isEmpty) {
                    return const Center(child: Text("No exams yet."));
                  }

                  return ListView.builder(
                    itemCount: docs.length,
                    itemBuilder: (context, index) {
                      final doc = docs[index]; // ✅ Define doc here
                      final exam = doc.data() as Map<String, dynamic>;

                      return ExamCard(
                        examId: doc.id, // ✅ Now doc is defined
                        userId: userId,
                        classId: classId,
                        title: exam['title'],
                        min: exam['min'],
                        max: exam['max'],
                        avg: (exam['avg'] as num).toDouble(),
                        section: exam['section'] ?? 0,
                        onTap: () {
                          Navigator.push(
                            context,
                            MaterialPageRoute(
                              builder: (_) => QuestionsScreen(
                                className: className,
                                examTitle: exam['title'],
                                classId: classId,
                                examId: doc.id,
                              ),
                            ),
                          );
                        },
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
