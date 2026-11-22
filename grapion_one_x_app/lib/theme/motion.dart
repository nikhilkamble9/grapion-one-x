// //Added By Nikhil 18Nov26 21:29 For Motion & Animation Tokens
import 'package:flutter/material.dart';

class AppMotion {
  static const Duration splashTimeline = Duration(milliseconds: 4200);
  static const Duration fast = Duration(milliseconds: 200);
  static const Duration normal = Duration(milliseconds: 350);
  static const Duration slow = Duration(milliseconds: 600);

  static const Curve defaultCurve = Curves.easeInOutCubic;
  static const Curve bouncy = Curves.elasticOut;
  static const Curve smooth = Cubic(0.16, 1.0, 0.3, 1.0);

  //Added By Nikhil 21Nov26 20:43 For splash timings from ui_prototype_docspot START
  static const Duration ringOuter = Duration(milliseconds: 6000);
  static const Duration ringMiddle = Duration(milliseconds: 4000);
  static const Duration ringInner = Duration(milliseconds: 8000);
  static const Duration flare = Duration(milliseconds: 2500);
  static const Duration floatHalf = Duration(milliseconds: 1500); // 3s up-and-down cycle
  static const Duration satellitePulseHalf = Duration(milliseconds: 750); // 1.5s cycle
  static const Duration gridFly = Duration(milliseconds: 15000);
  static const Duration splashExit = Duration(milliseconds: 600);
  static const Curve ringMiddleCurve = Cubic(0.4, 0.0, 0.2, 1.0);
  static const Curve splashProgressCurve = Cubic(0.25, 1.0, 0.5, 1.0);
  //Added By Nikhil 21Nov26 20:43 For splash timings from ui_prototype_docspot END

  //Added By Nikhil 21Nov26 21:00 For screen motion from ui_prototype_docspot START
  static const Duration tabIn = Duration(milliseconds: 350); // tabSlideFadeIn
  static const Duration modalPop = Duration(milliseconds: 300); // modalPopIn
  static const Curve modalPopCurve = Cubic(0.175, 0.885, 0.32, 1.275); // slight overshoot
  static const Duration dock = Duration(milliseconds: 250); // .admin-dock-item transition
  static const Duration expand = Duration(milliseconds: 250); // request card arrow / expand
  //Added By Nikhil 21Nov26 21:00 For screen motion from ui_prototype_docspot END
}
