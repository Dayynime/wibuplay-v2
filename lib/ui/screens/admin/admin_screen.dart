import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/theme/app_colors.dart';
import '../../../data/models/admin_models.dart';
import '../../../data/models/chat_models.dart' show ChatProfile;
import '../../../data/repository/admin_repository.dart';
import '../../../data/repository/chat_repository.dart' show ChatRepository;
import '../../../providers.dart';
import '../../components/game_badges.dart' show UserAvatar;
import '../../components/role_badges.dart';

const Color _banRed = Color(0xFFE53935);
const Color _banRedSoft = Color(0xFFE57373);
const Color _okGreen = Color(0xFF43A047);
const Color _okGreenSoft = Color(0xFF81C784);
const Color _border = Color(0x14FFFFFF);

/// Menjalankan satu aksi admin: tampilkan loading, hasilnya jadi banner
/// sukses/gagal di atas, lalu daftar di semua tab di-refresh.
typedef AdminRun = Future<void> Function(Future<void> Function() action, String okMessage);

String _errorText(Object e, [String fallback = 'Terjadi kesalahan, coba lagi']) =>
    e is AdminException ? e.message : fallback;

bool _blank(String? s) => s == null || s.trim().isEmpty;

/// Profil chat (username/avatar) untuk [uids]; gagal = kosong (nama tetap
/// "Tanpa username"). Dipakai karena Edge Function admin tidak selalu
/// mengirim username.
Future<Map<String, ChatProfile>> _profilesFor(ChatRepository chat, Iterable<String> uids) async {
  final list = uids.where((u) => u.isNotEmpty).toList();
  if (list.isEmpty) return const {};
  try {
    return await chat.getProfilesForUids(list);
  } catch (_) {
    return const {};
  }
}

Future<List<AdminUser>> _fillUsers(ChatRepository chat, List<AdminUser> users) async {
  final profiles = await _profilesFor(
    chat,
    users.where((u) => _blank(u.username)).map((u) => u.firebaseUid),
  );
  if (profiles.isEmpty) return users;
  return [
    for (final u in users)
      if (profiles[u.firebaseUid] case final p?)
        u.withProfile(username: p.username, avatarUrl: p.avatarUrl)
      else
        u,
  ];
}

Future<List<AdminRoleEntry>> _fillRoles(ChatRepository chat, List<AdminRoleEntry> roles) async {
  final profiles = await _profilesFor(
    chat,
    roles.where((r) => _blank(r.username)).map((r) => r.firebaseUid),
  );
  if (profiles.isEmpty) return roles;
  return [
    for (final r in roles)
      if (profiles[r.firebaseUid] case final p?)
        r.withProfile(username: p.username, avatarUrl: p.avatarUrl)
      else
        r,
  ];
}

String _roleName(ZenimeRole r) {
  switch (r) {
    case ZenimeRole.developer:
      return 'Developer';
    case ZenimeRole.admin:
      return 'Admin';
    case ZenimeRole.moderator:
      return 'Moderator';
  }
}

/// Panel Admin (port AdminScreen.kt). Hanya untuk user yang punya role
/// (developer/admin/moderator). Role dicek ulang ke server saat layar dibuka,
/// dan setiap aksi dicek lagi di server.
class AdminScreen extends ConsumerStatefulWidget {
  const AdminScreen({super.key});

  @override
  ConsumerState<AdminScreen> createState() => _AdminScreenState();
}

class _AdminScreenState extends ConsumerState<AdminScreen> {
  ZenimeRole? _myRole;
  bool _loadingRole = true;
  String? _roleError;

  int _tab = 0;
  bool _processing = false;
  String? _message;
  bool _messageIsError = false;
  Timer? _messageTimer;

  /// Dinaikkan setelah tiap aksi sukses; tab yang mendengarkan akan memuat ulang.
  final ValueNotifier<int> _refresh = ValueNotifier<int>(0);

