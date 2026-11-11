import 'dart:convert';
import 'dart:io' show Platform;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:webview_flutter/webview_flutter.dart';

import 'native_scan.dart';
import 'native_ocr.dart';
import 'native_voice.dart';
import 'app_navigator.dart';

/// 线上网页地址（与现有安卓版、网页版完全同一个，保证功能 100% 一致）
const String kWebUrl = 'https://psc-saas.app.workbuddy.host/?sharecode=YR6B4D4PZA';

/// App 版本号（网页侧 PSCApp.version() 会取这个值）
const String kAppVersion = '1.6.0';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  // 沉浸式：状态栏透明，内容延伸到顶
  SystemChrome.setSystemUIOverlayStyle(const SystemUiOverlayStyle(
    statusBarColor: Colors.transparent,
    statusBarIconBrightness: Brightness.light,
    statusBarBrightness: Brightness.dark,
  ));
  runApp(const PscApp());
}

class PscApp extends StatelessWidget {
  const PscApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      navigatorKey: AppNavigator.key,
      title: '小捷·产销存',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        brightness: Brightness.dark,
        primaryColor: const Color(0xFF2F7BF6),
        scaffoldBackgroundColor: const Color(0xFF12141C),
        colorScheme: const ColorScheme.dark(
          primary: Color(0xFF2F7BF6),
          secondary: Color(0xFF6366F1),
        ),
        useMaterial3: true,
        splashColor: Colors.transparent,
        highlightColor: Colors.transparent,
      ),
      home: const WebShell(),
    );
  }
}

/// 判断当前平台（网页侧 PSCApp.platform() 会取这个值）
String get _platformName {
  if (Platform.isIOS) return 'ios';
  if (Platform.isAndroid) return 'android';
  return 'web';
}

class WebShell extends StatefulWidget {
  const WebShell({super.key});

  @override
  State<WebShell> createState() => _WebShellState();
}

class _WebShellState extends State<WebShell> {
  WebViewController? _controller;
  // 加载状态：loading=加载中 / ready=就绪 / error=加载失败
  String _status = 'loading';
  int _progress = 0;

  @override
  void initState() {
    super.initState();
    _init();
  }

  Future<void> _init() async {
    final ctrl = WebViewController()
      ..setJavaScriptMode(JavaScriptMode.unrestricted)
      ..setBackgroundColor(const Color(0xFF12141C))
      ..setNavigationDelegate(
        NavigationDelegate(
          onProgress: (p) {
            if (mounted) setState(() => _progress = p);
          },
          onPageStarted: (_) {
            if (mounted) setState(() => _status = 'loading');
          },
          onPageFinished: (_) {
            if (mounted) setState(() => _status = 'ready');
            _injectBridge();
          },
          onWebResourceError: (e) {
            if (mounted) setState(() => _status = 'error');
          },
        ),
      )
      ..addJavaScriptChannel('PscNative', onMessageReceived: _onNativeMessage)
      ..loadRequest(Uri.parse(kWebUrl));

    _controller = ctrl;
    if (mounted) setState(() {});
  }

  /// 重新加载（错误重试）
  Future<void> _reload() async {
    setState(() => _status = 'loading');
    await _controller?.reload();
  }

  /// 网页 -> 原生：网页通过消息通道调原生能力
  void _onNativeMessage(JavaScriptMessage msg) {
    try {
      final decoded = jsonDecode(msg.message) as Map<String, dynamic>;
      _handleNative(decoded);
    } catch (e) {
      // 忽略无法解析的消息
    }
  }

  /// 注入 PSCApp 桥对象：把原生能力暴露给网页，接口与现有安卓版完全一致
  Future<void> _injectBridge() async {
    if (_controller == null) return;
    final js = '''
(function(){
  if (window.PSCApp) return; // 已注入，避免重复
  window.__pscNativeCb = null;
  // iOS WKWebView 消息通道（webview_flutter addJavaScriptChannel 注入）
  var _post = function(obj){
    var s = JSON.stringify(obj);
    if (window.webkit && window.webkit.messageHandlers && window.webkit.messageHandlers.PscNative) {
      window.webkit.messageHandlers.PscNative.postMessage(s);
    } else if (window.PscNative && window.PscNative.postMessage) {
      window.PscNative.postMessage(s);
    }
  };
  window.PSCApp = {
    platform: function(){ return '$_platformName'; },
    version: function(){ return '$kAppVersion'; },
    openUrl: function(url){ _post({m:'openUrl', url:url}); },
    startScan: function(){ _post({m:'startScan'}); },
    startOcr: function(){ _post({m:'startOcr'}); },
    voiceSigned: function(authUrl, appId){ _post({m:'voice', authUrl:authUrl, appId:appId}); },
    speak: function(text){ _post({m:'speak', text:text}); },
    speakSigned: function(text, authUrl, appId){ _post({m:'speak', text:text, authUrl:authUrl, appId:appId}); }
  };
  // 蓝牙打印只在安卓暴露（iPhone 不支持佳博经典蓝牙 SPP）
  // 注意：网页侧 pairedPrinters() 是同步调用，webview_flutter 的 JSChannel 无法同步返回，
  // 因此安卓 Flutter 版暂不暴露打印接口；安卓打印沿用现有原生 Java 套壳 App。
})();
''';
    await _controller!.runJavaScript(js);
  }

