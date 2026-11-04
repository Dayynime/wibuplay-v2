import 'package:flutter/material.dart';

import '../../core/theme/app_colors.dart';
import '../../data/models/friend_models.dart';

/// Saring daftar teman berdasarkan nama atau nomor ID ("123" / "#123").
List<FriendDisplay> filterFriends(List<FriendDisplay> friends, String query) {
  final q = query.trim().toLowerCase().replaceFirst('#', '');
  if (q.isEmpty) return friends;
  return friends
      .where((f) => f.username.toLowerCase().contains(q) || (f.userNumber?.toString().contains(q) ?? false))
      .toList();
}

/// Kolom cari teman untuk lembar undang/bagikan (clan, nobar, catur).
class FriendSearchField extends StatefulWidget {
  const FriendSearchField({super.key, required this.onChanged});

  final ValueChanged<String> onChanged;

  @override
  State<FriendSearchField> createState() => _FriendSearchFieldState();
}

class _FriendSearchFieldState extends State<FriendSearchField> {
  final _ctrl = TextEditingController();

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return TextField(
      controller: _ctrl,
      onChanged: (v) {
        setState(() {}); // tombol hapus muncul/hilang
        widget.onChanged(v);
      },
      textInputAction: TextInputAction.search,
      style: const TextStyle(color: Colors.white, fontSize: 14),
      cursorColor: AppColors.accentViolet,
      decoration: InputDecoration(
        isDense: true,
        hintText: 'Cari nama atau ID teman',
        hintStyle: const TextStyle(color: AppColors.textMuted, fontSize: 14),
        prefixIcon: const Icon(Icons.search_rounded, color: AppColors.textMuted, size: 20),
        suffixIcon: _ctrl.text.isEmpty
            ? null
            : IconButton(
                icon: const Icon(Icons.close_rounded, color: AppColors.textMuted, size: 18),
                onPressed: () {
                  _ctrl.clear();
                  setState(() {});
                  widget.onChanged('');
                },
              ),
        filled: true,
        fillColor: const Color(0x0FFFFFFF),
        contentPadding: const EdgeInsets.symmetric(vertical: 10),
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide.none),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(color: AppColors.accentViolet),
        ),
      ),
    );
  }
}

/// Teks "tidak ketemu" saat pencarian kosong.
class FriendSearchEmpty extends StatelessWidget {
  const FriendSearchEmpty({super.key});

  @override
  Widget build(BuildContext context) {
    return const Padding(
      padding: EdgeInsets.all(16),
      child: Text('Tidak ada teman dengan nama atau ID itu.', style: TextStyle(color: AppColors.textSecondary)),
    );
  }
}