  String get _myUid => ref.read(authUserProvider).valueOrNull?.uid ?? '';

  @override
  void initState() {
    super.initState();
    // Ditunda satu microtask supaya setState di dalam _loadRole tidak jalan
    // di tengah initState.
    Future.microtask(() {
      if (mounted) _loadRole();
    });
  }

  @override
  void dispose() {
    _messageTimer?.cancel();
    _refresh.dispose();
    super.dispose();
  }

  Future<void> _loadRole() async {
    setState(() {
      _loadingRole = true;
      _roleError = null;
    });
    try {
      final r = await ref.read(adminRepositoryProvider).getMyRole();
      if (!mounted) return;
      setState(() {
        _myRole = ZenimeRole.fromValue(r.role);
        _loadingRole = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _myRole = null;
        _loadingRole = false;
        _roleError = _errorText(e, 'Gagal cek akses, coba lagi.');
      });
    }
  }

  void _showMessage(String text, bool isError) {
    _messageTimer?.cancel();
    setState(() {
      _message = text;
      _messageIsError = isError;
    });
    _messageTimer = Timer(const Duration(seconds: 5), () {
      if (mounted) setState(() => _message = null);
    });
  }

  Future<void> _run(Future<void> Function() action, String okMessage) async {
    if (_processing) return;
    _messageTimer?.cancel();
    setState(() {
      _processing = true;
      _message = null;
    });
    try {
      await action();
      if (!mounted) return;
      _showMessage(okMessage, false);
      _refresh.value++;
    } catch (e) {
      if (mounted) _showMessage(_errorText(e), true);
    } finally {
      if (mounted) setState(() => _processing = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.backgroundDark,
      appBar: AppBar(
        backgroundColor: AppColors.backgroundDark,
        foregroundColor: AppColors.textWhite,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        title: const Text('Panel Admin', style: TextStyle(fontWeight: FontWeight.w800, fontSize: 20)),
      ),
      body: _buildBody(),
    );
  }

  Widget _buildBody() {
    if (_loadingRole) {
      return const Center(
        child: CircularProgressIndicator(color: AppColors.accentViolet, strokeWidth: 3),
      );
    }
    final role = _myRole;
    if (role == null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                _roleError ?? 'Kamu nggak punya akses ke halaman ini.',
                textAlign: TextAlign.center,
                style: const TextStyle(color: AppColors.textSecondary),
              ),
              if (_roleError != null) ...[
                const SizedBox(height: 8),
                TextButton(onPressed: _loadRole, child: const Text('Coba lagi')),
              ],
            ],
          ),
        ),
      );
    }

    final labels = <String>[
      'Semua User',
      if (role == ZenimeRole.developer) 'Pemegang Role',
      'Info',
    ];
    final tab = _tab < labels.length ? _tab : 0;
    final info = roleInfoFrom(role.name, null);

    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 4, 16, 10),
          child: Row(
            children: [
              if (info != null) RoleBadgeChip(info: info, height: 22),
            ],
          ),
        ),
        if (_message != null)
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 10),
            child: _FeedbackCard(text: _message!, isError: _messageIsError),
          ),
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
          child: _PillTabs(
            labels: labels,
            selected: tab,
            onChanged: (i) => setState(() => _tab = i),
          ),
        ),
        if (_processing)
          const LinearProgressIndicator(
            minHeight: 2,
            color: AppColors.accentViolet,
            backgroundColor: Colors.transparent,
          ),
        Expanded(
          // IndexedStack: tab tetap hidup, jadi pencarian dan daftar tidak
          // hilang waktu pindah tab.
          child: IndexedStack(
            index: tab,
            children: [
              _UserListTab(
                myRole: role,
                myUid: _myUid,
                refresh: _refresh,
                busy: _processing,
                onAction: _run,
              ),
              if (role == ZenimeRole.developer)
                _RoleHoldersTab(
                  refresh: _refresh,
                  busy: _processing,
                  onAction: _run,
                ),
              _InfoTab(role: role),
            ],
          ),
        ),
      ],
    );
  }
}