  /// 原生侧把结果回传给网页（网页 callNative 期待 window.__pscNativeCb 被调用）
  Future<void> _replyToWeb(Map<String, dynamic> payload) async {
    if (_controller == null) return;
    final json = jsonEncode(payload);
    final js = "if(window.__pscNativeCb){window.__pscNativeCb($json);}";
    await _controller!.runJavaScript(js);
  }

  /// 处理网页发来的原生调用
  Future<void> _handleNative(Map<String, dynamic> msg) async {
    final m = msg['m'] as String?;
    switch (m) {
      case 'openUrl':
        final url = msg['url'] as String?;
        if (url != null && url.isNotEmpty) {
          await _openExternal(url);
        }
        break;
      case 'startScan':
        final res = await NativeScan.start();
        await _replyToWeb(res);
        break;
      case 'startOcr':
        final res = await NativeOcr.start();
        await _replyToWeb(res);
        break;
      case 'voice':
        final res = await NativeVoice.listen(
          authUrl: msg['authUrl'] as String?,
          appId: msg['appId'] as String?,
        );
        await _replyToWeb(res);
        break;
      case 'speak':
        NativeVoice.speak(
          text: msg['text'] as String?,
          authUrl: msg['authUrl'] as String?,
          appId: msg['appId'] as String?,
        );
        break;
    }
  }

  /// 站外链接跳系统浏览器
  Future<void> _openExternal(String url) async {
    final uri = Uri.tryParse(url);
    if (uri == null) return;
    try {
      await launchUrl(uri, mode: LaunchMode.externalApplication);
    } catch (_) {
      // 跳转失败静默
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Stack(
        children: [
          // WebView 主体
          if (_controller != null)
            WebViewWidget(controller: _controller!),

          // 加载中 / 错误页遮罩
          if (_status == 'loading')
            _buildLoading(),
          if (_status == 'error')
            _buildError(),
        ],
      ),
    );
  }

  /// 漂亮的加载页（小狗 logo + 进度条）
  Widget _buildLoading() {
    return Container(
      color: const Color(0xFF12141C),
      child: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // 小狗 logo
            Container(
              width: 88,
              height: 88,
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(24),
                gradient: const LinearGradient(
                  colors: [Color(0xFF2F7BF6), Color(0xFF6366F1)],
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                ),
              ),
              child: const Icon(Icons.pets, color: Colors.white, size: 48),
            ),
            const SizedBox(height: 20),
            const Text(
              '小捷·产销存',
              style: TextStyle(
                color: Colors.white,
                fontSize: 20,
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(height: 24),
            SizedBox(
              width: 160,
              child: LinearProgressIndicator(
                value: _progress > 0 ? _progress / 100 : null,
                backgroundColor: Colors.white12,
                color: const Color(0xFF2F7BF6),
                minHeight: 3,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            const SizedBox(height: 12),
            Text(
              '正在加载…',
              style: TextStyle(color: Colors.white54, fontSize: 13),
            ),
          ],
        ),
      ),
    );
  }

  /// 加载失败重试页
  Widget _buildError() {
    return Container(
      color: const Color(0xFF12141C),
      child: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 88,
              height: 88,
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(24),
                color: Colors.white10,
              ),
              child: const Icon(Icons.wifi_off, color: Colors.white38, size: 48),
            ),
            const SizedBox(height: 20),
            const Text(
              '网络连接失败',
              style: TextStyle(
                color: Colors.white,
                fontSize: 18,
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              '请检查网络后重试',
              style: TextStyle(color: Colors.white54, fontSize: 13),
            ),
            const SizedBox(height: 24),
            ElevatedButton.icon(
              onPressed: _reload,
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFF2F7BF6),
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(horizontal: 28, vertical: 12),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
              ),
              icon: const Icon(Icons.refresh, size: 18),
              label: const Text('重新加载'),
            ),
          ],
        ),
      ),
    );
  }
}
