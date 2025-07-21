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
  static const String _ocrApiUrl = 'https://omarabualrob-ocr-api.hf.space/ocr';
  static const String _enhancementApiUrl = 'https://omarabualrob-enhancing-and-dividing-questions.hf.space/enhance-and-format';

  // This is the local function for cleaning raw multiple-choice text.
  String processRawMultipleChoiceText(String rawText) {
    print("--- Running Local MCQ Processing ---");
    final validAnswers = {'a', 'b', 'c', 'd'};
    final List<String> cleanedPairs = [];

    // Find all numbers in the text and their locations
    final numberMatches = RegExp(r'\d+').allMatches(rawText).toList();

    if (numberMatches.isEmpty) {
      return ""; // No numbers found, nothing to process
    }

    // Loop through each found number to find its corresponding answer
    for (int i = 0; i < numberMatches.length; i++) {
      final currentMatch = numberMatches[i];
      final String questionNumber = currentMatch.group(0)!;

      // Define the search space for the answer: from the end of the current number
      // to the start of the next number, or to the end of the string.
      final int searchStartIndex = currentMatch.end;
      final int searchEndIndex = (i + 1 < numberMatches.length)
          ? numberMatches[i + 1].start
          : rawText.length;

      final String searchArea = rawText.substring(searchStartIndex, searchEndIndex);

      // Find the first letter in the search area
      final letterMatch = RegExp(r'[a-zA-Z]').firstMatch(searchArea);

      String finalAnswer;
      if (letterMatch != null) {
        String foundLetter = letterMatch.group(0)!.toLowerCase();
        // If the found letter is valid, use it. Otherwise, default to 'a'.
        finalAnswer = validAnswers.contains(foundLetter) ? foundLetter : 'a';
      } else {
        // If no letter is found in the search area, default to 'a'.
        finalAnswer = 'a';
      }
      cleanedPairs.add('$questionNumber-$finalAnswer');
    }

    return cleanedPairs.join(', ');
  }

  // This function is for API-based enhancement of regular (non-MCQ) questions.
  Future<String> enhanceOcrText(String rawText) async {
    final uri = Uri.parse(_enhancementApiUrl);
    final headers = {'Content-Type': 'application/json', 'accept': 'application/json'};
    final body = jsonEncode({'text': rawText});

    print("🚀 Sending Enhancement API Request...");

    try {
      final response = await http.post(uri, headers: headers, body: body)
          .timeout(const Duration(seconds: 90));

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
      rethrow;
    }
  }

  // This function parses text that is already in the "Question: ... Answer: ..." format.
  List<ParsedQuestion> extractQuestionsFromText(String processedText) {
    final RegExp questionDelimiter = RegExp(r'(?=Question:)');
    final List<ParsedQuestion> parsedQuestions = [];
    final questionBlocks = processedText.split(questionDelimiter);

    for (final block in questionBlocks) {
      final trimmedBlock = block.trim();
      if (trimmedBlock.isEmpty) continue;

      final answerDelimiter = '\nAnswer: ';
      final answerIndex = trimmedBlock.indexOf(answerDelimiter);

      if (answerIndex != -1) {
        final String fullQuestionText = trimmedBlock.substring(0, answerIndex).trim();
        final String cleanedQuestion = fullQuestionText.replaceFirst('Question: ', '').trim();
        final String answer = trimmedBlock.substring(answerIndex + answerDelimiter.length).trim();

        parsedQuestions.add(ParsedQuestion(question: cleanedQuestion, answer: answer));
      }
    }
    return parsedQuestions;
  }

  // This is the initial OCR function to get raw text from an image.
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