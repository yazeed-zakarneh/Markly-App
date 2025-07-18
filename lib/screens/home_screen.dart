import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import '../dialogs/add_class_dialog.dart';
import '../dialogs/change_photo_dialog.dart';
import 'exam_list_screen.dart';
import '../widgets/custom_drawer.dart';

class HomeScreen extends StatelessWidget {
  const HomeScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final String userId = FirebaseAuth.instance.currentUser!.uid;

    return Scaffold(
      backgroundColor: Colors.white,
      drawer: CustomDrawer(onClose: () => Navigator.pop(context)),
      appBar: AppBar(
        automaticallyImplyLeading: false,
        backgroundColor: Colors.white,
        elevation: 0,
        title: Stack(
          alignment: Alignment.center,
          children: [
            Center(child: Image.asset('assets/images/logo_text.png', height: 40)),
            Positioned(
              right: 0,
              child: Builder(
                builder: (context) => IconButton(
                  icon: const Icon(Icons.menu, color: Color(0xFF1A237E)),
                  onPressed: () => Scaffold.of(context).openDrawer(),
                ),
              ),
            ),
          ],
        ),
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: () {
          showDialog(
            context: context,
            builder: (context) => const AddClassDialog(),
          );
        },
        backgroundColor: const Color(0xFF1A237E),
        child: const Icon(Icons.add, color: Colors.white),
      ),
      body: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            /// Search
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              decoration: BoxDecoration(
                color: Colors.grey[200],
                borderRadius: BorderRadius.circular(30),
              ),
              child: const TextField(
                decoration: InputDecoration(
                  hintText: 'Search',
                  border: InputBorder.none,
                  icon: Icon(Icons.search),
                ),
              ),
            ),
            const SizedBox(height: 20),

            /// Class List
            Expanded(
              child: StreamBuilder<QuerySnapshot>(
                stream: FirebaseFirestore.instance
                    .collection('users')
                    .doc(userId)
                    .collection('classes')
                    .orderBy('createdAt', descending: true)
                    .snapshots(),
                builder: (context, snapshot) {
                  if (snapshot.connectionState == ConnectionState.waiting) {
                    return const Center(child: CircularProgressIndicator());
                  }

                  if (!snapshot.hasData || snapshot.data!.docs.isEmpty) {
                    return const Center(child: Text('No courses yet.'));
                  }

                  return ListView(
                    children: snapshot.data!.docs.map((doc) {
                      final data = doc.data() as Map<String, dynamic>;
                      final classId = doc.id;
                      final className = data['name'] ?? 'Unnamed Course';
                      final imageUrl = data['imageUrl'] == 'default'
                          ? 'assets/images/logo.png'
                          : data['imageUrl'];

                      return SubjectCard(
                        title: className,
                        imagePath: imageUrl,
                        classId: classId,
                        userId: userId,
                        onTap: () {
                          Navigator.push(
                            context,
                            MaterialPageRoute(
                              builder: (_) => ExamListScreen(
                                classId: classId,
                                className: className,
                              ),
                            ),
                          );
                        },
                      );
                    }).toList(),
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class SubjectCard extends StatelessWidget {
  final String title;
  final String imagePath;
  final String classId;
  final String userId;
  final VoidCallback onTap;

  const SubjectCard({
    super.key,
    required this.title,
    required this.imagePath,
    required this.classId,
    required this.userId,
    required this.onTap,
  });

  void _showDeleteDialog(BuildContext context) async {
    final shouldDelete = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Delete Course', style: TextStyle(color: Color(0xFF1A237E)),),
        content: const Text('Are you sure you want to delete this course?', style: TextStyle(color: Colors.red,),),
        actions: [
          OutlinedButton(
            style: OutlinedButton.styleFrom(
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.all(Radius.circular(10))),
              side: BorderSide(color: Color(0xFF1A237E)),
            ),
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel', style: TextStyle(color: Color(0xFF1A237E)),),
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
          .collection('users')
          .doc(userId)
          .collection('classes')
          .doc(classId)
          .delete();

      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Course deleted')),
      );
    }
  }

  void _showRenameDialog(BuildContext context) {
    final controller = TextEditingController(text: title);

    showDialog(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text("Rename Course", style: TextStyle(color: Color(0xFF1A237E))),
        content: TextField(
          controller: controller,
          decoration: const InputDecoration(labelText: "New course Name"),
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
            style: ElevatedButton.styleFrom(
              backgroundColor: Color(0xFF1A237E),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.all(Radius.circular(10))),
            ),
            onPressed: () async {
              final newName = controller.text.trim();
              if (newName.isNotEmpty) {
                await FirebaseFirestore.instance
                    .collection('users')
                    .doc(userId)
                    .collection('classes')
                    .doc(classId)
                    .update({'name': newName});
              }
              Navigator.pop(context);
            },
            child: const Text("Save",style: TextStyle(color: Colors.white)),
          ),
        ],
      ),
    );
  }

  void _openChangePhotoDialog(BuildContext context) {
    showDialog(
      context: context,
      builder: (_) => ChangePhotoDialog(
        userId: userId,
        classId: classId,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final bool isNetworkImage = imagePath.startsWith('http');

    return GestureDetector(
      onTap: onTap,
      child: Card(
        elevation: 2,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        margin: const EdgeInsets.only(bottom: 16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            /// Image
            ClipRRect(
              borderRadius: const BorderRadius.vertical(top: Radius.circular(16)),
              child: isNetworkImage
                  ? Image.network(imagePath, fit: BoxFit.cover, height: 160, width: double.infinity)
                  : Image.asset(imagePath, fit: BoxFit.cover, height: 160, width: double.infinity),
            ),

            /// Title + 3-dot button
            Padding(
              padding: const EdgeInsets.all(12.0),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  /// Title
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(title, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
                        const SizedBox(height: 4),
                        const Text("Exams: #", style: TextStyle(color: Colors.grey, fontSize: 14)),
                      ],
                    ),
                  ),

                  /// Menu Button
                  PopupMenuButton<String>(
                    icon: const Icon(Icons.more_vert),
                    onSelected: (value) {
                      if (value == 'rename') {
                        _showRenameDialog(context);
                      } else if (value == 'photo') {
                        _openChangePhotoDialog(context);
                      } else if (value == 'delete') {
                        _showDeleteDialog(context);
                      }
                    },
                    itemBuilder: (context) => [
                      const PopupMenuItem<String>(
                        value: 'rename',
                        child: Text('Rename'),
                      ),
                      const PopupMenuItem<String>(
                        value: 'photo',
                        child: Text('Change Photo'),
                      ),
                      const PopupMenuItem<String>(
                        value: 'delete',
                        child: Text('Delete', style: TextStyle(color: Colors.red)),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}