import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:uuid/uuid.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:file_picker/file_picker.dart';
import '../services/socket_service.dart';
import 'package:share_plus/share_plus.dart';

class DonorScreen extends StatefulWidget {
  const DonorScreen({Key? key}) : super(key: key);

  @override
  State<DonorScreen> createState() => _DonorScreenState();
}

class _DonorScreenState extends State<DonorScreen> {
  String _pairingCode = "";
  String _status = "Initializing...";
  bool _isConnectedToPeer = false;
  
  int _connectedUsers = 0;
  double _maxUsers = 1;
  int _secondsActive = 0;
  Timer? _timer;

  @override
  void initState() {
    super.initState();
    _pairingCode = const Uuid().v4().substring(0, 6).toUpperCase();
    
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _loadSettingsAndConnect();
    });
  }

  void _shareCode() {
    Share.share(
      'Use my internet on OISS! My connection code is: $_pairingCode\n\nDownload OISS App: https://github.com/GCIS-Project/OISS',
    );
  }

  Future<void> _loadSettingsAndConnect() async {
    final prefs = await SharedPreferences.getInstance();
    setState(() {
      _maxUsers = prefs.getDouble('maxUsers') ?? 1;
    });
    
    _setupSocket();
  }

  void _setupSocket() async {
    final socketService = Provider.of<SocketService>(context, listen: false);
    
    await socketService.connect("ws://10.180.191.113:8000/ws");
    
    if (socketService.isConnected) {
      socketService.registerAsDonor(_pairingCode);
      setState(() {
        _status = "Waiting for someone to connect...";
      });
    }

    socketService.onApprovalRequest = (receiverId) {
      if (_connectedUsers >= _maxUsers) {
        // Automatically reject if max users reached
        socketService.rejectReceiver(receiverId);
      } else {
        _showApprovalDialog(receiverId);
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
        title: const Text('Donate Internet'),
        backgroundColor: Colors.green,
        foregroundColor: Colors.white,
        actions: [
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
              if (!_isConnectedToPeer) ...[
                const Text(
                  'Your Pairing Code',
                  style: TextStyle(fontSize: 18, color: Colors.grey),
                ),
                const SizedBox(height: 16),
                Container(
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
              ] else ...[
                // Active Dashboard Cards
                Card(
                  elevation: 4,
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                  child: ListTile(
                    leading: const Icon(Icons.people, color: Colors.blue, size: 40),
                    title: const Text("Users Connected", style: TextStyle(color: Colors.grey)),
                    subtitle: Text("$_connectedUsers / ${_maxUsers.round()}", style: const TextStyle(fontSize: 24, fontWeight: FontWeight.bold)),
                  ),
                ),
                const SizedBox(height: 16),
                Card(
                  elevation: 4,
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                  child: const ListTile(
                    leading: Icon(Icons.data_usage, color: Colors.orange, size: 40),
                    title: Text("Data Used", style: TextStyle(color: Colors.grey)),
                    subtitle: Text("0.0 MB", style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold)),
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
              const Spacer(),
              SizedBox(
                width: double.infinity,
                child: ElevatedButton.icon(
                  onPressed: () async {
                    FilePickerResult? result = await FilePicker.pickFiles();
                    if (result != null) {
                      File file = File(result.files.single.path!);
                      final bytes = await file.readAsBytes();
                      final base64String = base64Encode(bytes);
                      final socketService = Provider.of<SocketService>(context, listen: false);
                      socketService.sendFile(result.files.single.name, base64String);
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(content: Text('Sent ${result.files.single.name} to all receivers')),
                      );
                    }
                  },
                  icon: const Icon(Icons.attach_file),
                  label: const Padding(
                    padding: EdgeInsets.all(16.0),
                    child: Text('Share File', style: TextStyle(fontSize: 18)),
                  ),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.blue,
                    foregroundColor: Colors.white,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 12),
              SizedBox(
                width: double.infinity,
                child: ElevatedButton.icon(
                  onPressed: () {
                    Navigator.pop(context);
                  },
                  icon: const Icon(Icons.stop_circle),
                  label: const Padding(
                    padding: EdgeInsets.all(16.0),
                    child: Text('Stop Sharing', style: TextStyle(fontSize: 18)),
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
