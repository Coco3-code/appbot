import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_blue_plus/flutter_blue_plus.dart';

final Guid serviceUuid = Guid('6E400001-B5A3-F393-E0A9-E50E24DCCA9E');
final Guid cmdUuid = Guid('6E400003-B5A3-F393-E0A9-E50E24DCCA9E');
final Guid statusUuid = Guid('6E400004-B5A3-F393-E0A9-E50E24DCCA9E');

const robotStates = [
  'Manuel',
  'Errance',
  'STOP : déchet détecté',
  'Ramassage',
  'Sécurité : caméra perdue',
];

void main() => runApp(const MaterialApp(
      debugShowCheckedModeBanner: false,
      home: RemotePage(),
    ));

class RemotePage extends StatefulWidget {
  const RemotePage({super.key});
  @override
  State<RemotePage> createState() => _RemotePageState();
}

class _RemotePageState extends State<RemotePage> {
  BluetoothDevice? _device;
  BluetoothCharacteristic? _cmd;
  StreamSubscription? _scanSub;
  StreamSubscription? _valSub;
  StreamSubscription? _connSub;
  String _link = 'Non connecté';
  String _robot = '-';

  Future<void> _connect() async {
    setState(() => _link = 'Recherche du robot...');
    _scanSub?.cancel();
    _scanSub = FlutterBluePlus.scanResults.listen((results) async {
      if (results.isEmpty || _device != null) return;
      final d = results.first.device;
      _device = d;
      await FlutterBluePlus.stopScan();
      try {
        await d.connect();
        _connSub = d.connectionState.listen((s) {
          if (s == BluetoothConnectionState.disconnected && mounted) {
            setState(() {
              _link = 'Déconnecté';
              _device = null;
              _cmd = null;
            });
          }
        });
        final services = await d.discoverServices();
        for (final s in services.where((s) => s.uuid == serviceUuid)) {
          for (final c in s.characteristics) {
            if (c.uuid == cmdUuid) _cmd = c;
            if (c.uuid == statusUuid) {
              await c.setNotifyValue(true);
              _valSub = c.onValueReceived.listen((v) {
                if (v.isNotEmpty && mounted) {
                  setState(() =>
                      _robot = v[0] < robotStates.length ? robotStates[v[0]] : '?');
                }
              });
            }
          }
        }
        if (mounted) setState(() => _link = 'Connecté');
      } catch (e) {
        if (mounted) {
          setState(() {
            _link = 'Erreur : $e';
            _device = null;
          });
        }
      }
    });
    await FlutterBluePlus.startScan(
        withServices: [serviceUuid], timeout: const Duration(seconds: 10));
  }

  Future<void> _send(String ch) async {
    try {
      await _cmd?.write([ch.codeUnitAt(0)], withoutResponse: false);
    } catch (_) {}
  }

  @override
  void dispose() {
    _scanSub?.cancel();
    _valSub?.cancel();
    _connSub?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Robot déchets')),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            children: [
              Text(_link),
              const SizedBox(height: 8),
              Text(_robot,
                  style: const TextStyle(fontSize: 22, fontWeight: FontWeight.bold),
                  textAlign: TextAlign.center),
              const SizedBox(height: 8),
              ElevatedButton(onPressed: _connect, child: const Text('Connecter')),
              const SizedBox(height: 16),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                children: [
                  ElevatedButton(
                      onPressed: () => _send('A'), child: const Text('Mode AUTO')),
                  ElevatedButton(
                      onPressed: () => _send('M'), child: const Text('Mode MANUEL')),
                ],
              ),
              const Spacer(),
              HoldButton(Icons.keyboard_arrow_up, () => _send('F'), () => _send('X')),
              const SizedBox(height: 8),
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  HoldButton(Icons.keyboard_arrow_left, () => _send('L'), () => _send('X')),
                  const SizedBox(width: 98),
                  HoldButton(Icons.keyboard_arrow_right, () => _send('R'), () => _send('X')),
                ],
              ),
              const SizedBox(height: 8),
              HoldButton(Icons.keyboard_arrow_down, () => _send('B'), () => _send('X')),
              const Spacer(),
              SizedBox(
                width: double.infinity,
                height: 64,
                child: ElevatedButton(
                  style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
                  onPressed: () => _send('X'),
                  child: const Text('STOP',
                      style: TextStyle(fontSize: 24, color: Colors.white)),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Bouton maintenu : envoie la direction tant qu'on appuie, puis STOP au relachement.
class HoldButton extends StatelessWidget {
  final IconData icon;
  final VoidCallback onDown;
  final VoidCallback onUp;
  const HoldButton(this.icon, this.onDown, this.onUp, {super.key});

  @override
  Widget build(BuildContext context) {
    return Listener(
      onPointerDown: (_) => onDown(),
      onPointerUp: (_) => onUp(),
      onPointerCancel: (_) => onUp(),
      child: Container(
        width: 90,
        height: 90,
        decoration: BoxDecoration(
          color: Colors.blueGrey.shade700,
          borderRadius: BorderRadius.circular(16),
        ),
        child: Icon(icon, size: 56, color: Colors.white),
      ),
    );
  }
}
