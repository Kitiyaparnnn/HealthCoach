import 'dart:convert';
import 'dart:io';
import 'package:firebase_vertexai/firebase_vertexai.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:font_awesome_flutter/font_awesome_flutter.dart';
import 'package:image_picker/image_picker.dart';
import 'package:logger/web.dart';
import 'package:mime/mime.dart';
import 'package:video_player/video_player.dart';

var logger = Logger();

class UserInfo {
  String gender;
  int age;
  int height;
  int weight;
  String occupation;
  String fitnessGoals;
  String? injuries;

  UserInfo(
      {required this.gender,
      required this.age,
      required this.height,
      required this.weight,
      required this.occupation,
      required this.fitnessGoals,
      this.injuries});
}

var user = UserInfo(
    gender: "female",
    age: 25,
    height: 161,
    weight: 50,
    occupation: "student",
    fitnessGoals: "weight loss",
    injuries: "wrist pain");

String systemPrompt = '''
You are a friendly personal fitness coach helping a user who wants to get healthier but may not know much about exercise or nutrition.
The user is a ${user.gender}, ${user.age} years old, ${user.height} cm tall, weught ${user.weight} kg and has a ${user.occupation} job.
They want to ${user.fitnessGoals} and may have ${user.injuries}. 

When the user asks for suggestions, reply clearly, cus and supportively using steps (e.g., Step 1, Step 2...) at least 2 options. Keep each option under 100 words.

Examples of suggestion types:
- Simple exercise or workout plan for the day
- Healthy meal ideas with short recipes that fits their goals 
- Motivation enhancement
- Injury handling

Group all similar answer together and please give the response in a JSON format.
Object with a key "type" of "suggestions" and list of suggestions in the following format:
{
  "type": "suggestions",
  "response": [{'title':'description'}, {'title':'description'}]
}

Before giving detailed advice, ask for helpful context such as:
— What are your fitness goals? (e.g., weight loss, build strength, flexibility)
— Do you have any injuries or limitations?
— How much time do you have today to exercise?
— What kinds of workouts or meals do you enjoy?

Or if the user asks for follow-up questions, answer.
REsponse usinf this structure:
{
  "type": "response",
  "response": \$Gemini answer to the question or request for more information here
}

Remember, if you are asked anything outside your scope (like diagnosing serious injuries or medical conditions), kindly advise the user to consult a healthcare professional.
''';

class MessageContent {
  Attachment? attachment;
  String text;
  bool fromUser;
  MessageContent({this.attachment, this.text = '', this.fromUser = false});
}

class Attachment {
  String mimeType;
  Uint8List bytes;
  String path;
  Attachment({required this.mimeType, required this.bytes, required this.path});
}

class Suggestion {
  String title;
  String description;
  Suggestion({required this.title, required this.description});
}

class SuggestionContent extends MessageContent {
  List<Suggestion> suggestions = [];
  SuggestionContent(
      {required List<dynamic> suggestionsList,
      super.attachment,
      super.fromUser = false}) {
    for (var suggestion in suggestionsList) {
      var title = suggestion['title'];
      var description = suggestion['description'];
      suggestions.add(Suggestion(title: title, description: description));
    }
  }
}

class MyHomePage extends StatefulWidget {
  const MyHomePage({super.key, required this.title});

  final String title;

  @override
  State<MyHomePage> createState() => _MyHomePageState();
}

class _MyHomePageState extends State<MyHomePage> {
  GenerativeModel geminiModel = FirebaseVertexAI.instance.generativeModel(
    model: 'gemini-2.0-flash',
    systemInstruction: Content.text(systemPrompt),
    generationConfig: GenerationConfig(responseMimeType: 'application/json'),
  );

  late ChatSession chat;
  final List<MessageContent> _generatedMessages = <MessageContent>[];
  final TextEditingController textController = TextEditingController();
  final ImagePicker _picker = ImagePicker();
  Attachment? attachment;

  @override
  initState() {
    chat = geminiModel.startChat();
    super.initState();
  }

