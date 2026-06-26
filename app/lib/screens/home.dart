import 'package:flutter/material.dart';
import 'donor.dart';
import 'donor_settings.dart';
import 'receiver.dart';
import 'relay.dart';
import 'plugins.dart';

import 'package:share_plus/share_plus.dart';

class HomeScreen extends StatelessWidget {
  const HomeScreen({Key? key}) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('OISS'),
        actions: [
          IconButton(
            icon: const Icon(Icons.share),
            onPressed: () {
              Share.share(
                'Internet share karna ab aur bhi aasan aur secure hai! Download the OISS App (Open Internet Sharing System) now and join the community: https://github.com/GCIS-Project/OISS',
              );
            },
            tooltip: 'Share App',
          ),
        ],
      ),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(24.0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const SizedBox(height: 40),
              const Text(
                'GCIS',
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 48,
                  fontWeight: FontWeight.bold,
                  letterSpacing: 2,
                ),
              ),
              const SizedBox(height: 16),
              const Text(
                'Share internet. Help someone.',
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 18,
                  color: Colors.grey,
                ),
              ),
              const Spacer(),
              ElevatedButton.icon(
                onPressed: () {
                  Navigator.push(
                    context,
                    MaterialPageRoute(builder: (context) => const DonorSettingsScreen()),
                  );
                },
                icon: const Icon(Icons.wifi_tethering, size: 32),
                label: const Padding(
                  padding: EdgeInsets.all(20.0),
                  child: Text('Donate Internet', style: TextStyle(fontSize: 20)),
                ),
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFF4CAF50),
                  foregroundColor: Colors.white,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(16),
                  ),
                ),
              ),
              const SizedBox(height: 24),
              ElevatedButton.icon(
                onPressed: () {
                  Navigator.push(
                    context,
                    MaterialPageRoute(builder: (context) => const ReceiverScreen()),
                  );
                },
                icon: const Icon(Icons.wifi, size: 32),
                label: const Padding(
                  padding: EdgeInsets.all(20.0),
                  child: Text('Receive Internet', style: TextStyle(fontSize: 20)),
                ),
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFF2196F3),
                  foregroundColor: Colors.white,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(16),
                  ),
                ),
              ),
              const SizedBox(height: 24),
              ElevatedButton.icon(
                onPressed: () {
                  Navigator.push(
                    context,
                    MaterialPageRoute(builder: (context) => const RelayScreen()),
                  );
                },
                icon: const Icon(Icons.router, size: 32),
                label: const Padding(
                  padding: EdgeInsets.all(20.0),
                  child: Text('Run as Relay Node', style: TextStyle(fontSize: 20)),
                ),
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.purple,
                  foregroundColor: Colors.white,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(16),
                  ),
                ),
              ),
              const SizedBox(height: 24),
              ElevatedButton.icon(
                onPressed: () {
                  Navigator.push(
                    context,
                    MaterialPageRoute(builder: (context) => const PluginsScreen()),
                  );
                },
                icon: const Icon(Icons.extension, size: 32),
                label: const Padding(
                  padding: EdgeInsets.all(20.0),
                  child: Text('Plugins & SDK', style: TextStyle(fontSize: 20)),
                ),
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.orange,
                  foregroundColor: Colors.white,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(16),
                  ),
                ),
              ),
              const Spacer(),
              const Text(
                'Open Source | Privacy First',
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w500,
                  color: Colors.grey,
                ),
              ),
              const SizedBox(height: 20),
            ],
          ),
        ),
      ),
    );
  }
}
