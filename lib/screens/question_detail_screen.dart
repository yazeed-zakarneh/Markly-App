import 'dart:io';
import 'dart:convert';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:http_parser/http_parser.dart';
import 'package:image_picker/image_picker.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:http/http.dart' as http;
import '../widgets/custom_drawer.dart';

class QuestionDetailScreen extends StatefulWidget {
  final String classId;
  final String examId;
  final String questionId;
  final String questionName;
  final String className;
  final String examTitle;

  const QuestionDetailScreen({
    super.key,
    required this.classId,
    required this.examId,
    required this.questionId,
    required this.questionName,
    required this.className,
    required this.examTitle,
  });

  @override
  State<QuestionDetailScreen> createState() => _QuestionDetailScreenState();
}

class _QuestionDetailScreenState extends State<QuestionDetailScreen> {
  File? _image;
  final TextEditingController _text1Controller = TextEditingController();
  final TextEditingController _text2Controller = TextEditingController();
  bool _isSaving = false;
  bool _isLoading = true;
  bool _isOcrProcessing = false;
  String? _downloadUrl;

  @override
  void initState() {
    super.initState();
    _loadInitialData();
  }

  @override
  void dispose() {
    _text1Controller.dispose();
    _text2Controller.dispose();
    super.dispose();
  }

