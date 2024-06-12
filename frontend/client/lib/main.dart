import 'dart:convert';
import 'dart:html' as html;
import 'dart:js' as js;
import 'dart:js_interop' as js_interop;

import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_web_plugins/flutter_web_plugins.dart';
import 'package:hive/hive.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:provider/provider.dart';
import 'package:web/web.dart' as web;

import "package:client/models/state_models.dart";
import "package:client/configuration_web_mobile.dart";
import "package:client/gen/request.dart";
import "package:client/gen/response.dart";

// TODO: render conversation history
// TODO: render AIMessage
// TODO: create HumanMessage, AIMessage json models

Future<void> main() async {
  await Hive.initFlutter();
  // Do not need to call `Hive.close()` on app exit.
  await Hive.openBox('history');

  runApp(
    MultiProvider(
      providers: <ChangeNotifierProvider<ChangeNotifier>>[
        ChangeNotifierProvider<LLMModel>(
          create: (BuildContext context) => LLMModel(),
        ),
      ],
      child: Client(),
    ),
  );
}

class Client extends StatelessWidget {
  const Client({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(home: HomePage());
  }
}

class HomePage extends StatefulWidget {
  const HomePage({super.key});

  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> {
  final TextEditingController _promptTextEditingController =
      TextEditingController(text: '');
  final FocusNode _promptFocusNode =
      FocusNode(debugLabel: 'textFieldFocusNode');
  ScrollController _scrollController = ScrollController();
  bool _isLoading = false;
  bool _isInitialized = false;
  // Load from local secure store to runtime.
  final Box encryptedChatHistoryBox = Hive.box<dynamic>('history');

  final LLMModel llmDataModel = LLMModel();

  final navigator = html.window.navigator;

  @override
  void dispose() {
    _promptTextEditingController.dispose();
    _scrollController.dispose();
    _promptFocusNode.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final Size size = MediaQuery.sizeOf(context);
    final Orientation orientation = MediaQuery.orientationOf(context);
    final TextTheme textTheme = Theme.of(context).textTheme;
    final ColorScheme colorScheme = Theme.of(context).colorScheme;

    return Scaffold(
      body: LayoutBuilder(
          builder: (BuildContext context, BoxConstraints constraints) {
        return Column(
          mainAxisAlignment: MainAxisAlignment.start,
          children: <Widget>[
            // Conversation history.
            SizedBox(
                key: const Key('conversationHistoryContainerMobile'),
                width: size.width,
                // Necessary to set constraints.
                height: outputContainerHeightMobile(
                  size: size,
                  orientation: orientation,
                ),
                child: Container(
                  alignment: Alignment.topLeft,
                  decoration: const BoxDecoration(
                    color: Colors.transparent,
                  ),
                  child: llmDataModel.isFirstVisit
                      ? promptHintsContainer(textTheme: textTheme)
                      : generatedTextContainer(
                          size: size,
                          context: context,
                          orientation: orientation,
                          textTheme: textTheme,
                        ),
                )),
            // Text input.
            Padding(
                padding: const EdgeInsets.symmetric(horizontal: 8),
                child: SizedBox(
                  width: constraints.maxWidth,
                  height: size.height * 0.18,
                  child: TextFormField(
                    controller: _promptTextEditingController,
                    focusNode: _promptFocusNode,
                    readOnly: _isLoading ? true : false,
                    autovalidateMode: AutovalidateMode.onUserInteraction,
                    minLines: null,
                    maxLines:
                        null, // [maxLines,minLines] must both be null when expands is true
                    expands: true,
                    textInputAction: TextInputAction.newline,
                    keyboardType: TextInputType.multiline,
                    cursorWidth: 6.0,
                    textAlignVertical: TextAlignVertical.bottom,
                    decoration: InputDecoration(
                      isDense: true,
                      contentPadding: const EdgeInsets.all(8),
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(8),
                      ),
                      enabledBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(8),
                        borderSide: BorderSide(
                          color: colorScheme.secondary,
                        ),
                      ),
                      focusedBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(8),
                          borderSide: BorderSide(
                            color: colorScheme.secondary,
                          )),
                      helperText: ' ',
                      errorText: null,
                      suffixIcon: Padding(
                          padding: const EdgeInsets.only(right: 0, left: 0),
                          child: IconButton(
                            icon: const Icon(Icons.autorenew),
                            iconSize: 16,
                            splashRadius: 0.2,
                            color: colorScheme.secondary,
                            tooltip: 'Generate',
                            padding: const EdgeInsets.all(0),
                            onPressed: () async {
                              setState(() {
                                llmDataModel.isFirstVisit = false;
                              });
                              _promptFocusNode.unfocus();
                              await runLLMInference(
                                  human_message: _promptTextEditingController
                                      .text
                                      .toString());
                            },
                          )),
                    ),
                    maxLengthEnforcement: MaxLengthEnforcement.enforced,
                    validator: null,
                  ),
                )),
            // Warning text.
            Padding(
                padding: const EdgeInsets.symmetric(horizontal: 8),
                child: SizedBox(
                    child: Text(
                  "Llama3 can produce inaccurate results. Verify with trusted sources.",
                  style: textTheme.bodyLarge
                      ?.copyWith(color: Colors.blueGrey.shade400),
                ))),
          ],
        );
      }),
    );
  }

  double outputContainerHeightMobile(
      {required Size size, required Orientation orientation}) {
    switch (size.width.toInt()) {
      case <= windowCompactSmall:
        return size.height * 0.20;
      case <= windowCompactMedium:
        return size.height * 0.20;
      // Pixel 7 Portrait mode only. Focus on this dimension.
      case <= windowCompactLarge:
        return size.height * 0.76;
      default:
        return size.height * 0.35;
    }
  }

  Widget promptHintsContainer({required TextTheme textTheme}) {
    return Center(
        key: const Key('PromptHints'),
        child: SingleChildScrollView(
            child: Column(
          mainAxisAlignment: MainAxisAlignment.spaceEvenly,
          crossAxisAlignment: CrossAxisAlignment.center,
          children: <Widget>[
            // Content generation.
            Column(children: [
              Padding(
                  padding: const EdgeInsets.only(top: 8, bottom: 8),
                  child: Text(
                    'Content Generation',
                    style: textTheme.titleLarge,
                  )),
              SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  child: Row(
                    children: <Widget>[
                      Align(
                          alignment: Alignment.center,
                          child: Padding(
                              padding:
                                  const EdgeInsets.symmetric(horizontal: 8),
                              child: OutlinedButton(
                                  onPressed: () {
                                    _promptFocusNode.requestFocus();
                                    _promptTextEditingController.text =
                                        blurbPromptHint;
                                  },
                                  child: Text(
                                    "Write a blurb about this new",
                                    overflow: TextOverflow.ellipsis,
                                    style: textTheme.bodyLarge,
                                  )))),
                      Align(
                          alignment: Alignment.center,
                          child: Padding(
                              padding:
                                  const EdgeInsets.symmetric(horizontal: 8),
                              child: OutlinedButton(
                                  onPressed: () {
                                    _promptFocusNode.requestFocus();
                                    _promptTextEditingController.text =
                                        emailPromptHint;
                                  },
                                  child: Text(
                                    "Craft an email to colleague",
                                    overflow: TextOverflow.ellipsis,
                                    style: textTheme.bodyLarge,
                                  )))),
                      Align(
                          alignment: Alignment.center,
                          child: Padding(
                              padding:
                                  const EdgeInsets.symmetric(horizontal: 8),
                              child: OutlinedButton(
                                  onPressed: () {
                                    _promptFocusNode.requestFocus();
                                    _promptTextEditingController.text =
                                        scifiPromptHint;
                                  },
                                  child: Text(
                                    "In the neon-lit underbelly",
                                    overflow: TextOverflow.ellipsis,
                                    style: textTheme.bodyLarge,
                                  )))),
                    ],
                  )),
            ]),
            // Brainstorming | tools.
            Column(children: <Widget>[
              Padding(
                  padding: const EdgeInsets.only(top: 8, bottom: 8),
                  child: Text(
                    'Brainstorm | Tools',
                    style: textTheme.titleLarge,
                  )),
              SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  child: Row(children: <Widget>[
                    // Brainstorm hint.
                    Align(
                        alignment: Alignment.center,
                        child: Padding(
                            padding: const EdgeInsets.symmetric(horizontal: 8),
                            child: OutlinedButton(
                                onPressed: () {
                                  _promptFocusNode.requestFocus();
                                  _promptTextEditingController.text =
                                      brainstormPromptHint;
                                },
                                child: Text(
                                  "Give me a list of",
                                  overflow: TextOverflow.ellipsis,
                                  style: textTheme.bodyLarge,
                                )))),
                    // Tool-Math hint.
                    Align(
                        alignment: Alignment.center,
                        child: Padding(
                            padding: const EdgeInsets.symmetric(horizontal: 8),
                            child: OutlinedButton(
                                onPressed: () {
                                  _promptFocusNode.requestFocus();
                                  _promptTextEditingController.text =
                                      toolMathPromptHint;
                                },
                                child: Text(
                                  "Math",
                                  overflow: TextOverflow.ellipsis,
                                  style: textTheme.bodyLarge,
                                )))),
                    // Tool-Search hint.
                    Align(
                        alignment: Alignment.center,
                        child: Padding(
                            padding: const EdgeInsets.symmetric(horizontal: 8),
                            child: OutlinedButton(
                                onPressed: () {
                                  _promptFocusNode.requestFocus();
                                  _promptTextEditingController.text =
                                      toolSearchPromptHint;
                                },
                                child: Text(
                                  "Search",
                                  overflow: TextOverflow.ellipsis,
                                  style: textTheme.bodyLarge,
                                )))),
                  ])),
            ]),
            // Open|closed QA.
            Column(children: <Widget>[
              Padding(
                  padding: const EdgeInsets.only(top: 8, bottom: 8),
                  child: Text(
                    'QnA',
                    style: textTheme.titleLarge,
                  )),
              SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  child: Row(children: <Widget>[
                    Align(
                        alignment: Alignment.center,
                        child: Padding(
                            padding: const EdgeInsets.symmetric(horizontal: 8),
                            child: OutlinedButton(
                                onPressed: () {
                                  _promptFocusNode.requestFocus();
                                  _promptTextEditingController.text =
                                      systemPromptHint;
                                },
                                child: Text(
                                  "Describe yourself in detail",
                                  overflow: TextOverflow.ellipsis,
                                  style: textTheme.bodyLarge,
                                )))),
                    Align(
                        alignment: Alignment.center,
                        child: Padding(
                            padding: const EdgeInsets.symmetric(horizontal: 8),
                            child: OutlinedButton(
                                onPressed: () {
                                  _promptFocusNode.requestFocus();
                                  _promptTextEditingController.text =
                                      openQNAPromptHint;
                                },
                                child: Text(
                                  "How do I build",
                                  overflow: TextOverflow.ellipsis,
                                  style: textTheme.bodyLarge,
                                )))),
                    Align(
                        alignment: Alignment.center,
                        child: Padding(
                            padding: const EdgeInsets.symmetric(horizontal: 8),
                            child: OutlinedButton(
                                onPressed: () {
                                  _promptFocusNode.requestFocus();
                                  _promptTextEditingController.text =
                                      closedQNAPromptHint;
                                },
                                child: Text(
                                  "Explain to me the difference",
                                  overflow: TextOverflow.ellipsis,
                                  style: textTheme.bodyLarge,
                                ))))
                  ])),
            ]),
          ],
        )));
  }

  Widget generatedTextContainer({
    required Size size,
    required BuildContext context,
    required Orientation orientation,
    required TextTheme textTheme,
  }) {
    return Container(
        child: Center(
            child:
                Text("GENERATED TEXT CONTAINER", style: textTheme.bodyLarge)));
  }

  bool isFetchAPISupported() {
    if (html.Performance.supported) {
      void perfObserver(dynamic list, html.PerformanceObserver observer) {
        list
            .getEntriesByType(PerformanceEventTypes.resource.value)
            .forEach((dynamic entry) {
          if (entry.initiatorType == WebAPIs.fetch.value) {
            print('Fetch API is supported in this browser.');
          } else {
            print('Fetch API is not supported in this browser.');
          }
        });
      }

      final html.PerformanceObserver observeFetch =
          html.PerformanceObserver(perfObserver);
      observeFetch.observe(<String, List<String>>{
        'entryTypes': <String>['resource']
      });
      // Disable additional performance events.
      observeFetch.disconnect();
      // Return true if browser support Fetch API.
      return true;
    } else {
      // Performance metrics not supported, fallback to manual feature detecton.
      print(
          'Performance metrics not supported, fallback to manual feature detection.');
      // Return false if browser does not support Fetch API.
      return false;
    }
  }

  Future<void> runLLMInference({required String human_message}) async {
    final String url = "${const String.fromEnvironment('ENDPOINT')}/generate";
    // Send network request to remote hosted inference server.
    if (isFetchAPISupported() && navigator.onLine == true) {
      final String requestBody =
          jsonEncode(BaseRequest.fromJson(<String, dynamic>{
        'data': {"human_message": human_message},
      }));

      final Map<String, dynamic> requestHeaders = {
        "accept": 'application/json',
        "content-type": "application/json",
        "cache-control": "no-cache"
      };

      final Map<String, Object?> options = <String, Object?>{
        'method': 'POST',
        'headers': requestHeaders,
        'body': requestBody,
        'mode': 'cors',
        'cache': 'default',
        'credentials': 'same-origin',
      };

      await html.window
          .fetch(Uri.parse(url), options)
          .then((dynamic response) async {
        final dynamic object =
            js.JsObject(js.context['Response'] as js.JsFunction);

        if (object['ok'] != true) {
          // Network error.
          print('Network error with fetch operation.');
        } else {
          // Write response body to local store.
          final String response_json_text = await response.text();
          // Decode JSON to Dart Map.
          print(jsonDecode(response_json_text)['data']['api_message']);
          print(jsonDecode(response_json_text)['data']['human_message']);
          print(jsonDecode(response_json_text)['data']['ai_message']);
        }
      });
    } else {
      // Fallback to offline local on-device inference.
    }
  }
}

/// Available web features and APIs.
enum WebAPIs {
  fetch('fetch');

  const WebAPIs(this.value);

  final String value;
}

/// Subscribe to various performance event types supported in chrome 109.
enum PerformanceEventTypes {
  element('element'),
  event('event'),
  firstInput('first-input'),
  largestContentfulPaint('largest-contentful-paint'),
  layoutShift('layout-shift'),
  longtask('longtask'),
  mark('mark'),
  measure('measure'),
  navigation('navigation'),
  paint('paint'),
  resource('resource');

  const PerformanceEventTypes(this.value);

  /// Returns string representation of enumerated values.
  final String value;
}
