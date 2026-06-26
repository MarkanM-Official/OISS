import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'donor_setup.dart';

class DonorSettingsScreen extends StatefulWidget {
  const DonorSettingsScreen({Key? key}) : super(key: key);

  @override
  State<DonorSettingsScreen> createState() => _DonorSettingsScreenState();
}

class _DonorSettingsScreenState extends State<DonorSettingsScreen> {
  String _speedLimit = "2 Mbps";
  bool _enableDataLimit = false;
  final TextEditingController _dataLimitController = TextEditingController();
  double _maxUsers = 1;
  String _sessionTimer = "No limit";

  final List<String> _speedOptions = ["1 Mbps", "2 Mbps", "5 Mbps", "10 Mbps", "No Limit"];
  final List<String> _timerOptions = ["30 minutes", "1 hour", "2 hours", "4 hours", "No limit"];

  @override
  void initState() {
    super.initState();
    _loadSettings();
  }

  Future<void> _loadSettings() async {
    final prefs = await SharedPreferences.getInstance();
    setState(() {
      _speedLimit = prefs.getString('speedLimit') ?? "2 Mbps";
      _enableDataLimit = prefs.getBool('enableDataLimit') ?? false;
      _dataLimitController.text = prefs.getString('dataLimitMB') ?? "";
      _maxUsers = prefs.getDouble('maxUsers') ?? 1;
      _sessionTimer = prefs.getString('sessionTimer') ?? "No limit";
    });
  }

  Future<void> _saveSettings() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('speedLimit', _speedLimit);
    await prefs.setBool('enableDataLimit', _enableDataLimit);
    await prefs.setString('dataLimitMB', _dataLimitController.text);
    await prefs.setDouble('maxUsers', _maxUsers);
    await prefs.setString('sessionTimer', _sessionTimer);
  }

  @override
  void dispose() {
    _dataLimitController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text("Sharing Settings")),
      body: ListView(
        padding: const EdgeInsets.all(24.0),
        children: [
          const Text("Max Speed for Receiver", style: TextStyle(fontWeight: FontWeight.bold)),
          DropdownButton<String>(
            value: _speedLimit,
            isExpanded: true,
            items: _speedOptions.map((String value) {
              return DropdownMenuItem<String>(
                value: value,
                child: Text(value),
              );
            }).toList(),
            onChanged: (val) {
              setState(() {
                _speedLimit = val!;
              });
            },
          ),
          const SizedBox(height: 24),

          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Text("Enable Daily Data Limit", style: TextStyle(fontWeight: FontWeight.bold)),
              Switch(
                value: _enableDataLimit,
                onChanged: (val) {
                  setState(() {
                    _enableDataLimit = val;
                  });
                },
              ),
            ],
          ),
          if (_enableDataLimit)
            TextField(
              controller: _dataLimitController,
              keyboardType: TextInputType.number,
              decoration: const InputDecoration(
                hintText: "Enter limit in MB",
                border: OutlineInputBorder(),
              ),
            ),
          const SizedBox(height: 24),

          const Text("Max Users Allowed", style: TextStyle(fontWeight: FontWeight.bold)),
          Slider(
            value: _maxUsers,
            min: 1,
            max: 5,
            divisions: 4,
            label: _maxUsers.round().toString(),
            onChanged: (val) {
              setState(() {
                _maxUsers = val;
              });
            },
          ),
          Text("${_maxUsers.round()} users", textAlign: TextAlign.center),
          const SizedBox(height: 24),

          const Text("Auto-stop after", style: TextStyle(fontWeight: FontWeight.bold)),
          DropdownButton<String>(
            value: _sessionTimer,
            isExpanded: true,
            items: _timerOptions.map((String value) {
              return DropdownMenuItem<String>(
                value: value,
                child: Text(value),
              );
            }).toList(),
            onChanged: (val) {
              setState(() {
                _sessionTimer = val!;
              });
            },
          ),
          const SizedBox(height: 40),

          ElevatedButton(
            onPressed: () async {
              await _saveSettings();
              if (mounted) {
                Navigator.pushReplacement(
                  context,
                  MaterialPageRoute(builder: (context) => const DonorSetupScreen()),
                );
              }
            },
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.green,
              foregroundColor: Colors.white,
              padding: const EdgeInsets.symmetric(vertical: 16),
            ),
            child: const Text("Start Sharing", style: TextStyle(fontSize: 18)),
          ),
        ],
      ),
    );
  }
}