// ------------------------------------------------------------------- umum

class _PillTabs extends StatelessWidget {
  const _PillTabs({required this.labels, required this.selected, required this.onChanged});

  final List<String> labels;
  final int selected;
  final ValueChanged<int> onChanged;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(4),
      decoration: BoxDecoration(
        color: AppColors.surfaceDark,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: _border),
      ),
      child: Row(
        children: [
          for (var i = 0; i < labels.length; i++)
            Expanded(
              child: GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTap: () => onChanged(i),
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 220),
                  height: 38,
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(12),
                    gradient: i == selected
                        ? const LinearGradient(
                            colors: [AppColors.accentViolet, Color(0xFFFF6B4A)],
                          )
                        : null,
                  ),
                  child: Text(
                    labels[i],
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      color: i == selected ? Colors.white : AppColors.textSecondary,
                      fontSize: 13,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

class _FeedbackCard extends StatelessWidget {
  const _FeedbackCard({required this.text, required this.isError});

  final String text;
  final bool isError;

  @override
  Widget build(BuildContext context) {
    final base = isError ? _banRed : _okGreen;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: base.withValues(alpha: 0.14),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Text(
        text,
        style: TextStyle(
          color: isError ? _banRedSoft : _okGreenSoft,
          fontSize: 13.5,
        ),
      ),
    );
  }
}

class _ActionChip extends StatelessWidget {
  const _ActionChip({
    required this.text,
    required this.onTap,
    this.destructive = false,
  });

  final String text;
  final VoidCallback? onTap;
  final bool destructive;

  @override
  Widget build(BuildContext context) {
    final color = destructive ? _banRedSoft : AppColors.accentViolet;
    return Opacity(
      opacity: onTap == null ? 0.4 : 1,
      child: Material(
        color: (destructive ? _banRed : AppColors.accentViolet).withValues(alpha: 0.16),
        borderRadius: BorderRadius.circular(8),
        child: InkWell(
          borderRadius: BorderRadius.circular(8),
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
            child: Text(
              text,
              style: TextStyle(color: color, fontSize: 12.5, fontWeight: FontWeight.w700),
            ),
          ),
        ),
      ),
    );
  }
}

class _StatusChip extends StatelessWidget {
  const _StatusChip(this.text);

  final String text;

  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
        decoration: BoxDecoration(
          color: _banRed.withValues(alpha: 0.16),
          borderRadius: BorderRadius.circular(20),
        ),
        child: Text(text, style: const TextStyle(color: _banRedSoft, fontSize: 11.5)),
      );
}

class _Card extends StatelessWidget {
  const _Card({required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) => Container(
        width: double.infinity,
        margin: const EdgeInsets.symmetric(vertical: 5),
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: AppColors.surfaceDark,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: _border),
        ),
        child: child,
      );
}

// --------------------------------------------------------------- Semua User

class _UserListTab extends ConsumerStatefulWidget {
  const _UserListTab({
    required this.myRole,
    required this.myUid,
    required this.refresh,
    required this.busy,
    required this.onAction,
  });

  final ZenimeRole myRole;
  final String myUid;
  final Listenable refresh;
  final bool busy;
  final AdminRun onAction;

  @override
  ConsumerState<_UserListTab> createState() => _UserListTabState();
}

class _UserListTabState extends ConsumerState<_UserListTab> {
  final TextEditingController _search = TextEditingController();
  Timer? _debounce;

  List<AdminUser> _users = const [];
  bool _loading = true;
  bool _loadingMore = false;
  bool _hasMore = false;
  String? _error;

  /// Nomor request terakhir; hasil request lama (mis. ketikan sebelumnya) dibuang.
  int _req = 0;

  @override
  void initState() {
    super.initState();
    widget.refresh.addListener(_onRefresh);
    Future.microtask(() {
      if (mounted) _load();
    });
  }

