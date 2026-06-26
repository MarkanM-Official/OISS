import 'package:flutter/material.dart';
import 'donor.dart';

class DonorSetupScreen extends StatefulWidget {
  const DonorSetupScreen({super.key});

  @override
  State<DonorSetupScreen> createState() => _DonorSetupScreenState();
}

class _DonorSetupScreenState extends State<DonorSetupScreen> {
  bool isPublic = false;
  double dataLimitMB = 0; // 0 means unlimited
  double maxUsers = 5;
  TextEditingController nameController = TextEditingController(text: "Anonymous OISS Node");

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Setup Your Server')),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(24.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text("Server Details", style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold)),
            const SizedBox(height: 16),
            TextField(
              controller: nameController,
              decoration: const InputDecoration(
                labelText: "Server Name",
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 24),
            SwitchListTile(
              title: const Text("Public Server"),
              subtitle: const Text("List my server in the global directory so anyone can connect."),
              value: isPublic,
              onChanged: (val) => setState(() => isPublic = val),
            ),
            const SizedBox(height: 24),
            const Text("Max Allowed Users"),
            Slider(
              value: maxUsers,
              min: 1,
              max: 100,
              divisions: 99,
              label: maxUsers.round().toString(),
              onChanged: (val) => setState(() => maxUsers = val),
            ),
            const SizedBox(height: 24),
            const Text("Data Limit (MB) - 0 for unlimited"),
            Slider(
              value: dataLimitMB,
              min: 0,
              max: 5000,
              divisions: 50,
              label: dataLimitMB == 0 ? "Unlimited" : "${dataLimitMB.round()} MB",
              onChanged: (val) => setState(() => dataLimitMB = val),
            ),
            const SizedBox(height: 40),
            SizedBox(
              width: double.infinity,
              height: 50,
              child: ElevatedButton(
                style: ElevatedButton.styleFrom(backgroundColor: Colors.green, foregroundColor: Colors.white),
                onPressed: () {
                  Navigator.pushReplacement(
                    context,
                    MaterialPageRoute(
                      builder: (_) => DonorScreen(
                        isPublic: isPublic,
                        serverName: nameController.text,
                        maxUsers: maxUsers.round(),
                        dataLimitMB: dataLimitMB,
                      ),
                    ),
                  );
                },
                child: const Text("Start Sharing", style: TextStyle(fontSize: 18)),
              ),
            )
          ],
        ),
      ),
    );
  }
}
