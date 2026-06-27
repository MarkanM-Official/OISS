import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:http/http.dart' as http;
import 'wifi_details.dart';
import '../services/socket_service.dart';
import 'package:provider/provider.dart';

class WifiListScreen extends StatefulWidget {
  const WifiListScreen({Key? key}) : super(key: key);

  @override
  _WifiListScreenState createState() => _WifiListScreenState();
}

class _WifiListScreenState extends State<WifiListScreen> {
  List<Map<String, dynamic>> _savedNetworks = [];
  final TextEditingController _searchController = TextEditingController();
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _loadSavedNetworks();
  }

  Future<void> _loadSavedNetworks() async {
    final prefs = await SharedPreferences.getInstance();
    final String? networksJson = prefs.getString('saved_networks');
    if (networksJson != null) {
      final List<dynamic> decoded = jsonDecode(networksJson);
      setState(() {
        _savedNetworks = List<Map<String, dynamic>>.from(decoded);
      });
    }
    setState(() {
      _isLoading = false;
    });
  }

  Future<void> _saveNetworks() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('saved_networks', jsonEncode(_savedNetworks));
  }

  Future<void> _addNetworkFromSearch() async {
    final uid = _searchController.text.trim();
    if (uid.isEmpty) return;
    
    // Auto-prompt connect by pinging server
    try {
      final response = await http.get(Uri.parse('https://oiss.onrender.com/api/check_server/\$uid'));
      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        if (data['exists'] == true) {
          String networkName = data['name'];
          final index = _savedNetworks.indexWhere((net) => net['uid'] == uid);
          if (index == -1) {
            setState(() {
              _savedNetworks.add({
                'uid': uid,
                'name': networkName,
                'password': '',
                'last_connected': DateTime.now().toIso8601String(),
              });
            });
            _saveNetworks();
          }
          _searchController.clear();
          FocusScope.of(context).unfocus();
          _promptConnect(uid, networkName);
        } else {
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(content: Text('Server not found or currently offline!'), backgroundColor: Colors.red),
            );
          }
        }
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Network error connecting to OISS server.'), backgroundColor: Colors.orange),
        );
      }
    }
  }

  void _scanQR() {
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('QR Scanner not implemented in this build.')),
    );
  }

  void _promptConnect(String uid, String name) {
    String enteredPassword = "";
    
    // Find if we have saved password
    final existing = _savedNetworks.firstWhere((net) => net['uid'] == uid, orElse: () => {});
    if (existing.isNotEmpty && existing['password'] != "") {
      _connectToNetwork(uid, existing['password']);
      return;
    }

    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('Connect to $name'),
        content: TextField(
          obscureText: true,
          decoration: const InputDecoration(
            labelText: "Password (leave empty if open)",
            border: OutlineInputBorder(),
          ),
          onChanged: (val) => enteredPassword = val,
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () {
              Navigator.pop(context);
              // Save password for future
              final index = _savedNetworks.indexWhere((net) => net['uid'] == uid);
              if (index != -1) {
                _savedNetworks[index]['password'] = enteredPassword;
                _saveNetworks();
              }
              _connectToNetwork(uid, enteredPassword);
            },
            child: const Text('Connect'),
          )
        ],
      ),
    );
  }

  void _connectToNetwork(String uid, String password) {
    // We will navigate to details screen which handles connection
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => WifiDetailsScreen(uid: uid, password: password),
      ),
    ).then((_) => _loadSavedNetworks()); // Reload in case they forgot the network
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading) {
      return const Center(child: CircularProgressIndicator());
    }

    return Scaffold(
      body: SafeArea(
        child: Column(
          children: [
            // Quick Actions Row
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 8.0),
              child: Row(
                children: [
                  Expanded(
                    child: ElevatedButton.icon(
                      style: ElevatedButton.styleFrom(
                        backgroundColor: const Color(0xFF1E1E1E),
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(vertical: 12),
                      ),
                      icon: const Icon(Icons.qr_code_scanner, color: Colors.blueAccent),
                      label: const Text("Scan QR"),
                      onPressed: _scanQR,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: ElevatedButton.icon(
                      style: ElevatedButton.styleFrom(
                        backgroundColor: const Color(0xFF1E1E1E),
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(vertical: 12),
                      ),
                      icon: const Icon(Icons.keyboard, color: Colors.blueAccent),
                      label: const Text("Enter Code"),
                      onPressed: () {
                         FocusScope.of(context).requestFocus(FocusNode()); // dismiss if open
                      },
                    ),
                  ),
                ],
              ),
            ),
            
            // Search Bar
            Padding(
              padding: const EdgeInsets.all(16.0),
              child: TextField(
                controller: _searchController,
                style: const TextStyle(color: Colors.white),
                decoration: InputDecoration(
                  hintText: 'Search network by UID...',
                  hintStyle: const TextStyle(color: Colors.grey),
                  prefixIcon: const Icon(Icons.search, color: Colors.grey),
                  suffixIcon: IconButton(
                    icon: const Icon(Icons.add_circle, color: Colors.blueAccent),
                    onPressed: _addNetworkFromSearch,
                  ),
                  filled: true,
                  fillColor: const Color(0xFF1E1E1E),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                    borderSide: BorderSide.none,
                  ),
                ),
                onSubmitted: (_) => _addNetworkFromSearch(),
              ),
            ),
            
            // Network List
            Expanded(
              child: _savedNetworks.isEmpty
                  ? const Center(
                      child: Text(
                        "No saved networks.\nSearch a UID to add one.",
                        textAlign: TextAlign.center,
                        style: TextStyle(color: Colors.grey),
                      ),
                    )
                  : ListView.builder(
                      itemCount: _savedNetworks.length,
                      itemBuilder: (context, index) {
                        final net = _savedNetworks[index];
                        return ListTile(
                          leading: const CircleAvatar(
                            backgroundColor: Colors.blueAccent,
                            child: Icon(Icons.wifi, color: Colors.white),
                          ),
                          title: Text(net['name'] ?? 'Unknown Network', style: const TextStyle(fontWeight: FontWeight.bold)),
                          subtitle: Text("UID: ${net['uid']}"),
                          trailing: const Icon(Icons.lock, size: 16, color: Colors.grey),
                          onTap: () => _promptConnect(net['uid'], net['name']),
                        );
                      },
                    ),
            ),
          ],
        ),
      ),
    );
  }
}
