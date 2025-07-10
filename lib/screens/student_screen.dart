import 'dart:io';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:markly/models/student_model.dart';
import 'package:markly/widgets/custom_drawer.dart';

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
  final List<File> _pickedImages = [];
  final List<String> _imageUrls = [];
  final String userId = FirebaseAuth.instance.currentUser!.uid;

  @override
  void initState() {
    super.initState();
    _loadInitialData();
  }

  Future<void> _loadInitialData() async {
    // 1. Declare local variables.
    List<String> fetchedUrls = [];
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

      // 2. Fetch data into the local variable.
      if (docSnapshot.exists) {
        final data = docSnapshot.data();
        if (data != null && data.containsKey('imageUrls')) {
          final urls = List<dynamic>.from(data['imageUrls']);
          fetchedUrls.addAll(urls.map((e) => e.toString()));
        }
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed to load initial data: $e')),
        );
      }
    } finally {
      // 3. Use a single, final setState.
      if (mounted) {
        setState(() {
          _imageUrls.addAll(fetchedUrls);
          _isLoading = false;
        });
      }
    }
  }

  Future<void> _pickAndSaveImages() async {
    if (_isSaving) return;

    final picker = ImagePicker();
    final pickedFiles = await picker.pickMultiImage();

    if (pickedFiles.isEmpty) {
      return;
    }

    // 1. Isolate the newly picked files.
    final newImageFiles = pickedFiles.map((file) => File(file.path)).toList();

    // 2. Give immediate UI feedback for the new images.
    setState(() {
      _pickedImages.addAll(newImageFiles);
      _isSaving = true;
    });

    try {
      final List<String> newUrls = [];
      // Loop only over the newly picked files for uploading.
      for (final imageFile in newImageFiles) {
        final path =
            'student_answers/${userId}/${widget.examId}/${widget.student.id}/${DateTime.now().millisecondsSinceEpoch}.jpg';
        final ref = FirebaseStorage.instance.ref(path);
        await ref.putFile(imageFile);
        final url = await ref.getDownloadURL();
        newUrls.add(url);
      }

      if (newUrls.isNotEmpty) {
        final studentDocRef = FirebaseFirestore.instance
            .collection('users')
            .doc(userId)
            .collection('classes')
            .doc(widget.classId)
            .collection('exams')
            .doc(widget.examId)
            .collection('students')
            .doc(widget.student.id);

        await studentDocRef
            .update({'imageUrls': FieldValue.arrayUnion(newUrls)});

        // 3. Correctly transition state on success.
        setState(() {
          _imageUrls.addAll(newUrls);
          _pickedImages.clear(); // This is crucial.
        });
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
      // 6. Cleanup loading state.
      if (mounted) {
        setState(() {
          _isSaving = false;
        });
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
              child: ElevatedButton(
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFF1A237E),
                  foregroundColor: Colors.white,
                ),
                onPressed: _isSaving ? null : _pickAndSaveImages,
                child: _isSaving
                    ? const SizedBox(
                  width: 20,
                  height: 20,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    color: Colors.white,
                  ),
                )
                    : const Text('Add Answer Sheets'),
              ),
            ),
            const SizedBox(height: 16),
            Expanded(
              child: GridView.builder(
                gridDelegate:
                const SliverGridDelegateWithFixedCrossAxisCount(
                  crossAxisCount: 3,
                  crossAxisSpacing: 8,
                  mainAxisSpacing: 8,
                ),
                itemCount: _imageUrls.length + _pickedImages.length,
                itemBuilder: (context, index) {
                  Widget image;
                  if (index < _imageUrls.length) {
                    image = Image.network(_imageUrls[index],
                        fit: BoxFit.cover);
                  } else {
                    image = Image.file(
                        _pickedImages[index - _imageUrls.length],
                        fit: BoxFit.cover);
                  }
                  return ClipRRect(
                    borderRadius: BorderRadius.circular(8),
                    child: image,
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
