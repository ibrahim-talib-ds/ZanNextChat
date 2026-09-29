import 'package:flutter/material.dart';
import 'chatbot_page.dart';

void main() => runApp(const ZanNextChatApp());

class ZanNextChatApp extends StatelessWidget {
  const ZanNextChatApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'ZanNextChat',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        primaryColor: const Color(0xFF0A3A22),
        scaffoldBackgroundColor: const Color(0xFFF6F7F9),
        useMaterial3: true,
      ),
      home: const ChatbotPage(),
    );
  }
}
