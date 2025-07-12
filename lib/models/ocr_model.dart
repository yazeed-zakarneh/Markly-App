import 'dart:io';
import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:http_parser/http_parser.dart';

// A data class to hold a parsed question and its answer.
class ParsedQuestion {
  final String question;
  final String answer;

  ParsedQuestion({required this.question, required this.answer});
}

// A service class to handle all OCR-related operations.
class OcrService {
  static const String _ocrApiUrl = 'https://omarabualrob-ocr-api.hf.space/ocr';

  /// Takes raw OCR text and extracts questions based on the "Q#) ... ?" format.
  List<ParsedQuestion> extractQuestionsFromText(String rawText) {
    // This regex now includes 'O' to catch common OCR errors for 'Q'.
    final RegExp questionStartDelimiter = RegExp(r'(?=[QqOo]\d+\))');

    final List<ParsedQuestion> parsedQuestions = [];
    final singleLineText = rawText.replaceAll('\n', ' ').trim();
    final potentialQuestionBlocks = singleLineText.split(questionStartDelimiter);

    for (final block in potentialQuestionBlocks) {
      final trimmedBlock = block.trim();
      if (trimmedBlock.isEmpty) continue;

      final questionMarkIndex = trimmedBlock.indexOf('?');
      if (questionMarkIndex != -1) {
        final String question = trimmedBlock.substring(0, questionMarkIndex + 1).trim();
        final String answer = trimmedBlock.substring(questionMarkIndex + 1).trim();
        parsedQuestions.add(
            ParsedQuestion(question: question, answer: answer)
        );
      }
    }
    return parsedQuestions;
  }

  /// Performs OCR on an image file and returns the raw text.
  Future<String?> performOcr(File imageFile) async {
    final uri = Uri.parse(_ocrApiUrl);
    try {
      var request = http.MultipartRequest('POST', uri);
      request.files.add(
        await http.MultipartFile.fromPath(
          'file',
          imageFile.path,
          contentType: MediaType('image', 'jpeg'),
        ),
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