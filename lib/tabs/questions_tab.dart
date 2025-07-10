import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import '../screens/question_detail_screen.dart';

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

  void _showAddQuestionDialog() {
    final controller = TextEditingController();
    bool isLoading = false;

    showDialog(
      context: context,
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setDialogState) {
            return AlertDialog(
              title: const Text("Add Question"),
              content: TextField(
                controller: controller,
                decoration: const InputDecoration(
                  hintText: "Enter question text",
                  border: OutlineInputBorder(),
                ),
                autofocus: true,
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(context),
                  child: const Text("Cancel"),
                ),
                ElevatedButton(
                  onPressed: isLoading
                      ? null
                      : () async {
                    final name = controller.text.trim();
                    if (name.isNotEmpty) {
                      try {
                        setDialogState(() => isLoading = true);

                        await FirebaseFirestore.instance
                            .collection('users')
                            .doc(userId)
                            .collection('classes')
                            .doc(widget.classId)
                            .collection('exams')
                            .doc(widget.examId)
                            .collection('questions')
                            .add({
                          'name': name,
                          'createdAt': FieldValue.serverTimestamp(),
                        });

                        Navigator.pop(context);
                      } catch (e) {
                        setDialogState(() => isLoading = false);
                        print('❌ Failed to add question: $e');
                        ScaffoldMessenger.of(context).showSnackBar(
                          SnackBar(content: Text('Failed to add question: $e')),
                        );
                      }
                    }
                  },
                  child: isLoading
                      ? const SizedBox(
                    height: 20,
                    width: 20,
                    child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                  )
                      : const Text("Add"),
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
    final questionsRef = FirebaseFirestore.instance
        .collection('users')
        .doc(userId)
        .collection('classes')
        .doc(widget.classId)
        .collection('exams')
        .doc(widget.examId)
        .collection('questions')
        .orderBy('createdAt', descending: false);

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
              padding: const EdgeInsets.all(16),
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
                      style: const TextStyle(fontSize: 16),
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
            onPressed: _showAddQuestionDialog,
            backgroundColor: const Color(0xFF1A237E),
            child: const Icon(Icons.add),
          ),
        ),
      ],
    );
  }
}
