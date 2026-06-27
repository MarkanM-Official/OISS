import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'dart:math';
import 'dart:convert';
import 'package:flutter/services.dart';
import 'package:http/http.dart' as http;

class DonorProfileScreen extends StatefulWidget {
  const DonorProfileScreen({Key? key}) : super(key: key);

  @override
  _DonorProfileScreenState createState() => _DonorProfileScreenState();
}

class _DonorProfileScreenState extends State<DonorProfileScreen> {
  final TextEditingController _nameController = TextEditingController();
  final TextEditingController _passwordController = TextEditingController();
  
  double _dataLimitMB = 0;
  double _maxUsers = 5;
  String _permanentUid = "";
  
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _loadProfile();
  }

  Future<void> _loadProfile() async {
    final prefs = await SharedPreferences.getInstance();
    setState(() {
      _nameController.text = prefs.getString('wifi_name') ?? "My OISS Network";
      _passwordController.text = prefs.getString('wifi_password') ?? "";
      _dataLimitMB = (prefs.get('data_limit_mb') as num?)?.toDouble() ?? 0.0;
      _maxUsers = (prefs.get('max_users') as num?)?.toDouble() ?? 5.0;
      
      _permanentUid = prefs.getString('permanent_uid') ?? "";
      
      if (_permanentUid.isEmpty) {
        try {
          final response = await http.get(Uri.parse('https://oiss.onrender.com/api/generate_uid'));
          if (response.statusCode == 200) {
            _permanentUid = jsonDecode(response.body)['uid'];
          } else {
            _permanentUid = (100000000 + Random().nextInt(899999999)).toString(); // Fallback
          }
        } catch (e) {
          _permanentUid = (100000000 + Random().nextInt(899999999)).toString(); // Fallback
        }
        await prefs.setString('permanent_uid', _permanentUid);
      }
      
      _isLoading = false;
    });
  }

  Future<void> _saveProfile() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('wifi_name', _nameController.text);
    await prefs.setString('wifi_password', _passwordController.text);
    await prefs.setDouble('data_limit_mb', _dataLimitMB);
    await prefs.setDouble('max_users', _maxUsers);
    
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Profile Saved Successfully!'), backgroundColor: Colors.green),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading) {
      return const Center(child: CircularProgressIndicator());
    }
    
    return Scaffold(
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(24.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // UID Display
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: const Color(0xFF1E1E1E),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: Colors.blueAccent.withOpacity(0.5)),
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text("Permanent UID", style: TextStyle(color: Colors.grey, fontSize: 14)),
                      const SizedBox(height: 4),
                      Text(
                        _permanentUid,
                        style: const TextStyle(fontSize: 24, fontWeight: FontWeight.bold, letterSpacing: 2),
                      ),
                    ],
                  ),
                  IconButton(
                    icon: const Icon(Icons.copy, color: Colors.blueAccent),
                    onPressed: () {
                      Clipboard.setData(ClipboardData(text: _permanentUid));
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(content: Text('UID Copied!')),
                      );
                    },
                  ),
                ],
              ),
            ),
            const SizedBox(height: 32),
            
            const Text("Virtual Wi-Fi Configuration", style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold)),
            const SizedBox(height: 16),
            
            TextField(
              controller: _nameController,
              style: const TextStyle(color: Colors.white),
              decoration: const InputDecoration(
                labelText: "Network Name (SSID)",
                labelStyle: TextStyle(color: Colors.grey),
                border: OutlineInputBorder(),
                prefixIcon: Icon(Icons.wifi),
              ),
            ),
            const SizedBox(height: 16),
            
            TextField(
              controller: _passwordController,
              obscureText: true,
              style: const TextStyle(color: Colors.white),
              decoration: const InputDecoration(
                labelText: "Password (leave empty for open)",
                labelStyle: TextStyle(color: Colors.grey),
                border: OutlineInputBorder(),
                prefixIcon: Icon(Icons.lock),
              ),
            ),
            const SizedBox(height: 24),
            
            const Text("Connection Limits", style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold)),
            const SizedBox(height: 16),
            
            const Text("Max Allowed Users"),
            Slider(
              value: _maxUsers,
              min: 1,
              max: 20,
              divisions: 19,
              label: _maxUsers.round().toString(),
              activeColor: Colors.blueAccent,
              onChanged: (val) => setState(() => _maxUsers = val),
            ),
            
            const SizedBox(height: 16),
            const Text("Data Limit (MB) - 0 for unlimited"),
            Slider(
              value: _dataLimitMB,
              min: 0,
              max: 5000,
              divisions: 50,
              label: _dataLimitMB == 0 ? "Unlimited" : "${_dataLimitMB.round()} MB",
              activeColor: Colors.blueAccent,
              onChanged: (val) => setState(() => _dataLimitMB = val),
            ),
            
            const SizedBox(height: 40),
            
            SizedBox(
              width: double.infinity,
              height: 50,
              child: ElevatedButton.icon(
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.blueAccent,
                  foregroundColor: Colors.white,
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                ),
                icon: const Icon(Icons.save),
                label: const Text("Save Profile", style: TextStyle(fontSize: 18)),
                onPressed: _saveProfile,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
