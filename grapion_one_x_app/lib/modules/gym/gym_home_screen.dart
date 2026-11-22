// //Added By Nikhil 21Nov26 23:30 For Gym module entry (role-aware home shell; dashboards follow in the next steps)
// //Modified By Nikhil 22Nov26 08:41 For owner/staff dashboard + gym pages. Old: placeholder list of upcoming pages (full copy: AI Agents Temp\grapion-one-x\GymModuleSetup\22Nov26\backup\gym_owner_0841\gym_home_screen.dart)
import 'package:flutter/material.dart';

import '../../screens/home/entry_router.dart';
import '../../screens/profile/profile_screen.dart';
import '../../theme/app_theme.dart';
import '../../widgets/announcement_banner.dart';
import '../../widgets/doc_ui.dart';
import 'gym_common.dart';
import 'gym_members.dart';
import 'gym_setup_screens.dart';

class GymHomeScreen extends StatefulWidget {
  const GymHomeScreen({super.key, required this.entry, this.canSwitch = false});

  /// One entry from /workspaces/my-entries (business + role + branch).
  final Map<String, dynamic> entry;
  final bool canSwitch;

  @override
  State<GymHomeScreen> createState() => _GymHomeScreenState();
}

class _GymHomeScreenState extends State<GymHomeScreen> {
  Map<String, dynamic>? _o;
  GymCtx? _ctx;
  String? _branch; // null = all branches
  bool _failed = false;

