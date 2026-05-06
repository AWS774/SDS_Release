import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../services/auth_service.dart';
import '../services/device_service.dart';
import '../theme/app_theme.dart';
import '../theme/theme_notifier.dart';
import '../main.dart';

class ProfileScreen extends StatefulWidget {
  const ProfileScreen({super.key});

  @override
  State<ProfileScreen> createState() => _ProfileScreenState();
}

class _ProfileScreenState extends State<ProfileScreen> {
  final _authService = AuthService();
  final _deviceService = DeviceService();

  bool _isLoading = false;
  User? _currentUser;
  int _deviceCount = 0;

  @override
  void initState() {
    super.initState();
    _loadUserData();
  }

  Future<void> _loadUserData() async {
    setState(() => _isLoading = true);
    try {
      final user = _authService.currentUser;
      final deviceCount = await _deviceService.getDeviceCount();
      setState(() {
        _currentUser = user;
        _deviceCount = deviceCount;
      });
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Gagal memuat data pengguna: $e'),
            backgroundColor: AppTheme.dangerRed,
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Future<void> _logout() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Konfirmasi Logout'),
        content: const Text('Apakah Anda yakin ingin keluar dari aplikasi?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Batal'),
          ),
          TextButton(
            onPressed: () => Navigator.of(context).pop(true),
            style: TextButton.styleFrom(foregroundColor: AppTheme.dangerRed),
            child: const Text('Logout'),
          ),
        ],
      ),
    );

    if (confirmed == true) {
      try {
        await _authService.signOut();
        if (mounted) {
          Navigator.of(context).pushAndRemoveUntil(
            MaterialPageRoute(builder: (context) => const AuthWrapper()),
            (route) => false,
          );
        }
      } catch (e) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('Gagal logout: $e'),
              backgroundColor: AppTheme.dangerRed,
            ),
          );
        }
      }
    }
  }

  Future<void> _updateProfile() async {
    final nameController = TextEditingController(
      text: _currentUser?.userMetadata?['full_name'] ?? '',
    );

    final updated = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Update Profile'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: nameController,
              decoration: const InputDecoration(
                labelText: 'Nama Lengkap',
                prefixIcon: Icon(Icons.person),
              ),
            ),
            const SizedBox(height: 16),
            Text(
              'Email: ${_currentUser?.email ?? '-'}',
              style: TextStyle(
                color: Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.6),
                fontSize: 14,
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Batal'),
          ),
          TextButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('Simpan'),
          ),
        ],
      ),
    );

    if (updated == true && nameController.text.trim().isNotEmpty) {
      setState(() => _isLoading = true);
      try {
        await Supabase.instance.client.auth.updateUser(
          UserAttributes(data: {'full_name': nameController.text.trim()}),
        );
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Profile berhasil diperbarui'),
              backgroundColor: AppTheme.successGreen,
            ),
          );
        }
        await _loadUserData();
      } catch (e) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('Gagal update profile: $e'),
              backgroundColor: AppTheme.dangerRed,
            ),
          );
        }
      } finally {
        if (mounted) setState(() => _isLoading = false);
      }
    }
  }

  Future<void> _changePassword() async {
    final currentPasswordController = TextEditingController();
    final newPasswordController = TextEditingController();
    final confirmPasswordController = TextEditingController();

    final changed = await showDialog<bool>(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setState) => AlertDialog(
          title: const Text('Ganti Password'),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextField(
                  controller: currentPasswordController,
                  obscureText: true,
                  decoration: const InputDecoration(
                    labelText: 'Password Saat Ini',
                    prefixIcon: Icon(Icons.lock),
                  ),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: newPasswordController,
                  obscureText: true,
                  decoration: const InputDecoration(
                    labelText: 'Password Baru',
                    prefixIcon: Icon(Icons.lock_outline),
                  ),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: confirmPasswordController,
                  obscureText: true,
                  decoration: const InputDecoration(
                    labelText: 'Konfirmasi Password Baru',
                    prefixIcon: Icon(Icons.lock_outline),
                  ),
                  onChanged: (_) => setState(() {}),
                ),
                if (newPasswordController.text.isNotEmpty &&
                    confirmPasswordController.text.isNotEmpty &&
                    newPasswordController.text != confirmPasswordController.text)
                  Padding(
                    padding: const EdgeInsets.only(top: 8),
                    child: Text(
                      'Password tidak cocok',
                      style: TextStyle(color: AppTheme.dangerRed, fontSize: 12),
                    ),
                  ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(false),
              child: const Text('Batal'),
            ),
            TextButton(
              onPressed: (newPasswordController.text ==
                          confirmPasswordController.text &&
                      newPasswordController.text.length >= 6)
                  ? () => Navigator.of(context).pop(true)
                  : null,
              child: const Text('Ganti'),
            ),
          ],
        ),
      ),
    );

    if (changed == true) {
      setState(() => _isLoading = true);
      try {
        await Supabase.instance.client.auth.updateUser(
          UserAttributes(password: newPasswordController.text),
        );
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Password berhasil diperbarui'),
              backgroundColor: AppTheme.successGreen,
            ),
          );
        }
      } catch (e) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('Gagal ganti password: $e'),
              backgroundColor: AppTheme.dangerRed,
            ),
          );
        }
      } finally {
        if (mounted) setState(() => _isLoading = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final isDark = themeNotifier.isDarkMode;
    final primaryBlue =
        isDark ? AppTheme.darkPrimaryBlue : AppTheme.lightPrimaryBlue;
    final cardColor = isDark ? AppTheme.darkCard : AppTheme.lightCard;
    final textPrimary =
        isDark ? AppTheme.darkTextPrimary : AppTheme.lightTextPrimary;
    final textSecondary =
        isDark ? AppTheme.darkTextSecondary : AppTheme.lightTextSecondary;
    final divider = isDark ? AppTheme.darkDivider : const Color(0xFFE2E8F0);

    return ListenableBuilder(
      listenable: themeNotifier,
      builder: (context, _) {
        return Scaffold(
          appBar: AppBar(
            title: const Text('Profile Pengguna'),
            backgroundColor:
                isDark ? AppTheme.darkSurface : AppTheme.lightPrimaryBlue,
            foregroundColor: isDark ? AppTheme.darkTextPrimary : Colors.white,
            elevation: 0,
          ),
          body: _isLoading
              ? const Center(child: CircularProgressIndicator())
              : RefreshIndicator(
                  onRefresh: _loadUserData,
                  child: SingleChildScrollView(
                    physics: const AlwaysScrollableScrollPhysics(),
                    child: Column(
                      children: [
                        // ── Header gradient ───────────────────────────────
                        Container(
                          width: double.infinity,
                          decoration: BoxDecoration(
                            gradient: LinearGradient(
                              begin: Alignment.topLeft,
                              end: Alignment.bottomRight,
                              colors: isDark
                                  ? [
                                      AppTheme.darkSurface,
                                      AppTheme.darkCardElevated,
                                    ]
                                  : [
                                      AppTheme.lightPrimaryBlue,
                                      AppTheme.lightPrimaryDark,
                                    ],
                            ),
                            borderRadius: const BorderRadius.only(
                              bottomLeft: Radius.circular(32),
                              bottomRight: Radius.circular(32),
                            ),
                          ),
                          padding:
                              const EdgeInsets.fromLTRB(24, 40, 24, 32),
                          child: Column(
                            children: [
                              // Avatar
                              Container(
                                width: 100,
                                height: 100,
                                decoration: BoxDecoration(
                                  color: isDark
                                      ? AppTheme.darkInputFill
                                      : Colors.white,
                                  borderRadius: BorderRadius.circular(50),
                                  border: Border.all(
                                    color: isDark
                                        ? AppTheme.darkDivider
                                        : Colors.white,
                                    width: 4,
                                  ),
                                  boxShadow: [
                                    BoxShadow(
                                      color: Colors.black.withValues(alpha: 0.15),
                                      blurRadius: 12,
                                      offset: const Offset(0, 4),
                                    ),
                                  ],
                                ),
                                child: Icon(
                                  Icons.person,
                                  size: 60,
                                  color: primaryBlue,
                                ),
                              ),
                              const SizedBox(height: 16),
                              Text(
                                _currentUser?.userMetadata?['full_name'] ??
                                    'Pengguna',
                                style: TextStyle(
                                  fontSize: 24,
                                  fontWeight: FontWeight.bold,
                                  color: isDark
                                      ? AppTheme.darkTextPrimary
                                      : Colors.white,
                                ),
                              ),
                              const SizedBox(height: 4),
                              Text(
                                _currentUser?.email ?? '-',
                                style: TextStyle(
                                  fontSize: 15,
                                  color: isDark
                                      ? AppTheme.darkTextSecondary
                                      : Colors.white.withValues(alpha: 0.85),
                                ),
                              ),
                            ],
                          ),
                        ),

                        Padding(
                          padding: const EdgeInsets.all(20),
                          child: Column(
                            children: [
                              // ── Dark Mode Card ────────────────────────────
                              _buildCard(
                                isDark: isDark,
                                cardColor: cardColor,
                                divider: divider,
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    _buildSectionHeader(
                                      icon: Icons.palette_outlined,
                                      label: 'Tampilan',
                                      primaryBlue: primaryBlue,
                                      textPrimary: textPrimary,
                                    ),
                                    const SizedBox(height: 16),
                                    Row(
                                      children: [
                                        Container(
                                          width: 40,
                                          height: 40,
                                          decoration: BoxDecoration(
                                            color: isDark
                                                ? AppTheme.darkInputFill
                                                : const Color(0xFF1E293B)
                                                    .withValues(alpha: 0.08),
                                            borderRadius:
                                                BorderRadius.circular(10),
                                          ),
                                          child: Icon(
                                            isDark
                                                ? Icons.dark_mode_rounded
                                                : Icons.light_mode_rounded,
                                            color: isDark
                                                ? AppTheme.darkPrimaryBlue
                                                : const Color(0xFF1E293B),
                                            size: 22,
                                          ),
                                        ),
                                        const SizedBox(width: 14),
                                        Expanded(
                                          child: Column(
                                            crossAxisAlignment:
                                                CrossAxisAlignment.start,
                                            children: [
                                              Text(
                                                'Dark Mode',
                                                style: TextStyle(
                                                  fontSize: 15,
                                                  fontWeight: FontWeight.w600,
                                                  color: textPrimary,
                                                ),
                                              ),
                                              const SizedBox(height: 2),
                                              Text(
                                                isDark
                                                    ? 'Tema gelap aktif'
                                                    : 'Tema terang aktif',
                                                style: TextStyle(
                                                  fontSize: 12,
                                                  color: textSecondary,
                                                ),
                                              ),
                                            ],
                                          ),
                                        ),
                                        // Toggle switch
                                        Switch(
                                          value: isDark,
                                          onChanged: (_) =>
                                              themeNotifier.toggleDarkMode(),
                                          activeColor: primaryBlue,
                                        ),
                                      ],
                                    ),
                                  ],
                                ),
                              ),

                              const SizedBox(height: 16),

                              // ── Info Akun Card ────────────────────────────
                              _buildCard(
                                isDark: isDark,
                                cardColor: cardColor,
                                divider: divider,
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    _buildSectionHeader(
                                      icon: Icons.info_outline,
                                      label: 'Informasi Akun',
                                      primaryBlue: primaryBlue,
                                      textPrimary: textPrimary,
                                    ),
                                    const SizedBox(height: 20),
                                    _buildInfoRow(
                                      label: 'Tanggal Bergabung',
                                      value: _formatDate(
                                        _currentUser?.createdAt != null
                                            ? DateTime.parse(
                                                _currentUser!.createdAt)
                                            : null,
                                      ),
                                      icon: Icons.calendar_today,
                                      textPrimary: textPrimary,
                                      textSecondary: textSecondary,
                                    ),
                                    Divider(
                                        height: 24,
                                        color: divider,
                                        thickness: 1),
                                    _buildInfoRow(
                                      label: 'Jumlah Alat Terdaftar',
                                      value: '$_deviceCount alat',
                                      icon: Icons.devices,
                                      textPrimary: textPrimary,
                                      textSecondary: textSecondary,
                                    ),
                                    Divider(
                                        height: 24,
                                        color: divider,
                                        thickness: 1),
                                    _buildInfoRow(
                                      label: 'Status Email',
                                      value: _currentUser?.emailConfirmedAt !=
                                              null
                                          ? 'Terverifikasi'
                                          : 'Belum Terverifikasi',
                                      icon: _currentUser?.emailConfirmedAt !=
                                              null
                                          ? Icons.verified
                                          : Icons.warning,
                                      color:
                                          _currentUser?.emailConfirmedAt != null
                                              ? AppTheme.successGreen
                                              : AppTheme.warningAmber,
                                      textPrimary: textPrimary,
                                      textSecondary: textSecondary,
                                    ),
                                  ],
                                ),
                              ),

                              const SizedBox(height: 16),

                              // ── Aksi Card ─────────────────────────────────
                              _buildCard(
                                isDark: isDark,
                                cardColor: cardColor,
                                divider: divider,
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    _buildSectionHeader(
                                      icon: Icons.manage_accounts_outlined,
                                      label: 'Kelola Akun',
                                      primaryBlue: primaryBlue,
                                      textPrimary: textPrimary,
                                    ),
                                    const SizedBox(height: 16),
                                    _buildActionButton(
                                      icon: Icons.edit_outlined,
                                      label: 'Update Profile',
                                      onTap: _updateProfile,
                                      color: primaryBlue,
                                      isDark: isDark,
                                      filled: true,
                                    ),
                                    const SizedBox(height: 10),
                                    _buildActionButton(
                                      icon: Icons.lock_outline,
                                      label: 'Ganti Password',
                                      onTap: _changePassword,
                                      color: primaryBlue,
                                      isDark: isDark,
                                      filled: false,
                                    ),
                                    const SizedBox(height: 10),
                                    _buildActionButton(
                                      icon: Icons.logout_rounded,
                                      label: 'Logout',
                                      onTap: _logout,
                                      color: AppTheme.dangerRed,
                                      isDark: isDark,
                                      filled: false,
                                    ),
                                  ],
                                ),
                              ),

                              const SizedBox(height: 16),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
        );
      },
    );
  }

  // ── Helper widgets ─────────────────────────────────────────────────────────

  Widget _buildCard({
    required bool isDark,
    required Color cardColor,
    required Color divider,
    required Widget child,
  }) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: cardColor,
        borderRadius: BorderRadius.circular(16),
        border: isDark ? Border.all(color: divider, width: 1) : null,
        boxShadow: isDark
            ? null
            : [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.06),
                  blurRadius: 12,
                  offset: const Offset(0, 4),
                ),
              ],
      ),
      child: child,
    );
  }

  Widget _buildSectionHeader({
    required IconData icon,
    required String label,
    required Color primaryBlue,
    required Color textPrimary,
  }) {
    return Row(
      children: [
        Icon(icon, color: primaryBlue, size: 20),
        const SizedBox(width: 10),
        Text(
          label,
          style: TextStyle(
            fontSize: 16,
            fontWeight: FontWeight.bold,
            color: textPrimary,
          ),
        ),
      ],
    );
  }

  Widget _buildInfoRow({
    required String label,
    required String value,
    required IconData icon,
    required Color textPrimary,
    required Color textSecondary,
    Color? color,
  }) {
    return Row(
      children: [
        Icon(icon, size: 20, color: color ?? textSecondary),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                label,
                style: TextStyle(fontSize: 12, color: textSecondary),
              ),
              const SizedBox(height: 2),
              Text(
                value,
                style: TextStyle(
                  fontSize: 14,
                  color: color ?? textPrimary,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildActionButton({
    required IconData icon,
    required String label,
    required VoidCallback onTap,
    required Color color,
    required bool isDark,
    required bool filled,
  }) {
    if (filled) {
      return SizedBox(
        width: double.infinity,
        height: 50,
        child: ElevatedButton.icon(
          onPressed: onTap,
          icon: Icon(icon, size: 18),
          label: Text(label),
          style: ElevatedButton.styleFrom(
            backgroundColor: color,
            foregroundColor: Colors.white,
            elevation: 0,
            shape:
                RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          ),
        ),
      );
    }

    return SizedBox(
      width: double.infinity,
      height: 50,
      child: OutlinedButton.icon(
        onPressed: onTap,
        icon: Icon(icon, size: 18),
        label: Text(label),
        style: OutlinedButton.styleFrom(
          foregroundColor: color,
          side: BorderSide(color: color.withValues(alpha: 0.7)),
          shape:
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        ),
      ),
    );
  }

  String _formatDate(DateTime? date) {
    if (date == null) return '-';
    return '${date.day}/${date.month}/${date.year}';
  }
}