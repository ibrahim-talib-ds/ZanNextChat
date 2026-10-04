import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:intl/intl.dart';
import 'package:speech_to_text/speech_to_text.dart' as stt;
import 'package:image_picker/image_picker.dart';
import 'package:flutter_markdown/flutter_markdown.dart';

class ChatbotPage extends StatefulWidget {
  const ChatbotPage({super.key});
  @override
  State<ChatbotPage> createState() => _ChatbotPageState();
}

class _ChatbotPageState extends State<ChatbotPage> {
  static const Color kPrimary = Color(0xFF0A3A22);
  static const Color kBg = Color(0xFFF6F7F9);

  // ── Groq (text) ──
  static const String kGroqKey = "PASTE_YOUR_GROQ_KEY_HERE";
  static const String kGroqUrl = "https://api.groq.com/openai/v1/chat/completions";
  static const String kModel = "openai/gpt-oss-120b";
  static const String kVisionModel = "qwen/qwen3.8-27b";
        static const String kSystemPrompt = '''You are ZanNextChat — the official friendly AI assistant inside the ZanNext app.

━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
ABOUT ZANNEXT
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
ZanNext is a marketplace in Zanzibar where people buy and sell products
(phones, fashion, home goods, sports gear, etc.). Buyers browse, chat, order.
Sellers list products and manage orders.

━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
PAYMENT
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
• No checkout page, no in-app payment.
• Preferred: CASH ON DELIVERY (pay when product arrives).
• Optional: direct mobile money (M-Pesa, Tigo Pesa, Airtel Money) only
  if you trust the seller. ZanNext is not responsible for direct transfers.

━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
MARKDOWN FORMATTING (MUST USE)
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
The app renders MARKDOWN. Always format answers with:
- ## Header  → for section titles
- **Bold**   → for important words
- • or -     → for bullet lists
- 1. 2. 3.   → for numbered steps
- Blank line between sections

NEVER write plain asterisks like **this** on their own line.
ALWAYS put a blank line before and after headers.

━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
YOUR WRITING STYLE (VERY IMPORTANT)
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
1. Be warm, polite, and friendly — like a helpful shopkeeper in Zanzibar.
2. Use SHORT sections with clear headers.
3. Use bullets (•) and numbers (1., 2., 3.) — never long paragraphs.
4. Use emojis lightly (👋 ✅ 💡 🛒 🏪) — max 3 per message.
5. Add a blank line between sections — makes it easy to read.
6. Start answers with a friendly opener when natural:
   "Sure! 😊", "Great question!", "Here's how:", "Karibu!"
7. End with a small helpful nudge:
   "Need anything else?", "Anything else I can help with?",
   "Feel free to ask!"
8. Keep it SHORT — 3 to 8 lines total for most answers.
9. If unsure, say: "Let me check on that — please contact support." Never guess.
10. NEVER mention AI, Groq, Llama, or any model name.

━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
EXAMPLE ANSWERS (STUDY THE FORMAT)
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

User: how do I buy?
You:
Sure! Here's how to buy on ZanNext 👇

1️⃣ Open the product you like
2️⃣ Tap "Buy Now"
3️⃣ Choose your delivery location
4️⃣ Confirm the order

📦 The seller prepares it right away.
💰 Payment: CASH ON DELIVERY — pay when it arrives.

Need help with anything else? 😊

─────

User: how do I sell?
You:
Karibu! 🏪 Becoming a seller is easy:

1. Open your profile
2. Tap "Become a Seller"
3. Fill in your shop details
4. Submit for approval

Once approved, you can list products and start selling! 🎉

Want help adding your first product?

─────

User: [image of shoes]
You:
I can see you shared a photo of shoes 👟

📌 Product: Men's black dress shoes
📂 Category: Formal Shoes
💰 Price range (Zanzibar): 25,000 – 60,000 TZS
🏪 Best fit for: Men's fashion / Formal wear

💡 To sell this on ZanNext:
1. Take a clear photo
2. Go to Seller Dashboard → Add Product
3. Set price and category
4. Publish

Need help listing it? Just ask! 😊

━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
ZANNEXT QUICK HELP
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
• Buy: product → Buy Now → location → confirm
• Track order: Orders tab → open order → see status
• Cancel order: open order → Cancel (while Pending)
• Chat seller: open product → seller name → Chat
• Forgot password: login → Forgot Password → email
• Become seller: profile → Become a Seller
• Add product: dashboard → Add Product → photos → details
• Receive orders: notification → Orders → Confirm → Ship → Deliver

Always guide the user step-by-step. Be kind. Be clear. Be Zanzibar-friendly.''';

