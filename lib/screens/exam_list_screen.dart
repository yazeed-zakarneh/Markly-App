import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import '../widgets/exam_card.dart';
import '../dialogs/add_exam_dialog.dart';
import '../screens/questions_screen.dart';
import '../widgets/custom_drawer.dart';


class ExamListScreen extends StatefulWidget {
  final String classId;
  final String className;

  const ExamListScreen({
    super.key,
    required this.classId,
    required this.className,
  });

  @override
  State<ExamListScreen> createState() => _ExamListScreenState();
}

class _ExamListScreenState extends State<ExamListScreen> {
  // ⬇️ UPDATE: Added state for the search query and controller
  String _searchQuery = '';
  final _searchController = TextEditingController();

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

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
            builder: (_) => AddExamDialog(userId: userId, classId: widget.classId),
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
            Text(
              widget.className,
              style: const TextStyle(
                fontWeight: FontWeight.bold,
                fontSize: 18,
                color: Color(0xFF1A237E),
              ),
            ),
            Container(
              margin: const EdgeInsets.only(top: 8),
              padding: const EdgeInsets.symmetric(horizontal: 16),
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(30),
                color: Colors.grey[200],
              ),
              // ⬇️ UPDATE: Connected the TextField to the controller and onChanged
              child: TextField(
                controller: _searchController,
                onChanged: (value) {
                  setState(() {
                    _searchQuery = value.toLowerCase();
                  });
                },
                decoration: InputDecoration(
                  hintText: "Search exams...",
                  border: InputBorder.none,
                  icon: const Icon(Icons.search),
                  suffixIcon: _searchQuery.isNotEmpty
                      ? IconButton(
                    icon: const Icon(Icons.clear),
                    onPressed: () {
                      _searchController.clear();
                      setState(() {
                        _searchQuery = '';
                      });
                    },
                  )
                      : null,
                ),
              ),
            ),
            const SizedBox(height: 12),
            Expanded(
              child: StreamBuilder<QuerySnapshot>(
                stream: FirebaseFirestore.instance
                    .collection('users')
                    .doc(userId)
                    .collection('classes')
                    .doc(widget.classId)
                    .collection('exams')
                    .orderBy('section')
                    .snapshots(),
                builder: (context, snapshot) {
                  if (!snapshot.hasData) {
                    return const Center(child: CircularProgressIndicator());
                  }

                  // ⬇️ UPDATE: Filtering logic added here
                  final allDocs = snapshot.data!.docs;
                  final filteredDocs = allDocs.where((doc) {
                    final data = doc.data() as Map<String, dynamic>;
                    final examTitle = (data['title'] ?? '').toLowerCase();
                    return examTitle.contains(_searchQuery);
                  }).toList();

                  if (filteredDocs.isEmpty) {
                    if (_searchQuery.isNotEmpty) {
                      return const Center(child: Text("No matching exams found."));
                    }
                    return const Center(child: Text("No exams yet."));
                  }

                  // Build the ListView with the filtered list
                  return ListView.builder(
                    itemCount: filteredDocs.length,
                    itemBuilder: (context, index) {
                      final doc = filteredDocs[index];
                      final exam = doc.data() as Map<String, dynamic>;

                      return ExamCard(
                        examId: doc.id,
                        userId: userId,
                        classId: widget.classId,
                        title: exam['title'],
                        min: (exam['min'] as num? ?? 0.0).toDouble(),
                        max: (exam['max'] as num? ?? 0.0).toDouble(),
                        avg: (exam['avg'] as num? ?? 0.0).toDouble(),
                        scaleMaxGrade: (exam['scaleMaxGrade'] as num? ?? 0).toDouble(),
                        section: exam['section'] ?? 0,
                        onTap: () {
                          Navigator.push(
                            context,
                            MaterialPageRoute(
                              builder: (_) => QuestionsScreen(
                                className: widget.className,
                                examTitle: exam['title'],
                                classId: widget.classId,
                                examId: doc.id,
                                  section: exam['section']
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