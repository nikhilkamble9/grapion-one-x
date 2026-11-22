// //Added By Nikhil 18Nov26 21:43 For Admin Portal with Floating Black Pill Dock Bar
//Modified By Nikhil 21Nov26 21:00 For admin portal matching ui_prototype_docspot (top-aligned tabs, reject, DB modules). Old: full file backed up at D:\AI Agents Temp\grapion-one-x\GrapionOneX_DocSpot_CleanUI\21Nov26\backup\allscreens_2100_DesignMatch\ START
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../services/api_client.dart';
import '../../theme/app_theme.dart';
import '../../theme/motion.dart';
import '../../widgets/doc_ui.dart';
import '../../widgets/module_card.dart';
import '../auth/login_screen.dart';
import 'super_admin_screens.dart'; //Added By Nikhil 22Nov26 01:22 For Control tab
import '../../widgets/announcement_banner.dart'; //Added By Nikhil 22Nov26 08:35 For announcement banners

class AdminDashboardScreen extends StatefulWidget {
  const AdminDashboardScreen({super.key});

  @override
  State<AdminDashboardScreen> createState() => _AdminDashboardScreenState();
}

class _AdminDashboardScreenState extends State<AdminDashboardScreen> {
  static const _periodLabel = {'weekly': 'Weekly', 'monthly': 'Monthly', 'quarterly': 'Quarterly', 'yearly': 'Yearly'};

  int _currentTab = 0; // 0: Home (pending requests), 1: Modules, 2: Control (super admin only)
  bool _isSuper = false; //Added By Nikhil 22Nov26 01:22 For Control tab visibility
  final Set<String> _expandedRequestIds = {};

  bool _loading = true;
  String? _error;
  Map<String, dynamic> _metrics = {'pending_count': 0, 'pending_volume_rupees': 0};
  List<dynamic> _pendingRequests = [];
  List<dynamic> _cancellations = []; //Added By Nikhil 21Nov26 22:44 For module cancellation queue
  List<dynamic> _modules = [];
  bool _modulesLoading = true;
  Map<String, Map<String, dynamic>> _countries = {};

  @override
  void initState() {
    super.initState();
    _fetchAdminDashboard();
    _fetchModules();
    _fetchCountries();
    _fetchRole(); //Added By Nikhil 22Nov26 01:22 For Control tab visibility
  }

  //Added By Nikhil 22Nov26 01:22 For Control tab visibility (server still enforces super_admin on every call)
  Future<void> _fetchRole() async {
    try {
      final res = await apiClient.get('/auth/me');
      if (res.statusCode == 200 && mounted) setState(() => _isSuper = jsonDecode(res.body)['role'] == 'super_admin');
    } catch (_) {}
  }

