import 'package:flutter/material.dart';
import '../widgets/custom_drawer.dart';
import '../tabs/questions_tab.dart';
import '../tabs/students_tab.dart';

class QuestionsScreen extends StatelessWidget {
  final String className;
  final String examTitle;
  final String classId;
  final String examId;

  const QuestionsScreen({
    super.key,
    required this.className,
    required this.examTitle,
    required this.classId,
    required this.examId,
  });

  @override
  Widget build(BuildContext context) {
    return DefaultTabController(
      length: 2,
      child: Scaffold(
        backgroundColor: Colors.white,
        endDrawer: CustomDrawer(onClose: () => Navigator.pop(context)),
        appBar: AppBar(
          backgroundColor: Colors.white,
          elevation: 0,
          title: Image.asset(
            'assets/images/logo_text.png', // Make sure this asset is correctly added
            height: 40,
          ),
          centerTitle: true,
          bottom: PreferredSize(
            preferredSize: const Size.fromHeight(96),
            child: Column(
              children: [
                const SizedBox(height: 8),
                Container(
                  alignment: Alignment.centerLeft,
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
                  child: Text(
                    '$className - $examTitle',
                    style: const TextStyle(
                      color: Color(0xFF1A237E),
                      fontWeight: FontWeight.bold,
                      fontSize: 16,
                    ),
                  ),
                ),


                const TabBar(
                  indicatorColor: Color(0xFF1A237E),
                  labelColor: Color(0xFF1A237E),
                  unselectedLabelColor: Colors.grey,
                  labelStyle: TextStyle(fontWeight: FontWeight.bold),
                  tabs: [
                    Tab(
                      icon: Icon(Icons.help),
                        text: 'Questions'
                    ),
                    Tab(
                      icon: Icon(Icons.people_alt_rounded),
                        text: 'Students'
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
        body: TabBarView(
          children: [
            QuestionsTab(classId: classId, examId: examId, className: className,
              examTitle: examTitle,),
            StudentsTab(classId: classId, examId: examId, className: className,
                examTitle: examTitle),
          ],
        ),
      ),
    );
  }
}

