import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:mobile_scanner/mobile_scanner.dart';
import 'package:flutter/services.dart';
import '../services/socket_service.dart';

class ReceiverScreen extends StatefulWidget {
  const ReceiverScreen({Key? key}) : super(key: key);

  @override
  State<ReceiverScreen> createState() => _ReceiverScreenState();
}

class _ReceiverScreenState extends State<ReceiverScreen> {
  final TextEditingController _codeController = TextEditingController();
  String _status = "Enter a code or scan QR";
  bool _isConnected = false;
  bool _isScanning = false;
  MobileScannerController cameraController = MobileScannerController();

  void _connect(String code) async {
    final socketService = Provider.of<SocketService>(context, listen: false);
    await socketService.connect("wss://oiss.onrender.com/ws");

    if (socketService.isConnected) {
      socketService.joinAsReceiver(code);
      setState(() {
        _status = "Connecting to donor...";
      });
    }

    socketService.onWaitingApproval = () {
      setState(() {
        _status = "Waiting for donor to approve...";
      });
    };

    socketService.onConnected = (_) async {
      setState(() {
        _status = "Connected! Starting VPN...";
        _isConnected = true;
        _isScanning = false;
      });
      socketService.startLocalProxy();
      
      // Start VPN Service natively
      const platform = MethodChannel('com.oiss.vpn/control');
      try {
        final bool result = await platform.invokeMethod('startVpn');
        if (result) {
           setState(() {
             _status = "VPN Tunnel Active! Global internet sharing enabled.";
           });
        } else {
           setState(() {
             _status = "Please grant VPN permissions and try again.";
           });
        }
      } catch (e) {
        setState(() {
          _status = "Failed to start VPN: $e";
        });
      }
    };

    socketService.onFileReceived = (filename, base64Data) {
      if (mounted) {
        setState(() {
          _status = "Received file: $filename";
        });
      }
    };
    
    socketService.onAdminNotification = (message) {
      if (mounted) {
        showDialog(
          context: context,
          builder: (context) => AlertDialog(
            title: const Row(
              children: [
                Icon(Icons.campaign, color: Colors.blue),
                SizedBox(width: 10),
                Text("Admin Broadcast"),
              ],
            ),
            content: Text(message),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context),
                child: const Text("OK"),
              )
            ],
          ),
        );
      }
    };



    socketService.onRejected = () {
      setState(() {
        _status = "Connection rejected by donor.";
        socketService.disconnect();
      });
    };
    
    socketService.onError = (err) {
      setState(() {
        _status = "Error: $err";
      });
    };
    
    socketService.onDonorDisconnected = () {
      setState(() {
        _status = "Donor disconnected.";
        _isConnected = false;
        socketService.disconnect();
      });
    };
  }

  @override
  void dispose() {
    Provider.of<SocketService>(context, listen: false).disconnect();
    cameraController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Receive Internet'),
        backgroundColor: Colors.blue,
        foregroundColor: Colors.white,
      ),
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(24.0),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              if (_isScanning) ...[
                const Text("Scanning QR Code...", style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
                const SizedBox(height: 16),
                SizedBox(
                  height: 300,
                  width: 300,
                  child: MobileScanner(
                    controller: cameraController,
                    onDetect: (capture) {
                      final List<Barcode> barcodes = capture.barcodes;
                      for (final barcode in barcodes) {
                        if (barcode.rawValue != null) {
                          setState(() {
                            _codeController.text = barcode.rawValue!;
                            _isScanning = false;
                          });
                          _connect(barcode.rawValue!);
                          break;
                        }
                      }
                    },
                  ),
                ),
                const SizedBox(height: 16),
                ElevatedButton(
                  onPressed: () => setState(() => _isScanning = false),
                  child: const Text("Cancel Scan"),
                ),
                const SizedBox(height: 40),
              ] else if (!_isConnected) ...[
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                  decoration: BoxDecoration(
                    border: Border.all(color: Colors.green, width: 2),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: TextField(
                    controller: _codeController,
                    textAlign: TextAlign.center,
                    style: const TextStyle(fontSize: 32, fontWeight: FontWeight.bold, letterSpacing: 4),
                    decoration: const InputDecoration(
                      border: InputBorder.none,
                      hintText: "000000",
                    ),
                    textCapitalization: TextCapitalization.characters,
                    maxLength: 6,
                  ),
                ),
                const SizedBox(height: 24),
                SizedBox(
                  width: double.infinity,
                  height: 50,
                  child: ElevatedButton(
                    onPressed: () {
                      if (_codeController.text.length >= 6) {
                        _connect(_codeController.text);
                      }
                    },
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.blue,
                      foregroundColor: Colors.white,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                    ),
                    child: const Text('Connect', style: TextStyle(fontSize: 18)),
                  ),
                ),
                const SizedBox(height: 16),
                SizedBox(
                  width: double.infinity,
                  height: 50,
                  child: OutlinedButton.icon(
                    onPressed: () => setState(() => _isScanning = true),
                    icon: const Icon(Icons.qr_code_scanner),
                    label: const Text('Scan QR Code', style: TextStyle(fontSize: 18)),
                  ),
                ),
                const SizedBox(height: 40),
              ] else ...[
                 const Icon(Icons.vpn_key, size: 80, color: Colors.blue),
                 const SizedBox(height: 20),
                 const Text("VPN Tunnel is Active!", textAlign: TextAlign.center, style: TextStyle(fontSize: 18, color: Colors.green, fontWeight: FontWeight.bold)),
                 const SizedBox(height: 16),
                 Consumer<SocketService>(
                   builder: (context, service, child) {
                     return Text(
                       "⚡ Speed: ${service.currentSpeedMBps.toStringAsFixed(2)} MB/s",
                       style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: Colors.blue),
                     );
                   }
                 ),
                 const SizedBox(height: 16),
                 const Text("All your phone's apps and browser traffic is now securely routed through the Donor device. You can verify this by checking your IP on whatsmyip.com", textAlign: TextAlign.center, style: TextStyle(color: Colors.grey)),
                 const SizedBox(height: 40),
              ],
              Text(
                _status,
                textAlign: TextAlign.center,
                style: const TextStyle(fontSize: 16, color: Colors.black87),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