  @override
  void dispose() {
    widget.refresh.removeListener(_onRefresh);
    _debounce?.cancel();
    _search.dispose();
    super.dispose();
  }

  void _onRefresh() => _load(silent: true);

  void _onSearchChanged(String _) {
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 350), () => _load());
  }

  /// [silent] = refresh setelah aksi: daftar lama tetap tampil, tanpa spinner.
  Future<void> _load({bool silent = false}) async {
    final id = ++_req;
    if (!silent) {
      setState(() {
        _loading = true;
        _error = null;
      });
    }
    try {
      final (rawList, more) =
          await ref.read(adminRepositoryProvider).listUsers(search: _search.text, offset: 0);
      final list = await _fillUsers(ref.read(chatRepositoryProvider), rawList);
      if (!mounted || id != _req) return;
      setState(() {
        _users = list;
        _hasMore = more;
        _loading = false;
        _error = null;
      });
    } catch (e) {
      if (!mounted || id != _req) return;
      setState(() {
        _loading = false;
        if (!silent) _error = _errorText(e, 'Gagal memuat daftar user');
      });
    }
  }

  Future<void> _loadMore() async {
    if (_loadingMore || !_hasMore) return;
    final id = _req;
    setState(() => _loadingMore = true);
    try {
      final (rawList, more) = await ref
          .read(adminRepositoryProvider)
          .listUsers(search: _search.text, offset: _users.length);
      final list = await _fillUsers(ref.read(chatRepositoryProvider), rawList);
      if (!mounted) return;
      if (id != _req) {
        setState(() => _loadingMore = false);
        return;
      }
      setState(() {
        _users = [..._users, ...list];
        _hasMore = more;
        _loadingMore = false;
      });
    } catch (_) {
      if (mounted) setState(() => _loadingMore = false);
    }
  }

  Future<void> _setRole(AdminUser u) async {
    final result = await showDialog<_RoleResult>(
      context: context,
      builder: (_) => _RoleAssignDialog(user: u),
    );
    if (result == null || !mounted) return;
    final repo = ref.read(adminRepositoryProvider);
    if (result.remove) {
      await widget.onAction(() => repo.removeRole(u.firebaseUid), 'Role dicabut');
    } else {
      await widget.onAction(
        () => repo.setRole(u.firebaseUid, result.role!.name, badgeColor: result.badgeColor),
        'Role berhasil diset',
      );
    }
  }

  Future<void> _banDevice(AdminUser u) async {
    final r = await showDialog<_ReasonResult>(
      context: context,
      builder: (_) => _ReasonDialog(
        title: 'Ban device: ${u.displayName}',
        description: 'Target nggak akan bisa daftar/login lagi dari HP yang sama.',
      ),
    );
    if (r == null || !mounted) return;
    await widget.onAction(
      () => ref.read(adminRepositoryProvider).banDevice(u.firebaseUid, reason: r.reason),
      'Device diban',
    );
  }

  Future<void> _banAccount(AdminUser u) async {
    final r = await showDialog<_ReasonResult>(
      context: context,
      builder: (_) => _ReasonDialog(
        title: 'Ban akun: ${u.displayName}',
        description: 'Target nggak bisa login lagi walau ganti device.',
      ),
    );
    if (r == null || !mounted) return;
    await widget.onAction(
      () => ref.read(adminRepositoryProvider).banUser(u.firebaseUid, reason: r.reason),
      'Akun diban',
    );
  }

  Future<void> _unbanAccount(AdminUser u) => widget.onAction(
        () => ref.read(adminRepositoryProvider).unbanUser(u.firebaseUid),
        'Ban akun dicabut',
      );

  Future<void> _unbanDevice(AdminUser u) {
    final deviceId = u.lastDeviceId;
    if (deviceId == null || deviceId.isEmpty) return Future.value();
    return widget.onAction(
      () => ref.read(adminRepositoryProvider).unbanDevice(deviceId),
      'Ban device dicabut',
    );
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 4, 16, 8),
          child: TextField(
            controller: _search,
            onChanged: _onSearchChanged,
            textInputAction: TextInputAction.search,
            style: const TextStyle(color: Colors.white),
            cursorColor: AppColors.accentViolet,
            decoration: InputDecoration(
              hintText: 'Cari nama, kode Zenime, atau UID...',
              hintStyle: const TextStyle(color: AppColors.textMuted, fontSize: 14),
              prefixIcon: const Icon(Icons.search, color: AppColors.textMuted),
              filled: true,
              fillColor: AppColors.surfaceDark,
              contentPadding: const EdgeInsets.symmetric(vertical: 12),
              enabledBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(14),
                borderSide: const BorderSide(color: _border),
              ),
              focusedBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(14),
                borderSide: const BorderSide(color: AppColors.accentViolet),
              ),
            ),
          ),
        ),
        Expanded(child: _buildList()),
      ],
    );
  }

  Widget _buildList() {
    if (_loading) {
      return const Center(
        child: CircularProgressIndicator(color: AppColors.accentViolet, strokeWidth: 3),
      );
    }
    if (_error != null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(_error!, textAlign: TextAlign.center, style: const TextStyle(color: _banRedSoft)),
              const SizedBox(height: 8),
              TextButton(onPressed: () => _load(), child: const Text('Coba lagi')),
            ],
          ),
        ),
      );
    }
    if (_users.isEmpty) {
      return const Center(
        child: Text('Nggak ada user ditemukan.', style: TextStyle(color: AppColors.textSecondary)),
      );
    }
    return ListView.builder(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 24),
      itemCount: _users.length + 1,
      itemBuilder: (context, i) {
        if (i == _users.length) {
          if (!_hasMore) return const SizedBox(height: 8);
          return Padding(
            padding: const EdgeInsets.symmetric(vertical: 12),
            child: Center(
              child: _loadingMore
                  ? const SizedBox(
                      width: 24,
                      height: 24,
                      child: CircularProgressIndicator(strokeWidth: 2.5, color: AppColors.accentViolet),
                    )
                  : OutlinedButton(
                      onPressed: _loadMore,
                      child: const Text('Muat lebih banyak'),
                    ),
            ),
          );
        }
        final u = _users[i];
        return _UserRow(
          user: u,
          isSelf: u.firebaseUid == widget.myUid,
          myRole: widget.myRole,
          busy: widget.busy,
          onSetRole: () => _setRole(u),
          onBanDevice: () => _banDevice(u),
          onUnbanDevice: () => _unbanDevice(u),
          onBanAccount: () => _banAccount(u),
          onUnbanAccount: () => _unbanAccount(u),
        );
      },
    );
  }
}