  String get _role => widget.entry['role_code'] as String? ?? '';

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final o = await gymGet(context, '/gym/${widget.entry['workspace_id']}/overview');
    if (!mounted) return;
    setState(() {
      _failed = o == null;
      if (o != null) {
        _o = o;
        _ctx = GymCtx.fromOverview(o);
      }
    });
  }

  Map<String, dynamic> get _stats {
    if (_o == null) return const {};
    if (_branch == null) return Map<String, dynamic>.from(_o!['totals'] as Map);
    final b = (_o!['branches'] as List).firstWhere((b) => b['id'] == _branch, orElse: () => null);
    return Map<String, dynamic>.from((b?['stats'] as Map?) ?? const {});
  }

  void _open(Widget screen) => Navigator.of(context).push(docRoute(screen)).then((_) => _load());

  @override
  Widget build(BuildContext context) {
    final ctx = _ctx;
    return Scaffold(
      body: SafeArea(
        child: RefreshIndicator(
          color: AppTheme.primary,
          onRefresh: _load,
          child: ListView(
            padding: kScreenPadding,
            physics: const AlwaysScrollableScrollPhysics(),
            children: [
              _header(),
              const SizedBox(height: 14),
              const AnnouncementBanners(),
              if (_role == 'member') ..._memberSoon()
              else if (ctx == null && !_failed) gymLoading
              else if (ctx == null) gymEmpty('Could not load your gym. Pull down to try again.')
              else ...[
                BranchChips(ctx: ctx, selected: _branch, onChanged: (b) => setState(() => _branch = b)),
                const SizedBox(height: 12),
                ..._holidayToday(),
                _statsGrid(),
                const SizedBox(height: 6),
                const Text('MANAGE', style: TextStyle(fontSize: 11, fontWeight: FontWeight.w800, letterSpacing: 1, color: AppTheme.textSubtle)),
                const SizedBox(height: 10),
                ..._actions(ctx),
              ],
            ],
          ),
        ),
      ),
    );
  }

  Widget _header() => Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: ScreenTitle(
              title: widget.entry['workspace_name'] ?? 'Grapion Gym',
              subtitle: [
                'Grapion Gym',
                if (widget.entry['branch_name'] != null) widget.entry['branch_name'] as String else if (_role == 'owner') 'All branches',
              ].join(' • '),
              trailing: StatusChip(
                widget.entry['role_name'] ?? '',
                bg: AppTheme.primary,
                fg: Colors.white,
                fontSize: 10,
                fontWeight: FontWeight.w800,
              ),
            ),
          ),
          if (widget.canSwitch) ...[
            SmallPill(label: '⇄ Switch', onTap: () => routeAfterLogin(context)),
            const SizedBox(width: 6),
          ],
          GestureDetector(
            onTap: () => Navigator.of(context).push(docRoute(const ProfileScreen())),
            child: Container(
              width: 32,
              height: 32,
              alignment: Alignment.center,
              decoration: const BoxDecoration(color: AppTheme.chipBg, shape: BoxShape.circle),
              child: const Icon(Icons.person_outline, size: 18, color: AppTheme.textPrimary),
            ),
          ),
        ],
      );

  List<Widget> _holidayToday() {
    final list = (_o?['branches'] as List? ?? [])
        .where((b) => (_branch == null || b['id'] == _branch) && b['stats']?['holiday_today'] != null)
        .map((b) => '${b['name']}: ${b['stats']['holiday_today']}')
        .toList();
    if (list.isEmpty) return const [];
    return [
      DocCard(
        padding: const EdgeInsets.all(14),
        gradient: const LinearGradient(colors: [Color(0xFFFFFBEB), Color(0xFFFEF3C7)]),
        borderColor: AppTheme.warningLight,
        child: Text('🏖️ Holiday today — ${list.join(' • ')}', style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w700)),
      ),
    ];
  }

  Widget _statsGrid() {
    final s = _stats;
    int n(String k) => (s[k] as num?)?.toInt() ?? 0;
    final tiles = <(String, String, Color, VoidCallback?)>[
      ('${n('active')}', 'Active members', AppTheme.primaryDark, () => _open(MembersScreen(ctx: _ctx!, branch: _branch, status: 'active'))),
      ('${n('expiring')}', 'Expiring soon', AppTheme.warningOrange, () => _open(MembersScreen(ctx: _ctx!, branch: _branch, status: 'expiring'))),
      ('${n('expired')}', 'Expired', AppTheme.errorRed, () => _open(MembersScreen(ctx: _ctx!, branch: _branch, status: 'expired'))),
      ('${n('inside_now')}', 'Inside now', AppTheme.accentBlue, null),
      ('${n('visits_today')}', 'Visits today', AppTheme.textPrimary, null),
      if (_ctx!.can('payments.record')) ('${n('pending_payments')}', 'Payments to verify', AppTheme.warningOrange,
          () => _open(PaymentsScreen(ctx: _ctx!, branch: _branch, status: 'pending'))),
    ];
    final revenue = s['month_revenue_paise'];
    return Column(
      children: [
        if (revenue != null)
          DocCard(
            gradient: const LinearGradient(colors: [AppTheme.pillDark, Color(0xFF1E293B)]),
            borderColor: AppTheme.pillDark,
            padding: const EdgeInsets.all(18),
            child: Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text('Collected this month', style: TextStyle(fontSize: 11, color: Colors.white70)),
                      const SizedBox(height: 4),
                      Text(formatMoney((revenue as num) / 100),
                          style: const TextStyle(fontSize: 24, fontWeight: FontWeight.w800, color: Colors.white)),
                    ],
                  ),
                ),
                Column(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    Text('${n('members')} members', style: const TextStyle(fontSize: 11, color: Colors.white70)),
                    Text('${n('staff')} staff', style: const TextStyle(fontSize: 11, color: Colors.white70)),
                  ],
                ),
              ],
            ),
          ),
        LayoutBuilder(builder: (context, c) {
          final cols = c.maxWidth > 600 ? 3 : 2;
          final w = (c.maxWidth - (cols - 1) * 10) / cols;
          return Wrap(
            spacing: 10,
            runSpacing: 10,
            children: [
              for (final (value, label, color, onTap) in tiles)
                SizedBox(
                  width: w,
                  child: DocCard(
                    margin: EdgeInsets.zero,
                    padding: const EdgeInsets.all(14),
                    onTap: onTap,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        TweenAnimationBuilder<double>(
                          tween: Tween(begin: 0, end: double.tryParse(value) ?? 0),
                          duration: MediaQuery.of(context).disableAnimations ? Duration.zero : const Duration(milliseconds: 600),
                          curve: Curves.easeOutCubic,
                          builder: (_, v, _) =>
                              Text('${v.round()}', style: TextStyle(fontSize: 22, fontWeight: FontWeight.w800, color: color)),
                        ),
                        Text(label, style: const TextStyle(fontSize: 11, color: AppTheme.textMuted, fontWeight: FontWeight.w600)),
                      ],
                    ),
                  ),
                ),
            ],
          );
        }),
        const SizedBox(height: 14),
      ],
    );
  }

  List<Widget> _actions(GymCtx ctx) {
    final items = <(String, String, String, Widget?)>[
      if (ctx.can('members.view')) ('🏋️', 'Members', 'Add, search, plans, check-in', MembersScreen(ctx: ctx, branch: _branch)),
      if (ctx.can('payments.record')) ('💰', 'Payments', 'Record, verify, history', PaymentsScreen(ctx: ctx, branch: _branch)),
      if (ctx.can('plans.view')) ('🎫', 'Plans', ctx.can('plans.edit') ? 'Prices per branch' : 'View plans & prices', PlansScreen(ctx: ctx, branch: _branch)),
      if (ctx.can('members.view')) ('🗓', 'Batches', 'Member time slots & trainers', BatchesScreen(ctx: ctx, branch: _branch)),
      //Modified By Nikhil 22Nov26 10:47 For Staff and Shifts as two options. Old: ('🧑‍🤝‍🧑', 'Staff & Shifts', 'Roles, shifts, pay', StaffScreen(ctx: ctx, branch: _branch))
      if (ctx.can('staff.manage')) ('🧑‍🤝‍🧑', 'Staff', 'Managers, receptionists, trainers, pay', StaffScreen(ctx: ctx, branch: _branch)),
      if (ctx.can('staff.manage')) ('🕘', 'Shifts', 'Staff working hours', StaffScreen(ctx: ctx, branch: _branch, view: 'shifts')), //Added By Nikhil 22Nov26 10:47 For Shifts as its own option
      ('🏖️', 'Holidays & Timings', ctx.can('holidays.edit') ? 'Notifies members & staff' : 'Opening hours & holidays', HolidaysScreen(ctx: ctx, branch: _branch)),
      if (ctx.isOwner || ctx.can('business.manage')) ('📍', 'Branches & Settings', 'Attendance rules, reminders, UPI', BranchesScreen(ctx: ctx)),
      ('🧖', 'Services', 'Spa, diet plans, PT packages', null),
    ];
    return [
      for (final (icon, title, sub, screen) in items)
        DocCard(
          padding: const EdgeInsets.all(14),
          margin: const EdgeInsets.only(bottom: 10),
          onTap: () => screen == null ? showDevModuleDialog(context, title) : _open(screen),
          child: Row(
            children: [
              Text(icon, style: const TextStyle(fontSize: 22)),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(title, style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w800)),
                    Text(sub, style: const TextStyle(fontSize: 11, color: AppTheme.textMuted)),
                  ],
                ),
              ),
              if (screen == null)
                const StatusChip('In Development', bg: Color(0xFFFFFBEB), fg: AppTheme.warningOrange, fontSize: 10)
              else
                const Icon(Icons.chevron_right, color: AppTheme.textSubtle),
            ],
          ),
        ),
    ];
  }

  List<Widget> _memberSoon() => [
        DocCard(
          gradient: const LinearGradient(colors: [AppTheme.pillDark, Color(0xFF1E293B)]),
          borderColor: AppTheme.pillDark,
          child: const Row(
            children: [
              Text('🏋️', style: TextStyle(fontSize: 26)),
              SizedBox(width: 12),
              Expanded(
                child: Text('Your member page (membership, visits, payments, notices) is being built next.',
                    style: TextStyle(fontSize: 12, color: Colors.white, height: 1.4)),
              ),
            ],
          ),
        ),
      ];
}
