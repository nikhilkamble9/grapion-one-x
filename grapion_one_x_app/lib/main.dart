// //Added By Nikhil 18Nov26 23:02 For Module Registry Bootstrapping
import 'package:flutter/material.dart';
import 'theme/app_theme.dart';
import 'screens/common/launch_screen.dart';
import 'modules/module_registry.dart';
import 'modules/gym/gym_module.dart';
import 'services/push_service.dart'; //Added By Nikhil 22Nov26 00:10 For push notifications

//Modified By Nikhil 22Nov26 00:10 For Firebase init before runApp. Old: void main() {
Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await PushService.init(); //Added By Nikhil 22Nov26 00:10 For push notifications (Android only for now)
  
  // Register all module implementations present in code
  ModuleRegistry.register(GymModuleDefinition());

  runApp(const GrapionOneXApp());
}

class GrapionOneXApp extends StatelessWidget {
  const GrapionOneXApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'G.One.X',
      debugShowCheckedModeBanner: false,
      scaffoldMessengerKey: appMessengerKey, //Added By Nikhil 22Nov26 00:10 For foreground push banners
      theme: AppTheme.lightTheme,
      home: const LaunchScreen(),
    );
  }
}