class _UserRow extends StatelessWidget {
  const _UserRow({
    required this.user,
    required this.isSelf,
    required this.myRole,
    required this.busy,
    required this.onSetRole,
    required this.onBanDevice,
    required this.onUnbanDevice,
    required this.onBanAccount,
    required this.onUnbanAccount,
  });

  final AdminUser user;
  final bool isSelf;
  final ZenimeRole myRole;
  final bool busy;
  final VoidCallback onSetRole;
  final VoidCallback onBanDevice;
  final VoidCallback onUnbanDevice;
  final VoidCallback onBanAccount;
  final VoidCallback onUnbanAccount;

  @override
  Widget build(BuildContext context) {
    final entryRole = ZenimeRole.fromValue(user.role);
    final roleInfo = roleInfoFrom(user.role, user.badgeColor);
    final isDev = myRole == ZenimeRole.developer;
    final canBanAccount = isDev || myRole == ZenimeRole.admin;
    // Tombol Unban Device butuh device terakhir user; kalau tidak ada, nonaktif.
    final hasDevice = (user.lastDeviceId ?? '').isNotEmpty;

    return _Card(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              UserAvatar(username: user.displayName, url: user.avatarUrl, size: 40),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      user.displayName,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 14.5,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    if ((user.zenimeCode ?? '').isNotEmpty)
                      Text(
                        user.zenimeCode!,
                        style: const TextStyle(color: AppColors.textSecondary, fontSize: 12),
                      ),
                  ],
                ),
              ),
              if (isSelf)
                const Text(
                  'Kamu',
                  style: TextStyle(
                    color: AppColors.accentViolet,
                    fontSize: 12,
                    fontWeight: FontWeight.w700,
                  ),
                ),
            ],
          ),
          if (roleInfo != null || user.bannedAccount || user.bannedDevice) ...[
            const SizedBox(height: 8),
            Wrap(
              spacing: 6,
              runSpacing: 6,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                if (roleInfo != null) RoleBadgeChip(info: roleInfo, height: 22),
                if (user.bannedAccount) const _StatusChip('Diban (akun)'),
                if (user.bannedDevice) const _StatusChip('Diban (device)'),
              ],
            ),
          ],
          if (!isSelf) ...[
            const SizedBox(height: 10),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                if (isDev) ...[
                  _ActionChip(
                    text: entryRole != null ? 'Ubah Role' : 'Set Role',
                    onTap: busy ? null : onSetRole,
                  ),
                  if (user.bannedDevice)
                    _ActionChip(
                      text: 'Unban Device',
                      onTap: busy || !hasDevice ? null : onUnbanDevice,
                    )
                  else
                    _ActionChip(
                      text: 'Ban Device',
                      destructive: true,
                      onTap: busy ? null : onBanDevice,
                    ),
                ],
                if (canBanAccount)
                  if (user.bannedAccount)
                    _ActionChip(text: 'Unban Akun', onTap: busy ? null : onUnbanAccount)
                  else
                    _ActionChip(
                      text: 'Ban Akun',
                      destructive: true,
                      onTap: busy ? null : onBanAccount,
                    ),
              ],
            ),
          ],
        ],
      ),
    );
  }
}

