// //Added By Nikhil 18Nov26 23:01 For Grapion Gym Module Manifest
import 'package:flutter/material.dart';
import '../module_registry.dart';

class GymModuleDefinition implements AppModuleDefinition {
  @override
  String get code => 'gym';

  @override
  String get name => 'Grapion Gym';

  /// Currently in active engineering - set to FALSE so it stays in Preview!
  @override
  bool get isImplemented => false;

  @override
  Widget buildHomeScreen(BuildContext context) {
    return const Scaffold(
      body: Center(
        child: Text('Grapion Gym Dashboard'),
      ),
    );
  }
}
