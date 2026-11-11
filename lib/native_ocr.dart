import 'dart:typed_data';

import 'package:flutter/services.dart';
import 'package:image_picker/image_picker.dart';

/// 拍照 OCR 识单：拍照 -> 识别文字，返回 {ok:true, text:...}
/// 接口契约与现有安卓版 startOcr 完全一致（网页通过 window.__pscNativeCb 接收）
///
/// 说明：iOS 上文字识别走系统 Vision 框架（原生层 NativeBridge.swift 实现），
/// 这里拍照后把图片字节通过 MethodChannel 交给原生识别。
class NativeOcr {
  static const MethodChannel _channel = MethodChannel('psc/ocr');

  static Future<Map<String, dynamic>> start() async {
    final picker = ImagePicker();
    try {
      final XFile? shot = await picker.pickImage(
        source: ImageSource.camera,
        imageQuality: 80,
        maxWidth: 1600,
      );
      if (shot == null) {
        return {'ok': false, 'reason': 'cancel'};
      }

      final bytes = await shot.readAsBytes();
      final text = await _recognize(bytes);

      if (text == null || text.isEmpty) {
        return {'ok': false, 'reason': 'error', 'message': '识别失败，请重试'};
      }
      return {'ok': true, 'text': text};
    } catch (e) {
      return {'ok': false, 'reason': 'error', 'message': '拍照或识别出错：$e'};
    }
  }

  /// 调用 iOS 原生 Vision 识别中文文字
  static Future<String?> _recognize(Uint8List bytes) async {
    try {
      final result = await _channel
          .invokeMethod<String>('recognize', {'bytes': bytes});
      return result;
    } catch (e) {
      return null;
    }
  }
}
