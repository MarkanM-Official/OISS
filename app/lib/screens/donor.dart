import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:uuid/uuid.dart';
import 'package:file_picker/file_picker.dart';
import '../services/socket_service.dart';
import 'package:share_plus/share_plus.dart';
import 'package:qr_flutter/qr_flutter.dart';

class DonorScreen extends StatefulWidget {
  final bool isPublic;
  final String serverName;
  final int maxUsers;
  final double dataLimitMB;

  const DonorScreen({
    Key? key,
    required this.isPublic,
    required this.serverName,
    required this.maxUsers,
    required this.dataLimitMB,
  }) : super(key: key);

  @override
  State<DonorScreen> createState() => _DonorScreenState();
}

class _DonorScreenState extends State<DonorScreen> {
  String _pairingCode = "";
  String _status = "Initializing...";
  bool _isConnectedToPeer = false;
  
  int _connectedUsers = 0;
  int _secondsActive = 0;
  Timer? _timer;

  @override
  void initState() {
    super.initState();
    _pairingCode = const Uuid().v4().substring(0, 6).toUpperCase();
    
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _setupSocket();
    });
  }

  void _shareCode() {
    Share.share(
      'Use my internet on OISS! My connection code is: $_pairingCode\n\nDownload OISS App: https://github.com/MarkanM-Official/OISS',
    );
  }

  void _setupSocket() async {
    final socketService = Provider.of<SocketService>(context, listen: false);
    
    await socketService.connect("wss://oiss.onrender.com/ws");
    
    if (socketService.isConnected) {
      // Pass all the config to socket service
      socketService.registerAsDonorConfigured(
        _pairingCode,
        widget.isPublic,
        widget.serverName,
        widget.maxUsers,
        widget.dataLimitMB,
      );
      setState(() {
        _status = widget.isPublic ? "Public Server Active. Waiting for peers..." : "Waiting for someone to connect...";
      });
    }

    socketService.onApprovalRequest = (receiverId) {
      if (_connectedUsers >= widget.maxUsers) {
        socketService.rejectReceiver(receiverId);
      } else {
        if (widget.isPublic) {
          // Public servers auto-approve connections
          socketService.approveReceiver(receiverId);
        } else {
          _showApprovalDialog(receiverId);
        }
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

    socketService.onConnected = (_) {
      setState(() {
        _status = "Connected! Sharing active.";
        _isConnectedToPeer = true;
        _connectedUsers++;
      });
      _startTimer();
    };
    
    socketService.onError = (error) {
      setState(() {
        _status = "Error: $error";
      });
    };
  }

  void _startTimer() {
    if (_timer != null && _timer!.isActive) return;
    _timer = Timer.periodic(const Duration(seconds: 1), (timer) {
      setState(() {
        _secondsActive++;
      });
    });
  }

  String _formatTime(int seconds) {
    int h = seconds ~/ 3600;
    int m = (seconds % 3600) ~/ 60;
    int s = seconds % 60;
    return '${h.toString().padLeft(2, '0')}:${m.toString().padLeft(2, '0')}:${s.toString().padLeft(2, '0')}';
  }

  void _showApprovalDialog(String receiverId) {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) {
        return AlertDialog(
          title: const Text('Connection Request'),
          content: const Text('Someone wants to use your internet. Allow?'),
          actions: [
            TextButton(
              onPressed: () {
                Provider.of<SocketService>(context, listen: false).rejectReceiver(receiverId);
                Navigator.pop(context);
              },
              style: TextButton.styleFrom(foregroundColor: Colors.red),
              child: const Text('Reject'),
            ),
            ElevatedButton(
              onPressed: () {
                Provider.of<SocketService>(context, listen: false).approveReceiver(receiverId);
                Navigator.pop(context);
              },
              style: ElevatedButton.styleFrom(backgroundColor: Colors.green),
              child: const Text('Allow'),
            ),
          ],
        );
      },
    );
  }

  @override
  void dispose() {
    _timer?.cancel();
    Provider.of<SocketService>(context, listen: false).disconnect();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.serverName),
        backgroundColor: widget.isPublic ? Colors.purple : Colors.green,
        foregroundColor: Colors.white,
        actions: [
          if (!widget.isPublic)
            IconButton(
              icon: const Icon(Icons.share),
              onPressed: _shareCode,
              tooltip: 'Share Code',
            ),
        ],
      ),
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(24.0),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              if (!widget.isPublic && !_isConnectedToPeer) ...[
                const Text(
                  'Scan QR Code to Connect',
                  style: TextStyle(fontSize: 18, color: Colors.grey),
                ),
                const SizedBox(height: 16),
                QrImageView(
                  data: _pairingCode,
                  version: QrVersions.auto,
                  size: 200.0,
                ),
                const SizedBox(height: 16),
                const Text('OR USE TEXT CODE', style: TextStyle(fontWeight: FontWeight.bold)),
                Container(
                  margin: const EdgeInsets.only(top: 10),
                  padding: const EdgeInsets.symmetric(horizontal: 40, vertical: 20),
                  decoration: BoxDecoration(
                    color: Colors.grey[200],
                    borderRadius: BorderRadius.circular(16),
                  ),
                  child: Text(
                    _pairingCode,
                    style: const TextStyle(
                      fontSize: 48,
                      fontWeight: FontWeight.bold,
                      letterSpacing: 4,
                    ),
                  ),
                ),
                const SizedBox(height: 40),
              ] else if (widget.isPublic && !_isConnectedToPeer) ...[
                 const Icon(Icons.public, size: 80, color: Colors.purple),
                 const SizedBox(height: 20),
                 const Text("Your server is listed publicly.\nWaiting for automatic connections...", textAlign: TextAlign.center, style: TextStyle(fontSize: 18)),
                 const SizedBox(height: 40),
              ] else ...[
                // Active Dashboard Cards
                Card(
                  elevation: 4,
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                  child: ListTile(
                    leading: const Icon(Icons.people, color: Colors.blue, size: 40),
                    title: const Text("Users Connected", style: TextStyle(color: Colors.grey)),
                    subtitle: Text("$_connectedUsers / ${widget.maxUsers}", style: const TextStyle(fontSize: 24, fontWeight: FontWeight.bold)),
                  ),
                ),
                const SizedBox(height: 16),
                Card(
                  elevation: 4,
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                  child: ListTile(
                    leading: const Icon(Icons.data_usage, color: Colors.orange, size: 40),
                    title: const Text("Data Limit", style: TextStyle(color: Colors.grey)),
                    subtitle: Text(widget.dataLimitMB == 0 ? "Unlimited" : "${widget.dataLimitMB.round()} MB", style: const TextStyle(fontSize: 24, fontWeight: FontWeight.bold)),
                  ),
                ),
                const SizedBox(height: 16),
                Card(
                  elevation: 4,
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                  child: ListTile(
                    leading: const Icon(Icons.timer, color: Colors.green, size: 40),
                    title: const Text("Time Active", style: TextStyle(color: Colors.grey)),
                    subtitle: Text(_formatTime(_secondsActive), style: const TextStyle(fontSize: 24, fontWeight: FontWeight.bold)),
                  ),
                ),
                const SizedBox(height: 40),
              ],
              Text(
                _status,
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.w500,
                  color: _isConnectedToPeer ? Colors.green : Colors.black87,
                ),
              ),
              if (_isConnectedToPeer) ...[
                const SizedBox(height: 16),
                Consumer<SocketService>(
                  builder: (context, service, child) {
                    return Text(
                      "⚡ Speed: ${service.currentSpeedMBps.toStringAsFixed(2)} MB/s",
                      style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: Colors.blue),
                    );
                  }
                ),
              ],
              const Spacer(),
              SizedBox(
                width: double.infinity,
                child: ElevatedButton.icon(
                  onPressed: () {
                    Navigator.pop(context);
                  },
                  icon: const Icon(Icons.stop_circle),
                  label: const Padding(
                    padding: EdgeInsets.all(16.0),
                    child: Text('Stop Server', style: TextStyle(fontSize: 18)),
                  ),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.red,
                    foregroundColor: Colors.white,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
