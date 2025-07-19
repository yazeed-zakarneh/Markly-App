import 'dart:io';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_storage/firebase_storage.dart';
import '../widgets/custom_drawer.dart';

class ProfileScreen extends StatefulWidget {
  const ProfileScreen({super.key});

  @override
  State<ProfileScreen> createState() => _ProfileScreenState();
}

class _ProfileScreenState extends State<ProfileScreen> {
  User? _currentUser;
  File? _selectedImageFile;

  final TextEditingController _nameDisplayController = TextEditingController();
  final TextEditingController _emailDisplayController = TextEditingController();

  late TextEditingController _dialogNameController;
  File? _dialogSelectedImageFile;

  @override
  void initState() {
    super.initState();
    _currentUser = FirebaseAuth.instance.currentUser;
    _initializeUserInfo();
  }

  @override
  void dispose() {
    _nameDisplayController.dispose();
    _emailDisplayController.dispose();
    super.dispose();
  }

  void _initializeUserInfo() {
    if (_currentUser != null) {
      _nameDisplayController.text = _currentUser!.displayName ?? 'No Name Set';
      _emailDisplayController.text = _currentUser!.email ?? 'No Email';
    }
  }

  void _showUpdateProfileDialog() {
    _dialogNameController = TextEditingController(text: _currentUser?.displayName ?? '');
    _dialogSelectedImageFile = null; // Reset for dialog; will be set if user picks anew

    bool isLoading = false;

    showDialog(
      context: context,
      builder: (_) => Dialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        child: SingleChildScrollView(
          child: Padding(
            padding: const EdgeInsets.all(20),
            child: StatefulBuilder(
              builder: (context, setDialogState) => Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Text(
                    "Update Profile",
                    style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: Color(0xFF1A237E)),
                  ),
                  const SizedBox(height: 16),
                  GestureDetector(
                    onTap: () async {
                      final picker = ImagePicker();
                      final picked = await picker.pickImage(source: ImageSource.gallery);
                      if (picked != null) {
                        setDialogState(() {
                          _dialogSelectedImageFile = File(picked.path);
                        });
                      }
                    },
                    child: CircleAvatar(
                      radius: 45,
                      backgroundImage: _dialogSelectedImageFile != null
                          ? FileImage(_dialogSelectedImageFile!)
                          : (_currentUser?.photoURL != null
                          ? NetworkImage(_currentUser!.photoURL!)
                          : null) as ImageProvider<Object>?,
                      child: _dialogSelectedImageFile == null && _currentUser?.photoURL == null
                          ? const Icon(Icons.camera_alt, size: 40)
                          : null,
                    ),
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: _dialogNameController,
                    decoration: const InputDecoration(labelText: 'Name'),
                  ),
                  const SizedBox(height: 20),
                  if (isLoading)
                    const Center(child: CircularProgressIndicator())
                  else
                    Row(
                      mainAxisAlignment: MainAxisAlignment.end,
                      children: [
                        OutlinedButton(
                          style: OutlinedButton.styleFrom(
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.all(Radius.circular(10))),
                            side: BorderSide(color: Color(0xFF1A237E)),
                          ),
                          onPressed: () => Navigator.pop(context),
                          child: const Text("Cancel", style: TextStyle(color: Color(0xFF1A237E))),
                        ),
                        const SizedBox(width: 8),
                        ElevatedButton(
                          style: ElevatedButton.styleFrom(
                            backgroundColor: Color(0xFF1A237E),
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.all(Radius.circular(10))),
                          ),
                          onPressed: () async {
                            setDialogState(() => isLoading = true);
                            try {
                              if (_currentUser == null) {
                                throw Exception("User not signed in.");
                              }

                              final newName = _dialogNameController.text.trim();
                              bool nameChanged = newName != (_currentUser!.displayName ?? '');

                              if (nameChanged && newName.isNotEmpty) {
                                await _currentUser!.updateDisplayName(newName);
                              }

                              String? newPhotoUrl;
                              if (_dialogSelectedImageFile != null) {
                                if (_dialogSelectedImageFile!.existsSync()) {
                                  final storageRef = FirebaseStorage.instance
                                      .ref()
                                      .child('user_profiles')
                                      .child('${_currentUser!.uid}.jpg');

                                  await storageRef.putFile(_dialogSelectedImageFile!);
                                  newPhotoUrl = await storageRef.getDownloadURL();
                                  await _currentUser!.updatePhotoURL(newPhotoUrl);
                                }
                              }

                              await _currentUser!.reload();
                              _currentUser = FirebaseAuth.instance.currentUser;

                              setState(() {
                                _nameDisplayController.text = _currentUser!.displayName ?? 'No Name Set';
                                _emailDisplayController.text = _currentUser!.email ?? 'No Email';
                                _selectedImageFile = null;
                              });

                              Navigator.pop(context);
                              ScaffoldMessenger.of(context).showSnackBar(
                                const SnackBar(content: Text('Profile updated successfully!')),
                              );

                            } catch (e) {
                              Navigator.pop(context);
                              ScaffoldMessenger.of(context).showSnackBar(
                                SnackBar(
                                  content: Text("Failed to update profile: $e"),
                                  backgroundColor: Colors.red,
                                ),
                              );
                            } finally {
                              setDialogState(() => isLoading = false);
                            }
                          },
                          child: const Text("Save",style: TextStyle(color: Colors.white)),
                        ),
                      ],
                    ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    ImageProvider<Object>? profileImageProvider;
    if (_currentUser?.photoURL != null) {
      profileImageProvider = NetworkImage(_currentUser!.photoURL!);
    }

    return Scaffold(
      backgroundColor: Colors.white,
      // Add the CustomDrawer to the Scaffold
      endDrawer: CustomDrawer(onClose: () => Navigator.pop(context)), // Assuming CustomDrawer is imported
      appBar: AppBar(
        backgroundColor: Colors.white,
        elevation: 0,
        title: Text(
          'Profile',
          style: TextStyle(
            fontSize: 18,
            color: Color(0xFF1A237E),
            fontWeight: FontWeight.bold,
          ),
        ),
        centerTitle: true,
      ),
      body: SingleChildScrollView(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 24.0),
          child: Column(
            children: [
              const SizedBox(height: 20),
              Stack(
                alignment: Alignment.center,
                children: [
                  CircleAvatar(
                    radius: 55,
                    backgroundColor: const Color(0xFFE0E0E0),
                    backgroundImage: profileImageProvider,
                    child: profileImageProvider == null
                        ? const Icon(Icons.person, size: 70, color: Colors.black54)
                        : null,
                  ),
                ],
              ),
              const SizedBox(height: 32),
              const Align(
                alignment: Alignment.centerLeft,
                child: Text("Name", style: TextStyle(fontWeight: FontWeight.bold)),
              ),
              const SizedBox(height: 6),
              TextFormField(
                controller: _nameDisplayController,
                readOnly: true,
                decoration: InputDecoration(
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
                ),
              ),
              const SizedBox(height: 20),
              const Align(
                alignment: Alignment.centerLeft,
                child: Text("Email", style: TextStyle(fontWeight: FontWeight.bold)),
              ),
              const SizedBox(height: 6),
              TextFormField(
                controller: _emailDisplayController,
                readOnly: true,
                decoration: InputDecoration(
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
                ),
              ),
              const SizedBox(height: 30),
              SizedBox(
                width: double.infinity,
                child: ElevatedButton(
                  onPressed: _showUpdateProfileDialog,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFF1A237E),
                    padding: const EdgeInsets.symmetric(vertical: 14),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                  ),
                  child: const Text("Update Profile", style: TextStyle(fontSize: 16, color: Colors.white)),
                ),
              ),
              const SizedBox(height: 20),
            ],
          ),
        ),
      ),
    );
  }
}