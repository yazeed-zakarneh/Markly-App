import 'dart:convert';
import 'package:http/http.dart' as http;

class GradingService {
  Future<double> gradeAnswer({
    required String question,
    required String keyAnswer,
    required String studentAnswer,
  }) async {
    // Your correct API URL
    final uri = Uri.parse('http://213.192.2.92:40053/grade');

    try {
      final response = await http.post(
        uri,
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({
          'question': question,
          'key_answer': keyAnswer,
          'student_answer': studentAnswer,
        }),
      );

      // --- NEW RESPONSE HANDLING LOGIC ---
      if (response.statusCode == 200) {
        final responseBody = jsonDecode(response.body);

        // This print statement is very useful for debugging, let's keep it.
        print("✅ Grading API Success Response Body: $responseBody");

        // The key from your example is 'score'.
        final dynamic scoreValue = responseBody['score'];

        if (scoreValue == null) {
          throw Exception("API response is successful but is missing the 'score' key.");
        }

        // Handle if the score is already a number (best case).
        if (scoreValue is num) {
          return scoreValue.toDouble();
        }
        // Handle if the score is a string that can be converted to a number.
        else if (scoreValue is String) {
          final parsedScore = double.tryParse(scoreValue);
          if (parsedScore != null) {
            return parsedScore;
          }
        }

        // If it's neither a number nor a parsable string, throw an error.
        throw Exception("API returned an invalid score format (Value was: '$scoreValue').");

      } else {
        // This is how your example handles errors, which is good.
        // It provides the status code and the server's error message.
        throw Exception("Grading API failed with status: ${response.statusCode} - ${response.body}");
      }
      // --- END OF NEW LOGIC ---

    } catch (e) {
      print("Grading Service Error: $e");
      rethrow; // Rethrow the exception so the UI layer can display the error message.
    }
  }
}