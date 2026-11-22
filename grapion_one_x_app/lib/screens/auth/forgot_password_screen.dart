// //Added By Nikhil 18Nov26 21:37 For 3-Step Password Recovery
//Modified By Nikhil 21Nov26 21:00 For Forgot Password matching ui_prototype_docspot. Old: full file backed up at D:\AI Agents Temp\grapion-one-x\GrapionOneX_DocSpot_CleanUI\21Nov26\backup\allscreens_2100_DesignMatch\ START
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../services/api_client.dart';
import '../../theme/app_theme.dart';
import '../../theme/motion.dart';
import '../../widgets/doc_ui.dart';

class ForgotPasswordScreen extends StatefulWidget {
  const ForgotPasswordScreen({super.key});

  @override
  State<ForgotPasswordScreen> createState() => _ForgotPasswordScreenState();
}

class _ForgotPasswordScreenState extends State<ForgotPasswordScreen> {
  static const _stepNames = {1: 'Username', 2: 'Mobile Verification', 3: 'Set New Password'};

  int _currentStep = 1;
  final _userCtrl = TextEditingController();
  final _mobileCtrl = TextEditingController();
  final _pass1Ctrl = TextEditingController();
  final _pass2Ctrl = TextEditingController();

  String _validatedUser = '';
  bool _loading = false;
  String? _error;
  String? _success;

  @override
  void dispose() {
    for (final c in [_userCtrl, _mobileCtrl, _pass1Ctrl, _pass2Ctrl]) {
      c.dispose();
    }
    super.dispose();
  }

  String _detail(dynamic data, String fallback) => data is Map && data['detail'] is String ? data['detail'] : fallback;

  void _goTo(int step) => setState(() {
        _currentStep = step;
        _error = null;
      });

