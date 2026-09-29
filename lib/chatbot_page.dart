import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:intl/intl.dart';

class ChatbotPage extends StatefulWidget {
  const ChatbotPage({super.key});
  @override
  State<ChatbotPage> createState() => _ChatbotPageState();
}

class _ChatbotPageState extends State<ChatbotPage> {
  static const Color kPrimary = Color(0xFF0A3A22);
  static const Color kBg = Color(0xFFF6F7F9);

  static const String kGroqKey = "PASTE_YOUR_GROQ_KEY_HERE";
  static const String kGroqUrl =
      "https://api.groq.com/openai/v1/chat/completions";
  static const String kModel = "openai/gpt-oss-120b";

  static const String kSystemPrompt = '''
You are ZanNextChat — the official AI assistant inside the ZanNext mobile app.

ABOUT ZANNEXT
ZanNext is a marketplace app in Zanzibar where people buy and sell products
(phones, fashion, home goods, sports gear, and more). Buyers browse, chat,
and order. Sellers list products and manage orders.

PAYMENT RULES
- ZanNext has NO checkout page and NO in-app payment.
- Method 1 (RECOMMENDED): CASH ON DELIVERY — pay the seller when the product arrives.
- Method 2 (ONLY if you trust the seller): direct mobile money via M-Pesa, Tigo Pesa, or Airtel Money.
- ALWAYS recommend cash on delivery first.

BUYER HELP
- Buy: 1) Open product 2) Tap "Buy Now" 3) Choose delivery location 4) Confirm
- Track order: Orders tab → tap order → see status
- Cancel: open order → Cancel Order (Pending/Confirmed only)
- Chat seller: open product → tap seller name → Chat
- Review: delivered order → "Rate this order" → stars → submit
- Forgot password: login → Forgot Password → email → reset link

SELLER HELP
- Become seller: profile → Become a Seller → fill shop → submit
- Add product: dashboard → Add Product → photos → details → category → publish
- Receive orders: push notification → Orders → Confirm → Prepare → Mark Shipped → Mark Delivered
- Get paid: arranged with buyer (cash on delivery or mobile money)

RULES
1. ALWAYS be helpful. Never refuse a reasonable question.
2. Answer in SIMPLE ENGLISH.
3. Keep answers SHORT — 2-5 sentences.
4. Use numbers for steps.
5. Use emojis occasionally (👋 ✅ 💡 🛒).
6. NEVER mention you are an AI, Groq, or Llama — you are ZanNextChat.
7. If user writes in Swahili, reply in Swahili.
8. Stay warm and human.

Answer ANY question — about ZanNext or anything else in the world.
''';

  final TextEditingController _controller = TextEditingController();
  final ScrollController _scroll = ScrollController();
  final List<ChatMessage> _messages = [];
  bool _loading = false;

  @override
  void initState() {
    super.initState();
    _loadHistory();
  }

  @override
  void dispose() {
    _controller.dispose();
    _scroll.dispose();
    super.dispose();
  }

