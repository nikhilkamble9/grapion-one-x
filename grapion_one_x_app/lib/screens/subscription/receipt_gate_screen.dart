// //Added By Nikhil 18Nov26 23:05 For Dynamic Pending Approval Status on Gate
//Modified By Nikhil 21Nov26 21:00 For receipt gate matching ui_prototype_docspot + DB data. Old: full file backed up at D:\AI Agents Temp\grapion-one-x\GrapionOneX_DocSpot_CleanUI\21Nov26\backup\allscreens_2100_DesignMatch\ START
import 'dart:convert';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';

import '../../services/api_client.dart';
import '../../theme/app_theme.dart';
import '../../widgets/doc_ui.dart';
import '../auth/login_screen.dart';
import '../home/entry_router.dart'; //Added By Nikhil 21Nov26 23:30 For role-based routing
import '../profile/profile_screen.dart'; //Added By Nikhil 21Nov26 22:36 For avatar → Profile Settings
import 'store_screen.dart';

class ReceiptGateScreen extends StatefulWidget {
  final bool isSubscribed;

  const ReceiptGateScreen({super.key, required this.isSubscribed});

  @override
  State<ReceiptGateScreen> createState() => _ReceiptGateScreenState();
}

class _ReceiptGateScreenState extends State<ReceiptGateScreen> {
  bool _loading = true;
  String? _error;
  bool _hasAccess = false;
  Map<String, dynamic>? _pendingRequest;
  Map<String, dynamic>? _ended;
  Map<String, dynamic>? _openCancel; //Added By Nikhil 21Nov26 22:44 For cancel / keep subscription on pending request
  bool _cancelBusy = false; //Added By Nikhil 21Nov26 22:44 For cancel / keep subscription //Added By Nikhil 21Nov26 22:36 For "ended on … Renew"
  List<dynamic> _catalogModules = [];
  List<dynamic> _myModules = [];
  String _symbol = '₹';
  double _rate = 1.0;
  String _initials = '';

