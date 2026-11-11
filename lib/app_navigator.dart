import 'package:flutter/material.dart';

/// 全局 navigator key：让扫码/OCR 等原生页面能在无 context 的静态方法里打开
class AppNavigator {
  AppNavigator._();
  static final GlobalKey<NavigatorState> key = GlobalKey<NavigatorState>();

  static void push(Widget page) {
    key.currentState?.push(MaterialPageRoute(builder: (_) => page));
  }
}