  void sendMessage(String message) async {
    final attachmentFile = attachment;

    setState(() {
      _generatedMessages.add(MessageContent(
          attachment: attachment, text: message, fromUser: true));
      // logger.d("User input: {'message': $message, 'attachment': ${attachmentFile != null ? 'yes' : 'no'}");
      textController.clear();
      attachment = null;
    });

    GenerateContentResponse response;
    if (attachmentFile != null) {
      response = await chat.sendMessage(Content.multi([
        TextPart(message),
        InlineDataPart(attachmentFile.mimeType, attachmentFile.bytes)
      ]));
    } else {
      response = await chat.sendMessage(Content.text(message));
    }

    setState(() {
      var text = response.text;
      var obj = jsonDecode(text!) as Map<String, dynamic>;

      // logger.d("Gemini response: $obj");

      if (obj['type'] == 'suggestions') {
        var suggestionsList = obj['response'] as List<dynamic>;
        _generatedMessages.add(SuggestionContent(
          suggestionsList: suggestionsList,
          fromUser: false,
        ));
      } else {
        var answers = obj['response'] as String;
        _generatedMessages.add(MessageContent(
          text: answers,
          fromUser: false,
        ));
      }
    });
  }

  void getMedia() async {
    if (attachment != null) {
      showDialog(
          context: context,
          builder: (context) {
            return const AlertDialog(
              title: Text(
                "You've already selected an attachment.",
                style: TextStyle(fontSize: 16),
              ),
            );
          });
    } else {
      try {
        final XFile? picked = await _picker.pickMedia();
        // logger.d("Picked file: $picked");
        if (picked == null) return logger.d("No file selected");

        // final String? mimeType = picked.mimeType;
        final String? mimeType = lookupMimeType(picked.path);
        final Uint8List bytes = await picked.readAsBytes();
        final String path = picked.path;

        if (mimeType == null) return logger.d("No mime type found");
        setState(() {
          attachment = Attachment(mimeType: mimeType, bytes: bytes, path: path);
          // logger.i("Attachment selected: {'mimeType': $mimeType, 'bytes': ${bytes.length}, 'path': $path}");
        });
      } catch (e) {
        logger.e("Error picking media: $e");
      }
    }
  }

  void showAdjustedUserInfo() {
    String? gender = user.gender;
    String? goal = user.fitnessGoals;
    int? age = user.age;
    int? height = user.height;
    int? weight = user.weight;
    String occupation = user.occupation;
    String injuries = user.injuries ?? "";

    showDialog(
      context: context,
      builder: (context) {
        return StatefulBuilder(builder: (context, setState) {
          return Dialog(
            shape:
                RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
            child: Padding(
              padding: const EdgeInsets.all(20),
              child: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Text(
                      "User Info",
                      style: TextStyle(
                          fontWeight: FontWeight.bold,
                          fontSize: 18,
                          color: Colors.teal),
                    ),
                    const SizedBox(height: 20),
                    Row(
                      children: [
                        const Text("Gender: "),
                        const SizedBox(width: 8),
                        _genderButton("female", gender == "female", () {
                          setState(() {
                            gender = "female";
                            user.gender = gender!;
                          });
                        }),
                        const SizedBox(width: 8),
                        _genderButton("male", gender == "male", () {
                          setState(() {
                            gender = "male";
                            user.gender = gender!;
                          });
                        }),
                      ],
                    ),
                    const SizedBox(height: 12),
                    Row(
                      children: [
                        const Text("Age: "),
                        const SizedBox(width: 8),
                        _valueBox(
                          initial: age?.toString() ?? '',
                          onChanged: (val) {
                            final parsed = int.tryParse(val);
                            if (parsed != null) {
                              setState(() {
                                age = parsed;
                                user.age = parsed;
                              });
                            }
                          },
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),
                    Row(
                      children: [
                        const Text("Weight: "),
                        _valueBox(
                          initial: weight?.toString() ?? '',
                          suffix: "kg",
                          onChanged: (val) {
                            final parsed = int.tryParse(val);
                            if (parsed != null) {
                              setState(() {
                                weight = parsed;
                                user.weight = parsed;
                              });
                            }
                          },
                        ),
                        const Spacer(),
                        const Text("Height: "),
                        _valueBox(
                          initial: height?.toString() ?? '',
                          suffix: "cm",
                          onChanged: (val) {
                            final parsed = int.tryParse(val);
                            if (parsed != null) {
                              setState(() {
                                height = parsed;
                                user.height = parsed;
                              });
                            }
                          },
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),
                    const Row(
                      children: [Text("Occupation:")],
                    ),
                    const SizedBox(height: 6),
                    TextField(
                      controller: TextEditingController(text: occupation),
                      decoration: _inputDecoration(),
                      onChanged: (val) {
                        setState(() {
                          occupation = val;
                          user.occupation = val;
                        });
                      },
                    ),
                    const SizedBox(height: 12),
                    const Row(
                      children: [Text("Fitness Goal:")],
                    ),
                    const SizedBox(height: 6),
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Expanded(
                          child: SingleChildScrollView(
                            scrollDirection: Axis.horizontal,
                            child: Row(
                              children: [
                                _tagButton("weight loss", goal == "weight loss",
                                    () {
                                  setState(() {
                                    goal = "weight loss";
                                    user.fitnessGoals = "weight loss";
                                  });
                                }),
                                const SizedBox(width: 8),
                                _tagButton(
                                    "stay healthy", goal == "stay healthy", () {
                                  setState(() {
                                    goal = "stay healthy";
                                    user.fitnessGoals = "stay healthy";
                                  });
                                }),
                                const SizedBox(width: 8),
                                _tagButton("flexibility", goal == "flexibility",
                                    () {
                                  setState(() {
                                    goal = "flexibility";
                                    user.fitnessGoals = "flexibility";
                                  });
                                }),
                              ],
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),
                    const Row(
                      children: [Text("Injuries:")],
                    ),
                    const SizedBox(height: 6),
                    TextField(
                      controller: TextEditingController(text: injuries),
                      decoration: _inputDecoration(hint: "None"),
                      onChanged: (val) {
                        setState(() {
                          injuries = val;
                          user.injuries = val;
                        });
                      },
                    ),
                    const SizedBox(height: 20),
                    Align(
                      alignment: Alignment.bottomRight,
                      child: TextButton(
                        onPressed: () => Navigator.pop(context),
                        child: const Text(
                          "Save",
                          style: TextStyle(color: Colors.teal),
                        ),
                      ),
                    )
                  ],
                ),
              ),
            ),
          );
        });
      },
    );
  }

  Widget _genderButton(String label, bool selected, VoidCallback onTap) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        decoration: BoxDecoration(
          color: selected ? Colors.teal.shade200 : Colors.transparent,
          border: Border.all(color: Colors.grey),
          borderRadius: BorderRadius.circular(16),
        ),
        child: Text(label),
      ),
    );
  }

