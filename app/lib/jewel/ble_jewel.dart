import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_blue_plus/flutter_blue_plus.dart';

import 'jewel_link.dart';
import 'protocol.dart';

/// Liaison Bluetooth Low Energy avec le bijou.
class BleJewel implements JewelLink {
  final ValueNotifier<bool> _connected = ValueNotifier(false);
  final LineDecoder _decoder = LineDecoder();
  final Map<int, Completer<Map<String, dynamic>>> _pending = {};

  BluetoothDevice? _device;
  BluetoothCharacteristic? _rx;
  StreamSubscription<BluetoothConnectionState>? _connectionSub;
  Timer? _retryTimer;
  Future<void> _writeQueue = Future.value();
  int _nextId = 1;
  bool _disposed = false;

  @override
  ValueListenable<bool> get connected => _connected;

  @override
  Future<String> findJewel() async {
    await _ensureBluetoothOn();

    ScanResult? best;
    final sub = FlutterBluePlus.onScanResults.listen((results) {
      for (final r in results) {
        if (best == null || r.rssi > best!.rssi) best = r;
      }
    });
    try {
      await FlutterBluePlus.startScan(
        withServices: [Guid(serviceUuid)],
        timeout: const Duration(seconds: 12),
      );
      // Dès qu'un bijou est vu, on laisse encore un court instant pour
      // retenir le plus proche s'il y en a plusieurs.
      final deadline = DateTime.now().add(const Duration(seconds: 12));
      while (best == null && DateTime.now().isBefore(deadline)) {
        await Future<void>.delayed(const Duration(milliseconds: 300));
      }
      if (best != null) {
        await Future<void>.delayed(const Duration(milliseconds: 1500));
      }
    } on PlatformException catch (e) {
      throw JewelException(JewelError.permission, e.message);
    } on FlutterBluePlusException catch (e) {
      throw JewelException(JewelError.permission, e.description);
    } finally {
      await sub.cancel();
      await FlutterBluePlus.stopScan().catchError((_) {});
    }

    final found = best;
    if (found == null) throw const JewelException(JewelError.notFound);
    return found.device.remoteId.str;
  }

  Future<void> _ensureBluetoothOn() async {
    if (!await FlutterBluePlus.isSupported) {
      throw const JewelException(JewelError.bluetoothOff, 'unsupported');
    }
    Future<BluetoothAdapterState> settled() => FlutterBluePlus.adapterState
        .firstWhere((s) => s == BluetoothAdapterState.on || s == BluetoothAdapterState.off || s == BluetoothAdapterState.unauthorized)
        .timeout(const Duration(seconds: 4), onTimeout: () => BluetoothAdapterState.unknown);

    var state = await settled();
    if (state == BluetoothAdapterState.off && Platform.isAndroid) {
      // Android propose d'activer le Bluetooth à la place de l'utilisateur.
      try {
        await FlutterBluePlus.turnOn();
        state = await settled();
      } catch (_) {}
    }
    if (state == BluetoothAdapterState.unauthorized) {
      throw const JewelException(JewelError.permission);
    }
    if (state != BluetoothAdapterState.on) {
      throw const JewelException(JewelError.bluetoothOff);
    }
  }

  @override
  Future<void> attach(String id) async {
    final device = BluetoothDevice.fromId(id);
    _device = device;
    _connectionSub = device.connectionState.listen((state) {
      if (state == BluetoothConnectionState.connected) {
        _onConnected(device);
      } else {
        _onDisconnected();
      }
    });
    await _connect(device);
  }

  /// `autoConnect` demande au système de se reconnecter tout seul dès que le
  /// bijou revient à portée.
  Future<void> _connect(BluetoothDevice device) async {
    try {
      await device.connect(autoConnect: true, mtu: null);
    } catch (_) {
      _scheduleRetry(device);
    }
  }

  void _scheduleRetry(BluetoothDevice device) {
    _retryTimer?.cancel();
    if (_disposed) return;
    _retryTimer = Timer(const Duration(seconds: 5), () => _connect(device));
  }

  Future<void> _onConnected(BluetoothDevice device) async {
    try {
      if (Platform.isAndroid) {
        await device.requestMtu(247).catchError((_) => 23);
      }
      final services = await device.discoverServices();
      final service = services.firstWhere((s) => s.uuid == Guid(serviceUuid));
      final rx = service.characteristics.firstWhere((c) => c.uuid == Guid(rxUuid));
      final tx = service.characteristics.firstWhere((c) => c.uuid == Guid(txUuid));

      _decoder.reset();
      final sub = tx.onValueReceived.listen(_onData);
      device.cancelWhenDisconnected(sub);
      await tx.setNotifyValue(true);

      _rx = rx;
      _connected.value = true;
    } catch (_) {
      // Service introuvable ou connexion perdue en cours de route : on repart
      // de zéro un peu plus tard.
      await device.disconnect().catchError((_) {});
      _scheduleRetry(device);
    }
  }

  void _onDisconnected() {
    _rx = null;
    _connected.value = false;
    for (final c in _pending.values) {
      c.completeError(const JewelException(JewelError.notConnected));
    }
    _pending.clear();
  }

  void _onData(List<int> chunk) {
    for (final message in _decoder.add(chunk)) {
      final id = message['id'];
      if (id is int) _pending.remove(id)?.complete(message);
    }
  }

  @override
  Future<Map<String, dynamic>> request(
    String cmd, {
    Map<String, dynamic>? args,
    Duration timeout = const Duration(seconds: 10),
  }) async {
    final device = _device;
    final rx = _rx;
    if (device == null || rx == null || !_connected.value) {
      throw const JewelException(JewelError.notConnected);
    }

    final id = _nextId++;
    final completer = Completer<Map<String, dynamic>>();
    _pending[id] = completer;

    // Un seul message à la fois sur le lien, découpé selon la taille maximale
    // d'un paquet Bluetooth.
    final bytes = encodeRequest(id, cmd, args);
    final write = _writeQueue.then((_) async {
      final chunkSize = device.mtuNow - 3;
      for (var i = 0; i < bytes.length; i += chunkSize) {
        final end = i + chunkSize > bytes.length ? bytes.length : i + chunkSize;
        await rx.write(
          bytes.sublist(i, end),
          withoutResponse: !rx.properties.write,
        );
      }
    });
    _writeQueue = write.catchError((_) {});

    try {
      await write;
      return checkResponse(await completer.future.timeout(timeout));
    } on TimeoutException {
      throw const JewelException(JewelError.timeout);
    } on JewelException {
      rethrow;
    } catch (e) {
      throw JewelException(JewelError.notConnected, '$e');
    } finally {
      _pending.remove(id);
    }
  }

  @override
  Future<void> dispose() async {
    _disposed = true;
    _retryTimer?.cancel();
    await _connectionSub?.cancel();
    _onDisconnected();
    await _device?.disconnect().catchError((_) {});
  }
}
