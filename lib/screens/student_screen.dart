import 'dart:convert';
import 'dart:io';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:http_parser/http_parser.dart';
import 'package:image_picker/image_picker.dart';
import 'package:markly/models/student_model.dart';
import 'package:markly/widgets/custom_drawer.dart';

class _AnswerSheet {
  final String imageUrl;
  final String ocrText;
  final TextEditingController controller;

  _AnswerSheet({required this.imageUrl, required this.ocrText})
      : controller = TextEditingController(text: ocrText);

  factory _AnswerSheet.fromMap(Map<String, dynamic> map) {
    return _AnswerSheet(
      imageUrl: map['imageUrl'] as String,
      ocrText: map['ocrText'] as String,
    );
  }
}

class _OcrImageState {
  final File imageFile;
  bool isOcrProcessing = true;
  String ocrResult = '';
  final TextEditingController controller = TextEditingController();

  _OcrImageState({required this.imageFile});
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
  bool _isSaving = false;
  final List<_OcrImageState> _imageStates = [];
  final List<_AnswerSheet> _savedAnswerSheets = [];
  final String userId = FirebaseAuth.instance.currentUser!.uid;
  bool _isProcessingQueue = false;

  @override
  void initState() {
    super.initState();
    _loadInitialData();
  }

  Future<void> _loadInitialData() async {
    try {
      final docSnapshot = await FirebaseFirestore.instance
          .collection('users')
          .doc(userId)
          .collection('classes')
          .doc(widget.classId)
          .collection('exams')
          .doc(widget.examId)
          .collection('students')
          .doc(widget.student.id)
          .get();

      if (docSnapshot.exists) {
        final data = docSnapshot.data();
        if (data != null && data.containsKey('answerSheets')) {
          // Robustly parse the data from Firestore
          final rawSheets = data['answerSheets'] as List<dynamic>;
          final loadedSheets = rawSheets.map((rawData) {
            final mapData = Map<String, dynamic>.from(rawData as Map);
            return _AnswerSheet.fromMap(mapData);
          }).toList();

          if (mounted) {
            setState(() {
              _savedAnswerSheets
                  .clear(); // Clear before adding to prevent duplicates
              _savedAnswerSheets.addAll(loadedSheets);
            });
          }
        }
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed to load initial data: $e')),
        );
      }
    } finally {
      if (mounted) {
        setState(() {
          _isLoading = false;
        });
      }
    }
  }

  String _formatOcrText(String rawText) {
    final RegExp questionPattern = RegExp(r'^\s*(\d+|[a-zA-Z])[\.\)]');
    final lines = rawText.split('\n');
    final List<String> formattedLines = [];

    for (final line in lines) {
      final trimmedLine = line.trim();
      if (trimmedLine.isEmpty) {
        continue;
      }
      if (questionPattern.hasMatch(trimmedLine)) {
        if (formattedLines.isNotEmpty) {
          formattedLines.add('');
        }
      }
      formattedLines.add(trimmedLine);
    }
    return formattedLines.join('\n');
  }

  Future<void> _runOcrForImage(_OcrImageState imageState) async {
    final uri = Uri.parse('https://omarabualrob-ocr-api.hf.space/ocr');
    try {
      var request = http.MultipartRequest('POST', uri)
        ..files.add(
          await http.MultipartFile.fromPath(
            'file',
            imageState.imageFile.path,
            contentType: MediaType('image', 'jpeg'),
          ),
        );

      var streamedResponse =
          await request.send().timeout(const Duration(minutes: 10));
      var response = await http.Response.fromStream(streamedResponse);

      if (response.statusCode == 200) {
        final Map<String, dynamic> responseBody = jsonDecode(response.body);
        if (responseBody.containsKey('text')) {
          final rawText = responseBody['text'] as String;
          imageState.ocrResult = _formatOcrText(rawText);
        } else {
          throw Exception('OCR API response format was unexpected.');
        }
      } else {
        throw Exception('Failed to load OCR data: ${response.statusCode}');
      }
    } catch (e) {
      imageState.ocrResult = 'Error performing OCR: $e';
    } finally {
      if (mounted) {
        setState(() {
          imageState.isOcrProcessing = false;
          imageState.controller.text = imageState.ocrResult;
        });
      }
    }
  }

  Future<void> _pickImagesAndPerformOcr() async {
    if (_isSaving) return;

    final picker = ImagePicker();
    final pickedFiles = await picker.pickMultiImage(
      maxWidth: 1800,
      maxHeight: 1800,
      imageQuality: 85,
    );

    if (pickedFiles.isEmpty) {
      return;
    }

    final newImageStates = pickedFiles
        .map((file) => _OcrImageState(imageFile: File(file.path)))
        .toList();

    setState(() {
      _imageStates.addAll(newImageStates);
    });

    // Process sequentially to avoid overwhelming the API
    for (final imageState in newImageStates) {
      await _runOcrForImage(imageState);
    }
  }

  Future<void> _saveAllData() async {
    if (_isSaving || _imageStates.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('No new answer sheets to save.')),
      );
      return;
    }

    setState(() {
      _isSaving = true;
    });

    try {
      final List<Map<String, String>> newAnswerSheets = [];
      for (final imageState in _imageStates) {
        final path =
            'student_answers/${userId}/${widget.examId}/${widget.student.id}/${DateTime.now().millisecondsSinceEpoch}.jpg';
        final ref = FirebaseStorage.instance.ref(path);
        await ref.putFile(imageState.imageFile);
        final url = await ref.getDownloadURL();
        newAnswerSheets.add({
          'imageUrl': url,
          'ocrText': imageState.controller.text,
        });
      }

      if (newAnswerSheets.isNotEmpty) {
        final studentDocRef = FirebaseFirestore.instance
            .collection('users')
            .doc(userId)
            .collection('classes')
            .doc(widget.classId)
            .collection('exams')
            .doc(widget.examId)
            .collection('students')
            .doc(widget.student.id);

        // Use .update() for modifying an existing document.
        await studentDocRef.update({
          'answerSheets': FieldValue.arrayUnion(newAnswerSheets),
        });

        if (mounted) {
          setState(() {
            final newlySavedSheets = newAnswerSheets.map((d) =>
                _AnswerSheet(imageUrl: d['imageUrl']!, ocrText: d['ocrText']!));
            _savedAnswerSheets.addAll(newlySavedSheets);
            _imageStates.clear();
          });
        }
      }

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Answers saved successfully.')),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed to save answers: $e')),
        );
      }
    } finally {
      if (mounted) {
        setState(() {
          _isSaving = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    bool isProcessing = _imageStates.any((s) => s.isOcrProcessing);

    return Scaffold(
      backgroundColor: Colors.white,
      drawer: CustomDrawer(onClose: () => Navigator.pop(context)),
      floatingActionButton: FloatingActionButton(
        onPressed: (_isSaving || isProcessing) ? null : _saveAllData,
        backgroundColor:
            (_isSaving || isProcessing) ? Colors.grey : const Color(0xFF1A237E),
        child: _isSaving
            ? const CircularProgressIndicator(color: Colors.white)
            : const Icon(Icons.save, color: Colors.white),
      ),
      appBar: AppBar(
        backgroundColor: Colors.white,
        elevation: 0,
        automaticallyImplyLeading: false,
        title: Row(
          children: [
            IconButton(
              icon: const Icon(Icons.arrow_back, color: Color(0xFF1A237E)),
              onPressed: () => Navigator.pop(context),
            ),
            const Spacer(),
            Image.asset(
              'assets/images/logo_text.png',
              height: 40,
            ),
            const Spacer(),
            Builder(
              builder: (context) => IconButton(
                icon: const Icon(Icons.menu, color: Color(0xFF1A237E)),
                onPressed: () => Scaffold.of(context).openDrawer(),
              ),
            ),
          ],
        ),
      ),
      body: _isLoading
          ? const Center(
              child: CircularProgressIndicator(color: Color(0xFF1A237E)))
          : Padding(
              padding: const EdgeInsets.all(16.0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    widget.student.name,
                    style: const TextStyle(
                      fontSize: 22,
                      fontWeight: FontWeight.bold,
                      color: Color(0xFF1A237E),
                    ),
                  ),
                  Text(
                    'ID: ${widget.student.studentId}',
                    style: TextStyle(
                      fontSize: 16,
                      color: Colors.grey[700],
                    ),
                  ),
                  const SizedBox(height: 24),
                  Center(
                    child: ElevatedButton.icon(
                      style: ElevatedButton.styleFrom(
                        backgroundColor: const Color(0xFF1A237E),
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(
                            horizontal: 20, vertical: 12),
                      ),
                      onPressed: _isSaving ? null : _pickImagesAndPerformOcr,
                      icon: const Icon(Icons.add_a_photo_outlined),
                      label: const Text('Add & Scan Answer Sheets'),
                    ),
                  ),
                  const SizedBox(height: 16),
                  const Divider(),
                  const SizedBox(height: 16),
                  Expanded(
                    child: ListView.builder(
                      itemCount:
                          _savedAnswerSheets.length + _imageStates.length,
                      itemBuilder: (context, index) {
                        // Display previously saved images
                        if (index < _savedAnswerSheets.length) {
                          final sheet = _savedAnswerSheets[index];
                          return Card(
                            margin: const EdgeInsets.only(bottom: 16),
                            child: Padding(
                              padding: const EdgeInsets.all(8.0),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text('Saved Answer Sheet ${index + 1}',
                                      style: const TextStyle(
                                          fontWeight: FontWeight.bold)),
                                  const SizedBox(height: 8),
                                  ClipRRect(
                                    borderRadius: BorderRadius.circular(8),
                                    child: Image.network(sheet.imageUrl,
                                        fit: BoxFit.cover, loadingBuilder:
                                            (context, child, loadingProgress) {
                                      if (loadingProgress == null) return child;
                                      return Container(
                                        height: 200,
                                        alignment: Alignment.center,
                                        child: CircularProgressIndicator(
                                          value: loadingProgress
                                                      .expectedTotalBytes !=
                                                  null
                                              ? loadingProgress
                                                      .cumulativeBytesLoaded /
                                                  loadingProgress
                                                      .expectedTotalBytes!
                                              : null,
                                        ),
                                      );
                                    }, errorBuilder:
                                            (context, error, stackTrace) {
                                      return Container(
                                        height: 200,
                                        alignment: Alignment.center,
                                        child: const Icon(Icons.error,
                                            color: Colors.red, size: 40),
                                      );
                                    }),
                                  ),
                                  const SizedBox(height: 12),
                                  TextField(
                                    controller: sheet.controller,
                                    decoration: const InputDecoration(
                                      labelText: 'Saved OCR Text',
                                      border: OutlineInputBorder(),
                                    ),
                                    maxLines: null,
                                    readOnly: true,
                                  ),
                                ],
                              ),
                            ),
                          );
                        }

                        // Display newly picked images with OCR results
                        final imageStateIndex =
                            index - _savedAnswerSheets.length;
                        final imageState = _imageStates[imageStateIndex];
                        return Card(
                          margin: const EdgeInsets.only(bottom: 16),
                          child: Padding(
                            padding: const EdgeInsets.all(8.0),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text('New Image ${imageStateIndex + 1}',
                                    style: const TextStyle(
                                        fontWeight: FontWeight.bold)),
                                const SizedBox(height: 8),
                                Stack(
                                  alignment: Alignment.center,
                                  children: [
                                    ClipRRect(
                                      borderRadius: BorderRadius.circular(8.0),
                                      child: Image.file(imageState.imageFile,
                                          fit: BoxFit.cover),
                                    ),
                                    if (imageState.isOcrProcessing)
                                      const CircularProgressIndicator(),
                                  ],
                                ),
                                const SizedBox(height: 12),
                                TextField(
                                  controller: imageState.controller,
                                  decoration: const InputDecoration(
                                    labelText: 'Extracted Text (OCR Result)',
                                    border: OutlineInputBorder(),
                                  ),
                                  maxLines: null,
                                  readOnly: imageState.isOcrProcessing,
                                ),
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