// ----------------------------------------------------------- Pemegang Role

class _RoleHoldersTab extends ConsumerStatefulWidget {
  const _RoleHoldersTab({
    required this.refresh,
    required this.busy,
    required this.onAction,
  });

  final Listenable refresh;
  final bool busy;
  final AdminRun onAction;

  @override
  ConsumerState<_RoleHoldersTab> createState() => _RoleHoldersTabState();
}

class _RoleHoldersTabState extends ConsumerState<_RoleHoldersTab> {
  List<AdminRoleEntry> _roles = const [];
  bool _loading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    widget.refresh.addListener(_onRefresh);
    Future.microtask(() {
      if (mounted) _load();
    });
  }

  @override
  void dispose() {
    widget.refresh.removeListener(_onRefresh);
    super.dispose();
  }

  void _onRefresh() => _load(silent: true);

  Future<void> _load({bool silent = false}) async {
    if (!silent) {
      setState(() {
        _loading = true;
        _error = null;
      });
    }
    try {
      final rawList = await ref.read(adminRepositoryProvider).listRoles();
      final list = await _fillRoles(ref.read(chatRepositoryProvider), rawList);
      if (!mounted) return;
      setState(() {
        _roles = list;
        _loading = false;
        _error = null;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        if (!silent) _error = _errorText(e, 'Gagal memuat daftar role');
      });
    }
  }

  Future<void> _remove(AdminRoleEntry entry) async {
    final name = entry.displayName;
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppColors.surfaceDark,
        title: const Text('Cabut role?', style: TextStyle(color: AppColors.textWhite)),
        content: Text(
          '$name akan kembali jadi user biasa.',
          style: const TextStyle(color: AppColors.textSecondary),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Batal')),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Cabut', style: TextStyle(color: _banRedSoft)),
          ),
        ],
      ),
    );
    if (ok != true || !mounted) return;
    await widget.onAction(
      () => ref.read(adminRepositoryProvider).removeRole(entry.firebaseUid),
      'Role dicabut',
    );
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return const Center(
        child: CircularProgressIndicator(color: AppColors.accentViolet, strokeWidth: 3),
      );
    }
    if (_error != null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(_error!, textAlign: TextAlign.center, style: const TextStyle(color: _banRedSoft)),
              const SizedBox(height: 8),
              TextButton(onPressed: () => _load(), child: const Text('Coba lagi')),
            ],
          ),
        ),
      );
    }
    if (_roles.isEmpty) {
      return const Center(
        child: Text('Belum ada pemegang role.', style: TextStyle(color: AppColors.textSecondary)),
      );
    }
    return ListView.builder(
      padding: const EdgeInsets.fromLTRB(16, 4, 16, 24),
      itemCount: _roles.length,
      itemBuilder: (context, i) {
        final e = _roles[i];
        final info = roleInfoFrom(e.role, e.badgeColor);
        if (info == null) return const SizedBox.shrink();
        final name = e.displayName;
        return _Card(
          child: Row(
            children: [
              UserAvatar(username: name, url: e.avatarUrl, size: 40),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      name,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 14.5,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(height: 4),
                    RoleBadgeChip(info: info, height: 22),
                  ],
                ),
              ),
              _ActionChip(
                text: 'Cabut',
                destructive: true,
                onTap: widget.busy ? null : () => _remove(e),
              ),
            ],
          ),
        );
      },
    );
  }
}

