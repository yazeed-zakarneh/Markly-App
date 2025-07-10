import 'dart:io';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:cloud_firestore/cloud_firestore.dart';

class AddClassDialog extends StatefulWidget {
  const AddClassDialog({super.key});

  @override
  State<AddClassDialog> createState() => _AddClassDialogState();
}

class _AddClassDialogState extends State<AddClassDialog> {
  final TextEditingController classNameController = TextEditingController();
  File? selectedImage;
  bool isLoading = false;

  Future<void> pickImage() async {
    final picker = ImagePicker();
    final picked = await picker.pickImage(source: ImageSource.gallery);

    if (picked != null) {
      setState(() {
        selectedImage = File(picked.path);
      });
    }
  }

  Future<void> saveClass() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null || classNameController.text.trim().isEmpty) return;

    setState(() => isLoading = true);

    String? imageUrl;

    try {
      // Upload image to Firebase Storage
      if (selectedImage != null) {
        final ref = FirebaseStorage.instance
            .ref('class_images/${user.uid}/${DateTime.now().millisecondsSinceEpoch}.jpg');
        await ref.putFile(selectedImage!);
        imageUrl = await ref.getDownloadURL();
      }

      // Save class info to Firestore
      await FirebaseFirestore.instance
          .collection('users')
          .doc(user.uid)
          .collection('classes')
          .add({
        'name': classNameController.text.trim(),
        'imageUrl': imageUrl ?? 'default', // You can replace 'default' with a default asset later
        'createdAt': Timestamp.now(),
      });

      Navigator.pop(context);
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text("Failed to add course")),
      );
    } finally {
      setState(() => isLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Dialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text("Add Course", style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
            const SizedBox(height: 16),

            TextField(
              controller: classNameController,
              decoration: const InputDecoration(
                hintText: 'Course Name',
                border: OutlineInputBorder(
                    borderRadius: BorderRadius.all(Radius.circular(10))),
              ),
            ),
            const SizedBox(height: 16),

            GestureDetector(
              onTap: pickImage,
              child: Container(
                height: 120,
                width: double.infinity,
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(color: Colors.blue.shade200),
                ),
                child: selectedImage != null
                    ? ClipRRect(
                  borderRadius: BorderRadius.circular(10),
                  child: Image.file(selectedImage!, fit: BoxFit.cover),
                )
                    : Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: const [
                    Icon(Icons.cloud_upload_outlined, size: 32, color: Colors.blue),
                    SizedBox(height: 8),
                    Text('Tap to select image'),
                    Text('Supports .jpg/.png', style: TextStyle(fontSize: 12, color: Colors.grey)),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 20),

            Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                OutlinedButton(

                  onPressed: () => Navigator.pop(context),
                  child: const Text("Cancel", ),
                ),
                const SizedBox(width: 8),
                ElevatedButton(

                  onPressed: isLoading ? null : saveClass,
                  child: isLoading
                      ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                      : const Text("Save",),
                ),
                
              ],
            ),
          ],
        ),
      ),
    );
  }
}
