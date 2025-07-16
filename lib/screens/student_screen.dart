import 'dart:io';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:markly/models/student_model.dart';
import 'package:markly/widgets/custom_drawer.dart';
import '../models/ocr_model.dart';


class AnswerSheet {
  final String imageUrl;
  final String ocrText;

  AnswerSheet({required this.imageUrl, required this.ocrText});

  factory AnswerSheet.fromMap(Map<String, dynamic> map) {
    return AnswerSheet(
      imageUrl: map['imageUrl'] as String,
      ocrText: map['ocrText'] as String? ?? '',
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'imageUrl': imageUrl,
      'ocrText': ocrText,
    };
  }
}

class StudentScreen extends StatefulWidget {
  final Student student;
  final String classId;
  final String examId;

  const StudentScreen({
    super.key,
    required this.student,
    required this.classId,
    required this.examId,
  });

  @override
  State<StudentScreen> createState() => _StudentPageState();
}

class _StudentPageState extends State<StudentScreen> {
  bool _isLoading = true;
  bool _isProcessing = false;
  final List<AnswerSheet> _savedAnswerSheets = [];
  final String userId = FirebaseAuth.instance.currentUser!.uid;
  final OcrService _ocrService = OcrService();

  @override
  void initState() {
    super.initState();
    _loadInitialData();
  }

  Future<void> _loadInitialData() async {
    // This method is fine, no changes needed.
    try {
      final docSnapshot = await FirebaseFirestore.instance
          .collection('users').doc(userId).collection('classes')
          .doc(widget.classId).collection('exams').doc(widget.examId)
          .collection('students').doc(widget.student.id).get();

      if (docSnapshot.exists) {
        final data = docSnapshot.data();
        if (data != null && data.containsKey('answerSheets')) {
          final dynamic rawSheetsData = data['answerSheets'];
          if (rawSheetsData is List) {
            final loadedSheets = rawSheetsData
                .whereType<Map>()
                .map((mapData) => AnswerSheet.fromMap(Map<String, dynamic>.from(mapData)))
                .toList();
            if (mounted) {
              setState(() {
                _savedAnswerSheets.addAll(loadedSheets);
              });
            }
          }
        }
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Failed to load initial data: $e')));
      }
    } finally {
      if (mounted) {
        setState(() => _isLoading = false);
      }
    }
  }

