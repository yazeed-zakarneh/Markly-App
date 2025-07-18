import 'dart:io';
import 'dart:async';
import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:http_parser/http_parser.dart';

class ParsedQuestion {
  final String question;
  final String answer;
  ParsedQuestion({required this.question, required this.answer});
}

class OcrService {
  // Existing OCR API URL
  static const String _ocrApiUrl = 'https://omarabualrob-ocr-api.hf.space/ocr';

  // NEW: URL for the new enhancement API
  static const String _enhancementApiUrl = 'https://omarabualrob-enhancing-and-dividing-questions.hf.space/enhance-and-format';

  // NEW METHOD: Calls the enhancement API
  Future<String> enhanceOcrText(String rawText) async {
    final uri = Uri.parse(_enhancementApiUrl);
    final headers = {'Content-Type': 'application/json', 'accept': 'application/json'};
    final body = jsonEncode({'text': rawText});

    print("🚀 Sending Enhancement API Request...");

    try {
      final response = await http.post(uri, headers: headers, body: body)
          .timeout(const Duration(seconds: 60));

      if (response.statusCode == 200) {
        final responseBody = jsonDecode(response.body);
        final processedText = responseBody['processed_text'] as String?;
        if (processedText == null) {
          throw Exception("Enhancement API response is missing 'processed_text'.");
        }
        print("✅ Enhancement API Success.");
        return processedText;
      } else {
        throw Exception("Enhancement API failed with status: ${response.statusCode} - ${response.body}");
      }
    } on TimeoutException {
      throw Exception("Enhancement request timed out.");
    } catch (e) {
      print("Enhancement Service Error: $e");
      rethrow; // Pass the error up to the UI
    }
  }

  // UPDATED: This now parses the clean output from the enhancement API
  List<ParsedQuestion> extractQuestionsFromText(String processedText) {
    // The new delimiter is the literal string "Question: "
    final RegExp questionDelimiter = RegExp(r'(?=Question:)');
    final List<ParsedQuestion> parsedQuestions = [];

    // Split the entire text block by the "Question:" delimiter
    final questionBlocks = processedText.split(questionDelimiter);

    for (final block in questionBlocks) {
      final trimmedBlock = block.trim();
      if (trimmedBlock.isEmpty) continue; // Skip any empty splits

      // The answer is delimited by the literal string "\nAnswer: "
      final answerDelimiter = '\nAnswer: ';
      final answerIndex = trimmedBlock.indexOf(answerDelimiter);

      if (answerIndex != -1) {
        // The question is everything from the start up to the answer delimiter
        final String question = trimmedBlock.substring(0, answerIndex).trim();

        // The answer is everything after the delimiter
        final String answer = trimmedBlock.substring(answerIndex + answerDelimiter.length).trim();

        parsedQuestions.add(ParsedQuestion(question: question, answer: answer));
      }
    }
    return parsedQuestions;
  }

  // UNCHANGED: This method remains the same
  Future<String?> performOcr(File imageFile) async {
    final uri = Uri.parse(_ocrApiUrl);
    try {
      var request = http.MultipartRequest('POST', uri);
      request.files.add(
        await http.MultipartFile.fromPath('file', imageFile.path, contentType: MediaType('image', 'jpeg')),
      );
      var streamedResponse = await request.send();
      var response = await http.Response.fromStream(streamedResponse);
      if (response.statusCode == 200) {
        final Map<String, dynamic> responseBody = jsonDecode(response.body);
        return responseBody['text'] as String?;
      } else {
        throw Exception('Failed to load OCR data: ${response.statusCode}');
      }
    } catch (e) {
      print("OCR Service Error: $e");
      rethrow;
    }
  }
}