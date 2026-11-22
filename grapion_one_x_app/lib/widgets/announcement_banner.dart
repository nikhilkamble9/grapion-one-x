// //Added By Nikhil 22Nov26 08:35 For live announcement banners + Help & support card (Platform Settings)
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../services/api_client.dart';
import '../theme/app_theme.dart';
import '../theme/motion.dart';
import 'doc_ui.dart';

/// Shows the live banners for this user (max 3). Dismiss hides one until the app restarts.
class AnnouncementBanners extends StatefulWidget {
  const AnnouncementBanners({super.key});
  static final Set<String> _dismissed = {};

  @override
  State<AnnouncementBanners> createState() => _AnnouncementBannersState();
}

class _AnnouncementBannersState extends State<AnnouncementBanners> {
  List<dynamic> _items = const [];

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final res = await apiClient.get('/meta/announcements');
      if (!mounted || res.statusCode != 200) return;
      setState(() => _items = jsonDecode(res.body)['announcements'] as List);
    } catch (_) {
      // Banners are optional: never block the screen on them.
    }
  }

  static (Color, Color, String) _look(String? style) => switch (style) {
        'success' => (AppTheme.successLight, AppTheme.primaryDark, '✅'),
        'warning' => (const Color(0xFFFFFBEB), AppTheme.warningOrange, '⚠️'),
        _ => (const Color(0xFFEFF6FF), const Color(0xFF1D4ED8), '📣'),
      };

  @override
  Widget build(BuildContext context) {
    final visible = _items.where((a) => !AnnouncementBanners._dismissed.contains(a['id'])).toList();
    return AnimatedSize(
      duration: AppMotion.expand,
      curve: Curves.easeOutCubic,
      alignment: Alignment.topCenter,
      child: Column(
        children: [
          for (final a in visible)
            Builder(builder: (context) {
              final (bg, fg, icon) = _look(a['style'] as String?);
              return Container(
                margin: const EdgeInsets.only(bottom: 10),
                padding: const EdgeInsets.fromLTRB(14, 12, 6, 12),
                decoration: BoxDecoration(
                  color: bg,
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(color: fg.withValues(alpha: 0.25)),
                ),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(icon, style: const TextStyle(fontSize: 18)),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(a['title'] ?? '', style: TextStyle(fontSize: 13, fontWeight: FontWeight.w800, color: fg)),
                          const SizedBox(height: 2),
                          Text(a['message'] ?? '', style: const TextStyle(fontSize: 12, height: 1.35, color: AppTheme.textPrimary)),
                        ],
                      ),
                    ),
                    IconButton(
                      tooltip: 'Hide',
                      visualDensity: VisualDensity.compact,
                      icon: Icon(Icons.close, size: 16, color: fg),
                      onPressed: () => setState(() => AnnouncementBanners._dismissed.add(a['id'] as String)),
                    ),
                  ],
                ),
              );
            }),
        ],
      ),
    );
  }
}

/// Help & support card (Profile). Hidden when the Super Admin has not filled any contact.
class SupportCard extends StatefulWidget {
  const SupportCard({super.key});
  @override
  State<SupportCard> createState() => _SupportCardState();
}

class _SupportCardState extends State<SupportCard> {
  Map<String, dynamic>? _s;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final res = await apiClient.get('/meta/support');
      if (!mounted || res.statusCode != 200) return;
      setState(() => _s = Map<String, dynamic>.from(jsonDecode(res.body)));
    } catch (_) {}
  }

  @override
  Widget build(BuildContext context) {
    final s = _s;
    if (s == null) return const SizedBox.shrink();
    final rows = <(IconData, String, String)>[
      if ((s['phone'] ?? '').toString().isNotEmpty) (Icons.call_outlined, 'Phone', s['phone']),
      if ((s['whatsapp'] ?? '').toString().isNotEmpty) (Icons.chat_outlined, 'WhatsApp', s['whatsapp']),
      if ((s['email'] ?? '').toString().isNotEmpty) (Icons.mail_outline, 'Email', s['email']),
    ];
    if (rows.isEmpty) return const SizedBox.shrink();
    return DocCard(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('🆘 Help & support', style: TextStyle(fontSize: 14, fontWeight: FontWeight.w800)),
          if ((s['hours'] ?? '').toString().isNotEmpty)
            Text(s['hours'], style: const TextStyle(fontSize: 11, color: AppTheme.textMuted)),
          const SizedBox(height: 8),
          for (final (icon, label, value) in rows)
            InkWell(
              borderRadius: BorderRadius.circular(10),
              onTap: () {
                Clipboard.setData(ClipboardData(text: value));
                ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('$label copied')));
              },
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 8),
                child: Row(
                  children: [
                    Icon(icon, size: 18, color: AppTheme.primaryDark),
                    const SizedBox(width: 10),
                    Text('$label  ', style: const TextStyle(fontSize: 12, color: AppTheme.textMuted)),
                    Expanded(child: Text(value, style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w700))),
                    const Icon(Icons.copy, size: 14, color: AppTheme.textSubtle),
                  ],
                ),
              ),
            ),
        ],
      ),
    );
  }
}