  Future<void> _loadHistory() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString("zannextchat_history");
    if (raw != null && raw.isNotEmpty) {
      final List<dynamic> list = jsonDecode(raw);
      setState(() =>
          _messages.addAll(list.map((e) => ChatMessage.fromJson(e))));
    }
    if (_messages.isEmpty) {
      _messages.add(ChatMessage(
        role: "assistant",
        content:
            "Hello! 👋 I'm ZanNextChat. Ask me anything about buying, selling, "
            "orders, or payments on ZanNext. I'm here 24/7!",
        time: DateTime.now(),
      ));
    }
    _scrollDown(instant: true);
  }

  Future<void> _saveHistory() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString("zannextchat_history",
        jsonEncode(_messages.map((m) => m.toJson()).toList()));
  }

  Future<void> _clearHistory() async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text("Clear chat?"),
        content: const Text("This will delete all your chat history."),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text("Cancel")),
          TextButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text("Clear",
                  style: TextStyle(color: Colors.red))),
        ],
      ),
    );
    if (ok != true) return;
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove("zannextchat_history");
    setState(() {
      _messages.clear();
      _messages.add(ChatMessage(
        role: "assistant",
        content: "Chat cleared. 👋 Ask me anything about ZanNext.",
        time: DateTime.now(),
      ));
    });
    await _saveHistory();
  }

  Future<void> _send() async {
    final text = _controller.text.trim();
    if (text.isEmpty || _loading) return;

    setState(() {
      _messages
          .add(ChatMessage(role: "user", content: text, time: DateTime.now()));
      _loading = true;
      _controller.clear();
    });
    _scrollDown();
    await _saveHistory();

    final history = _messages
        .reversed
        .take(10)
        .toList()
        .reversed
        .map((m) => {"role": m.role, "content": m.content})
        .toList();

    String reply;
    try {
      final resp = await http
          .post(
            Uri.parse(kGroqUrl),
            headers: {
              "Content-Type": "application/json",
              "Authorization": "Bearer $kGroqKey",
            },
            body: jsonEncode({
              "model": kModel,
              "messages": [
                {"role": "system", "content": kSystemPrompt},
                ...history,
              ],
              "temperature": 0.7,
              "max_tokens": 800,
            }),
          )
          .timeout(const Duration(seconds: 30));

      if (resp.statusCode == 200) {
        final data = jsonDecode(resp.body);
        reply = data["choices"][0]["message"]["content"].toString().trim();
      } else {
        reply =
            "⚠️ AI is busy. Please try again. (${resp.statusCode})";
      }
    } catch (e) {
      reply = "📡 Connection problem. Check your internet and try again.";
    }

    setState(() {
      _loading = false;
      _messages.add(
          ChatMessage(role: "assistant", content: reply, time: DateTime.now()));
    });
    _scrollDown();
    await _saveHistory();
  }

  void _scrollDown({bool instant = false}) {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!_scroll.hasClients) return;
      final target = _scroll.position.maxScrollExtent + 80;
      if (instant) {
        _scroll.jumpTo(target);
      } else {
        _scroll.animateTo(target,
            duration: const Duration(milliseconds: 280),
            curve: Curves.easeOut);
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: kBg,
      appBar: AppBar(
        backgroundColor: kPrimary,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios_new,
              color: Colors.white, size: 20),
          onPressed: () => Navigator.pop(context),
        ),
        title: Row(
          children: [
            Container(
              width: 38,
              height: 38,
              decoration: const BoxDecoration(
                  color: Colors.white, shape: BoxShape.circle),
              child: ClipOval(
                child: Image.asset(
                  'assets/images/zannextchat.png',
                  width: 38,
                  height: 38,
                  fit: BoxFit.cover,
                ),
              ),
            ),
            const SizedBox(width: 10),
            const Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Text("ZanNextChat",
                    style: TextStyle(
                        color: Colors.white,
                        fontSize: 16,
                        fontWeight: FontWeight.w700)),
                SizedBox(height: 2),
                Row(children: [
                  _OnlineDot(),
                  SizedBox(width: 4),
                  Text("Online",
                      style:
                          TextStyle(color: Colors.white70, fontSize: 11)),
                ]),
              ],
            ),
          ],
        ),
        actions: [
          PopupMenuButton<String>(
            icon: const Icon(Icons.more_vert, color: Colors.white),
            onSelected: (v) {
              if (v == "clear") _clearHistory();
            },
            itemBuilder: (_) => const [
              PopupMenuItem(
                value: "clear",
                child: Row(children: [
                  Icon(Icons.delete_outline, size: 18),
                  SizedBox(width: 8),
                  Text("Clear chat"),
                ]),
              ),
            ],
          ),
        ],
      ),
      body: Column(
        children: [
          Expanded(
            child: ListView.builder(
              controller: _scroll,
              padding:
                  const EdgeInsets.symmetric(horizontal: 12, vertical: 16),
              itemCount: _messages.length + (_loading ? 1 : 0),
              itemBuilder: (_, i) {
                if (i == _messages.length && _loading) {
                  return const TypingBubble();
                }
                final m = _messages[i];
                return MessageBubble(
                  message: m,
                  onLongPress: () {
                    Clipboard.setData(ClipboardData(text: m.content));
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(
                          content: Text("Copied ✅"),
                          duration: Duration(seconds: 1)),
                    );
                  },
                );
              },
            ),
          ),
          _InputBar(
              controller: _controller, loading: _loading, onSend: _send),
        ],
      ),
    );
  }
}

class ChatMessage {
  final String role;
  final String content;
  final DateTime time;
  ChatMessage(
      {required this.role, required this.content, required this.time});
  Map<String, dynamic> toJson() =>
      {"role": role, "content": content, "time": time.toIso8601String()};
  factory ChatMessage.fromJson(Map<String, dynamic> j) => ChatMessage(
        role: j["role"],
        content: j["content"],
        time: DateTime.tryParse(j["time"] ?? "") ?? DateTime.now(),
      );
}

class MessageBubble extends StatelessWidget {
  final ChatMessage message;
  final VoidCallback onLongPress;
  const MessageBubble(
      {super.key, required this.message, required this.onLongPress});

  static const Color kPrimary = Color(0xFF0A3A22);

