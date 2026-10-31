import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../core/theme.dart';

/// Стандартные эмодзи по категориям.
const Map<String, List<String>> kEmojiCategories = {
  'Смайлики': [
    '😀', '😃', '😄', '😁', '😆', '😅', '🤣', '😂', '🙂', '🙃', '😉', '😊',
    '😇', '🥰', '😍', '🤩', '😘', '😗', '😚', '😙', '🥲', '😋', '😛', '😜',
    '🤪', '😝', '🤑', '🤗', '🤭', '🫢', '🫣', '🤫', '🤔', '🫡', '🤐', '🤨',
    '😐', '😑', '😶', '🫥', '😏', '😒', '🙄', '😬', '🤥', '😌', '😔', '😪',
    '🤤', '😴', '😷', '🤒', '🤕', '🤢', '🤮', '🥵', '🥶', '🥴', '😵', '🤯',
    '🤠', '🥳', '🥸', '😎', '🤓', '🧐', '😕', '🫤', '😟', '🙁', '😮', '😯',
    '😲', '😳', '🥺', '🥹', '😦', '😧', '😨', '😰', '😥', '😢', '😭', '😱',
    '😖', '😣', '😞', '😓', '😩', '😫', '🥱', '😤', '😡', '😠', '🤬', '😈',
  ],
  'Жесты': [
    '👋', '🤚', '🖐', '✋', '🖖', '🫱', '🫲', '🫳', '🫴', '👌', '🤌', '🤏',
    '✌', '🤞', '🫰', '🤟', '🤘', '🤙', '👈', '👉', '👆', '🖕', '👇', '☝',
    '🫵', '👍', '👎', '✊', '👊', '🤛', '🤜', '👏', '🙌', '🫶', '👐', '🤲',
    '🤝', '🙏', '✍', '💪', '🦾', '🦿', '🦵', '🦶', '👂', '🦻', '👃', '🧠',
  ],
  'Сердца': [
    '❤', '🧡', '💛', '💚', '💙', '💜', '🖤', '🤍', '🤎', '💔', '❤‍🔥',
    '❤‍🩹', '❣', '💕', '💞', '💓', '💗', '💖', '💘', '💝', '💟', '☮', '✝',
  ],
  'Природа': [
    '🌸', '💮', '🏵', '🌹', '🥀', '🌺', '🌻', '🌼', '🌷', '🌱', '🪴', '🌲',
    '🌳', '🌴', '🌵', '🌾', '🌿', '☘', '🍀', '🍁', '🍂', '🍃', '🌍', '🌎',
    '🌏', '🌑', '🌒', '🌓', '🌔', '🌕', '🌖', '🌗', '🌘', '🌙', '🌚', '🌛',
  ],
  'Еда': [
    '🍏', '🍎', '🍐', '🍊', '🍋', '🍌', '🍉', '🍇', '🍓', '🫐', '🍈', '🍒',
    '🍑', '🥭', '🍍', '🥥', '🥝', '🍅', '🍆', '🥑', '🥦', '🥬', '🥒', '🌶',
    '🫑', '🌽', '🥕', '🫒', '🧄', '🧅', '🥔', '🍠', '🥐', '🍞', '🥖', '🥨',
    '🧀', '🥚', '🍳', '🧈', '🥞', '🧇', '🥓', '🥩', '🍗', '🍖', '🌭', '🍔',
  ],
  'Объекты': [
    '⚽', '🏀', '🏈', '⚾', '🥎', '🎾', '🏐', '🏉', '🥏', '🎱', '🪀', '🏓',
    '🏸', '🏒', '🏑', '🥍', '🏏', '🪃', '🥅', '⛳', '🪁', '🏹', '🎣', '🤿',
    '🥊', '🥋', '🎽', '🛹', '🛼', '🛷', '⛸', '🎿', '⛷', '🏂', '🪂', '🏋',
  ],
  'Символы': [
    '✅', '❌', '⭐', '🌟', '✨', '⚡', '🔥', '💯', '🎉', '🎊', '🎁', '🏆',
    '🥇', '🥈', '🥉', '🎯', '🚀', '💡', '📌', '📎', '📅', '⏰', '🔔', '📣',
    '💬', '💭', '👁‍🗨', '🗨', '🗯', '♠', '♣', '♥', '♦', '🃏', '🀄', '🎴',
  ],
};

