import 'package:flutter/material.dart';

class PluginsScreen extends StatelessWidget {
  const PluginsScreen({Key? key}) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Plugins & SDK'),
        backgroundColor: Colors.orange,
        foregroundColor: Colors.white,
      ),
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(24.0),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Icon(Icons.extension, size: 80, color: Colors.orange),
              const SizedBox(height: 24),
              const Text(
                'Coming Soon!',
                style: TextStyle(
                  fontSize: 32,
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(height: 16),
              const Text(
                'OISS is expanding beyond internet sharing. Soon you will be able to share compute power, install plugins, and build apps using the OISS Developer SDK.',
                textAlign: TextAlign.center,
                style: TextStyle(fontSize: 16, color: Colors.grey, height: 1.5),
              ),
              const SizedBox(height: 40),
              Card(
                elevation: 4,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                child: const ListTile(
                  leading: Icon(Icons.memory, color: Colors.blue, size: 40),
                  title: Text("Compute Sharing", style: TextStyle(fontWeight: FontWeight.bold)),
                  subtitle: Text("Donate CPU/GPU resources"),
                  trailing: Icon(Icons.lock_clock),
                ),
              ),
              const SizedBox(height: 16),
              Card(
                elevation: 4,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                child: const ListTile(
                  leading: Icon(Icons.store, color: Colors.green, size: 40),
                  title: Text("Plugin Marketplace", style: TextStyle(fontWeight: FontWeight.bold)),
                  subtitle: Text("Install community extensions"),
                  trailing: Icon(Icons.lock_clock),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
