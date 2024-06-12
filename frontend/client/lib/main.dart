import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_web_plugins/flutter_web_plugins.dart';
import 'package:hive/hive.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:provider/provider.dart';

import "package:client/models/state_models.dart";
import "package:client/configuration_web_mobile.dart";

// TODO: ada encrypted store for storing conversation history
// TODO: add text field for user input
// TODO: render conversation history
// TODO: render AIMessage
// TODO: create request, response json models
// TODO: create HumanMessage, AIMessage json models
// TODO: add prompt hints

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
                  // Display prompt hints to guide
                  // responsible usage behavior on first
                  // first.
                  child: llmDataModel.isFirstVisit
                      ? promptHintsContainer(textTheme: textTheme)
                      // Show list of generated text if keyboard no focus.
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
                        borderRadius: BorderRadius.circular(16),
                      ),
                      enabledBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(16),
                        borderSide: BorderSide(
                          color: colorScheme.secondary,
                        ),
                      ),
                      focusedBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(16),
                          borderSide: BorderSide(
                            color: colorScheme.secondary,
                          )),
                      helperText: ' ',
                      errorText: null,
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
        child: Text("GENERATED TEXT CONTAINER", style: textTheme.bodyLarge));
  }
}
