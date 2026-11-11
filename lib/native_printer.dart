import 'dart:io' show Platform;

import 'package:flutter/services.dart';

/// 蓝牙打印桥（佳博标签机 TSPL）。
/// 安卓端走 MethodChannel psc/printer；iPhone 端不支持（苹果不开放经典蓝牙 SPP）。
class NativePrinter {
  static const MethodChannel _channel = MethodChannel('psc/printer');

  /// 当前设备是否支持蓝牙打印
  static bool get supported => Platform.isAndroid;

  /// 列出已配对打印机，返回 [{name, mac}, ...]
  static Future<List<Map<String, String>>> paired() async {
    if (!supported) return [];
    try {
      final result = await _channel.invokeListMethod('paired');
      if (result == null) return [];
      return result
          .whereType<Map>()
          .map((e) => {
                'name': (e['name'] ?? '').toString(),
                'mac': (e['mac'] ?? '').toString(),
              })
          .toList();
    } catch (_) {
      return [];
    }
  }

  /// 打印标签：mac 为打印机地址，tspl 为完整 TSPL 指令串
  /// 返回 {ok:true, message} 或抛异常
  static Future<Map<String, dynamic>> print({
    required String mac,
    required String tspl,
  }) async {
    if (!supported) {
      return {'ok': false, 'message': '当前设备不支持蓝牙打印'};
    }
    try {
      final result = await _channel.invokeMethod('print', {
        'mac': mac,
        'tspl': tspl,
      });
      if (result is Map) {
        return {
          'ok': result['ok'] == true,
          'message': (result['message'] ?? '').toString(),
        };
      }
      return {'ok': true, 'message': '打印完成'};
    } on PlatformException catch (e) {
      return {'ok': false, 'message': e.message ?? '打印失败'};
    }
  }
}