  /// The new, streamlined workflow for adding one sheet.
  Future<void> _addAndProcessSheet() async {
    if (_isProcessing) return;

    final picker = ImagePicker();
    // --- THIS IS THE FIX ---
    final pickedFile = await picker.pickImage(
      source: ImageSource.gallery, // Required parameter added
      maxWidth: 1800,
      maxHeight: 1800,
      imageQuality: 85,
    );
    // --- END OF FIX ---

    if (pickedFile == null) return;

    setState(() => _isProcessing = true);
    final imageFile = File(pickedFile.path);

    try {
      final ocrText = await _ocrService.performOcr(imageFile);
      if (ocrText == null) {
        throw Exception("OCR failed or returned no text.");
      }

      final path =
          'student_answers/${userId}/${widget.examId}/${widget.student.id}/${DateTime.now().millisecondsSinceEpoch}.jpg';
      final ref = FirebaseStorage.instance.ref(path);
      await ref.putFile(imageFile);
      final imageUrl = await ref.getDownloadURL();

      final newSheet = AnswerSheet(imageUrl: imageUrl, ocrText: ocrText);
      final studentDocRef = FirebaseFirestore.instance
          .collection('users').doc(userId).collection('classes')
          .doc(widget.classId).collection('exams').doc(widget.examId)
          .collection('students').doc(widget.student.id);

      await studentDocRef.update({
        'answerSheets': FieldValue.arrayUnion([newSheet.toMap()]),
      });

      if (mounted) {
        setState(() {
          _savedAnswerSheets.add(newSheet);
        });
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Answer sheet saved successfully!')),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed to process sheet: $e')),
        );
      }
    } finally {
      if (mounted) {
        setState(() => _isProcessing = false);
      }
    }
  }

  Future<void> _deleteAnswerSheet(AnswerSheet sheetToDelete) async {
    // This method is fine, no changes needed.
    final confirm = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Delete Answer Sheet'),
        content: const Text('Are you sure you want to permanently delete this answer sheet?'),
        actions: [
          TextButton(onPressed: () => Navigator.of(context).pop(false), child: const Text('Cancel')),
          TextButton(onPressed: () => Navigator.of(context).pop(true), child: const Text('Delete', style: TextStyle(color: Colors.red))),
        ],
      ),
    );
    if (confirm != true) return;

    final sheetIndex = _savedAnswerSheets.indexOf(sheetToDelete);
    setState(() => _savedAnswerSheets.remove(sheetToDelete));

    try {
      final studentDocRef = FirebaseFirestore.instance
          .collection('users').doc(userId).collection('classes')
          .doc(widget.classId).collection('exams').doc(widget.examId)
          .collection('students').doc(widget.student.id);

      await studentDocRef.update({'answerSheets': FieldValue.arrayRemove([sheetToDelete.toMap()])});
    } catch (e) {
      setState(() => _savedAnswerSheets.insert(sheetIndex, sheetToDelete));
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Failed to delete sheet: $e')));
      }
    }
  }


  @override
  Widget build(BuildContext context) {
    // The build method is correct and does not need changes.
    return Scaffold(
      backgroundColor: Colors.white,
      drawer: CustomDrawer(onClose: () => Navigator.pop(context)),
      appBar: AppBar(
        backgroundColor: Colors.white,
        elevation: 0,
        automaticallyImplyLeading: false,
        title: Row(
          children: [
            IconButton(icon: const Icon(Icons.arrow_back, color: Color(0xFF1A237E)), onPressed: () => Navigator.pop(context)),
            const Spacer(),
            Image.asset('assets/images/logo_text.png', height: 40),
            const Spacer(),
            Builder(builder: (context) => IconButton(icon: const Icon(Icons.menu, color: Color(0xFF1A237E)), onPressed: () => Scaffold.of(context).openDrawer())),
          ],
        ),
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator(color: Color(0xFF1A237E)))
          : Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(widget.student.name, style: const TextStyle(fontSize: 22, fontWeight: FontWeight.bold, color: Color(0xFF1A237E))),
            Text('ID: ${widget.student.studentId}', style: TextStyle(fontSize: 16, color: Colors.grey[700])),
            const SizedBox(height: 24),
            Center(
              child: ElevatedButton.icon(
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFF1A237E),
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
                ),
                onPressed: _isProcessing ? null : _addAndProcessSheet,
                icon: _isProcessing
                    ? Container(width: 20, height: 20, margin: const EdgeInsets.only(right: 8), child: const CircularProgressIndicator(color: Colors.white, strokeWidth: 2))
                    : const Icon(Icons.add_a_photo_outlined),
                label: Text(_isProcessing ? 'Processing...' : 'Add & Scan Sheet'),
              ),
            ),
            const SizedBox(height: 16),
            const Divider(),
            const SizedBox(height: 16),
            Expanded(
              child: ListView.builder(
                itemCount: _savedAnswerSheets.length,
                itemBuilder: (context, index) {
                  final sheet = _savedAnswerSheets[index];
                  final List<ParsedQuestion> parsedPairs = _ocrService.extractQuestionsFromText(sheet.ocrText);

                  return Card(
                    margin: const EdgeInsets.only(bottom: 16),
                    child: Padding(
                      padding: const EdgeInsets.all(12.0),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              Text('Answer Sheet ${index + 1}', style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
                              const Spacer(),
                              IconButton(
                                icon: const Icon(Icons.delete_outline, color: Colors.red),
                                onPressed: () => _deleteAnswerSheet(sheet),
                              )
                            ],
                          ),
                          const SizedBox(height: 8),
                          ClipRRect(
                            borderRadius: BorderRadius.circular(8),
                            child: Image.network(
                              sheet.imageUrl,
                              fit: BoxFit.cover,
                              loadingBuilder: (context, child, loadingProgress) {
                                if (loadingProgress == null) return child;
                                return Container(height: 200, alignment: Alignment.center, child: const CircularProgressIndicator());
                              },
                              errorBuilder: (context, error, stackTrace) {
                                return Container(height: 200, alignment: Alignment.center, child: const Icon(Icons.error, color: Colors.red, size: 40));
                              },
                            ),
                          ),
                          const Divider(height: 24, thickness: 1),
                          const Text("Parsed Questions & Answers:", style: TextStyle(fontWeight: FontWeight.bold, color: Colors.teal, fontSize: 15)),
                          const SizedBox(height: 8),
                          if (parsedPairs.isEmpty && sheet.ocrText.isNotEmpty)
                            const Text("(Could not parse any Q&A pairs)"),
                          ...parsedPairs.map((qa) {
                            return Padding(
                              padding: const EdgeInsets.only(bottom: 16.0),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(qa.question, style: const TextStyle(fontWeight: FontWeight.bold)),
                                  const SizedBox(height: 4),
                                  Text(qa.answer, style: TextStyle(color: Colors.grey[800], fontStyle: FontStyle.italic)),
                                ],
                              ),
                            );
                          }).toList(),
                        ],
                      ),
                    ),
                  );
                },
              ),
            )
          ],
        ),
      ),
    );
  }
}