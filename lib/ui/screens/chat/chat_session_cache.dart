import '../../../data/models/chat_models.dart';

/// Cache in-memory (hidup selama proses app jalan) buat Chat Global, biar
/// layar chat LANGSUNG nampilin pesan + badge terakhir yang udah pernah
/// dimuat, tanpa nunggu spinner. Data terbaru tetap di-fetch di belakang
/// layar dan nimpa cache ini pas udah datang. Port ChatSessionCache.kt.
class ChatSessionCache {
  ChatSessionCache._();

  static List<ChatMessage> messages = const [];
  static Set<String> premiumUids = const {};
  static Map<String, String> clanTags = const {};
  static Map<String, int> levels = const {};
  static Map<String, String> usernameColors = const {};
  static Map<String, int> userNumbers = const {};
  static Map<String, String> avatarUrls = const {};

  static void save({
    required List<ChatMessage> messages,
    required Set<String> premiumUids,
    required Map<String, String> clanTags,
    required Map<String, int> levels,
    required Map<String, String> usernameColors,
    required Map<String, int> userNumbers,
    required Map<String, String> avatarUrls,
  }) {
    // Jangan timpa cache yang udah isi pakai state kosong (misal pas awal).
    if (messages.isEmpty) return;
    ChatSessionCache.messages = messages;
    ChatSessionCache.premiumUids = premiumUids;
    ChatSessionCache.clanTags = clanTags;
    ChatSessionCache.levels = levels;
    ChatSessionCache.usernameColors = usernameColors;
    ChatSessionCache.userNumbers = userNumbers;
    ChatSessionCache.avatarUrls = avatarUrls;
  }
}