/// Панель выбора эмодзи: категории + избранные (кастомные).
class EmojiPicker extends StatefulWidget {
  const EmojiPicker({super.key, required this.onPick});

  final ValueChanged<String> onPick;

  @override
  State<EmojiPicker> createState() => _EmojiPickerState();
}

class _EmojiPickerState extends State<EmojiPicker>
    with SingleTickerProviderStateMixin {
  late final TabController _tabCtrl;
  List<String> _favorites = [];
  static const _kFav = 'emoji_favorites_v1';

  @override
  void initState() {
    super.initState();
    _tabCtrl = TabController(length: kEmojiCategories.length + 1, vsync: this);
    _loadFavorites();
  }

  Future<void> _loadFavorites() async {
    final prefs = await SharedPreferences.getInstance();
    setState(() {
      _favorites = prefs.getStringList(_kFav) ?? [];
    });
  }

  Future<void> _addFavorite(String emoji) async {
    if (_favorites.contains(emoji)) return;
    final prefs = await SharedPreferences.getInstance();
    setState(() {
      _favorites = [emoji, ..._favorites];
      if (_favorites.length > 48) _favorites = _favorites.sublist(0, 48);
    });
    await prefs.setStringList(_kFav, _favorites);
  }

  @override
  void dispose() {
    _tabCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final tabs = [
      const Tab(text: '★'),
      ...kEmojiCategories.keys.map((k) => Tab(text: k)),
    ];
    return Container(
      height: 280,
      decoration: BoxDecoration(
        color: const Color(0xFF1E2F52),
        borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
      ),
      child: Column(
        children: [
          TabBar(
            controller: _tabCtrl,
            isScrollable: true,
            labelColor: AppPalette.accent,
            unselectedLabelColor: Colors.white60,
            indicatorColor: AppPalette.accent,
            tabs: tabs,
          ),
          Expanded(
            child: TabBarView(
              controller: _tabCtrl,
              children: [
                _grid(_favorites, isFavoriteTab: true),
                for (final list in kEmojiCategories.values) _grid(list),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _grid(List<String> emojis, {bool isFavoriteTab = false}) {
    if (emojis.isEmpty) {
      return Center(
        child: Text(
          isFavoriteTab
              ? 'Нажмите ★ на эмодзи, чтобы добавить в избранные'
              : 'Пусто',
          style: const TextStyle(color: Colors.white60),
        ),
      );
    }
    return GridView.builder(
      padding: const EdgeInsets.all(8),
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 8,
        mainAxisSpacing: 4,
        crossAxisSpacing: 4,
      ),
      itemCount: emojis.length,
      itemBuilder: (context, i) {
        final e = emojis[i];
        return GestureDetector(
          onTap: () => widget.onPick(e),
          onLongPress: () => _addFavorite(e),
          child: Container(
            decoration: BoxDecoration(
              color: Colors.white.withOpacity(0.06),
              borderRadius: BorderRadius.circular(10),
            ),
            alignment: Alignment.center,
            child: Text(e, style: const TextStyle(fontSize: 22)),
          ),
        );
      },
    );
  }
}

/// Открывает панель эмодзи снизу.
Future<void> showEmojiPicker(
  BuildContext context,
  ValueChanged<String> onPick,
) async {
  await showModalBottomSheet<void>(
    context: context,
    backgroundColor: Colors.transparent,
    builder: (ctx) => EmojiPicker(onPick: (e) {
      onPick(e);
      Navigator.pop(ctx);
    }),
  );
}