  Future<void> _loadInitialData() async {
    // This function is correct, no changes needed
    try {
      final userId = FirebaseAuth.instance.currentUser!.uid;
      final docSnapshot = await FirebaseFirestore.instance
          .collection('users')
          .doc(userId)
          .collection('classes')
          .doc(widget.classId)
          .collection('exams')
          .doc(widget.examId)
          .collection('questions')
          .doc(widget.questionId)
          .get();

      if (docSnapshot.exists && mounted) {
        final data = docSnapshot.data();
        setState(() {
          _text1Controller.text = data?['text1'] ?? '';
          _text2Controller.text = data?['text2'] ?? '';
          _downloadUrl = data?['imageUrl'];
        });
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed to load existing data: $e')),
        );
      }
    } finally {
      if (mounted) {
        setState(() => _isLoading = false);
      }
    }
  }

  /// Formats raw OCR text by adding newlines before questions.
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

  Future<String?> _performOcrOnImage(File imageFile) async {
    // This function is now correct and working
    setState(() {
      _isOcrProcessing = true;
    });
    final uri = Uri.parse('https://omarabualrob-ocr-api.hf.space/ocr');
    try {
      var request = http.MultipartRequest('POST', uri);
      request.files.add(
        await http.MultipartFile.fromPath(
          'file',
          imageFile.path,
          contentType: MediaType('image', 'jpeg'),
        ),
      );
      var streamedResponse =
          await request.send().timeout(const Duration(minutes: 2));
      var response = await http.Response.fromStream(streamedResponse);
      if (response.statusCode == 200) {
        final Map<String, dynamic> responseBody = jsonDecode(response.body);
        if (responseBody.containsKey('text')) {
          return responseBody['text'] as String;
        } else {
          throw Exception('OCR API success response format was unexpected.');
        }
      } else {
        print('OCR API Error Status Code: ${response.statusCode}');
        print('OCR API Error Response Body: ${response.body}');
        throw Exception('Failed to load OCR data: ${response.statusCode}');
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('$e')));
      }
      return null;
    } finally {
      if (mounted) {
        setState(() {
          _isOcrProcessing = false;
        });
      }
    }
  }

  Future<void> _pickImage() async {
    if (_isOcrProcessing) return;
    final picker = ImagePicker();
    final picked = await picker.pickImage(
      source: ImageSource.gallery,
      maxWidth: 1800,
      maxHeight: 1800,
      imageQuality: 85,
    );
    if (picked != null) {
      final imageFile = File(picked.path);
      setState(() {
        _image = imageFile;
      });
      final extractedText = await _performOcrOnImage(imageFile);
      if (extractedText != null && mounted) {
        final formattedText = _formatOcrText(extractedText);
        setState(() {
          _text1Controller.text = formattedText;
        });
      }
    }
  }

  Future<void> _saveData() async {
    // This function is correct, no changes needed
    if (_image == null &&
        _text1Controller.text.isEmpty &&
        _text2Controller.text.isEmpty &&
        _downloadUrl == null) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Nothing to save.')),
        );
      }
      return;
    }
    setState(() => _isSaving = true);
    final userId = FirebaseAuth.instance.currentUser!.uid;
    try {
      String? imageUrl = _downloadUrl;
      if (_image != null) {
        final ref = FirebaseStorage.instance.ref().child(
            'question_uploads/${widget.questionId}_${DateTime.now().millisecondsSinceEpoch}.jpg');
        await ref.putFile(_image!);
        imageUrl = await ref.getDownloadURL();
        if (mounted) {
          setState(() => _downloadUrl = imageUrl);
        }
      }
      await FirebaseFirestore.instance
          .collection('users')
          .doc(userId)
          .collection('classes')
          .doc(widget.classId)
          .collection('exams')
          .doc(widget.examId)
          .collection('questions')
          .doc(widget.questionId)
          .set({
        'imageUrl': imageUrl,
        'text1': _text1Controller.text,
        'text2': _text2Controller.text,
        'updatedAt': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(const SnackBar(content: Text('Saved successfully')));
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('Failed to save: $e')));
      }
    } finally {
      if (mounted) {
        setState(() => _isSaving = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    // This build method is correct, no changes needed
    ImageProvider? imageProvider;
    if (_image != null) {
      imageProvider = FileImage(_image!);
    } else if (_downloadUrl != null) {
      imageProvider = NetworkImage(_downloadUrl!);
    }

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
              onPressed: () => Navigator.pop(context),
            ),
            const Spacer(),
            Image.asset('assets/images/logo_text.png', height: 40),
            const Spacer(),
            Builder(
              builder: (context) => IconButton(
                icon: const Icon(Icons.menu, color: Color(0xFF1A237E)),
                onPressed: () => Scaffold.of(context).openDrawer(),
              ),
            ),
          ],
        ),
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(48),
          child: Padding(
            padding: const EdgeInsets.only(left: 16, bottom: 12, right: 16),
            child: Align(
              alignment: Alignment.centerLeft,
              child: Text(
                '${widget.className} > ${widget.examTitle} > ${widget.questionName}',
                style: const TextStyle(
                  fontWeight: FontWeight.bold,
                  color: Color(0xFF1A237E),
                  fontSize: 16,
                ),
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ),
        ),
      ),
      body: _isLoading
          ? const Center(
              child: CircularProgressIndicator(color: Color(0xFF1A237E)))
          : SingleChildScrollView(
              padding: const EdgeInsets.all(20),
              child: Column(
                children: [
                  GestureDetector(
                    onTap: _isOcrProcessing ? null : _pickImage,
                    child: Container(
                      height: 220,
                      width: double.infinity,
                      decoration: BoxDecoration(
                        color: Colors.grey[200],
                        borderRadius: BorderRadius.circular(16),
                        image: imageProvider != null
                            ? DecorationImage(
                                image: imageProvider,
                                fit: BoxFit.cover,
                              )
                            : null,
                      ),
                      child: _isOcrProcessing
                          ? const Center(
                              child: CircularProgressIndicator(
                                  valueColor: AlwaysStoppedAnimation<Color>(
                                      Color(0xFF1A237E))))
                          : (imageProvider == null
                              ? const Center(
                                  child: Icon(Icons.add_a_photo,
                                      size: 50, color: Colors.grey))
                              : null),
                    ),
                  ),
                  const SizedBox(height: 20),
                  TextField(
                    controller: _text1Controller,
                    decoration: const InputDecoration(
                      labelText: 'Extracted Text (OCR Result)',
                      border: OutlineInputBorder(),
                    ),
                    maxLines: null,
                  ),
                  const SizedBox(height: 16),
                  TextField(
                    controller: _text2Controller,
                    decoration: const InputDecoration(
                      labelText: 'Grade / Notes',
                      border: OutlineInputBorder(),
                    ),
                    maxLines: null,
                  ),
                  const SizedBox(height: 24),
                  ElevatedButton(
                    onPressed: _isSaving ? null : _saveData,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFF1A237E),
                      padding: const EdgeInsets.symmetric(
                          horizontal: 32, vertical: 14),
                      shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12)),
                    ),
                    child: _isSaving
                        ? const SizedBox(
                            height: 20,
                            width: 20,
                            child: CircularProgressIndicator(
                                strokeWidth: 2, color: Colors.white))
                        : const Text('Save',
                            style:
                                TextStyle(fontSize: 16, color: Colors.white)),
                  ),
                ],
              ),
            ),
    );
  }
}
