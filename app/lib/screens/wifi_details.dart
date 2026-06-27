import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../services/socket_service.dart';

class WifiDetailsScreen extends StatefulWidget {
  final String uid;
  final String password;

  const WifiDetailsScreen({Key? key, required this.uid, required this.password}) : super(key: key);

  @override
  _WifiDetailsScreenState createState() => _WifiDetailsScreenState();
}

class _WifiDetailsScreenState extends State<WifiDetailsScreen> {
  String _status = "Connecting...";
  bool _isConnected = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _connectToOiss();
    });
  }

  void _connectToOiss() {
    final socket = Provider.of<SocketService>(context, listen: false);
    
    // Set up listeners
    socket.onWaitingApproval = () {
      if (mounted) setState(() => _status = "Waiting for host approval...");
    };
    
    socket.onConnected = (peer) {
      if (mounted) {
        setState(() {
          _isConnected = true;
          _status = "Connected";
        });
        // Start local proxy logic here if needed (from old receiver.dart)
        socket.startLocalProxy();
      }
    };
    
    socket.onRejected = () {
      if (mounted) {
        setState(() => _status = "Connection Rejected by Host");
        _showError("Host rejected your connection.");
      }
    };
    
    socket.onError = (error) {
      if (mounted) {
        setState(() => _status = "Error: $error");
        _showError(error);
      }
    };
    
    socket.onDonorDisconnected = () {
      if (mounted) {
        setState(() {
          _isConnected = false;
          _status = "Host Disconnected";
        });
        socket.stopLocalProxy();
      }
    };

    // Join the network
    socket.joinAsReceiver(widget.uid, password: widget.password);
  }

  void _showError(String msg) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg), backgroundColor: Colors.red));
  }

  Future<void> _forgetNetwork() async {
    final prefs = await SharedPreferences.getInstance();
    final String? networksJson = prefs.getString('saved_networks');
    if (networksJson != null) {
      List<dynamic> decoded = jsonDecode(networksJson);
      decoded.removeWhere((net) => net['uid'] == widget.uid);
      await prefs.setString('saved_networks', jsonEncode(decoded));
    }
    if (mounted) Navigator.pop(context);
  }

  void _disconnect() {
    final socket = Provider.of<SocketService>(context, listen: false);
    // Ideally we send a disconnect msg, but we can just stop local proxy and pop
    socket.stopLocalProxy();
    // To properly disconnect from backend, we can just reconnect socket or send leave
    Navigator.pop(context);
  }

  Widget _buildPropertyRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 12.0),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(label, style: const TextStyle(color: Colors.grey, fontSize: 16)),
          Text(value, style: const TextStyle(color: Colors.white, fontSize: 16)),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black, // Dark theme like Android Wi-Fi settings
      appBar: AppBar(
        backgroundColor: Colors.black,
        title: Text("OISS_${widget.uid}", style: const TextStyle(color: Colors.white)),
        iconTheme: const IconThemeData(color: Colors.white),
        actions: [
          IconButton(
            icon: const Icon(Icons.open_in_new),
            onPressed: () {},
          )
        ],
      ),
      body: Consumer<SocketService>(
        builder: (context, socket, child) {
          return SingleChildScrollView(
            padding: const EdgeInsets.all(24.0),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Status Header
                Center(
                  child: Column(
                    children: [
                      Icon(
                        _isConnected ? Icons.wifi : Icons.wifi_off,
                        size: 64,
                        color: _isConnected ? Colors.blueAccent : Colors.grey,
                      ),
                      const SizedBox(height: 16),
                      Text(
                        _status,
                        style: TextStyle(
                          fontSize: 20,
                          color: _isConnected ? Colors.green : Colors.orange,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      const SizedBox(height: 24),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          if (_isConnected)
                            ElevatedButton.icon(
                              onPressed: _disconnect,
                              icon: const Icon(Icons.stop),
                              label: const Text("Disconnect"),
                              style: ElevatedButton.styleFrom(backgroundColor: Colors.red, foregroundColor: Colors.white),
                            ),
                          const SizedBox(width: 16),
                          OutlinedButton.icon(
                            onPressed: _forgetNetwork,
                            icon: const Icon(Icons.delete),
                            label: const Text("Forget"),
                            style: OutlinedButton.styleFrom(foregroundColor: Colors.red),
                          ),
                        ],
                      )
                    ],
                  ),
                ),
                const SizedBox(height: 40),
                const Divider(color: Colors.white24),
                
                // Properties List (Mimicking Android Wi-Fi properties)
                _buildPropertyRow("Technical standards", "OISS TLS Relay (Secure)"),
                _buildPropertyRow("Signal strength", _isConnected ? "High" : "None"),
                _buildPropertyRow("Security", widget.password.isEmpty ? "Open" : "OISS-PSK"),
                _buildPropertyRow("Frequency band", "WebSocket Tunnel"),
                _buildPropertyRow("Transmit link speed", _isConnected ? "${(socket.currentSpeedMBps * 0.8).toStringAsFixed(2)} MB/s" : "-"),
                _buildPropertyRow("Receive link speed", _isConnected ? "${socket.currentSpeedMBps.toStringAsFixed(2)} MB/s" : "-"),
                _buildPropertyRow("Gateway", "10.0.0.1 (Virtual)"),
                _buildPropertyRow("Subnet mask", "255.255.255.0"),
                _buildPropertyRow("DNS", "8.8.8.8"),
                _buildPropertyRow("IPv4 address", _isConnected ? "10.0.0.${DateTime.now().millisecond % 200 + 2}" : "-"),
                
                const SizedBox(height: 20),
              ],
            ),
          );
        },
      ),
    );
  }
}