  final TextEditingController _controller = TextEditingController();
  final ScrollController _scroll = ScrollController();
  final List<ChatMessage> _messages = [];
  bool _loading = false;

  // ── Voice ──
  final stt.SpeechToText _speech = stt.SpeechToText();
  bool _isListening = false;

  // ── Image picker + pending image ──
  final ImagePicker _picker = ImagePicker();
  XFile? _pendingImage;
  String? _pendingImageBase64;

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
    final raw = prefs.getString("zannextchat_history_v3");
    if (raw != null && raw.isNotEmpty) {
      final List<dynamic> list = jsonDecode(raw);
      setState(() => _messages.addAll(list.map((e) => ChatMessage.fromJson(e))));
    }
    if (_messages.isEmpty) {
      _messages.add(ChatMessage(
        role: "assistant",
        content: "Hello! 👋 I'm ZanNextChat.\n\n"
            "Ask me anything, send a 🎤 voice note, or share a 📸 product photo "
            "and I'll analyze it for you.",
        time: DateTime.now(),
        type: "text",
      ));
    }
    _scrollDown(instant: true);
  }

  Future<void> _saveHistory() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(
        "zannextchat_history_v3",
        jsonEncode(_messages.map((m) => m.toJson()).toList()));
  }

  Future<void> _clearHistory() async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text("Clear chat?"),
        content: const Text("This will delete all chat history."),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text("Cancel")),
          TextButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text("Clear", style: TextStyle(color: Colors.red))),
        ],
      ),
    );
    if (ok != true) return;
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove("zannextchat_history_v3");
    setState(() {
      _messages.clear();
      _messages.add(ChatMessage(
        role: "assistant",
        content: "Chat cleared. 👋",
        time: DateTime.now(),
        type: "text",
      ));
    });
    await _saveHistory();
  }

  // ═══════════════════════════════════════════
  //  VOICE
  // ═══════════════════════════════════════════
  Future<void> _toggleListening() async {
    if (_isListening) {
      await _speech.stop();
      setState(() => _isListening = false);
      return;
    }

    final available = await _speech.initialize(
      onStatus: (status) {
        if (status == 'done' || status == 'notListening') {
          if (mounted) setState(() => _isListening = false);
        }
      },
      onError: (err) {
        if (mounted) setState(() => _isListening = false);
      },
    );

    if (!available) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text("Microphone not available")),
        );
      }
      return;
    }

    setState(() => _isListening = true);
    await _speech.listen(
      onResult: (result) {
        setState(() {
          _controller.text = result.recognizedWords;
        });
        if (result.finalResult) setState(() => _isListening = false);
      },
      listenFor: const Duration(seconds: 30),
      pauseFor: const Duration(seconds: 3),
      partialResults: true,
    );
  }

  // ═══════════════════════════════════════════
  //  IMAGE — only stores, does NOT send
  // ═══════════════════════════════════════════
  Future<void> _pickImage(ImageSource source) async {
    try {
      final XFile? file = await _picker.pickImage(
        source: source,
        maxWidth: 1024,
        imageQuality: 80,
      );
      if (file == null) return;

      final bytes = await file.readAsBytes();
      setState(() {
        _pendingImage = file;
        _pendingImageBase64 = base64Encode(bytes);
      });

      // Focus input so user can type description
      FocusScope.of(context).requestFocus(FocusNode());
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text("Image error: $e")));
      }
    }
  }

  void _cancelPendingImage() {
    setState(() {
      _pendingImage = null;
      _pendingImageBase64 = null;
    });
  }

  // ═══════════════════════════════════════════
  //  SEND — text via Groq, image via Gemini
  // ═══════════════════════════════════════════
  Future<void> _send() async {
    final text = _controller.text.trim();
    final hasImage = _pendingImageBase64 != null;

    if (text.isEmpty && !hasImage) return;
    if (_loading) return;

    final imageToSend = _pendingImageBase64;

    // Add user message
    setState(() {
      _messages.add(ChatMessage(
        role: "user",
        content: hasImage
            ? "📸 ${text.isEmpty ? '[Photo] Analyze this product' : text}"
            : text,
        time: DateTime.now(),
        type: hasImage ? "image" : "text",
        imageBase64: imageToSend,
      ));
      _loading = true;
      _controller.clear();
      _pendingImage = null;
      _pendingImageBase64 = null;
    });
    _scrollDown();
    await _saveHistory();

    String reply;

    if (hasImage) {
      // ── Gemini Vision ──
      final prompt = text.isEmpty
          ? "Analyze this product image. Identify what it is, its category, "
            "likely price range in Zanzibar, and how the seller should list it on ZanNext."
          : "$text\n\nAlso analyze the product in the image.";
      reply = await _analyzeImage(imageToSend!, prompt);
    } else {
      // ── Groq Text ──
      reply = await _askGroq(text);
    }

    setState(() {
      _loading = false;
      _messages.add(ChatMessage(
        role: "assistant",
        content: reply,
        time: DateTime.now(),
        type: "text",
      ));
    });
    _scrollDown();
    await _saveHistory();
  }

  Future<String> _askGroq(String text) async {
    final history = _messages
        .where((m) => m.type == "text" && m.content.isNotEmpty)
        .toList()
        .reversed
        .take(10)
        .toList()
        .reversed
        .map((m) => {"role": m.role, "content": m.content})
        .toList();

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
        return data["choices"][0]["message"]["content"].toString().trim();
      }
      return "⚠️ AI is busy. Please try again. (${resp.statusCode})";
    } catch (_) {
      return "📡 Connection problem. Check your internet and try again.";
    }
  }

  Future<String> _analyzeImage(String base64Image, String userPrompt) async {
    try {
      final resp = await http
          .post(
            Uri.parse(kGroqUrl),
            headers: {
              "Content-Type": "application/json",
              "Authorization": "Bearer $kGroqKey",
            },
            body: jsonEncode({
              "model": kVisionModel,
              "messages": [
                {
                  "role": "user",
                  "content": [
                    {"type": "text", "text": "$kSystemPrompt\n\nUser request: $userPrompt"},
                    {
                      "type": "image_url",
                      "image_url": {
                        "url": "data:image/jpeg;base64,$base64Image"
                      }
                    }
                  ]
                }
              ],
              "temperature": 0.7,
              "max_tokens": 800,
            }),
          )
          .timeout(const Duration(seconds: 45));

      if (resp.statusCode == 200) {
        final data = jsonDecode(resp.body);
        return data["choices"][0]["message"]["content"].toString().trim();
      }
      return "⚠️ Vision unavailable. Code: ${resp.statusCode}";
    } catch (e) {
      return "📡 Image analysis failed: ${e.toString().substring(0, 80)}";
    }
  }


  // ═══════════════════════════════════════════
  //  Message options (copy / edit)
  // ═══════════════════════════════════════════
  void _copyMessage(ChatMessage m) {
    Clipboard.setData(ClipboardData(text: m.content));
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text("Copied ✅"), duration: Duration(seconds: 1)),
    );
  }

  Future<void> _editAndResend(int index) async {
    final m = _messages[index];
    final controller = TextEditingController(text: m.content);

    final newText = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text("Edit message"),
        content: TextField(
          controller: controller,
          maxLines: 5,
          autofocus: true,
          decoration: const InputDecoration(
            hintText: "Edit your message...",
            border: OutlineInputBorder(),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text("Cancel"),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, controller.text.trim()),
            child: const Text("Resend", style: TextStyle(color: kPrimary)),
          ),
        ],
      ),
    );

    if (newText == null || newText.isEmpty) return;

    // Remove this message AND everything after it (since it's a new conversation flow)
    setState(() {
      _messages.removeRange(index, _messages.length);
      _messages.add(ChatMessage(
        role: "user",
        content: newText,
        time: DateTime.now(),
        type: "text",
      ));
      _loading = true;
    });
    _scrollDown();
    await _saveHistory();

    // Get fresh AI response
    final reply = await _askGroq(newText);
    setState(() {
      _loading = false;
      _messages.add(ChatMessage(
        role: "assistant",
        content: reply,
        time: DateTime.now(),
        type: "text",
      ));
    });
    _scrollDown();
    await _saveHistory();
  }

  void _showMessageOptions(ChatMessage m, int index) {
    final isUser = m.role == "user";

    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) => SafeArea(
        child: Wrap(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 12, 20, 8),
              child: Text(
                isUser ? "Your message" : "ZanNextChat reply",
                style: const TextStyle(
                  color: Colors.black54,
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
            if (isUser)
              ListTile(
                leading: const Icon(Icons.edit, color: kPrimary),
                title: const Text("Edit & Resend"),
                subtitle: const Text("Change your message and get a new reply"),
                onTap: () {
                  Navigator.pop(ctx);
                  _editAndResend(index);
                },
              ),
            ListTile(
              leading: const Icon(Icons.copy, color: kPrimary),
              title: const Text("Copy"),
              onTap: () {
                Navigator.pop(ctx);
                _copyMessage(m);
              },
            ),
            ListTile(
              leading: const Icon(Icons.close, color: Colors.grey),
              title: const Text("Cancel"),
              onTap: () => Navigator.pop(ctx),
            ),
          ],
        ),
      ),
    );
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

  void _showImageSourceSheet() {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) => SafeArea(
        child: Wrap(
          children: [
            ListTile(
              leading: const Icon(Icons.camera_alt, color: kPrimary),
              title: const Text("Take Photo"),
              onTap: () {
                Navigator.pop(ctx);
                _pickImage(ImageSource.camera);
              },
            ),
            ListTile(
              leading: const Icon(Icons.photo_library, color: kPrimary),
              title: const Text("Choose from Gallery"),
              onTap: () {
                Navigator.pop(ctx);
                _pickImage(ImageSource.gallery);
              },
            ),
          ],
        ),
      ),
    );
  }

  // ═══════════════════════════════════════════
  //  BUILD
  // ═══════════════════════════════════════════
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: kBg,
      appBar: AppBar(
        backgroundColor: kPrimary,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios_new, color: Colors.white, size: 20),
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
                  errorBuilder: (_, __, ___) => const Center(
                      child: Text("🤖", style: TextStyle(fontSize: 20))),
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
                      style: TextStyle(color: Colors.white70, fontSize: 11)),
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
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 16),
              itemCount: _messages.length + (_loading ? 1 : 0),
              itemBuilder: (_, i) {
                if (i == _messages.length && _loading) {
                  return const TypingBubble();
                }
                return MessageBubble(
                  message: _messages[i],
                  onLongPress: () => _showMessageOptions(_messages[i], i),
                );
              },
            ),
          ),
          // ── Pending image preview ──
          if (_pendingImageBase64 != null)
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              color: Colors.white,
              child: Row(
                children: [
                  ClipRRect(
                    borderRadius: BorderRadius.circular(8),
                    child: Image.memory(
                      base64Decode(_pendingImageBase64!),
                      width: 60,
                      height: 60,
                      fit: BoxFit.cover,
                    ),
                  ),
                  const SizedBox(width: 10),
                  const Expanded(
                    child: Text(
                      "Add a description (optional) and tap send →",
                      style: TextStyle(color: Colors.black54, fontSize: 12),
                    ),
                  ),
                  IconButton(
                    icon: const Icon(Icons.close, color: Colors.red),
                    onPressed: _cancelPendingImage,
                  ),
                ],
              ),
            ),
          _InputBar(
            controller: _controller,
            loading: _loading,
            isListening: _isListening,
            hasPendingImage: _pendingImageBase64 != null,
            onSend: _send,
            onVoice: _toggleListening,
            onImage: _showImageSourceSheet,
          ),
        ],
      ),
    );
  }
}

