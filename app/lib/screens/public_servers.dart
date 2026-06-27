import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:http/http.dart' as http;
import '../services/socket_service.dart';

class PublicServersScreen extends StatefulWidget {
  const PublicServersScreen({super.key});

  @override
  State<PublicServersScreen> createState() => _PublicServersScreenState();
}

class _PublicServersScreenState extends State<PublicServersScreen> {
  List<dynamic> _servers = [];
  bool _isLoading = true;
  String _error = "";
  
  bool _isConnected = false;
  String _status = "";

  @override
  void initState() {
    super.initState();
    _fetchServers();
  }

  Future<void> _fetchServers() async {
    setState(() {
      _isLoading = true;
      _error = "";
    });
    try {
      final response = await http.get(Uri.parse('https://oiss.onrender.com/api/servers'));
      if (response.statusCode == 200) {
        setState(() {
          _servers = jsonDecode(response.body);
          _isLoading = false;
        });
      } else {
        setState(() {
          _error = "Failed to load servers.";
          _isLoading = false;
        });
      }
    } catch (e) {
      setState(() {
        _error = "Error: $e";
        _isLoading = false;
      });
    }
  }

  void _connectToServer(String uid) async {
    final socketService = Provider.of<SocketService>(context, listen: false);
    await socketService.connect("wss://oiss.onrender.com/ws");

    if (socketService.isConnected) {
      // Actually, joining requires the 6 digit pairing code.
      // Since public servers use their UUID as their identifier in DB, but the websocket expects a 6-digit code.
      // Wait, let's just send the UID as the code for public servers.
      // Or we can modify joinAsReceiver to accept a UID.
      // Let's modify joinAsReceiver to send either a code or uid.
      socketService.joinAsReceiver(uid); 
      setState(() {
        _status = "Connecting to $uid...";
      });
    }

    socketService.onConnected = (_) {
      setState(() {
        _status = "Connected! Receiving internet.";
        _isConnected = true;
      });
      _showConnectedDialog();
    };
    
    socketService.onError = (err) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text("Error: $err")));
    };
  }

  void _showConnectedDialog() {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (_) => AlertDialog(
        title: const Text("Connected!"),
        content: const Text("You are now receiving internet securely from the OISS Public Network."),
        actions: [
          ElevatedButton(
            onPressed: () {
              Navigator.pop(context);
              // In a real app, we'd navigate to a dedicated connected state screen.
            },
            child: const Text("OK"),
          )
        ],
      )
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Available Public Servers'),
        actions: [
          IconButton(icon: const Icon(Icons.refresh), onPressed: _fetchServers)
        ],
      ),
      body: _isLoading 
        ? const Center(child: CircularProgressIndicator())
        : _error.isNotEmpty 
          ? Center(child: Text(_error, style: const TextStyle(color: Colors.red)))
          : _servers.isEmpty
            ? const Center(child: Text("No public servers available right now."))
            : ListView.builder(
                itemCount: _servers.length,
                itemBuilder: (context, index) {
                  final server = _servers[index];
                  return Card(
                    margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                    child: ListTile(
                      leading: const CircleAvatar(
                        backgroundColor: Colors.purple,
                        child: Icon(Icons.public, color: Colors.white),
                      ),
                      title: Text(server['name'], style: const TextStyle(fontWeight: FontWeight.bold)),
                      subtitle: Text("Limit: ${server['data_limit_mb'] == 0 ? 'Unlimited' : server['data_limit_mb'].toString() + ' MB'} | Users: ${server['current_connections']}/${server['max_users']}"),
                      trailing: ElevatedButton(
                        onPressed: () => _connectToServer(server['uid']),
                        child: const Text("Connect"),
                      ),
                    ),
                  );
                },
              ),
    );
  }
}