  @override
  void initState() {
    super.initState();
    _hasAccess = widget.isSubscribed;
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final results = await Future.wait([
        apiClient.get('/subscriptions/my-status'),
        apiClient.get('/subscriptions/catalog'),
        apiClient.get('/auth/me'),
        apiClient.get('/subscriptions/cancellations'), //Added By Nikhil 21Nov26 22:44 For open cancellation
      ]);
      if (results.any((r) => r.statusCode == 401)) {
        await _handleSignOut();
        return;
      }
      final status = jsonDecode(results[0].body);
      final catalog = jsonDecode(results[1].body);
      final me = jsonDecode(results[2].body);

      List<dynamic> mine = [];
      final hasAccess = status['has_access'] == true;
      if (hasAccess) {
        final myRes = await apiClient.get('/subscriptions/my-modules');
        if (myRes.statusCode == 200) mine = jsonDecode(myRes.body)['modules'] ?? [];
      }
      if (!mounted) return;
      //Added By Nikhil 21Nov26 21:16 For approved users moving to their modules home START
      if (hasAccess) {
        await routeAfterLogin(context); //Modified By Nikhil 21Nov26 23:30 For role-based routing. Old: pushAndRemoveUntil(MyModulesScreen(asHome: true))
        return;
      }
      //Added By Nikhil 21Nov26 21:16 For approved users moving to their modules home END
      setState(() {
        _hasAccess = hasAccess;
        _pendingRequest = status['pending_request'];
        _ended = status['ended_subscription']; //Added By Nikhil 21Nov26 22:36 For "ended on … Renew"
        //Added By Nikhil 21Nov26 22:44 For open cancellation on the pending request
        _openCancel = results[3].statusCode == 200
            ? ((jsonDecode(results[3].body)['open'] as List?) ?? [])
                .cast<Map<String, dynamic>>()
                .where((c) => c['cancel_type'] == 'pending_request')
                .firstOrNull
            : null;
        _catalogModules = catalog['modules'] ?? [];
        _symbol = (catalog['currency_symbol'] as String? ?? '₹').trim();
        _rate = (catalog['fx_rate'] as num? ?? 1).toDouble();
        _myModules = mine;
        _initials = initialsOf(me['first_name'] ?? '', me['last_name'] ?? '');
        _loading = false;
      });
    } catch (_) {
      if (mounted) {
        setState(() {
          _error = 'Could not load your subscription. Pull down to retry.';
          _loading = false;
        });
      }
    }
  }

  //Added By Nikhil 21Nov26 22:44 For cancel / keep subscription START
  Future<void> _requestCancel() async {
    final reason = await showReasonDialog(
      context,
      title: 'Cancel subscription request?',
      message: 'The admin will see your reason. You can keep the subscription until the admin reviews it.',
      label: 'Cancellation reason',
      confirmLabel: 'Cancel Subscription',
    );
    if (reason == null || !mounted) return;
    setState(() => _cancelBusy = true);
    try {
      final res = await apiClient.post('/subscriptions/cancellations', {'target': 'pending_request', 'reason': reason});
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text(res.statusCode == 201 ? 'Cancellation sent to the admin' : apiDetail(res.body, 'Could not cancel')),
      ));
    } catch (_) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Connection error')));
    } finally {
      if (mounted) setState(() => _cancelBusy = false);
      await _load();
    }
  }

  Future<void> _keepSubscription() async {
    final id = _openCancel?['id'];
    if (id == null) return;
    setState(() => _cancelBusy = true);
    try {
      final res = await apiClient.post('/subscriptions/cancellations/$id/withdraw', {});
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text(res.statusCode == 200 ? 'Great — your subscription request continues' : apiDetail(res.body, 'Could not update')),
      ));
    } catch (_) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Connection error')));
    } finally {
      if (mounted) setState(() => _cancelBusy = false);
      await _load();
    }
  }
  //Added By Nikhil 21Nov26 22:44 For cancel / keep subscription END

  Future<void> _handleSignOut() async {
    await apiClient.clearToken();
    if (!mounted) return;
    Navigator.of(context).pushAndRemoveUntil(docRoute(const LoginScreen()), (_) => false);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: RefreshIndicator(
          color: AppTheme.primary,
          onRefresh: _load,
          child: LayoutBuilder(
            builder: (context, constraints) => SingleChildScrollView(
              physics: const AlwaysScrollableScrollPhysics(),
              padding: kScreenPadding,
              child: ConstrainedBox(
                constraints: BoxConstraints(minHeight: constraints.maxHeight - kScreenPadding.vertical),
                child: IntrinsicHeight(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          const ScreenTitle(title: 'Account Active', size: 20),
                          GestureDetector( //Added By Nikhil 21Nov26 22:36 For avatar → Profile Settings
                            onTap: () => Navigator.of(context).push(docRoute(const ProfileScreen())).then((_) => _load()),
                            child: Container(
                            width: 32,
                            height: 32,
                            alignment: Alignment.center,
                            decoration: const BoxDecoration(color: AppTheme.chipBg, shape: BoxShape.circle),
                            child: Text(_initials, style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w800)),
                          ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 12),
                      if (_error != null) MessageBanner(_error!),
                      if (_loading)
                        const Padding(
                          padding: EdgeInsets.symmetric(vertical: 80),
                          child: Center(child: CircularProgressIndicator(color: AppTheme.primary)),
                        )
                      else
                        _buildReceipt(),
                      const Spacer(),
                      const SizedBox(height: 16),
                      Center(
                        child: TextButton(
                          onPressed: _handleSignOut,
                          child: const Text(
                            'Sign Out',
                            style: TextStyle(
                              fontSize: 13,
                              fontWeight: FontWeight.w800,
                              color: AppTheme.errorRed,
                              decoration: TextDecoration.underline,
                              decorationColor: AppTheme.errorRed,
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildReceipt() {
    final pending = _pendingRequest;
    final (String icon, Color iconBg, String title, String subtitle) = _hasAccess
        ? ('✅', AppTheme.successLight, 'Subscription Active', 'Your subscribed modules are ready to use.')
        : pending != null
            ? ('⏳', AppTheme.warningLight, 'Approval Pending', 'Request ${pending['request_number']} is under admin review.')
            //Modified By Nikhil 21Nov26 22:36 For ended state. Old: : ('📄', …, 'Subscription Needed', 'No active service modules assigned to your account yet.');
            : _ended != null
                ? ('⌛', AppTheme.errorLight, 'Subscription Ended',
                    'Your subscription for ${_ended!['module_name']} ended on ${formatServerDateTime(_ended!['ended_at'] as String?, withTime: false)}. Do you want to renew?')
                : ('📄', const Color(0xFFEFF6FF), 'Subscription Needed', 'No active service modules assigned to your account yet.');

    final rows = _hasAccess ? _myModules : _catalogModules;

    return Container(
          width: double.infinity,
          margin: const EdgeInsets.only(top: 10),
          padding: const EdgeInsets.fromLTRB(20, 24, 20, 24),
          decoration: BoxDecoration(
            gradient: const LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              colors: [Colors.white, AppTheme.cardSubtle],
            ),
            borderRadius: BorderRadius.circular(AppTheme.radiusLg),
            border: Border.all(color: AppTheme.borderSubtle, width: 1.5),
            boxShadow: const [BoxShadow(color: Color(0x0F000000), blurRadius: 35, spreadRadius: -10, offset: Offset(0, 15))],
          ),
          child: Column(
            children: [
              Container(
                width: 52,
                height: 52,
                alignment: Alignment.center,
                decoration: BoxDecoration(color: iconBg, borderRadius: BorderRadius.circular(18)),
                child: Text(icon, style: const TextStyle(fontSize: 24)),
              ),
              const SizedBox(height: 12),
              Text(title, style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w800, color: AppTheme.textPrimary)),
              const SizedBox(height: 4),
              Text(subtitle, textAlign: TextAlign.center, style: const TextStyle(fontSize: 12, color: AppTheme.textMuted)),
              const SizedBox(height: 16),
              // .receipt-divider with the two side notches anchored to it (stays aligned if text wraps).
              const SizedBox(
                height: 24,
                child: Stack(
                  clipBehavior: Clip.none,
                  children: [
                    Center(child: _DashedDivider()),
                    Positioned(left: -31.5, top: 2, child: _Notch()),
                    Positioned(right: -31.5, top: 2, child: _Notch()),
                  ],
                ),
              ),
              const SizedBox(height: 4),
              for (final m in rows) _buildModuleRow(m),
              if (rows.isEmpty)
                const Padding(
                  padding: EdgeInsets.symmetric(vertical: 12),
                  child: Text('No modules available yet.', style: TextStyle(fontSize: 12, color: AppTheme.textMuted)),
                ),
              const SizedBox(height: 14),
              if (_hasAccess)
                PillButton(
                  label: 'All Modules →',
                  variant: PillVariant.accent,
                  onPressed: () => routeAfterLogin(context), //Modified By Nikhil 21Nov26 23:30 For role-based routing. Old: push(MyModulesScreen())
                )
              else if (pending != null)
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 16),
                  decoration: BoxDecoration(
                    color: AppTheme.warningLight,
                    borderRadius: BorderRadius.circular(99),
                    border: Border.all(color: const Color(0xFFFDE68A)),
                  ),
                  child: Text(
                    '⏳ Awaiting Approval • ${formatMoney(pending['final_amount'] as num, symbol: _symbol, rate: _rate)}',
                    textAlign: TextAlign.center,
                    style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w800, color: Color(0xFF92400E)),
                  ),
                )
              else
                PillButton(
                  label: _ended != null ? 'Renew →' : 'Subscribe Now →', //Modified By Nikhil 21Nov26 22:36 For Renew. Old: 'Subscribe Now →'
                  variant: PillVariant.accent,
                  onPressed: () => Navigator.of(context)
                      .push(docRoute(StoreScreen(preselectCodes: [if (_ended != null) _ended!['module_code'] as String])))
                      .then((_) => _load()),
                ),
              //Added By Nikhil 21Nov26 22:44 For cancel / keep subscription on the pending request START
              if (!_hasAccess && pending != null) ...[
                const SizedBox(height: 10),
                if (_openCancel == null)
                  PillButton(
                    label: 'Cancel Subscription',
                    variant: PillVariant.secondary,
                    foreground: AppTheme.errorRed,
                    loading: _cancelBusy,
                    onPressed: _requestCancel,
                  )
                else ...[
                  MessageBanner(
                    '🛑 Cancellation requested • ${_openCancel!['reason']}. The admin will review it — changed your mind?',
                  ),
                  Row(
                    children: [
                      Expanded(
                        child: PillButton(
                          label: 'Keep Subscription',
                          variant: PillVariant.accent,
                          loading: _cancelBusy,
                          padding: const EdgeInsets.all(12),
                          fontSize: 13,
                          onPressed: _keepSubscription,
                        ),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: PillButton(
                          label: 'Continue Cancelling',
                          variant: PillVariant.secondary,
                          foreground: AppTheme.errorRed,
                          padding: const EdgeInsets.all(12),
                          fontSize: 13,
                          onPressed: () => ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(content: Text('Your cancellation stays with the admin for review')),
                          ),
                        ),
                      ),
                    ],
                  ),
                ],
              ],
              //Added By Nikhil 21Nov26 22:44 For cancel / keep subscription on the pending request END
            ],
          ),
        );
  }

  Widget _buildModuleRow(dynamic m) {
    final Widget trailing;
    if (_hasAccess) {
      trailing = StatusChip(
        'Until ${formatServerDateTime(m['expires_at'] as String?, withTime: false)}',
        bg: AppTheme.successLight,
        fg: AppTheme.primaryDark,
      );
    } else {
      final monthly = ((m['prices'] as Map?)?['monthly'] as num?) ?? 0;
      trailing = _BlurredAmount(symbol: _symbol, digits: groupDigits(monthly * _rate));
    }
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        color: AppTheme.cardSubtle,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppTheme.cardBorder),
      ),
      child: Row(
        children: [
          Text(m['icon'] ?? '📦', style: const TextStyle(fontSize: 14)),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              m['name'] ?? '',
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: AppTheme.textPrimary),
            ),
          ),
          trailing,
        ],
      ),
    );
  }
}

