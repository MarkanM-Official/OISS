import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'donor.dart';

class DonorSetupScreen extends StatefulWidget {
  const DonorSetupScreen({super.key});

  @override
  State<DonorSetupScreen> createState() => _DonorSetupScreenState();
}

class _DonorSetupScreenState extends State<DonorSetupScreen> {
  bool _isLoading = true;
  String _wifiName = "";
  double _dataLimitMB = 0;
  double _maxUsers = 5;
  String _permanentUid = "";
  String _password = "";
  String _serverDuration = "All-Time";

  @override
  void initState() {
    super.initState();
    _loadConfig();
  }

  Future<void> _loadConfig() async {
    final prefs = await SharedPreferences.getInstance();
    setState(() {
      _wifiName = prefs.getString('wifi_name') ?? "My OISS Network";
      _password = prefs.getString('wifi_password') ?? "";
      _dataLimitMB = prefs.getDouble('data_limit_mb') ?? 0;
      _maxUsers = prefs.getDouble('max_users') ?? 5;
      _permanentUid = prefs.getString('permanent_uid') ?? "";
      _isLoading = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading) {
      return const Center(child: CircularProgressIndicator());
    }

    return Scaffold(
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(32.0),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Icon(Icons.wifi_tethering, size: 100, color: Colors.green),
              const SizedBox(height: 24),
              Text(
                _wifiName,
                style: const TextStyle(fontSize: 28, fontWeight: FontWeight.bold),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 8),
              Text(
                "UID: ${_permanentUid.isEmpty ? 'Not Set' : _permanentUid}",
                style: const TextStyle(fontSize: 16, color: Colors.grey),
              ),
              const SizedBox(height: 8),
              Text(
                "Security: ${_password.isEmpty ? 'Open' : 'WPA/WPA2 PSK'}",
                style: const TextStyle(fontSize: 16, color: Colors.grey),
              ),
              const SizedBox(height: 16),
              DropdownButton<String>(
                value: _serverDuration,
                dropdownColor: const Color(0xFF1E1E1E),
                style: const TextStyle(color: Colors.white, fontSize: 16),
                items: const [
                  DropdownMenuItem(value: "All-Time", child: Text("All-Time (Permanent)")),
                  DropdownMenuItem(value: "24-Hours", child: Text("24-Hours (One-time)")),
                  DropdownMenuItem(value: "1-Hour", child: Text("1-Hour")),
                ],
                onChanged: (val) {
                  if (val != null) setState(() => _serverDuration = val);
                },
              ),
              const SizedBox(height: 32),
              SizedBox(
                width: 200,
                height: 200,
                child: ElevatedButton(
                  style: ElevatedButton.styleFrom(
                    shape: const CircleBorder(),
                    backgroundColor: Colors.green,
                    foregroundColor: Colors.white,
                    elevation: 10,
                  ),
                  onPressed: () {
                    if (_permanentUid.isEmpty) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(content: Text("Please setup your profile first in the Profile tab.")),
                      );
                      return;
                    }
                    Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (_) => DonorScreen(
                          isPublic: false,
                          serverName: _wifiName,
                          maxUsers: _maxUsers.round(),
                          dataLimitMB: _dataLimitMB,
                          password: _password,
                          isTemp: _serverDuration != "All-Time",
                          uid: _permanentUid,
                        ),
                      ),
                    );
                  },
                  child: const Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(Icons.power_settings_new, size: 64),
                      SizedBox(height: 8),
                      Text("POWER ON", style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold)),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 32),
              const Text(
                "Tap to start broadcasting your virtual Wi-Fi.",
                textAlign: TextAlign.center,
                style: TextStyle(color: Colors.grey),
              )
            ],
          ),
        ),
      ),
    );
  }
}