// ═══════════════════════════════════════════════
//  Message model
// ═══════════════════════════════════════════════
class ChatMessage {
  final String role;
  final String content;
  final DateTime time;
  final String type;
  final String? imageBase64;

  ChatMessage({
    required this.role,
    required this.content,
    required this.time,
    this.type = "text",
    this.imageBase64,
  });

  Map<String, dynamic> toJson() => {
        "role": role,
        "content": content,
        "time": time.toIso8601String(),
        "type": type,
        "imageBase64": imageBase64,
      };

  factory ChatMessage.fromJson(Map<String, dynamic> j) => ChatMessage(
        role: j["role"],
        content: j["content"],
        time: DateTime.tryParse(j["time"] ?? "") ?? DateTime.now(),
        type: j["type"] ?? "text",
        imageBase64: j["imageBase64"],
      );
}

// ═══════════════════════════════════════════════
//  Message bubble
// ═══════════════════════════════════════════════
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
                padding: const EdgeInsets.all(10),
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
                        color: Colors.black.withValues(alpha: 0.04),
                        blurRadius: 4,
                        offset: const Offset(0, 2)),
                  ],
                ),
                child: Column(
                  crossAxisAlignment: isUser
                      ? CrossAxisAlignment.end
                      : CrossAxisAlignment.start,
                  children: [
                    if (message.imageBase64 != null)
                      ClipRRect(
                        borderRadius: BorderRadius.circular(10),
                        child: Image.memory(
                          base64Decode(message.imageBase64!),
                          width: 200,
                          fit: BoxFit.cover,
                        ),
                      ),
                    if (message.imageBase64 != null) const SizedBox(height: 6),
                    isUser
                        ? Text(
                            message.content,
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 14.5,
                              height: 1.4,
                            ),
                          )
                        : MarkdownBody(
                            data: message.content,
                            selectable: true,
                            styleSheet: MarkdownStyleSheet(
                              p: const TextStyle(
                                color: Color(0xFF1A1A1A),
                                fontSize: 14.5,
                                height: 1.5,
                              ),
                              h1: const TextStyle(
                                color: Color(0xFF0A3A22),
                                fontSize: 20,
                                fontWeight: FontWeight.w700,
                                height: 1.6,
                              ),
                              h2: const TextStyle(
                                color: Color(0xFF0A3A22),
                                fontSize: 17,
                                fontWeight: FontWeight.w700,
                                height: 1.5,
                              ),
                              h3: const TextStyle(
                                color: Color(0xFF0A3A22),
                                fontSize: 15.5,
                                fontWeight: FontWeight.w700,
                                height: 1.4,
                              ),
                              strong: const TextStyle(
                                fontWeight: FontWeight.w700,
                                color: Color(0xFF0A3A22),
                              ),
                              em: const TextStyle(
                                fontStyle: FontStyle.italic,
                              ),
                              listBullet: const TextStyle(
                                color: Color(0xFF0A3A22),
                                fontSize: 14.5,
                                height: 1.5,
                              ),
                              code: TextStyle(
                                backgroundColor: const Color(0xFFF1F3F5),
                                color: const Color(0xFF0A3A22),
                                fontFamily: 'monospace',
                                fontSize: 13,
                              ),
                              blockquoteDecoration: BoxDecoration(
                                color: const Color(0xFFF1F3F5),
                                borderRadius: BorderRadius.circular(6),
                                border: const Border(
                                  left: BorderSide(
                                    color: Color(0xFF0A3A22),
                                    width: 3,
                                  ),
                                ),
                              ),
                              blockquotePadding: const EdgeInsets.all(10),
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
          errorBuilder: (_, __, ___) =>
              const Center(child: Text("🤖", style: TextStyle(fontSize: 15))),
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
                    color: Colors.black.withValues(alpha: 0.04),
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
                          .withValues(alpha: 0.3 + 0.7 * s),
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
  final bool isListening;
  final bool hasPendingImage;
  final VoidCallback onSend;
  final VoidCallback onVoice;
  final VoidCallback onImage;

  const _InputBar({
    required this.controller,
    required this.loading,
    required this.isListening,
    required this.hasPendingImage,
    required this.onSend,
    required this.onVoice,
    required this.onImage,
  });

  static const Color kPrimary = Color(0xFF0A3A22);

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      top: false,
      child: Container(
        padding: const EdgeInsets.fromLTRB(8, 8, 8, 10),
        decoration: BoxDecoration(
          color: Colors.white,
          boxShadow: [
            BoxShadow(
                color: Colors.black.withValues(alpha: 0.05),
                blurRadius: 10,
                offset: const Offset(0, -2)),
          ],
        ),
        child: Row(
          children: [
            IconButton(
              icon: const Icon(Icons.camera_alt, color: kPrimary),
              onPressed: loading ? null : onImage,
            ),
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
                  decoration: InputDecoration(
                    hintText: hasPendingImage
                        ? "Describe the product (optional)..."
                        : "Type a message...",
                    hintStyle:
                        const TextStyle(color: Colors.black38, fontSize: 14),
                    border: InputBorder.none,
                    contentPadding: const EdgeInsets.symmetric(vertical: 12),
                  ),
                ),
              ),
            ),
            const SizedBox(width: 4),
            IconButton(
              icon: Icon(
                isListening ? Icons.mic : Icons.mic_none,
                color: isListening ? Colors.red : kPrimary,
              ),
              onPressed: loading ? null : onVoice,
            ),
            const SizedBox(width: 4),
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