  Future<void> _fetchAdminDashboard() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final res = await apiClient.get('/admin/dashboard');
      //Added By Nikhil 21Nov26 22:44 For module cancellation queue
      final cRes = await apiClient.get('/admin/cancellations');
      if (cRes.statusCode == 200 && mounted) _cancellations = jsonDecode(cRes.body)['cancellations'] ?? [];
      if (!mounted) return;
      if (res.statusCode == 200) {
        final data = jsonDecode(res.body);
        setState(() {
          _metrics = Map<String, dynamic>.from(data['metrics']);
          _pendingRequests = data['pending_requests'] ?? [];
          _loading = false;
        });
      } else if (res.statusCode == 401 || res.statusCode == 403) {
        _signOut();
      } else {
        setState(() {
          _error = 'Could not load pending requests';
          _loading = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _error = 'Connection error';
          _loading = false;
        });
      }
    }
  }

  // Module list comes from the database (same catalog the store uses), not from the app code.
  Future<void> _fetchModules() async {
    try {
      final res = await apiClient.get('/subscriptions/catalog');
      if (!mounted) return;
      setState(() {
        if (res.statusCode == 200) _modules = jsonDecode(res.body)['modules'] ?? [];
        _modulesLoading = false;
      });
    } catch (_) {
      if (mounted) setState(() => _modulesLoading = false);
    }
  }

  Future<void> _fetchCountries() async {
    try {
      final res = await apiClient.get('/meta/countries');
      if (res.statusCode != 200 || !mounted) return;
      final list = jsonDecode(res.body)['countries'] as List;
      setState(() => _countries = {for (final c in list) c['code'] as String: Map<String, dynamic>.from(c)});
    } catch (_) {/* details fall back to the country code */}
  }

  Future<void> _signOut() async {
    await apiClient.clearToken();
    if (!mounted) return;
    Navigator.of(context).pushAndRemoveUntil(docRoute(const LoginScreen()), (_) => false);
  }

  void _toast(String msg) => ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));

  // ---------------- Approve (Record Verified Payment) ----------------

  void _showApprovalSheet(Map<String, dynamic> req) {
    String method = 'upi';
    final upiIdCtrl = TextEditingController();
    final utrCtrl = TextEditingController();
    final cardNameCtrl = TextEditingController();
    final cardLast4Ctrl = TextEditingController();
    String? sheetError;
    bool submitting = false;

    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.white,
      barrierColor: const Color(0x590F172A),
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(28))),
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setSheet) {
          Future<void> confirm() async {
            // Admin must record the real reference — nothing is pre-filled.
            final err = switch (method) {
              'upi' when upiIdCtrl.text.trim().isEmpty || utrCtrl.text.trim().length < 4 =>
                'Enter the payer UPI ID and the last 4–5 digits of the UTR.',
              'card' when cardNameCtrl.text.trim().isEmpty || cardLast4Ctrl.text.length != 4 =>
                'Enter the cardholder name and the last 4 digits of the card.',
              _ => null,
            };
            if (err != null) {
              setSheet(() => sheetError = err);
              return;
            }
            setSheet(() {
              submitting = true;
              sheetError = null;
            });
            final ok = await _approveRequest(req['id'] as String, {
              'payment_method': method,
              if (method == 'upi') 'payer_upi_id': upiIdCtrl.text.trim(),
              if (method == 'upi') 'utr_last_digits': utrCtrl.text.trim(),
              if (method == 'card') 'cardholder_name': cardNameCtrl.text.trim(),
              if (method == 'card') 'card_last_four': cardLast4Ctrl.text,
            });
            if (!ctx.mounted) return;
            if (ok) {
              Navigator.pop(ctx);
            } else {
              setSheet(() {
                submitting = false;
                sheetError = 'Could not approve. Please try again.';
              });
            }
          }

          return Padding(
            padding: EdgeInsets.fromLTRB(24, 12, 24, 24 + MediaQuery.viewInsetsOf(ctx).bottom),
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Center(
                    child: Container(
                      width: 36,
                      height: 4,
                      margin: const EdgeInsets.only(bottom: 16),
                      decoration: BoxDecoration(color: AppTheme.borderSubtle, borderRadius: BorderRadius.circular(4)),
                    ),
                  ),
                  Row(
                    children: [
                      const Expanded(
                        child: Text('Record Verified Payment', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w800)),
                      ),
                      IconButton(
                        tooltip: 'Close',
                        onPressed: () => Navigator.pop(ctx),
                        icon: const Text('×', style: TextStyle(fontSize: 20, fontWeight: FontWeight.w700, color: AppTheme.textSubtle)),
                      ),
                    ],
                  ),
                  Text(
                    'Select payment method confirmed via back-office • ${req['request_number']} • ${formatMoney(req['final_amount'] as num)}',
                    style: const TextStyle(fontSize: 12, color: AppTheme.textMuted),
                  ),
                  const SizedBox(height: 14),
                  SegmentTabs(
                    options: const {'cash': 'Cash', 'upi': 'UPI', 'card': 'Card'},
                    selected: method,
                    onChanged: (m) => setSheet(() {
                      method = m;
                      sheetError = null;
                    }),
                  ),
                  const SizedBox(height: 16),
                  if (sheetError != null) MessageBanner(sheetError!),
                  if (method == 'upi') ...[
                    DocField(label: 'Payer UPI ID', controller: upiIdCtrl, hint: 'e.g. nikhil@okaxis'),
                    DocField(
                      label: 'Last 4–5 Digits of Ref/UTR',
                      controller: utrCtrl,
                      hint: 'e.g. 8492',
                      keyboardType: TextInputType.number,
                      inputFormatters: [FilteringTextInputFormatter.digitsOnly, LengthLimitingTextInputFormatter(5)],
                    ),
                  ],
                  if (method == 'card') ...[
                    DocField(label: 'Cardholder Name', controller: cardNameCtrl, hint: 'Name on card'),
                    // Only the last 4 digits are ever accepted (no full card number — PCI).
                    DocField(
                      label: 'Last 4 Digits of Card',
                      controller: cardLast4Ctrl,
                      hint: 'e.g. 4022',
                      keyboardType: TextInputType.number,
                      inputFormatters: [FilteringTextInputFormatter.digitsOnly, LengthLimitingTextInputFormatter(4)],
                    ),
                  ],
                  if (method == 'cash')
                    const Padding(
                      padding: EdgeInsets.only(bottom: 12),
                      child: Text(
                        '✓ Cash received and verified directly in person.',
                        style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: AppTheme.primary),
                      ),
                    ),
                  PillButton(
                    label: 'Confirm & Activate Modules',
                    variant: PillVariant.accent,
                    loading: submitting,
                    onPressed: confirm,
                  ),
                ],
              ),
            ),
          );
        },
      ),
    ).whenComplete(() {
      upiIdCtrl.dispose();
      utrCtrl.dispose();
      cardNameCtrl.dispose();
      cardLast4Ctrl.dispose();
    });
  }

  Future<bool> _approveRequest(String id, Map<String, dynamic> body) async {
    try {
      final res = await apiClient.post('/admin/requests/$id/approve', body);
      if (!mounted) return false;
      if (res.statusCode == 200) {
        _toast('Subscription activated! Modules now accessible.');
        _expandedRequestIds.remove(id);
        _fetchAdminDashboard();
        return true;
      }
      return false;
    } catch (_) {
      return false;
    }
  }

  // ---------------- Reject ----------------

  Future<void> _rejectRequest(Map<String, dynamic> req) async {
    final reasonCtrl = TextEditingController();
    final reason = await showDialog<String>(
      context: context,
      builder: (ctx) {
        String? err;
        return StatefulBuilder(
          builder: (ctx, setD) => AlertDialog(
            backgroundColor: Colors.white,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(AppTheme.radiusLg)),
            title: Text('Reject ${req['request_number']}?', style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w800)),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (err != null) MessageBanner(err!),
                DocField(label: 'Enter rejection reason', controller: reasonCtrl, hint: 'e.g. Payment not received'),
              ],
            ),
            actions: [
              Row(
                children: [
                  Expanded(
                    child: PillButton(
                      label: 'Cancel',
                      variant: PillVariant.secondary,
                      padding: const EdgeInsets.all(10),
                      fontSize: 12,
                      onPressed: () => Navigator.pop(ctx),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: PillButton(
                      label: 'Reject',
                      padding: const EdgeInsets.all(10),
                      fontSize: 12,
                      onPressed: () {
                        final r = reasonCtrl.text.trim();
                        if (r.length < 2) {
                          setD(() => err = 'Please enter a reason (min 2 characters).');
                          return;
                        }
                        Navigator.pop(ctx, r);
                      },
                    ),
                  ),
                ],
              ),
            ],
          ),
        );
      },
    );
    reasonCtrl.dispose();
    if (reason == null || !mounted) return;

    try {
      final res = await apiClient.post('/admin/requests/${req['id']}/reject', {'reason': reason});
      if (!mounted) return;
      if (res.statusCode == 200) {
        _toast('Request ${req['request_number']} rejected');
        _expandedRequestIds.remove(req['id']);
        _fetchAdminDashboard();
      } else {
        _toast('Could not reject the request');
      }
    } catch (_) {
      if (mounted) _toast('Connection error');
    }
  }

  // ---------------- Layout ----------------

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: Stack(
          children: [
            Positioned.fill(
              child: AnimatedSwitcher(
                duration: AppMotion.tabIn,
                transitionBuilder: (child, anim) => TabInTransition(animation: anim, child: child),
                // Default layout centres the child vertically — that pushed the header down when the
                // list was short. Pin every tab to the top and let it fill the height.
                layoutBuilder: (current, previous) => current ?? const SizedBox.shrink(), //Modified By Nikhil 21Nov26 21:16 For no tab overlap (old tab hidden at once, like prototype). Old: Stack(children: [...previous, ?current])
                //Modified By Nikhil 22Nov26 01:22 For Control tab. Old: _currentTab == 0 ? _buildHomeTab() : _buildModulesTab()
                child: switch (_currentTab) {
                  0 => _buildHomeTab(),
                  1 => _buildModulesTab(),
                  _ => SuperAdminHomeTab(
                      key: const ValueKey('control_tab'),
                      header: _header(
                        title: 'Control Center',
                        subtitle: 'Super Admin only',
                        badge: const StatusChip('Super Admin', bg: AppTheme.pillDark, fg: Colors.white, fontSize: 10, fontWeight: FontWeight.w800),
                      ),
                    ),
                },
              ),
            ),
            Positioned(left: 20, right: 20, bottom: 18, child: _buildDock()),
          ],
        ),
      ),
    );
  }

  Widget _buildDock() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: AppTheme.pillDark,
        borderRadius: BorderRadius.circular(99),
        boxShadow: const [BoxShadow(color: Color(0x590F172A), blurRadius: 30, offset: Offset(0, 12))],
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceAround,
        children: [
          _buildDockItem(0, Icons.home_outlined, 'Home'),
          _buildDockItem(1, Icons.grid_view_outlined, 'Modules'),
          if (_isSuper) _buildDockItem(2, Icons.shield_outlined, 'Control'), //Added By Nikhil 22Nov26 01:22 For super admin pages
        ],
      ),
    );
  }

  Widget _buildDockItem(int index, IconData icon, String label) {
    final active = _currentTab == index;
    final color = active ? AppTheme.pillDark : AppTheme.textSubtle;
    return Semantics(
      button: true,
      selected: active,
      child: GestureDetector(
        onTap: () => setState(() => _currentTab = index),
        child: AnimatedContainer(
          duration: AppMotion.dock,
          curve: AppMotion.ringMiddleCurve,
          padding: EdgeInsets.symmetric(horizontal: _isSuper ? 12 : 18, vertical: 10), //Modified By Nikhil 22Nov26 01:22 For 3 dock items. Old: horizontal: 18
          decoration: BoxDecoration(
            color: active ? Colors.white : Colors.transparent,
            borderRadius: BorderRadius.circular(99),
            boxShadow: active ? const [BoxShadow(color: Color(0x26000000), blurRadius: 12, offset: Offset(0, 4))] : null,
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon, size: 18, color: color),
              const SizedBox(width: 8),
              Text(label, style: TextStyle(fontWeight: FontWeight.w700, fontSize: 13, color: color)),
            ],
          ),
        ),
      ),
    );
  }

  Widget _header({required String title, required String subtitle, required Widget badge}) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 14),
      //Modified By Nikhil 22Nov26 10:47 For title on one line with the badge in line with Sign Out. Old: Row[Expanded(ScreenTitle(title, subtitle, trailing: badge)), SignOut] START
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: FittedBox(
                  fit: BoxFit.scaleDown,
                  alignment: Alignment.centerLeft,
                  child: Text(title,
                      maxLines: 1,
                      style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w800, letterSpacing: -0.5, color: AppTheme.textPrimary)),
                ),
              ),
              const SizedBox(width: 8),
              badge,
              const SizedBox(width: 8),
              SmallPill(
                label: 'Sign Out',
                onTap: _signOut,
                color: AppTheme.textMuted,
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
              ),
            ],
          ),
          const SizedBox(height: 2),
          Text(subtitle, style: const TextStyle(fontSize: 13, color: AppTheme.textMuted)),
        ],
      ),
      //Modified By Nikhil 22Nov26 10:47 For title on one line with the badge in line with Sign Out END
    );
  }

  static const _bottomPadForDock = EdgeInsets.fromLTRB(22, 16, 22, 100);

  Widget _buildHomeTab() {
    return RefreshIndicator(
      key: const ValueKey('home_tab'),
      color: AppTheme.primary,
      onRefresh: _fetchAdminDashboard,
      child: ListView(
        padding: _bottomPadForDock,
        physics: const AlwaysScrollableScrollPhysics(),
        children: [
          _header(
            title: 'Admin Dashboard',
            subtitle: 'Pending subscription approvals',
            badge: StatusChip(
              '${_metrics['pending_count']} New',
              bg: AppTheme.errorRed,
              fg: Colors.white,
              fontWeight: FontWeight.w800,
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
            ),
          ),
          const AnnouncementBanners(), //Added By Nikhil 22Nov26 08:35 For announcement banners

          // Summary metrics (fixed at the top)
          Row(
            children: [
              Expanded(child: _metricCard('${_metrics['pending_count']}', 'Pending Review', AppTheme.textPrimary)),
              const SizedBox(width: 10),
              Expanded(
                child: _metricCard(
                  formatMoney(_metrics['pending_volume_rupees'] as num? ?? 0),
                  'Pending Volume',
                  AppTheme.primary,
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          const Padding(
            padding: EdgeInsets.only(bottom: 8),
            child: Text(
              'PENDING APPROVAL QUEUE',
              style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: AppTheme.textMuted, letterSpacing: 0.5),
            ),
          ),
          if (_error != null) MessageBanner(_error!),
          if (_loading && _pendingRequests.isEmpty)
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 40),
              child: Center(child: CircularProgressIndicator(color: AppTheme.primary)),
            )
          else if (_pendingRequests.isEmpty)
            const DocCard(
              child: Center(
                child: Text('No pending subscription requests.', style: TextStyle(color: AppTheme.textMuted, fontSize: 13)),
              ),
            )
          else
            for (final r in _pendingRequests) _buildRequestCard(Map<String, dynamic>.from(r as Map)),
          //Added By Nikhil 21Nov26 22:44 For module cancellation queue START
          const SizedBox(height: 10),
          Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: Row(
              children: [
                const Text(
                  'CANCELLATION REQUESTS',
                  style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: AppTheme.textMuted, letterSpacing: 0.5),
                ),
                const SizedBox(width: 8),
                if (_cancellations.isNotEmpty)
                  StatusChip('${_cancellations.length}', bg: AppTheme.errorRed, fg: Colors.white, fontSize: 10,
                      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2)),
              ],
            ),
          ),
          if (_cancellations.isEmpty)
            const DocCard(
              child: Center(child: Text('No cancellation requests.', style: TextStyle(color: AppTheme.textMuted, fontSize: 13))),
            )
          else
            for (final c in _cancellations) _buildCancellationCard(Map<String, dynamic>.from(c as Map)),
          //Added By Nikhil 21Nov26 22:44 For module cancellation queue END
        ],
      ),
    );
  }

  Widget _metricCard(String value, String label, Color valueColor) {
    return DocCard(
      margin: EdgeInsets.zero,
      padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 14),
      borderColor: AppTheme.borderSubtle,
      gradient: const LinearGradient(
        begin: Alignment.topCenter,
        end: Alignment.bottomCenter,
        colors: [Colors.white, AppTheme.cardSubtle],
      ),
      child: Column(
        children: [
          FittedBox(
            fit: BoxFit.scaleDown,
            child: Text(value, style: TextStyle(fontSize: 22, fontWeight: FontWeight.w800, color: valueColor, height: 1.1)),
          ),
          const SizedBox(height: 2),
          Text(label, style: const TextStyle(fontSize: 11, color: AppTheme.textMuted, fontWeight: FontWeight.w700)),
        ],
      ),
    );
  }

  Widget _buildRequestCard(Map<String, dynamic> r) {
    final id = r['id'] as String;
    final isExpanded = _expandedRequestIds.contains(id);
    final base = (r['base_amount'] as num?) ?? 0;
    final fin = (r['final_amount'] as num?) ?? 0;
    final discountPct = base > 0 && fin < base ? ((base - fin) * 100 / base).round() : 0;
    final country = _countries[r['country_code']];
    final countryText = country == null ? '${r['country_code']}' : '${country['name']} • ${country['currency']}';
    final modules = (r['modules'] as List? ?? []).join(', ');
    final period = _periodLabel[r['billing_period']] ?? r['billing_period'];

    return DocCard(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      leftAccent: AppTheme.accentGold,
      onTap: () => setState(() => isExpanded ? _expandedRequestIds.remove(id) : _expandedRequestIds.add(id)),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        StatusChip(
                          r['request_number'] ?? '',
                          bg: AppTheme.chipBg,
                          fg: AppTheme.textMuted,
                          radius: 6,
                          fontWeight: FontWeight.w800,
                          padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
                        ),
                        const SizedBox(width: 8),
                        Flexible(
                          child: Text(
                            r['user_name'] ?? '',
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w800, color: AppTheme.textPrimary),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 2),
                    Text(
                      'Requested: ${formatServerDateTime(r['created_at'] as String?)}',
                      style: const TextStyle(fontSize: 11, color: AppTheme.textMuted),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              const StatusChip('Pending', bg: AppTheme.warningLight, fg: AppTheme.warningOrange),
              const SizedBox(width: 8),
              AnimatedRotation(
                turns: isExpanded ? 0.5 : 0,
                duration: AppMotion.expand,
                child: const Text('▼', style: TextStyle(fontSize: 14, fontWeight: FontWeight.w800, color: AppTheme.textMuted)),
              ),
            ],
          ),
          //Added By Nikhil 21Nov26 22:44 For user-requested cancellation banner START
          if (r['cancellation'] != null)
            Container(
              width: double.infinity,
              margin: const EdgeInsets.only(top: 10),
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              decoration: BoxDecoration(
                color: AppTheme.errorLight,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: const Color(0xFFFECACA)),
              ),
              child: Text(
                '🛑 User requested cancellation • ${r['cancellation']['reason']}\nReject = cancel the request • Approve = activate anyway (settled in back office)',
                style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: AppTheme.errorRed, height: 1.4),
              ),
            ),
          //Added By Nikhil 21Nov26 22:44 For user-requested cancellation banner END
          AnimatedSize(
            duration: AppMotion.expand,
            curve: Curves.easeOut,
            alignment: Alignment.topCenter,
            child: !isExpanded
                ? const SizedBox(width: double.infinity)
                : Padding(
                    padding: const EdgeInsets.only(top: 14),
                    child: Column(
                      children: [
                        const _DashedLine(),
                        const SizedBox(height: 12),
                        Container(
                          width: double.infinity,
                          margin: const EdgeInsets.only(bottom: 12),
                          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                          decoration: BoxDecoration(
                            color: AppTheme.cardSubtle,
                            borderRadius: BorderRadius.circular(12),
                            border: Border.all(color: AppTheme.cardBorder),
                          ),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              _detailLine('📞 ', '${r['mobile_number']}', ' ($countryText)'),
                              const SizedBox(height: 4),
                              _detailLine('📦 Module: ', modules, ' ($period Plan)'),
                              const SizedBox(height: 4),
                              Wrap(
                                spacing: 6,
                                crossAxisAlignment: WrapCrossAlignment.center,
                                children: [
                                  Text.rich(
                                    TextSpan(
                                      style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w800, color: AppTheme.textPrimary),
                                      children: [
                                        const TextSpan(text: 'Total Amount: '),
                                        TextSpan(text: formatMoney(fin), style: const TextStyle(color: AppTheme.primaryDark)),
                                      ],
                                    ),
                                  ),
                                  if (discountPct > 0)
                                    StatusChip(
                                      '$discountPct% Off',
                                      bg: AppTheme.errorLight,
                                      fg: AppTheme.errorRed,
                                      fontSize: 10,
                                      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                    ),
                                ],
                              ),
                            ],
                          ),
                        ),
                        Row(
                          children: [
                            Expanded(
                              child: PillButton(
                                label: 'Approve',
                                variant: PillVariant.accent,
                                padding: const EdgeInsets.all(10),
                                fontSize: 12,
                                fontWeight: FontWeight.w800,
                                onPressed: () => _showApprovalSheet(r),
                              ),
                            ),
                            const SizedBox(width: 8),
                            Expanded(
                              child: PillButton(
                                label: 'Reject',
                                variant: PillVariant.secondary,
                                foreground: AppTheme.errorRed,
                                padding: const EdgeInsets.all(10),
                                fontSize: 12,
                                onPressed: () => _rejectRequest(r),
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
          ),
        ],
      ),
    );
  }

  //Added By Nikhil 21Nov26 22:44 For module cancellation review START
  Widget _buildCancellationCard(Map<String, dynamic> c) {
    return DocCard(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      leftAccent: AppTheme.errorRed,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              StatusChip(c['cancellation_number'] ?? '', bg: AppTheme.chipBg, fg: AppTheme.textMuted, radius: 6,
                  fontWeight: FontWeight.w800, padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2)),
              const SizedBox(width: 8),
              Flexible(
                child: Text(c['user_name'] ?? '', overflow: TextOverflow.ellipsis,
                    style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w800, color: AppTheme.textPrimary)),
              ),
            ],
          ),
          const SizedBox(height: 2),
          Text('Requested: ${formatServerDateTime(c['created_at'] as String?)}',
              style: const TextStyle(fontSize: 11, color: AppTheme.textMuted)),
          const SizedBox(height: 10),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            decoration: BoxDecoration(
              color: AppTheme.cardSubtle,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: AppTheme.cardBorder),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _detailLine('📦 Module: ', '${c['module_name']}', ' (ends ${formatServerDateTime(c['expires_at'] as String?, withTime: false)})'),
                const SizedBox(height: 4),
                _detailLine('📞 ', '${c['mobile_number']}', ''),
                const SizedBox(height: 4),
                _detailLine('🗓 Used ', '${c['used_days']} of ${c['total_days']} days', ' • paid ${formatMoney((c['paid_amount'] as num?) ?? 0)}'),
                const SizedBox(height: 4),
                _detailLine('💬 Reason: ', '${c['reason']}', ''),
                const SizedBox(height: 6),
                Text.rich(TextSpan(
                  style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w800, color: AppTheme.textPrimary),
                  children: [
                    const TextSpan(text: 'Refund to settle: '),
                    TextSpan(text: formatMoney((c['refund_amount'] as num?) ?? 0), style: const TextStyle(color: AppTheme.errorRed)),
                  ],
                )),
              ],
            ),
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: PillButton(label: 'Approve & Refund', variant: PillVariant.accent, padding: const EdgeInsets.all(10),
                    fontSize: 12, fontWeight: FontWeight.w800, onPressed: () => _approveCancellationSheet(c)),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: PillButton(label: 'Reject', variant: PillVariant.secondary, foreground: AppTheme.errorRed,
                    padding: const EdgeInsets.all(10), fontSize: 12, onPressed: () => _rejectCancellation(c)),
              ),
            ],
          ),
        ],
      ),
    );
  }

  void _approveCancellationSheet(Map<String, dynamic> c) {
    String method = 'upi';
    final refCtrl = TextEditingController();
    final noteCtrl = TextEditingController();
    String? err;
    bool busy = false;
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(28))),
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setSheet) => Padding(
          padding: EdgeInsets.fromLTRB(24, 12, 24, 24 + MediaQuery.viewInsetsOf(ctx).bottom),
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Center(
                  child: Container(width: 36, height: 4, margin: const EdgeInsets.only(bottom: 16),
                      decoration: BoxDecoration(color: AppTheme.borderSubtle, borderRadius: BorderRadius.circular(4))),
                ),
                const Text('Record Refund Settlement', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w800)),
                Text('${c['cancellation_number']} • refund ${formatMoney((c['refund_amount'] as num?) ?? 0)} • module is switched off on approval',
                    style: const TextStyle(fontSize: 12, color: AppTheme.textMuted)),
                const SizedBox(height: 14),
                SegmentTabs(
                  options: const {'cash': 'Cash', 'upi': 'UPI', 'bank': 'Bank', 'card': 'Card'},
                  selected: method,
                  onChanged: (m) => setSheet(() => method = m),
                ),
                const SizedBox(height: 16),
                if (err != null) MessageBanner(err!),
                if (method != 'cash')
                  DocField(
                    label: method == 'card' ? 'Last 4 Digits of Card' : 'Last 4–6 Digits of Ref/UTR',
                    controller: refCtrl,
                    hint: 'e.g. 8492',
                    keyboardType: TextInputType.number,
                    inputFormatters: [FilteringTextInputFormatter.digitsOnly, LengthLimitingTextInputFormatter(method == 'card' ? 4 : 6)],
                  ),
                DocField(label: 'Note (optional)', controller: noteCtrl, hint: 'e.g. Refunded to same UPI'),
                PillButton(
                  label: 'Confirm Refund & Cancel Module',
                  variant: PillVariant.accent,
                  loading: busy,
                  onPressed: () async {
                    if (method != 'cash' && refCtrl.text.length < 4) {
                      setSheet(() => err = 'Enter the last digits of the refund reference.');
                      return;
                    }
                    setSheet(() { busy = true; err = null; });
                    try {
                      final res = await apiClient.post('/admin/cancellations/${c['id']}/approve', {
                        'refund_method': method,
                        if (method != 'cash') 'refund_reference': refCtrl.text,
                        if (noteCtrl.text.trim().isNotEmpty) 'note': noteCtrl.text.trim(),
                      });
                      if (!ctx.mounted) return;
                      if (res.statusCode == 200) {
                        Navigator.pop(ctx);
                        _toast('Cancellation approved — module switched off');
                        _fetchAdminDashboard();
                      } else {
                        setSheet(() { busy = false; err = apiDetail(res.body, 'Could not approve'); });
                      }
                    } catch (_) {
                      setSheet(() { busy = false; err = 'Connection error'; });
                    }
                  },
                ),
              ],
            ),
          ),
        ),
      ),
    ).whenComplete(() {
      refCtrl.dispose();
      noteCtrl.dispose();
    });
  }

  Future<void> _rejectCancellation(Map<String, dynamic> c) async {
    final note = await showReasonDialog(
      context,
      title: 'Reject ${c['cancellation_number']}?',
      message: 'The module stays active until its end date.',
      label: 'Reason for rejecting',
      confirmLabel: 'Reject',
    );
    if (note == null || !mounted) return;
    try {
      final res = await apiClient.post('/admin/cancellations/${c['id']}/reject', {'note': note});
      if (!mounted) return;
      _toast(res.statusCode == 200 ? 'Cancellation rejected — subscription continues' : apiDetail(res.body, 'Could not reject'));
      _fetchAdminDashboard();
    } catch (_) {
      if (mounted) _toast('Connection error');
    }
  }
  //Added By Nikhil 21Nov26 22:44 For module cancellation review END

  Widget _detailLine(String lead, String strong, String tail) {
    return Text.rich(
      TextSpan(
        style: const TextStyle(fontSize: 12, color: AppTheme.label),
        children: [
          TextSpan(text: lead),
          TextSpan(text: strong, style: const TextStyle(fontWeight: FontWeight.w800)),
          TextSpan(text: tail),
        ],
      ),
    );
  }

  Widget _buildModulesTab() {
    return RefreshIndicator(
      key: const ValueKey('modules_tab'),
      color: AppTheme.primary,
      onRefresh: _fetchModules,
      child: ListView(
        padding: _bottomPadForDock,
        physics: const AlwaysScrollableScrollPhysics(),
        children: [
          _header(
            title: 'All Modules',
            subtitle: 'Direct access to all backend business verticals',
            badge: const StatusChip(
              'Admin Access',
              bg: AppTheme.primary,
              fg: Colors.white,
              fontSize: 10,
              fontWeight: FontWeight.w800,
              padding: EdgeInsets.symmetric(horizontal: 8, vertical: 3),
            ),
          ),
          Container(
            margin: const EdgeInsets.only(bottom: 14),
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
            decoration: BoxDecoration(
              gradient: const LinearGradient(colors: [AppTheme.pillDark, Color(0xFF1E293B)]),
              borderRadius: BorderRadius.circular(AppTheme.radiusMd),
            ),
            child: const Row(
              children: [
                Text('🛡️', style: TextStyle(fontSize: 20)),
                SizedBox(width: 10),
                Expanded(
                  child: Text.rich(
                    TextSpan(
                      style: TextStyle(fontSize: 11, height: 1.4, color: Colors.white),
                      children: [
                        TextSpan(text: 'Admin Bypass Active: ', style: TextStyle(fontWeight: FontWeight.w800)),
                        TextSpan(text: 'Unconditional preview access enabled for all modules currently in engineering.'),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
          if (_modulesLoading)
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 40),
              child: Center(child: CircularProgressIndicator(color: AppTheme.primary)),
            )
          else if (_modules.isEmpty)
            const DocCard(child: Center(child: Text('No modules found.', style: TextStyle(color: AppTheme.textMuted))))
          else
            for (final m in _modules) ModuleCard(module: Map<String, dynamic>.from(m as Map)),
        ],
      ),
    );
  }
}

class _DashedLine extends StatelessWidget {
  const _DashedLine();

  @override
  Widget build(BuildContext context) {
    return CustomPaint(size: const Size(double.infinity, 1), painter: _DashedLinePainter());
  }
}

class _DashedLinePainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final p = Paint()
      ..color = AppTheme.borderSubtle
      ..strokeWidth = 1;
    for (double x = 0; x < size.width; x += 7) {
      canvas.drawLine(Offset(x, 0.5), Offset((x + 4).clamp(0, size.width), 0.5), p);
    }
  }

  @override
  bool shouldRepaint(covariant _DashedLinePainter oldDelegate) => false;
}
//Modified By Nikhil 21Nov26 21:00 For admin portal matching ui_prototype_docspot (top-aligned tabs, reject, DB modules) END
