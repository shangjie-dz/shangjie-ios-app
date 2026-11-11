import 'dart:async';

import 'package:flutter/material.dart';
import 'package:mobile_scanner/mobile_scanner.dart';

import 'app_navigator.dart';

/// 原生扫码：打开相机扫条码/二维码，返回 {ok:true, text:...}
/// 接口契约与现有安卓版 startScan 完全一致（网页通过 window.__pscNativeCb 接收）
class NativeScan {
  static Future<Map<String, dynamic>> start() {
    final completer = Completer<Map<String, dynamic>>();
    AppNavigator.push(ScanPage(onResult: (res) {
      if (!completer.isCompleted) completer.complete(res);
    }));
    return completer.future;
  }
}

/// 全屏扫码页
class ScanPage extends StatefulWidget {
  final void Function(Map<String, dynamic>) onResult;
  const ScanPage({super.key, required this.onResult});

  @override
  State<ScanPage> createState() => _ScanPageState();
}

class _ScanPageState extends State<ScanPage> {
  bool _done = false;

  void _finish(Map<String, dynamic> res) {
    if (_done) return;
    _done = true;
    widget.onResult(res);
    Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.black,
        foregroundColor: Colors.white,
        title: const Text('扫码'),
        leading: IconButton(
          icon: const Icon(Icons.close),
          onPressed: () => _finish({'ok': false, 'reason': 'cancel'}),
        ),
      ),
      body: MobileScanner(
        onDetect: (capture) {
          if (_done) return;
          final barcodes = capture.barcodes;
          if (barcodes.isEmpty) return;
          final code = barcodes.first.rawValue ?? '';
          if (code.isEmpty) return;
          _finish({'ok': true, 'text': code});
        },
      ),
    );
  }
}