  Widget _tagButton(String label, bool selected, VoidCallback onTap) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        decoration: BoxDecoration(
          color: selected ? Colors.teal.shade200 : Colors.transparent,
          border: Border.all(color: Colors.grey),
          borderRadius: BorderRadius.circular(16),
        ),
        child: Text(label),
      ),
    );
  }

  Widget _valueBox(
      {required String initial,
      String? suffix,
      required Function(String) onChanged}) {
    return SizedBox(
      width: 70,
      height: 35,
      child: TextField(
        controller: TextEditingController(text: initial),
        keyboardType: TextInputType.number,
        onChanged: onChanged,
        decoration: InputDecoration(
          suffixText: suffix,
          border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
          contentPadding:
              const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
        ),
      ),
    );
  }

  InputDecoration _inputDecoration({String? hint}) {
    return InputDecoration(
      hintText: hint,
      border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
      contentPadding: const EdgeInsets.symmetric(horizontal: 10),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
        appBar: AppBar(
          backgroundColor: Theme.of(context).colorScheme.inversePrimary,
          title: Text(widget.title,
              style:
                  const TextStyle(fontSize: 20, fontWeight: FontWeight.w600)),
          leading: IconButton(
              icon: const Icon(
                FontAwesomeIcons.sliders,
                size: 20,
              ),
              onPressed: showAdjustedUserInfo),
        ),
        body: Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Expanded(
                child: Padding(
                  padding: const EdgeInsets.all(8.0),
                  child: ListView.builder(
                    itemCount: _generatedMessages.length,
                    itemBuilder: (context, index) {
                      var message = _generatedMessages[index];

                      if (message.runtimeType == SuggestionContent) {
                        return SuggestionBubble(
                          suggestions:
                              (message as SuggestionContent).suggestions,
                        );
                      }

                      return MessageBubble(
                        text: message.text,
                        attachment: message.attachment,
                        isSender: message.fromUser,
                      );
                    },
                  ),
                ),
              ),
              AnimatedSwitcher(
                duration: const Duration(milliseconds: 300),
                child: attachment != null
                    ? Container(
                        width: MediaQuery.of(context).size.width,
                        padding: const EdgeInsets.all(8),
                        key: const ValueKey("popup"),
                        decoration: BoxDecoration(
                          color: Colors.teal.shade200,
                        ),
                        child: const Text(
                          "Media attached!",
                          style: TextStyle(color: Colors.white),
                          textAlign: TextAlign.center,
                        ),
                      )
                    : const SizedBox.shrink(key: ValueKey("empty")),
              ),
              Container(
                color: Colors.teal.shade200,
                padding: const EdgeInsets.fromLTRB(8, 8, 8, 20),
                child: Row(
                  children: [
                    IconButton(
                      icon: const Icon(FontAwesomeIcons.image),
                      onPressed: getMedia,
                    ),
                    const SizedBox.square(
                      dimension: 8,
                    ),
                    Expanded(
                      child: TextField(
                        controller: textController,
                        maxLines: 3,
                        minLines: 1,
                        decoration: const InputDecoration(
                          filled: true,
                          fillColor: Colors.white70,
                          border: OutlineInputBorder(
                              borderRadius:
                                  BorderRadius.all(Radius.circular(20))),
                          hintText: 'Type a message',
                        ),
                      ),
                    ),
                    const SizedBox.square(
                      dimension: 8,
                    ),
                    IconButton(
                      icon: const Icon(Icons.send),
                      onPressed: () {
                        if (textController.text.isNotEmpty) {
                          sendMessage(textController.text);
                        }
                      },
                    ),
                  ],
                ),
              ),
            ],
          ),
        ));
  }
}

