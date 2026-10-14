import 'package:flutter/material.dart';

/// A simple intent-based chatbot that answers common air-quality questions
/// using the AQI data already fetched by the main screen. This is NOT a
/// full LLM-based bot — it matches keywords in the user's message to a
/// fixed set of supported question types, which is an honest, scoped
/// approach for a mini project (see viva prep notes).
class ChatScreen extends StatefulWidget {
  final int aqi;
  final String category;
  final String cityName;
  final Map<String, dynamic>? pollutants;

  const ChatScreen({
    super.key,
    required this.aqi,
    required this.category,
    required this.cityName,
    required this.pollutants,
  });

  @override
  State<ChatScreen> createState() => _ChatScreenState();
}

class _ChatMessage {
  final String text;
  final bool isUser;
  _ChatMessage(this.text, this.isUser);
}

class _ChatScreenState extends State<ChatScreen> {
  final TextEditingController _controller = TextEditingController();
  final ScrollController _scrollController = ScrollController();
  final List<_ChatMessage> _messages = [];

  @override
  void initState() {
    super.initState();
    _messages.add(_ChatMessage(
      "👋 Hi! I'm your Air Quality Assistant for ${widget.cityName}. "
      "Ask me things like \"is it safe to jog? 🏃\", \"why is AQI high? 🤔\", "
      "\"should I wear a mask? 😷\", or \"what is PM2.5? 🌫️\"",
      false,
    ));
  }

