import 'dart:convert';
import 'dart:html' as html;
import 'dart:js' as js;
import 'dart:js_interop' as js_interop;

import 'package:flutter/cupertino.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_web_plugins/flutter_web_plugins.dart';
import 'package:hive/hive.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:provider/provider.dart';
import 'package:uuid/uuid.dart';
import 'package:web/web.dart' as web;
import 'package:flutter/services.dart';

import "package:client/models/state_models.dart";
import "package:client/configuration_web_mobile.dart";
import "package:client/gen/request.dart";
import "package:client/gen/response.dart";

// TODO: persist conversation history to local store
// TODO: load previous history from local store
final Uuid uuid = Uuid();

class Message {
  String content;

  Message({
    required String this.content,
  });
}

class SystemMessage extends Message {
  SystemMessage({content}) : super(content: content);
}

class AIMessage extends Message {
  AIMessage({content}) : super(content: content);
}

class HumanMessage extends Message {
  HumanMessage({content}) : super(content: content);
}

List<Message> messages = <Message>[];

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
  bool _isGenerating = false;
  // Load from local secure store to runtime.
  final Box encryptedChatHistoryBox = Hive.box<dynamic>('history');

  final LLMModel llmDataModel = LLMModel();

  final navigator = html.window.navigator;

  final String threadId = uuid.v4();

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
                  alignment: Alignment.topCenter,
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
                          constraints: constraints,
                          messages: messages,
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
                          child: _isGenerating
                              ? showSpinningIndicator()
                              : IconButton(
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
                                            humanMessage:
                                                _promptTextEditingController
                                                    .text
                                                    .toString(),
                                            threadId: threadId)
                                        .whenComplete(() {
                                      // Trigger rebuild of UI.
                                      setState(() {});

                                      // End progress indicator.
                                      _isGenerating = false;
                                    });
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
                  textAlign: TextAlign.start,
                ))),
          ],
        );
      }),
    );
  }

  Widget showSpinningIndicator() {
    /// Show 16x16 px spinning indicator with background color.
    return Center(
        widthFactor: 1.5,
        heightFactor: 1,
        child: SizedBox(
            width: 16.0,
            height: 16.0,
            child: CircularProgressIndicator(
              backgroundColor: Colors.amberAccent,
              strokeWidth: 1.5,
            )));
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
    required BoxConstraints constraints,
    required List<Message> messages,
  }) {
    final List<Message> messagesReversed = messages.reversed.toList();
    return Column(children: [
      Expanded(
          child: Container(
              color: Colors.transparent,
              child: Scrollbar(
                  controller: _scrollController,
                  thickness: 10.0,
                  radius: Radius.circular(8),
                  thumbVisibility: true,
                  child: ListView.builder(
                    reverse: true,
                    controller: _scrollController,
                    itemCount: messages.length,
                    itemBuilder: (BuildContext context, int index) {
                      return Padding(
                          padding: const EdgeInsets.only(
                              bottom: 8, left: 8, right: 16),
                          child: messagesReversed[index] is AIMessage
                              ? Row(
                                  mainAxisAlignment: MainAxisAlignment.start,
                                  children: <Widget>[
                                      Container(
                                        width: size.width * 0.85,
                                        padding: const EdgeInsets.all(8),
                                        decoration: BoxDecoration(
                                            color: Colors.blue,
                                            border: Border.all(
                                              color: Theme.of(context)
                                                  .colorScheme
                                                  .secondary,
                                            ),
                                            borderRadius:
                                                BorderRadius.circular(4)),
                                        child: Row(children: <Widget>[
                                          Column(
                                              crossAxisAlignment:
                                                  CrossAxisAlignment.start,
                                              children: <Widget>[
                                                Text(
                                                  "Llama3",
                                                  style: textTheme.bodyLarge,
                                                  textAlign: TextAlign.left,
                                                ),
                                                Text(
                                                  messagesReversed[index]
                                                      .content,
                                                  style: textTheme.bodyLarge,
                                                  softWrap: true,
                                                  textAlign: TextAlign.left,
                                                )
                                              ]),
                                        ]),
                                      ),
                                    ])
                              : Row(
                                  mainAxisAlignment: MainAxisAlignment.end,
                                  children: <Widget>[
                                      Container(
                                        width: size.width * 0.85,
                                        padding: const EdgeInsets.all(8),
                                        decoration: BoxDecoration(
                                            color: Colors.green,
                                            border: Border.all(
                                              color: Theme.of(context)
                                                  .colorScheme
                                                  .secondary,
                                            ),
                                            borderRadius:
                                                BorderRadius.circular(4)),
                                        child: Text(
                                            messagesReversed[index].content,
                                            style: textTheme.bodyLarge,
                                            textAlign: TextAlign.end,
                                            softWrap: true),
                                      )
                                    ]));
                    },
                  )))),
    ]);
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

  Future<void> runLLMInference(
      {required String humanMessage, required String threadId}) async {
    final String url = "${const String.fromEnvironment('ENDPOINT')}/generate";
    // Append to conversation history.
    messages.add(HumanMessage(content: humanMessage));

    // Send network request to remote hosted inference server.
    if (isFetchAPISupported() && navigator.onLine == true) {
      // Start progress indicator.
      _isGenerating = true;

      final String requestBody =
          jsonEncode(BaseRequest.fromJson(<String, dynamic>{
        'data': {"human_message": humanMessage},
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
          // Append decoded 'AIMessage' to conversation history.
          messages.add(AIMessage(
              content: jsonDecode(response_json_text)['data']['ai_message']));

          print('client threadID:$threadId');
          print('MESSAGES_LENGTH:${messages.length}');
          print('MESSAGES_ORDER:${messages}');

          // Persist entire conversation history to local storage.
          //encryptedChatHistoryBox
          //.put(threadId.toString(), [messages[0].content]);

          // Auto scroll to newest item.
          _scrollController.animateTo(
            _scrollController.position.minScrollExtent,
            duration: const Duration(milliseconds: 200),
            curve: Curves.easeInOut,
          );
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
