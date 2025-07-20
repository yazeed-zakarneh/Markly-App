import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';

class ExamCard extends StatelessWidget {
  final int section;
  final String title;
  final double min;
  final double max;
  final double avg;
  final double scaleMaxGrade;
  final String examId;
  final String classId;
  final String userId;
  final VoidCallback onTap;

  const ExamCard({
    super.key,
    required this.section,
    required this.title,
    required this.min,
    required this.max,
    required this.avg,
    required this.scaleMaxGrade,
    required this.examId,
    required this.classId,
    required this.userId,
    required this.onTap,
  });

  // This function is for renaming the exam title.
  void _showRenameDialog(BuildContext context) {
    final controller = TextEditingController(text: title);
    showDialog(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text("Rename Exam", style: TextStyle(color: Color(0xFF1A237E)),),
        content: TextField(
          controller: controller,
          decoration: const InputDecoration(labelText: "New Exam Name"),
        ),
        actions: [
          OutlinedButton(
              style: OutlinedButton.styleFrom(
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.all(Radius.circular(10))),
                side: const BorderSide(color: Color(0xFF1A237E)),
              ),
              onPressed: () => Navigator.pop(context),
              child: const Text("Cancel", style: TextStyle(color: Color(0xFF1A237E)))
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFF1A237E),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.all(Radius.circular(10))),
            ),
            onPressed: () async {
              final newName = controller.text.trim();
              if (newName.isNotEmpty) {
                await FirebaseFirestore.instance
                    .collection('users').doc(userId).collection('classes')
                    .doc(classId).collection('exams').doc(examId)
                    .update({'title': newName});
              }
              Navigator.pop(context);
            },
            child: const Text("Save", style: TextStyle(color: Colors.white),),
          ),
        ],
      ),
    );
  }

  // This function is for deleting the entire exam.
  void _showDeleteDialog(BuildContext context) async {
    final shouldDelete = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Delete Exam', style: TextStyle(color: Color(0xFF1A237E)),),
        content: const Text('Are you sure you want to delete this exam? You won\'t be able to restore it!', style: TextStyle(color: Colors.red)),
        actions: [
          OutlinedButton(
              style: OutlinedButton.styleFrom(
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.all(Radius.circular(10))),
                side: const BorderSide(color: Color(0xFF1A237E)),
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
            child: const Text('Delete', style: TextStyle(color: Colors.white)),
          ),
        ],
      ),
    );
    if (shouldDelete == true) {
      await FirebaseFirestore.instance
          .collection('users').doc(userId).collection('classes')
          .doc(classId).collection('exams').doc(examId).delete();
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Exam deleted')),
      );
    }
  }

  // ⬇️⬇️ NEW FUNCTION TO CHANGE THE SCALING GRADE ⬇️⬇️
  void _showChangeGradeDialog(BuildContext context) {
    final controller = TextEditingController(text: scaleMaxGrade.toStringAsFixed(0));

    showDialog(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text("Change Max Grade", style: TextStyle(color: Color(0xFF1A237E))),
        content: TextField(
          controller: controller,
          keyboardType: TextInputType.number,
          decoration: const InputDecoration(labelText: "New Max Grade (for scaling)"),
        ),
        actions: [
          OutlinedButton(
            style: OutlinedButton.styleFrom(
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
              side: const BorderSide(color: Color(0xFF1A237E)),
            ),
            onPressed: () => Navigator.pop(context),
            child: const Text("Cancel", style: TextStyle(color: Color(0xFF1A237E))),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFF1A237E),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
            ),
            onPressed: () async {
              final newGrade = double.tryParse(controller.text.trim());
              if (newGrade != null && newGrade > 0) {
                await FirebaseFirestore.instance
                    .collection('users').doc(userId).collection('classes')
                    .doc(classId).collection('exams').doc(examId)
                    .update({'scaleMaxGrade': newGrade});

                ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text('Grade updated. Re-grade students to apply changes.'))
                );
              }
              Navigator.pop(context);
            },
            child: const Text("Save", style: TextStyle(color: Colors.white)),
          ),
        ],
      ),
    );
  }

  // This function shows the menu with all options.
  void _showOptionsMenu(BuildContext context, Offset position) async {
    final selected = await showMenu<String>(
      context: context,
      position: RelativeRect.fromLTRB(position.dx, position.dy, 0, 0),
      items: [
        const PopupMenuItem(value: 'rename', child: Text('Rename')),
        // ⬇️⬇️ NEW MENU ITEM ⬇️⬇️
        const PopupMenuItem(value: 'change_grade', child: Text('Change Grade')),
        const PopupMenuItem(
          value: 'delete',
          child: Text('Delete', style: TextStyle(color: Colors.red)),
        ),
      ],
    );

    if (selected == 'rename') {
      _showRenameDialog(context);
      // ⬇️⬇️ NEW LOGIC TO HANDLE THE SELECTION ⬇️⬇️
    } else if (selected == 'change_grade') {
      _showChangeGradeDialog(context);
    } else if (selected == 'delete') {
      _showDeleteDialog(context);
    }
  }

  @override
  Widget build(BuildContext context) {
    final String maxGradeStr = scaleMaxGrade.toStringAsFixed(0);

    return GestureDetector(
      onTap: onTap,
      onLongPressStart: (details) => _showOptionsMenu(context, details.globalPosition),
      child: Card(
        margin: const EdgeInsets.only(bottom: 12),
        elevation: 2,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Row(
            children: [
              Container(
                width: 4,
                height: 50,
                decoration: BoxDecoration(
                  color: const Color(0xFF1A237E),
                  borderRadius: BorderRadius.circular(8),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(title, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
                    const SizedBox(height: 4),
                    Text(
                        "Min: ${min.toStringAsFixed(1)}/$maxGradeStr   Max: ${max.toStringAsFixed(1)}/$maxGradeStr",
                        style: const TextStyle(fontSize: 13, color: Colors.grey)
                    ),
                    Text(
                        "Avg: ${avg.toStringAsFixed(1)}/$maxGradeStr",
                        style: const TextStyle(fontSize: 13, color: Colors.grey)
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 4),
              Text('$section', style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
            ],
          ),
        ),
      ),
    );
  }
}