  Future<void> _step1VerifyUser() async {
    final username = _userCtrl.text.trim();
    if (username.isEmpty) {
      setState(() => _error = 'Please enter your username');
      return;
    }
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final res = await apiClient.post('/auth/forgot-password/verify-username', {'username': username});
      final data = jsonDecode(res.body);
      if (res.statusCode == 200) {
        // The design shows only "USER VALIDATED @username" — we do not display any part of the mobile number.
        _validatedUser = username;
        _goTo(2);
      } else {
        setState(() => _error = _detail(data, 'Username not found'));
      }
    } catch (e) {
      if (mounted) setState(() => _error = 'Connection error');
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _step2VerifyMobile() async {
    final mobile = _mobileCtrl.text.trim();
    if (mobile.isEmpty) {
      setState(() => _error = 'Please enter your registered mobile number');
      return;
    }
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final res = await apiClient.post('/auth/forgot-password/verify-mobile', {
        'username': _validatedUser,
        'mobile_number': mobile,
      });
      final data = jsonDecode(res.body);
      if (res.statusCode == 200) {
        _goTo(3);
      } else {
        setState(() => _error = _detail(data, 'Mobile number does not match'));
      }
    } catch (e) {
      if (mounted) setState(() => _error = 'Connection error');
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _step3ResetPassword() async {
    final p1 = _pass1Ctrl.text;
    final p2 = _pass2Ctrl.text;
    if (p1.isEmpty || p2.isEmpty) {
      setState(() => _error = 'Please enter both password fields.');
      return;
    }
    if (p1 != p2) {
      setState(() => _error = 'Passwords do not match. Please verify.');
      return;
    }
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final res = await apiClient.post('/auth/forgot-password/reset', {
        'username': _validatedUser,
        'mobile_number': _mobileCtrl.text.trim(),
        'new_password': p1,
      });
      final data = jsonDecode(res.body);
      if (res.statusCode == 200) {
        setState(() => _success = 'Password updated successfully! Please sign in with your new password.');
        await Future.delayed(const Duration(seconds: 2));
        if (mounted) Navigator.pop(context);
      } else {
        setState(() => _error = _detail(data, 'Failed to reset password (minimum 6 characters).'));
      }
    } catch (e) {
      if (mounted) setState(() => _error = 'Connection error');
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: LayoutBuilder(
          builder: (context, constraints) => SingleChildScrollView(
            padding: kScreenPadding,
            child: ConstrainedBox(
              // Lets the buttons sit at the bottom (margin-top:auto) while still scrolling on small screens.
              constraints: BoxConstraints(minHeight: constraints.maxHeight - kScreenPadding.vertical),
              child: IntrinsicHeight(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        SmallPill(label: '← Cancel', onTap: () => Navigator.pop(context)),
                        Text(
                          'Step $_currentStep of 3: ${_stepNames[_currentStep]}',
                          style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: AppTheme.textMuted),
                        ),
                      ],
                    ),
                    const SizedBox(height: 18),
                    Row(
                      children: [
                        for (var s = 1; s <= 3; s++) ...[
                          if (s > 1) const SizedBox(width: 8),
                          Expanded(
                            child: AnimatedContainer(
                              duration: const Duration(milliseconds: 300),
                              height: 4,
                              decoration: BoxDecoration(
                                color: _currentStep >= s ? AppTheme.primary : AppTheme.borderSubtle,
                                borderRadius: BorderRadius.circular(99),
                              ),
                            ),
                          ),
                        ],
                      ],
                    ),
                    const SizedBox(height: 20),
                    Expanded(
                      child: AnimatedSwitcher(
                        duration: AppMotion.tabIn,
                        transitionBuilder: (child, anim) => TabInTransition(animation: anim, child: child),
                        layoutBuilder: (current, previous) => current ?? const SizedBox.shrink(), //Modified By Nikhil 21Nov26 21:16 For no step overlap. Old: Stack(children: [...previous, ?current])
                        child: KeyedSubtree(key: ValueKey(_currentStep), child: _buildStep()),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildStep() {
    final messages = [
      if (_error != null) MessageBanner(_error!),
      if (_success != null) MessageBanner(_success!, success: true),
    ];

    switch (_currentStep) {
      case 1:
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const ScreenTitle(title: 'Account Recovery', subtitle: 'Step 1: Enter your registered username'),
            const SizedBox(height: 20),
            ...messages,
            DocField(
              label: 'Registered Username',
              controller: _userCtrl,
              hint: 'Your username', //Modified By Nikhil 22Nov26 12:22 For neutral placeholder. Old: 'e.g. nikhil_kamble'
              onSubmitted: (_) => _step1VerifyUser(),
            ),
            const Spacer(),
            const SizedBox(height: 40),
            PillButton(label: 'Validate & Continue →', loading: _loading, onPressed: _step1VerifyUser),
          ],
        );
      case 2:
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const ScreenTitle(title: 'Verify Identity', subtitle: 'Step 2: Enter your registered mobile number'),
            const SizedBox(height: 20),
            Container(
              width: double.infinity,
              margin: const EdgeInsets.only(bottom: 16),
              padding: const EdgeInsets.all(18),
              decoration: BoxDecoration(
                color: AppTheme.selectedBg,
                borderRadius: BorderRadius.circular(AppTheme.radiusLg),
                border: Border.all(color: const Color(0xFFBBF7D0)),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text('USER VALIDATED', style: TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: Color(0xFF15803D))),
                  Text('@$_validatedUser', style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w800, color: Color(0xFF166534))),
                ],
              ),
            ),
            ...messages,
            DocField(
              label: 'Registered Mobile Number',
              controller: _mobileCtrl,
              hint: '98765 43210',
              keyboardType: TextInputType.phone,
              inputFormatters: [FilteringTextInputFormatter.allow(RegExp(r'[0-9 ]')), LengthLimitingTextInputFormatter(15)],
              onSubmitted: (_) => _step2VerifyMobile(),
            ),
            const Spacer(),
            const SizedBox(height: 40),
            PillButton(label: 'Verify Mobile & Continue →', loading: _loading, onPressed: _step2VerifyMobile),
            const SizedBox(height: 10),
            PillButton(label: '← Back to Username', variant: PillVariant.secondary, onPressed: () => _goTo(1)),
          ],
        );
      default:
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const ScreenTitle(title: 'Set New Password', subtitle: 'Step 3: Create and confirm your new password'),
            const SizedBox(height: 20),
            ...messages,
            DocField(label: 'New Password', controller: _pass1Ctrl, hint: 'Enter new password', obscure: true),
            DocField(
              label: 'Type Again New Password',
              controller: _pass2Ctrl,
              hint: 'Type again new password',
              obscure: true,
              onSubmitted: (_) => _step3ResetPassword(),
            ),
            const Spacer(),
            const SizedBox(height: 40),
            PillButton(
              label: 'Submit & Update Password',
              variant: PillVariant.accent,
              loading: _loading,
              onPressed: _success == null ? _step3ResetPassword : null,
            ),
          ],
        );
    }
  }
}
//Modified By Nikhil 21Nov26 21:00 For Forgot Password matching ui_prototype_docspot END