class MessageBubble extends StatelessWidget {
  const MessageBubble(
      {required this.text, this.attachment, this.isSender = false, super.key});

  final String text;
  final Attachment? attachment;
  final bool isSender;

  @override
  Widget build(BuildContext context) {
    var width = MediaQuery.of(context).size.width;
    // var attachmentFile = attachment;

    return Row(
      mainAxisAlignment:
          isSender ? MainAxisAlignment.end : MainAxisAlignment.start,
      children: [
        Container(
          constraints: BoxConstraints(
            maxWidth: width * 0.7,
          ),
          padding: const EdgeInsets.all(10),
          margin: const EdgeInsets.symmetric(vertical: 5),
          decoration: BoxDecoration(
            color: isSender
                ? Theme.of(context).colorScheme.primary
                : Theme.of(context).colorScheme.surfaceContainer,
            borderRadius: BorderRadius.circular(10),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (attachment != null)
                Container(
                  height: 124,
                  padding: const EdgeInsets.all(10),
                  child: Row(
                    children: [
                      if (['image/png', 'image/jpeg']
                          .contains(attachment!.mimeType))
                        Container(
                            width: 100,
                            height: 100,
                            decoration: BoxDecoration(
                              borderRadius: BorderRadius.circular(10),
                              image: DecorationImage(
                                image: MemoryImage(attachment!.bytes),
                                fit: BoxFit.cover,
                              ),
                            )),
                      if (['video/mp4', 'video/quicktime']
                          .contains(attachment!.mimeType))
                        SizedBox(
                            width: 100,
                            height: 100,
                            child: VideoPlayer(VideoPlayerController.file(
                                File(attachment!.path)))),
                    ],
                  ),
                ),
              Text(
                text,
                style: TextStyle(color: isSender ? Colors.white : Colors.black),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class SuggestionBubble extends StatelessWidget {
  const SuggestionBubble({required this.suggestions, super.key});

  final List<Suggestion> suggestions;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Expanded(
            child: Container(
                constraints: const BoxConstraints(
                  maxHeight: 325,
                ),
                child: PageView(
                  children: List.generate(
                    suggestions.length,
                    (index) => SuggestionCard(
                      title: suggestions[index].title,
                      description: suggestions[index].description,
                      isEnd: index == suggestions.length - 1,
                    ),
                  ),
                )))
      ],
    );
  }
}

class SuggestionCard extends StatelessWidget {
  const SuggestionCard(
      {super.key,
      required this.title,
      required this.description,
      required this.isEnd});

  final String title;
  final String description;
  final bool isEnd;

  @override
  Widget build(BuildContext context) {
    var width = MediaQuery.of(context).size.width;
    return Card(
      child: Container(
        width: width * 0.7,
        padding: const EdgeInsets.all(10),
        child: Column(
          children: [
            Text(
              title,
              style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 18),
            ),
            Text(description),
            const Spacer(),
            if (!isEnd) const Icon(FontAwesomeIcons.circleArrowRight),
          ],
        ),
      ),
    );
  }
}
