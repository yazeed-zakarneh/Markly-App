

class Student {
  final String id;
  final String name;
  final String studentId;

  const Student({
    required this.id,
    required this.name,
    required this.studentId,
  });

  factory Student.fromMap(Map<String, dynamic> map, String documentId) {
    return Student(
      id: documentId,
      name: map['name'] as String,
      studentId: map['studentId'] as String,
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'name': name,
      'studentId': studentId,
    };
  }
}