  @override
  void dispose() {
    _controller.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  void _send() {
    final text = _controller.text.trim();
    if (text.isEmpty) return;

    setState(() {
      _messages.add(_ChatMessage(text, true));
      _messages.add(_ChatMessage(_generateReply(text), false));
    });

    _controller.clear();

    // Scroll to bottom after the frame builds
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scrollController.hasClients) {
        _scrollController.animateTo(
          _scrollController.position.maxScrollExtent,
          duration: const Duration(milliseconds: 250),
          curve: Curves.easeOut,
        );
      }
    });
  }

  // --- Intent matching -----------------------------------------------

  String _generateReply(String message) {
    final msg = message.toLowerCase();

    // Greetings
    if (_matchesAny(msg, ['hi', 'hello', 'hey'])) {
      return "👋 Hello! Ask me about air quality in ${widget.cityName} — "
          "for example, \"is it safe to exercise? 🏃\" or \"what's the AQI? 📊\"";
    }

    // Current AQI value
    if (_matchesAny(msg, ['what is the aqi', "what's the aqi", 'current aqi', 'aqi now'])) {
      return "📊 The current AQI in ${widget.cityName} is ${widget.aqi}, "
          "categorized as \"${widget.category}\" ${_categoryEmoji()}.";
    }

    // Safety for outdoor activity / exercise / jogging
    if (_matchesAny(msg, ['safe to jog', 'safe to run', 'safe to exercise',
        'safe outside', 'go outside', 'go for a walk', 'safe to walk'])) {
      return _adviceForActivity();
    }

    // Mask advice
    if (_matchesAny(msg, ['mask', 'wear a mask'])) {
      return _maskAdvice();
    }

    // Why is AQI high/bad
    if (_matchesAny(msg, ['why is aqi high', 'why is the air quality bad',
        'why is it bad', 'why bad', 'why high', 'reason'])) {
      return _dominantPollutantExplanation();
    }

    // Pollutant definitions
    if (msg.contains('pm2.5') || msg.contains('pm 2.5')) {
      return "🌫️ PM2.5 refers to fine particulate matter smaller than 2.5 "
          "micrometers — small enough to enter the lungs and bloodstream. "
          "Common sources include vehicle exhaust, dust, and burning. "
          "Right now it reads ${_pollutantValue('pm25')} in ${widget.cityName}.";
    }
    if (msg.contains('pm10')) {
      return "💨 PM10 refers to coarser particulate matter (up to 10 "
          "micrometers), like dust and pollen. It's less dangerous than "
          "PM2.5 but can still irritate airways. Current reading: "
          "${_pollutantValue('pm10')}.";
    }
    if (msg.contains('co') && !msg.contains('co2')) {
      return "🚗 CO (Carbon Monoxide) is a gas from vehicle emissions and "
          "combustion. At high levels it reduces oxygen in the blood. "
          "Current reading: ${_pollutantValue('co')}.";
    }
    if (msg.contains('no2')) {
      return "🏭 NO2 (Nitrogen Dioxide) mainly comes from vehicle and "
          "industrial emissions, and can irritate the respiratory system. "
          "Current reading: ${_pollutantValue('no2')}.";
    }
    if (msg.contains('o3') || msg.contains('ozone')) {
      return "☀️ O3 (Ozone) at ground level is a pollutant formed by chemical "
          "reactions between sunlight and vehicle/industrial emissions. "
          "Current reading: ${_pollutantValue('o3')}.";
    }

    // Sensitive groups
    if (_matchesAny(msg, ['children', 'elderly', 'asthma', 'sensitive'])) {
      return "👨‍👩‍👧 For sensitive groups (children, elderly, people with asthma "
          "or heart conditions): at AQI ${widget.aqi} (\"${widget.category}\"), "
          "${widget.aqi > 100 ? "it's best to limit outdoor exertion and keep rescue medication handy if applicable. ⚠️" : "current conditions are generally fine, but stay alert to any personal symptoms. ✅"}";
    }

    // Fallback
    return "🤔 I can help with questions about current AQI, whether it's "
        "safe to go outside 🏃, mask advice 😷, or what specific pollutants "
        "like PM2.5, PM10, CO, NO2, or O3 mean. Try asking one of those!";
  }

  bool _matchesAny(String msg, List<String> phrases) {
    return phrases.any((p) => msg.contains(p));
  }

  String _pollutantValue(String key) {
    if (widget.pollutants != null && widget.pollutants!.containsKey(key)) {
      return widget.pollutants![key]['v'].toString();
    }
    return "not reported at the nearest station";
  }

  String _categoryEmoji() {
    final aqi = widget.aqi;
    if (aqi <= 50) return '🟢';
    if (aqi <= 100) return '🟡';
    if (aqi <= 150) return '🟠';
    if (aqi <= 200) return '🔴';
    if (aqi <= 300) return '🟣';
    return '🟤';
  }

  String _adviceForActivity() {
    final aqi = widget.aqi;
    if (aqi <= 50) {
      return "✅ Yes, it's a great time to be outside — AQI is $aqi (Good) 🟢 "
          "in ${widget.cityName}. Enjoy your activity! 🏃‍♂️";
    } else if (aqi <= 100) {
      return "🙂 Generally fine for most people. AQI is $aqi (Moderate) 🟡 — "
          "if you're unusually sensitive to pollution, consider a shorter "
          "or lighter session.";
    } else if (aqi <= 150) {
      return "⚠️ Caution: AQI is $aqi (Unhealthy for Sensitive Groups) 🟠. "
          "If you have asthma, are elderly, or a child, consider indoor "
          "exercise instead today. 🏠";
    } else if (aqi <= 200) {
      return "❌ Not recommended: AQI is $aqi (Unhealthy) 🔴. Everyone may "
          "experience effects — it's best to move exercise indoors today. 🏠";
    } else {
      return "🚨 No — AQI is $aqi (${widget.category}). This is a health "
          "alert level. Please avoid outdoor activity entirely right now.";
    }
  }

  String _maskAdvice() {
    final aqi = widget.aqi;
    if (aqi <= 100) {
      return "✅ Not necessary at AQI $aqi — air quality is acceptable for "
          "most people right now.";
    } else if (aqi <= 150) {
      return "😷 Consider a mask (N95/KN95) if you're in a sensitive group "
          "and need to be outdoors for a while. AQI is $aqi.";
    } else {
      return "😷 Yes, wearing a mask (N95/KN95) outdoors is recommended at "
          "AQI $aqi. Ordinary cloth or surgical masks don't filter fine "
          "particulates effectively.";
    }
  }

  String _dominantPollutantExplanation() {
    if (widget.pollutants == null || widget.pollutants!.isEmpty) {
      return "📊 AQI is $aqiText (${widget.category}), but I don't have a "
          "detailed pollutant breakdown for this station.";
    }
    // Find the pollutant with the highest reported value among common ones
    final keys = ['pm25', 'pm10', 'co', 'no2', 'o3', 'so2'];
    String? topKey;
    double topVal = -1;
    for (final k in keys) {
      if (widget.pollutants!.containsKey(k)) {
        final v = (widget.pollutants![k]['v'] as num).toDouble();
        if (v > topVal) {
          topVal = v;
          topKey = k;
        }
      }
    }
    final names = {
      'pm25': 'PM2.5 (fine particulate matter) 🌫️',
      'pm10': 'PM10 (coarse particulate matter) 💨',
      'co': 'CO (carbon monoxide) 🚗',
      'no2': 'NO2 (nitrogen dioxide) 🏭',
      'o3': 'O3 (ground-level ozone) ☀️',
      'so2': 'SO2 (sulfur dioxide) 🏭',
    };
    if (topKey == null) {
      return "📊 AQI is $aqiText (${widget.category}) in ${widget.cityName}.";
    }
    return "📊 AQI is $aqiText (${widget.category}) ${_categoryEmoji()} in ${widget.cityName}, "
        "mainly driven by elevated ${names[topKey]} levels (reading: $topVal). "
        "This is often linked to vehicle traffic 🚗, dust 💨, or local burning 🔥, "
        "depending on the pollutant.";
  }

  String get aqiText => widget.aqi.toString();

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Air Quality Assistant '),
      ),
      body: Column(
        children: [
          Expanded(
            child: ListView.builder(
              controller: _scrollController,
              padding: const EdgeInsets.all(12),
              itemCount: _messages.length,
              itemBuilder: (context, index) {
                final m = _messages[index];
                return Align(
                  alignment: m.isUser
                      ? Alignment.centerRight
                      : Alignment.centerLeft,
                  child: Container(
                    margin: const EdgeInsets.symmetric(vertical: 4),
                    padding: const EdgeInsets.symmetric(
                        horizontal: 14, vertical: 10),
                    constraints: BoxConstraints(
                      maxWidth: MediaQuery.of(context).size.width * 0.75,
                    ),
                    decoration: BoxDecoration(
                      color: m.isUser
                          ? Colors.teal.shade400
                          : Colors.grey.shade200,
                      borderRadius: BorderRadius.circular(16),
                    ),
                    child: Text(
                      m.text,
                      style: TextStyle(
                        color: m.isUser ? Colors.white : Colors.black87,
                      ),
                    ),
                  ),
                );
              },
            ),
          ),
          SafeArea(
            child: Padding(
              padding: const EdgeInsets.all(8.0),
              child: Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: _controller,
                      decoration: InputDecoration(
                        hintText: 'Ask about air quality...',
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(24),
                        ),
                        contentPadding: const EdgeInsets.symmetric(
                            horizontal: 16, vertical: 10),
                      ),
                      onSubmitted: (_) => _send(),
                    ),
                  ),
                  const SizedBox(width: 8),
                  IconButton.filled(
                    onPressed: _send,
                    icon: const Icon(Icons.send),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}