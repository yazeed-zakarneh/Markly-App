// lib/dialogs/add_student_dialog.dart

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import '../models/student_model.dart';

class AddStudentDialog extends StatefulWidget {
  final String userId;
  final String classId;
  final String examId;
  final Student? existingStudent; // This is the new optional parameter

  const AddStudentDialog({
    super.key,
    required this.userId,
    required this.classId,
    required this.examId,
    this.existingStudent, // Make it optional
  });

  @override
  State<AddStudentDialog> createState() => _AddStudentDialogState();
}

class _AddStudentDialogState extends State<AddStudentDialog> {
  final _formKey = GlobalKey<FormState>();
  final _nameController = TextEditingController();
  final _studentIdController = TextEditingController();
  bool _isSaving = false;

  // Helper to check if we are editing
  bool get _isEditing => widget.existingStudent != null;

  @override
  void initState() {
    super.initState();
    // If we are editing, pre-fill the text fields with the student's data
    if (_isEditing) {
      _nameController.text = widget.existingStudent!.name;
      _studentIdController.text = widget.existingStudent!.studentId;
    }
  }

  @override
  void dispose() {
    _nameController.dispose();
    _studentIdController.dispose();
    super.dispose();
  }

  Future<void> _saveStudent() async {
    if (!_formKey.currentState!.validate()) {
      return;
    }

    setState(() => _isSaving = true);

    try {
      final collectionRef = FirebaseFirestore.instance
          .collection('users').doc(widget.userId)
          .collection('classes').doc(widget.classId)
          .collection('exams').doc(widget.examId)
          .collection('students');

      final studentData = {
        'name': _nameController.text.trim(),
        'studentId': _studentIdController.text.trim(),
      };

      if (_isEditing) {
        // If editing, UPDATE the existing document
        await collectionRef.doc(widget.existingStudent!.id).update(studentData);
      } else {
        // If adding, ADD a new document
        await collectionRef.add(studentData);
      }

      if (mounted) Navigator.of(context).pop();

    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed to save student: $e')),
        );
      }
    } finally {
      if (mounted) setState(() => _isSaving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      title: Text(
        _isEditing ? "Edit Student" : "Add Student",
        style: const TextStyle(color: Color(0xFF1A237E)),
      ),
      content: Form(
        key: _formKey,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextFormField(
              controller: _nameController,
              decoration: const InputDecoration(
                labelText: 'Student Name',
                border: OutlineInputBorder(
                    borderRadius: BorderRadius.all(Radius.circular(10))),
              ),
              validator: (value) {
                if (value == null || value.trim().isEmpty) {
                  return 'Please enter a student name.';
                }
                return null;
              },
            ),
            const SizedBox(height: 16),
            TextFormField(
              controller: _studentIdController,
              decoration: const InputDecoration(
                labelText: 'Student ID',
                border: OutlineInputBorder(
                    borderRadius: BorderRadius.all(Radius.circular(10))),
              ),
              validator: (value) {
                if (value == null || value.trim().isEmpty) {
                  return 'Please enter a student ID.';
                }
                return null;
              },
            ),
          ],
        ),
      ),
      actions: [
        OutlinedButton(
          style: OutlinedButton.styleFrom(
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.all(Radius.circular(10))),
            side: const BorderSide(color: Color(0xFF1A237E)),
          ),
          onPressed: _isSaving ? null : () => Navigator.of(context).pop(),
          child: const Text('Cancel', style: TextStyle(color: Color(0xFF1A237E))),
        ),
        ElevatedButton(
          style: ElevatedButton.styleFrom(
            backgroundColor: const Color(0xFF1A237E),
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.all(Radius.circular(10))),
          ),
          onPressed: _isSaving ? null : _saveStudent,
          child: _isSaving
              ? const SizedBox(
            width: 20,
            height: 20,
            child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
          )
              : const Text('Save', style: TextStyle(color: Colors.white)),
        ),
      ],
    );
  }
}