// -------------------------------------------------------------------- Info

class _InfoTab extends StatelessWidget {
  const _InfoTab({required this.role});

  final ZenimeRole role;

  @override
  Widget build(BuildContext context) {
    const title = TextStyle(color: Colors.white, fontSize: 15, fontWeight: FontWeight.w800);
    const body = TextStyle(color: AppColors.textSecondary, fontSize: 13.5, height: 1.4);
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        const Text('Tentang tab "Semua User"', style: title),
        const SizedBox(height: 8),
        const Text(
          'Cari user lewat username, kode Zenime (ZN-XXXXXX), atau UID, lalu '
          'tekan tombol aksi langsung di barisnya. Nggak perlu ngetik atau '
          'menyalin UID manual.',
          style: body,
        ),
        const SizedBox(height: 22),
        Text('Akses kamu: ${_roleName(role)}', style: title),
        const SizedBox(height: 8),
        const Text(
          'Developer: set/cabut role, ban dan unban akun, ban dan unban device.\n'
          'Admin: ban dan unban akun.\n'
          'Moderator: melihat daftar user.',
          style: body,
        ),
        const SizedBox(height: 22),
        const Text(
          'Semua aksi dicek ulang di server. Akun yang punya role nggak bisa di-ban.',
          style: body,
        ),
      ],
    );
  }
}

// ----------------------------------------------------------------- dialog

class _RoleResult {
  const _RoleResult.set(this.role, this.badgeColor) : remove = false;
  const _RoleResult.remove()
      : role = null,
        badgeColor = null,
        remove = true;

  final ZenimeRole? role;
  final String? badgeColor;
  final bool remove;
}

class _RoleAssignDialog extends StatefulWidget {
  const _RoleAssignDialog({required this.user});

  final AdminUser user;

  @override
  State<_RoleAssignDialog> createState() => _RoleAssignDialogState();
}

class _RoleAssignDialogState extends State<_RoleAssignDialog> {
  late ZenimeRole _role =
      ZenimeRole.fromValue(widget.user.role) ?? ZenimeRole.moderator;
  late final TextEditingController _color =
      TextEditingController(text: widget.user.badgeColor ?? '');
  String? _colorError;

  static final RegExp _hex = RegExp(r'^#?[0-9A-Fa-f]{6}$');

  @override
  void dispose() {
    _color.dispose();
    super.dispose();
  }