/// .amount-blurred-box — currency symbol visible, digits blurred.
class _BlurredAmount extends StatelessWidget {
  const _BlurredAmount({required this.symbol, required this.digits});
  final String symbol;
  final String digits;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      label: 'Price hidden until you subscribe',
      child: ExcludeSemantics(
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: AppTheme.borderSubtle, width: 1.5),
            boxShadow: const [BoxShadow(color: Color(0x08000000), blurRadius: 5, offset: Offset(0, 2))],
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(symbol, style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w900, color: AppTheme.textPrimary)),
              const SizedBox(width: 3),
              ImageFiltered(
                imageFilter: ui.ImageFilter.blur(sigmaX: 5, sigmaY: 5), // CSS blur(5px)
                child: Opacity(
                  opacity: 0.75,
                  child: Text(
                    digits,
                    style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w800, letterSpacing: 1.5, color: AppTheme.textPrimary),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _Notch extends StatelessWidget {
  const _Notch();

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 20,
      height: 20,
      decoration: const BoxDecoration(color: AppTheme.lightBg, shape: BoxShape.circle),
    );
  }
}

/// .receipt-divider — 2px dashed #CBD5E1
class _DashedDivider extends StatelessWidget {
  const _DashedDivider();

  @override
  Widget build(BuildContext context) {
    return CustomPaint(size: const Size(double.infinity, 2), painter: _DashPainter());
  }
}

class _DashPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final p = Paint()
      ..color = const Color(0xFFCBD5E1)
      ..strokeWidth = 2;
    const dash = 6.0, gap = 4.0;
    for (double x = 0; x < size.width; x += dash + gap) {
      canvas.drawLine(Offset(x, 1), Offset((x + dash).clamp(0, size.width), 1), p);
    }
  }

  @override
  bool shouldRepaint(covariant _DashPainter oldDelegate) => false;
}
//Modified By Nikhil 21Nov26 21:00 For receipt gate matching ui_prototype_docspot + DB data END
