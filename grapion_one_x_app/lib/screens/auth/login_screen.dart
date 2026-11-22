// //Added By Nikhil 18Nov26 21:33 For Sign In Screen with Gate Routing
//Modified By Nikhil 21Nov26 21:00 For Sign In matching ui_prototype_docspot. Old: full file backed up at D:\AI Agents Temp\grapion-one-x\GrapionOneX_DocSpot_CleanUI\21Nov26\backup\allscreens_2100_DesignMatch\ START
import 'dart:convert';

import 'package:flutter/material.dart';

import '../../services/api_client.dart';
import '../../theme/app_theme.dart';
import '../../widgets/doc_ui.dart';
import '../admin/admin_dashboard_screen.dart';
import '../common/launch_screen.dart';
import '../home/entry_router.dart'; //Added By Nikhil 21Nov26 23:30 For role-based routing
import 'forgot_password_screen.dart';
import 'register_screen.dart';

class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  final TextEditingController _userCtrl = TextEditingController();
  final TextEditingController _passCtrl = TextEditingController();
  bool _loading = false;
  String? _error;

  @override
  void dispose() {
    _userCtrl.dispose();
    _passCtrl.dispose();
    super.dispose();
  }

  Future<void> _handleLogin() async {
    final usernameOrEmail = _userCtrl.text.trim();
    final password = _passCtrl.text;

    if (usernameOrEmail.isEmpty || password.isEmpty) {
      setState(() => _error = 'Please enter both username and password');
      return;
    }

    setState(() {
      _loading = true;
      _error = null;
    });

    try {
      final res = await apiClient.post('/auth/login', {
        'username_or_email': usernameOrEmail,
        'password': password,
      });

      final data = jsonDecode(res.body);
      if (res.statusCode == 200) {
        await apiClient.saveToken(data['access_token']);
        final role = data['user']['role'];
        if (!mounted) return;

        if (role == 'admin' || role == 'super_admin') { //Modified By Nikhil 21Nov26 23:30 For super admin role. Old: if (role == 'admin') {
          Navigator.of(context).pushReplacement(docRoute(const AdminDashboardScreen()));
        } else {
          //Modified By Nikhil 21Nov26 23:30 For routing by module role (0 → gate, 1 → straight in, 2+ → picker). Old: my-status → MyModules / gate
          await routeAfterLogin(context);
        }
      } else {
        setState(() => _error = data['detail']?.toString() ?? 'Login failed');
      }
    } catch (e) {
      if (mounted) setState(() => _error = 'Connection error. Please check server.');
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: SingleChildScrollView(
          padding: kScreenPadding,
          child: AutofillGroup(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Brand pill + Replay Intro
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    const BrandPill(),
                    Material(
                      color: AppTheme.chipBg,
                      shape: const StadiumBorder(),
                      child: InkWell(
                        customBorder: const StadiumBorder(),
                        onTap: () => Navigator.of(context).pushReplacement(docRoute(const LaunchScreen())),
                        child: const Padding(
                          padding: EdgeInsets.symmetric(horizontal: 14, vertical: 6),
                          child: Text(
                            '▶ Replay Intro',
                            style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: AppTheme.textMuted),
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 30),
                const ScreenTitle(
                  title: 'Sign In to G.One.X',
                  subtitle: 'Manage your business modules & operations',
                ),
                const SizedBox(height: 24),

                if (_error != null) MessageBanner(_error!),

                DocField(
                  label: 'Username or Email',
                  controller: _userCtrl,
                  hint: 'e.g. nikhil_admin',
                  textInputAction: TextInputAction.next,
                  autofillHints: const [AutofillHints.username],
                ),
                DocField(
                  label: 'Password',
                  controller: _passCtrl,
                  hint: 'Enter password',
                  obscure: true,
                  textInputAction: TextInputAction.done,
                  onSubmitted: (_) => _handleLogin(),
                  autofillHints: const [AutofillHints.password],
                ),

                Align(
                  alignment: Alignment.centerRight,
                  child: GestureDetector(
                    onTap: () => Navigator.of(context).push(docRoute(const ForgotPasswordScreen())),
                    child: const Text(
                      'Forgot Password?',
                      style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: AppTheme.accentBlue),
                    ),
                  ),
                ),
                const SizedBox(height: 24),

                PillButton(label: 'Sign In', loading: _loading, onPressed: _handleLogin),
                const SizedBox(height: 20),

                Center(
                  child: Wrap(
                    crossAxisAlignment: WrapCrossAlignment.center,
                    children: [
                      const Text("Don't have an account? ", style: TextStyle(fontSize: 12, color: AppTheme.textMuted)),
                      GestureDetector(
                        onTap: () => Navigator.of(context).push(docRoute(const RegisterScreen())),
                        child: const Text(
                          'Create Account',
                          style: TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.w800,
                            color: AppTheme.textPrimary,
                            decoration: TextDecoration.underline,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
//Modified By Nikhil 21Nov26 21:00 For Sign In matching ui_prototype_docspot END