  @override
  Widget build(BuildContext context) {
    final isUser = message.role == "user";
    final timeStr = DateFormat("HH:mm").format(message.time);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        mainAxisAlignment:
            isUser ? MainAxisAlignment.end : MainAxisAlignment.start,
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          if (!isUser) const _BotAvatar(),
          Flexible(
            child: GestureDetector(
              onLongPress: onLongPress,
              child: Container(
                margin: const EdgeInsets.symmetric(horizontal: 6),
                padding:
                    const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                constraints: BoxConstraints(
                    maxWidth: MediaQuery.of(context).size.width * 0.75),
                decoration: BoxDecoration(
                  color: isUser ? kPrimary : Colors.white,
                  borderRadius: BorderRadius.only(
                    topLeft: const Radius.circular(16),
                    topRight: const Radius.circular(16),
                    bottomLeft: Radius.circular(isUser ? 16 : 4),
                    bottomRight: Radius.circular(isUser ? 4 : 16),
                  ),
                  boxShadow: [
                    BoxShadow(
                        color: Colors.black.withOpacity(0.04),
                        blurRadius: 4,
                        offset: const Offset(0, 2)),
                  ],
                ),
                child: Column(
                  crossAxisAlignment: isUser
                      ? CrossAxisAlignment.end
                      : CrossAxisAlignment.start,
                  children: [
                    Text(
                      message.content,
                      style: TextStyle(
                        color:
                            isUser ? Colors.white : const Color(0xFF1A1A1A),
                        fontSize: 14.5,
                        height: 1.4,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      timeStr,
                      style: TextStyle(
                        color: isUser ? Colors.white70 : Colors.black38,
                        fontSize: 10.5,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _BotAvatar extends StatelessWidget {
  const _BotAvatar();
  @override
  Widget build(BuildContext context) {
    return Container(
      width: 30,
      height: 30,
      decoration:
          const BoxDecoration(color: Colors.white, shape: BoxShape.circle),
      child: ClipOval(
        child: Image.asset(
          'assets/images/zannextchat.png',
          width: 30,
          height: 30,
          fit: BoxFit.cover,
        ),
      ),
    );
  }
}

class _OnlineDot extends StatelessWidget {
  const _OnlineDot();
  @override
  Widget build(BuildContext context) {
    return Container(
      width: 7,
      height: 7,
      decoration: const BoxDecoration(
          color: Color(0xFF4ADE80), shape: BoxShape.circle),
    );
  }
}

class TypingBubble extends StatefulWidget {
  const TypingBubble({super.key});
  @override
  State<TypingBubble> createState() => _TypingBubbleState();
}

class _TypingBubbleState extends State<TypingBubble>
    with SingleTickerProviderStateMixin {
  late final AnimationController _ctrl;
  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(
        vsync: this, duration: const Duration(milliseconds: 1200))
      ..repeat();
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        children: [
          const _BotAvatar(),
          Container(
            margin: const EdgeInsets.symmetric(horizontal: 6),
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: const BorderRadius.only(
                topLeft: Radius.circular(16),
                topRight: Radius.circular(16),
                bottomLeft: Radius.circular(4),
                bottomRight: Radius.circular(16),
              ),
              boxShadow: [
                BoxShadow(
                    color: Colors.black.withOpacity(0.04),
                    blurRadius: 4,
                    offset: const Offset(0, 2)),
              ],
            ),
            child: AnimatedBuilder(
              animation: _ctrl,
              builder: (_, __) => Row(
                mainAxisSize: MainAxisSize.min,
                children: List.generate(3, (i) {
                  final t = (_ctrl.value + i * 0.2) % 1.0;
                  final s = 0.6 + 0.4 * (1 - (t - 0.5).abs() * 2);
                  return Container(
                    margin: const EdgeInsets.symmetric(horizontal: 2.5),
                    width: 7,
                    height: 7,
                    decoration: BoxDecoration(
                      color: const Color(0xFF0A3A22)
                          .withOpacity(0.3 + 0.7 * s),
                      shape: BoxShape.circle,
                    ),
                  );
                }),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _InputBar extends StatelessWidget {
  final TextEditingController controller;
  final bool loading;
  final VoidCallback onSend;
  const _InputBar(
      {required this.controller, required this.loading, required this.onSend});

  static const Color kPrimary = Color(0xFF0A3A22);

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      top: false,
      child: Container(
        padding: const EdgeInsets.fromLTRB(12, 8, 12, 10),
        decoration: BoxDecoration(
          color: Colors.white,
          boxShadow: [
            BoxShadow(
                color: Colors.black.withOpacity(0.05),
                blurRadius: 10,
                offset: const Offset(0, -2)),
          ],
        ),
        child: Row(
          children: [
            Expanded(
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 14),
                decoration: BoxDecoration(
                  color: const Color(0xFFF1F3F5),
                  borderRadius: BorderRadius.circular(24),
                ),
                child: TextField(
                  controller: controller,
                  minLines: 1,
                  maxLines: 5,
                  textInputAction: TextInputAction.send,
                  onSubmitted: (_) => onSend(),
                  decoration: const InputDecoration(
                    hintText: "Type a message...",
                    hintStyle:
                        TextStyle(color: Colors.black38, fontSize: 14),
                    border: InputBorder.none,
                    contentPadding: EdgeInsets.symmetric(vertical: 12),
                  ),
                ),
              ),
            ),
            const SizedBox(width: 8),
            GestureDetector(
              onTap: loading ? null : onSend,
              child: Container(
                width: 46,
                height: 46,
                decoration: BoxDecoration(
                  color: loading ? Colors.grey : kPrimary,
                  shape: BoxShape.circle,
                ),
                child: loading
                    ? const Padding(
                        padding: EdgeInsets.all(12),
                        child: CircularProgressIndicator(
                            strokeWidth: 2, color: Colors.white),
                      )
                    : const Icon(Icons.send_rounded,
                        color: Colors.white, size: 20),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
