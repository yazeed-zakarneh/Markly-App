import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';

class AddExamDialog extends StatefulWidget {
  final String userId;
  final String classId;

  const AddExamDialog({
    super.key,
    required this.userId,
    required this.classId,
  });

  @override
  State<AddExamDialog> createState() => _AddExamDialogState();
}

class _AddExamDialogState extends State<AddExamDialog> {
  final nameController = TextEditingController();
  final gradeController = TextEditingController();
  final sectionController = TextEditingController();
  bool isSaving = false;

  @override
  void initState() {
    super.initState();
    _suggestNextSection();
  }

  void _suggestNextSection() async {
    final examsSnapshot = await FirebaseFirestore.instance
        .collection('users')
        .doc(widget.userId)
        .collection('classes')
        .doc(widget.classId)
        .collection('exams')
        .orderBy('section', descending: true)
        .limit(1)
        .get();

    if (examsSnapshot.docs.isNotEmpty) {
      final lastSection = examsSnapshot.docs.first['section'] ?? 0;
      sectionController.text = (lastSection + 1).toString();
    } else {
      sectionController.text = '1';
    }
  }

  @override
  void dispose() {
    nameController.dispose();
    gradeController.dispose();
    sectionController.dispose();
    super.dispose();
  }

  Future<void> _saveExam() async {
    final name = nameController.text.trim();
    final maxGrade = int.tryParse(gradeController.text) ?? 0;
    final section = int.tryParse(sectionController.text) ?? -1;

    if (name.isEmpty || maxGrade <= 0 || section <= 0) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text("Please fill all fields correctly")),
      );
      return;
    }

    setState(() => isSaving = true);

    await FirebaseFirestore.instance
        .collection('users')
        .doc(widget.userId)
        .collection('classes')
        .doc(widget.classId)
        .collection('exams')
        .add({
      'title': name,
      'max': maxGrade,
      'section': section,
      'min': 0,
      'avg': 0,
    });

    setState(() => isSaving = false);
    Navigator.pop(context);
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      title: const Text("Add Exam",style: TextStyle(color: Color(0xFF1A237E)),),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: nameController,
                    decoration: const InputDecoration(
                      labelText: "Name",
                      border: OutlineInputBorder(
                          borderRadius: BorderRadius.all(Radius.circular(10))),
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: TextField(
                    controller: gradeController,
                    decoration: const InputDecoration(
                      labelText: "Max Grade",
                      border: OutlineInputBorder(
                          borderRadius: BorderRadius.all(Radius.circular(10))),
                    ),
                    keyboardType: TextInputType.number,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            TextField(
              controller: sectionController,
              decoration: const InputDecoration(
                labelText: "Section",
                border: OutlineInputBorder(
                    borderRadius: BorderRadius.all(Radius.circular(10))),
              ),
              keyboardType: TextInputType.number,
            ),
          ],
        ),
      ),
      actions: [
        OutlinedButton(
          style: OutlinedButton.styleFrom(
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.all(Radius.circular(10))),
            side: BorderSide(color: Color(0xFF1A237E)),
          ),
          onPressed: () => Navigator.pop(context),
          child: const Text("Cancel", style: TextStyle(color: Color(0xFF1A237E))),
        ),
        ElevatedButton(
          onPressed: isSaving ? null : _saveExam,
          style: ElevatedButton.styleFrom(
            backgroundColor: const Color(0xFF1A237E),
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.all(Radius.circular(10))),
          ),
          child: isSaving
              ? const SizedBox(
            width: 20,
            height: 20,
            child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
          )
              : const Text("Save", style: TextStyle(color: Colors.white)),
        ),
      ],
    );
  }
}
