import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:path_provider/path_provider.dart';
import 'package:file_picker/file_picker.dart';
import '../services/socket_service.dart';

class ReceiverScreen extends StatefulWidget {
  const ReceiverScreen({Key? key}) : super(key: key);

  @override
  State<ReceiverScreen> createState() => _ReceiverScreenState();
}

class _ReceiverScreenState extends State<ReceiverScreen> {
  final TextEditingController _codeController = TextEditingController();
  String _status = "";
  bool _isConnectedToPeer = false;
  bool _isWaiting = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _setupSocket();
    });
  }

  void _setupSocket() {
    final socketService = Provider.of<SocketService>(context, listen: false);
    
    socketService.onWaitingApproval = () {
      setState(() {
        _status = "Waiting for approval...";
      });
    };

    socketService.onConnected = (_) {
      setState(() {
        _status = "Connected! You have internet access.";
        _isConnectedToPeer = true;
        _isWaiting = false;
      });
    };
    
    socketService.onRejected = () {
      setState(() {
        _status = "Request rejected by donor.";
        _isWaiting = false;
      });
    };

    socketService.onError = (error) {
      setState(() {
        _status = error == "Invalid code" ? "Invalid code. Try again." : "Error: $error";
        _isWaiting = false;
      });
    };
    
    socketService.onDonorDisconnected = () {
      setState(() {
        _status = "Donor disconnected.";
        _isConnectedToPeer = false;
      });
    };

    socketService.onFileReceived = (filename, base64Data) async {
      try {
        final bytes = base64Decode(base64Data);
        final directory = await getApplicationDocumentsDirectory();
        final file = File('${directory.path}/$filename');
        await file.writeAsBytes(bytes);
        
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('Received file: $filename'),
              backgroundColor: Colors.green,
            ),
          );
        }
      } catch (e) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Error saving file: $e'), backgroundColor: Colors.red),
          );
        }
      }
    };
  }

  void _connectToDonor() async {
    final code = _codeController.text.trim().toUpperCase();
    if (code.isEmpty || code.length != 6) {
      setState(() {
        _status = "Please enter a valid 6-digit code.";
      });
      return;
    }

    setState(() {
      _status = "Connecting to server...";
      _isWaiting = true;
    });

    final socketService = Provider.of<SocketService>(context, listen: false);
    if (!socketService.isConnected) {
      await socketService.connect("ws://10.180.191.113:8000/ws");
    }
    
    socketService.joinAsReceiver(code);
  }

  @override
  void dispose() {
    _codeController.dispose();
    Provider.of<SocketService>(context, listen: false).disconnect();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Receive Internet'),
      ),
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(24.0),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              if (!_isConnectedToPeer) ...[
                TextField(
                  controller: _codeController,
                  textAlign: TextAlign.center,
                  maxLength: 6,
                  textCapitalization: TextCapitalization.characters,
                  style: const TextStyle(
                    fontSize: 32,
                    fontWeight: FontWeight.bold,
                    letterSpacing: 8,
                  ),
                  decoration: InputDecoration(
                    hintText: "ENTER CODE",
                    hintStyle: TextStyle(
                      color: Colors.grey[400],
                      letterSpacing: 2,
                    ),
                    counterText: "",
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(16),
                    ),
                  ),
                ),
                const SizedBox(height: 24),
                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton(
                    onPressed: _isWaiting ? null : _connectToDonor,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFF2196F3),
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.all(16),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                    ),
                    child: _isWaiting 
                        ? const CircularProgressIndicator(color: Colors.white)
                        : const Text('Connect', style: TextStyle(fontSize: 18)),
                  ),
                ),
              ],
              const SizedBox(height: 40),
              Text(
                _status,
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.w500,
                  color: _isConnectedToPeer 
                      ? Colors.green 
                      : (_status.contains("rejected") || _status.contains("Invalid")) 
                          ? Colors.red 
                          : Colors.black87,
                ),
              ),
              if (_isConnectedToPeer) ...[
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
                          SnackBar(content: Text('Sent ${result.files.single.name} to donor')),
                        );
                      }
                    },
                    icon: const Icon(Icons.attach_file),
                    label: const Padding(
                      padding: EdgeInsets.all(16.0),
                      child: Text('Send File', style: TextStyle(fontSize: 18)),
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
              ]
            ],
          ),
        ),
      ),
    );
  }
}
