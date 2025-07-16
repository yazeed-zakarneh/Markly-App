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
    return {'imageUrl': imageUrl, 'ocrText': ocrText};
  }
}

/// A dedicated widget to display a single Question/Answer pair in a Card.
class _QaDisplayCard extends StatelessWidget {
  final ParsedQuestion qaPair;

  const _QaDisplayCard({required this.qaPair});

  @override
  Widget build(BuildContext context) {
    return Card(
      // The margin is removed from here to be controlled by the parent Column
      margin: const EdgeInsets.only(bottom: 16),
      elevation: 2,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              qaPair.question,
              style: const TextStyle(
                  fontWeight: FontWeight.bold,
                  fontSize: 16,
                  color: Color(0xFF1A237E)),
            ),
            const SizedBox(height: 8),
            const Divider(),
            const SizedBox(height: 8),
            Text(
              qaPair.answer.isNotEmpty
                  ? qaPair.answer
                  : "(No answer was provided)",
              style: TextStyle(
                  fontSize: 15,
                  color: Colors.grey[800],
                  fontStyle: FontStyle.italic),
            ),
          ],
        ),
      ),
    );
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
    try {
      final docSnapshot = await FirebaseFirestore.instance
          .collection('users').doc(userId).collection('classes')
          .doc(widget.classId).collection('exams').doc(widget.examId)
          .collection('students').doc(widget.student.id).get();
      if (docSnapshot.exists) {
        final data = docSnapshot.data();
        if (data != null && data.containsKey('answerSheets')) {
          final rawSheetsData = data['answerSheets'] as List;
          final loadedSheets = rawSheetsData.whereType<Map>().map((mapData) =>
              AnswerSheet.fromMap(Map<String, dynamic>.from(mapData))).toList();
          if (mounted) {
            setState(() => _savedAnswerSheets.addAll(loadedSheets));
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

  Future<void> _addAndProcessSheet() async {
    if (_isProcessing) return;
    final picker = ImagePicker();
    final pickedFile = await picker.pickImage(
        source: ImageSource.gallery,
        maxWidth: 1800,
        maxHeight: 1800,
        imageQuality: 85);
    if (pickedFile == null) return;
    setState(() => _isProcessing = true);
    final imageFile = File(pickedFile.path);
    try {
      final ocrText = await _ocrService.performOcr(imageFile);
      if (ocrText == null) throw Exception("OCR failed or returned no text.");
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
        'answerSheets': FieldValue.arrayUnion([newSheet.toMap()])
      });
      if (mounted) {
        setState(() => _savedAnswerSheets.add(newSheet));
        ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Answer sheet saved successfully!')));
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Failed to process sheet: $e')));
      }
    } finally {
      if (mounted) {
        setState(() => _isProcessing = false);
      }
    }
  }

  Future<void> _deleteAnswerSheet(AnswerSheet sheetToDelete) async {
    // This function is correct
    final confirm = await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
          title: const Text('Delete Answer Sheet'),
          content: const Text(
              'This will remove all questions parsed from this sheet. Are you sure?'),
          actions: [
            TextButton(
                onPressed: () => Navigator.of(context).pop(false),
                child: const Text('Cancel')),
            TextButton(
                onPressed: () => Navigator.of(context).pop(true),
                child: const Text('Delete',
                    style: TextStyle(color: Colors.red))),
          ],
        ));
    if (confirm != true) return;
    final sheetIndex = _savedAnswerSheets.indexOf(sheetToDelete);
    setState(() => _savedAnswerSheets.remove(sheetToDelete));
    try {
      final studentDocRef = FirebaseFirestore.instance
          .collection('users').doc(userId).collection('classes')
          .doc(widget.classId).collection('exams').doc(widget.examId)
          .collection('students').doc(widget.student.id);
      await studentDocRef.update({
        'answerSheets': FieldValue.arrayRemove([sheetToDelete.toMap()])
      });
    } catch (e) {
      setState(() => _savedAnswerSheets.insert(sheetIndex, sheetToDelete));
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Failed to delete sheet: $e')));
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      drawer: CustomDrawer(onClose: () => Navigator.pop(context)),
      appBar: AppBar(
        backgroundColor: Colors.white,
        elevation: 0,
        automaticallyImplyLeading: false,
        title: Row(
          children: [
            IconButton(
                icon: const Icon(Icons.arrow_back, color: Color(0xFF1A237E)),
                onPressed: () => Navigator.pop(context)),
            const Spacer(),
            Image.asset('assets/images/logo_text.png', height: 40),
            const Spacer(),
            Builder(
                builder: (context) => IconButton(
                    icon: const Icon(Icons.menu, color: Color(0xFF1A237E)),
                    onPressed: () => Scaffold.of(context).openDrawer())),
          ],
        ),
      ),
      body: _isLoading
          ? const Center(
          child: CircularProgressIndicator(color: Color(0xFF1A237E)))
          : Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 8.0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(widget.student.name,
                      style: const TextStyle(
                          fontSize: 22,
                          fontWeight: FontWeight.bold,
                          color: Color(0xFF1A237E))),
                  Text('ID: ${widget.student.studentId}',
                      style: TextStyle(fontSize: 16, color: Colors.grey[700])),
                ],
              ),
            ),
            const SizedBox(height: 16),
            Center(
              child: ElevatedButton.icon(
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFF1A237E),
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(
                      horizontal: 20, vertical: 12),
                ),
                onPressed: _isProcessing ? null : _addAndProcessSheet,
                icon: _isProcessing
                    ? Container(
                    width: 20,
                    height: 20,
                    margin: const EdgeInsets.only(right: 8),
                    child: const CircularProgressIndicator(
                        color: Colors.white, strokeWidth: 2))
                    : const Icon(Icons.add_a_photo_outlined),
                label:
                Text(_isProcessing ? 'Processing...' : 'Add & Scan Sheet'),
              ),
            ),
            const SizedBox(height: 16),
            const Divider(),
            Expanded(
              child: Builder(
                builder: (context) {
                  final allParsedQuestions = _savedAnswerSheets
                      .expand((sheet) => _ocrService.extractQuestionsFromText(sheet.ocrText))
                      .toList();

                  if (allParsedQuestions.isEmpty) {
                    return const Center(
                      child: Text(
                        "No questions parsed yet.\nScan an answer sheet to begin.",
                        textAlign: TextAlign.center,
                        style: TextStyle(fontSize: 16, color: Colors.grey),
                      ),
                    );
                  }

                  return ListView.builder(
                    padding: const EdgeInsets.only(top: 8),
                    itemCount: allParsedQuestions.length,
                    itemBuilder: (context, index) {
                      final qaPair = allParsedQuestions[index];
                      final questionNumber = index + 1;

                      // --- MODIFIED SECTION ---
                      // Wrap the card in a Column to add the number above it.
                      return Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          // The Question Number Header
                          Padding(
                            padding: const EdgeInsets.only(left: 4.0, bottom: 4.0),
                            child: Text(
                              'Question $questionNumber',
                              style: const TextStyle(
                                fontSize: 18,
                                fontWeight: FontWeight.bold,
                                color: Colors.black87,
                              ),
                            ),
                          ),
                          // The original card widget
                          _QaDisplayCard(qaPair: qaPair),
                        ],
                      );
                      // --- END OF MODIFIED SECTION ---
                    },
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