  void _save() {
    final raw = _color.text.trim();
    String? normalized;
    if (raw.isNotEmpty) {
      if (!_hex.hasMatch(raw)) {
        setState(() => _colorError = 'Format warna: #RRGGBB (contoh #43A047)');
        return;
      }
      normalized = (raw.startsWith('#') ? raw : '#$raw').toUpperCase();
    }
    Navigator.pop(context, _RoleResult.set(_role, normalized));
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      backgroundColor: AppColors.surfaceDark,
      title: Text(
        'Set Role: ${widget.user.displayName}',
        maxLines: 2,
        overflow: TextOverflow.ellipsis,
        style: const TextStyle(color: AppColors.textWhite, fontSize: 17),
      ),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            DropdownButtonFormField<ZenimeRole>(
              value: _role,
              dropdownColor: AppColors.surfaceCard,
              style: const TextStyle(color: Colors.white),
              decoration: const InputDecoration(
                labelText: 'Role',
                labelStyle: TextStyle(color: AppColors.textMuted),
              ),
              items: [
                for (final r in ZenimeRole.values)
                  DropdownMenuItem<ZenimeRole>(value: r, child: Text(_roleName(r))),
              ],
              onChanged: (r) {
                if (r != null) setState(() => _role = r);
              },
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _color,
              style: const TextStyle(color: Colors.white),
              cursorColor: AppColors.accentViolet,
              onChanged: (_) {
                if (_colorError != null) setState(() => _colorError = null);
              },
              decoration: InputDecoration(
                labelText: 'Warna badge (opsional)',
                labelStyle: const TextStyle(color: AppColors.textMuted),
                hintText: '#RRGGBB, kosongkan = warna default',
                hintStyle: const TextStyle(color: AppColors.textMuted, fontSize: 12),
                errorText: _colorError,
              ),
            ),
            if (widget.user.role != null) ...[
              const SizedBox(height: 14),
              GestureDetector(
                onTap: () => Navigator.pop(context, const _RoleResult.remove()),
                child: const Text(
                  'Cabut Role',
                  style: TextStyle(color: _banRedSoft, fontWeight: FontWeight.w700),
                ),
              ),
            ],
          ],
        ),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context), child: const Text('Batal')),
        FilledButton(
          style: FilledButton.styleFrom(backgroundColor: AppColors.accentViolet),
          onPressed: _save,
          child: const Text('Simpan'),
        ),
      ],
    );
  }
}

class _ReasonResult {
  const _ReasonResult(this.reason);

  final String? reason;
}

class _ReasonDialog extends StatefulWidget {
  const _ReasonDialog({required this.title, required this.description});

  final String title;
  final String description;

  @override
  State<_ReasonDialog> createState() => _ReasonDialogState();
}

class _ReasonDialogState extends State<_ReasonDialog> {
  final TextEditingController _reason = TextEditingController();

  @override
  void dispose() {
    _reason.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      backgroundColor: AppColors.surfaceDark,
      title: Text(
        widget.title,
        maxLines: 2,
        overflow: TextOverflow.ellipsis,
        style: const TextStyle(color: AppColors.textWhite, fontSize: 17),
      ),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            widget.description,
            style: const TextStyle(color: AppColors.textSecondary, fontSize: 13),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _reason,
            style: const TextStyle(color: Colors.white),
            cursorColor: AppColors.accentViolet,
            decoration: const InputDecoration(
              labelText: 'Alasan (opsional)',
              labelStyle: TextStyle(color: AppColors.textMuted),
            ),
          ),
        ],
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context), child: const Text('Batal')),
        FilledButton(
          style: FilledButton.styleFrom(backgroundColor: _banRed),
          onPressed: () {
            final t = _reason.text.trim();
            Navigator.pop(context, _ReasonResult(t.isEmpty ? null : t));
          },
          child: const Text('Konfirmasi'),
        ),
      ],
    );
  }
}
