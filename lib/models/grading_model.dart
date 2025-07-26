import 'dart:async';
import 'dart:convert';
import 'package:http/http.dart' as http;

class GradingService {
  Future<double> gradeAnswer({
    required String question,
    required String keyAnswer,
    required String studentAnswer,
  }) async {
    final uri = Uri.parse('http://213.192.2.118:40151/grade');

    try {

      final headers = {'Content-Type': 'application/json'};
      final body = jsonEncode({
        'question': question,
        'key_answer': keyAnswer,
        'student_answer': studentAnswer,
      });

      final response = await http
          .post(
        uri,
        headers: headers,
        body: body,
      )
          .timeout(const Duration(seconds: 60));

      if (response.statusCode == 200) {
        final responseBody = jsonDecode(response.body);

        final dynamic scoreValue = responseBody['score'];
        if (scoreValue == null) {
          throw Exception("API response is successful but is missing the 'score' key.");
        }
        if (scoreValue is num) {
          return scoreValue.toDouble();
        } else if (scoreValue is String) {
          final parsedScore = double.tryParse(scoreValue);
          if (parsedScore != null) {
            return parsedScore;
          }
        }
        throw Exception("API returned an invalid score format (Value was: '$scoreValue').");
      } else {
        throw Exception("Grading API failed with status: ${response.statusCode} - ${response.body}");
      }
    } on TimeoutException {
      throw Exception("Grading request timed out. Please check your network connection and try again.");
    } catch (e) {
      rethrow;
    }
  }
}