import 'package:flutter/material.dart';

// Use ChangeNotifier for data model, listening to app state and trigger ui rebuilds.
class LLMModel with ChangeNotifier {
  bool _isStreamingText = false;
  bool _isFirstVisit = true;
  // Check for history on local storage on every load and toggle flag.
  bool _isEmptyResponse = true;
  late int _latestResponseTimestamp;
  late int _humanMessageTimestamp;
  String _latestResponse = "●";
  late String _llmAIMessage;
  late String _llmHumanMessage;

  bool get isStreamingText => _isStreamingText;
  bool get isFirstVisit => _isFirstVisit;
  bool get isEmptyResponse => _isEmptyResponse;
  int get latestResponseTimestamp => _latestResponseTimestamp;
  String get latestResponse => _latestResponse;
  int get humanMessageTimestamp => _humanMessageTimestamp;
  String get llmAIMessage => _llmAIMessage;
  String get llmHumanMessage => _llmHumanMessage;

  set isStreamingText(bool value) {
    _isStreamingText = value;
    notifyListeners();
  }

  set isFirstVisit(bool value) {
    _isFirstVisit = value;
    notifyListeners();
  }

  set isEmptyResponse(bool value) {
    _isEmptyResponse = value;
    notifyListeners();
  }

  set latestResponseTimestamp(int value) {
    _latestResponseTimestamp = value;
    notifyListeners();
  }

  set latestResponse(String value) {
    _latestResponse = value;
    notifyListeners();
  }

  set llmAIMessage(String value) {
    _llmAIMessage = value;
    notifyListeners();
  }

  set humanMessageTimestamp(int value) {
    _humanMessageTimestamp = value;
    notifyListeners();
  }

  set llmHumanMessage(String value) {
    _llmHumanMessage = value;
    notifyListeners();
  }
}
