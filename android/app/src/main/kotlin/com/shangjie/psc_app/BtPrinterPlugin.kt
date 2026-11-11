package com.shangjie.psc_app

import android.Manifest
import android.annotation.SuppressLint
import android.bluetooth.BluetoothAdapter
import android.bluetooth.BluetoothDevice
import android.bluetooth.BluetoothSocket
import android.content.pm.PackageManager
import androidx.core.app.ActivityCompat
import androidx.core.content.ContextCompat
import io.flutter.embedding.engine.plugins.FlutterPlugin
import io.flutter.embedding.engine.plugins.activity.ActivityAware
import io.flutter.embedding.engine.plugins.activity.ActivityPluginBinding
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import io.flutter.plugin.common.MethodChannel.MethodCallHandler
import io.flutter.plugin.common.MethodChannel.Result
import java.io.OutputStream
import java.util.UUID

/**
 * 安卓蓝牙打印桥（佳博标签机 TSPL）。
 * 与现有安卓版 BtPrinter.java 完全对齐，供 Flutter 安卓端调用。
 * MethodChannel: psc/printer
 *   - paired   : 列出已配对设备，返回 [{name, mac}, ...]
 *   - print    : 参数 {mac, tspl}，打印
 */
class BtPrinterPlugin : FlutterPlugin, ActivityAware, MethodCallHandler {

    companion object {
        private val SPP_UUID: UUID = UUID.fromString("00001101-0000-1000-8000-00805F9B34FB")
    }

    private var channel: MethodChannel? = null
    private var binding: ActivityPluginBinding? = null
    private var socket: BluetoothSocket? = null
    private var out: OutputStream? = null

    private var pendingPrint: Map<String, Any>? = null

    override fun onAttachedToEngine(binding: FlutterPlugin.FlutterPluginBinding) {
        channel = MethodChannel(binding.binaryMessenger, "psc/printer")
        channel?.setMethodCallHandler(this)
    }

    override fun onDetachedFromEngine(binding: FlutterPlugin.FlutterPluginBinding) {
        channel?.setMethodCallHandler(null)
        channel = null
        close()
    }

    override fun onAttachedToActivity(binding: ActivityPluginBinding) {
        this.binding = binding
    }

    override fun onDetachedFromActivityForConfigChanges() {
        this.binding = null
    }

    override fun onReattachedToActivityForConfigChanges(binding: ActivityPluginBinding) {
        this.binding = binding
    }

    override fun onDetachedFromActivity() {
        this.binding = null
    }

    override fun onMethodCall(call: MethodCall, result: Result) {
        when (call.method) {
            "paired" -> result.success(paired())
            "print" -> {
                val mac = call.argument<String>("mac") ?: ""
                val tspl = call.argument<String>("tspl") ?: ""
                if (mac.isEmpty() || tspl.isEmpty()) {
                    result.error("ARG", "缺少打印机地址或打印内容", null)
                    return
                }
                doPrint(mac, tspl, result)
            }
            else -> result.notImplemented()
        }
    }

    private fun paired(): List<Map<String, String>> {
        val list = mutableListOf<Map<String, String>>()
        try {
            val adapter = BluetoothAdapter.getDefaultAdapter() ?: return list
            val devices = adapter.bondedDevices ?: return list
            for (d in devices) {
                if (d.name != null) list.add(mapOf("name" to d.name, "mac" to d.address))
            }
        } catch (_: Exception) {
        }
        return list
    }

    private fun hasBtPerm(): Boolean {
        val act = binding?.activity ?: return false
        return if (android.os.Build.VERSION.SDK_INT >= 31) {
            ContextCompat.checkSelfPermission(act, Manifest.permission.BLUETOOTH_CONNECT) ==
                PackageManager.PERMISSION_GRANTED
        } else {
            true
        }
    }

    private fun doPrint(mac: String, tspl: String, result: Result) {
        val act = binding?.activity ?: run {
            result.error("ACT", "activity 不可用", null)
            return
        }
        if (android.os.Build.VERSION.SDK_INT >= 31 && !hasBtPerm()) {
            pendingPrint = mapOf("mac" to mac, "tspl" to tspl)
            // 请求权限；结果需要在 Activity 里回传（简化处理：这里直接请求）
            ActivityCompat.requestPermissions(
                act,
                arrayOf(Manifest.permission.BLUETOOTH_CONNECT, Manifest.permission.BLUETOOTH_SCAN),
                9004
            )
            result.error("PERM", "需要蓝牙权限", null)
            return
        }
        // 后台线程打印
        Thread {
            try {
                if (!(socket?.isConnected == true)) {
                    connect(mac)
                }
                val data = (tspl + "\r\n").toByteArray(Charsets.GBK)
                val ok = send(data)
                if (ok) {
                    close()
                    act.runOnUiThread { result.success(mapOf("ok" to true, "message" to "打印完成")) }
                } else {
                    act.runOnUiThread { result.error("SEND", "发送失败，请检查打印机是否就绪", null) }
                }
            } catch (e: Exception) {
                close()
                act.runOnUiThread { result.error("PRINT", "打印出错：${e.message}", null) }
            }
        }.start()
    }

    @SuppressLint("MissingPermission")
    private fun connect(mac: String) {
        close()
        val adapter = BluetoothAdapter.getDefaultAdapter()
        val device: BluetoothDevice = adapter.getRemoteDevice(mac)
        socket = device.createRfcommSocketToServiceRecord(SPP_UUID)
        socket?.connect()
        out = socket?.outputStream
    }

    private fun send(data: ByteArray): Boolean {
        val o = out ?: return false
        return try {
            o.write(data)
            o.flush()
            true
        } catch (_: Exception) {
            close()
            false
        }
    }

    private fun close() {
        try { out?.close() } catch (_: Exception) {}
        try { socket?.close() } catch (_: Exception) {}
        out = null
        socket = null
    }
}
