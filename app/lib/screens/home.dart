import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:share_plus/share_plus.dart';

import 'donor_setup.dart';
import 'receiver.dart';
import 'relay.dart';
import 'plugins.dart';
import '../services/socket_service.dart';

// Placeholders for new screens
import 'donor_profile.dart'; // We will create this
import 'wifi_list.dart'; // We will create this

class HomeScreen extends StatefulWidget {
  const HomeScreen({Key? key}) : super(key: key);

  @override
  _HomeScreenState createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  int _currentIndex = 1; // Default to Receive (Wi-Fi list)

  final List<Widget> _tabs = [
    const DonorSetupScreen(),
    const WifiListScreen(), // Replacing ReceiverScreen
    const DonorProfileScreen(), // New Dashboard
  ];

  @override
  void initState() {
    super.initState();
    _initGlobalSocket();
  }

  Future<void> _initGlobalSocket() async {
    final socketService = Provider.of<SocketService>(context, listen: false);
    if (!socketService.isConnected) {
      await socketService.connect("wss://oiss.onrender.com/ws");
    }
    
    socketService.onAdminNotification = (message) {
      if (mounted) {
        showDialog(
          context: context,
          builder: (context) => AlertDialog(
            title: const Row(
              children: [
                Icon(Icons.campaign, color: Colors.blue),
                SizedBox(width: 10),
                Text("Admin Broadcast"),
              ],
            ),
            content: Text(message),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context),
                child: const Text("OK"),
              ),
            ],
          ),
        );
      }
    };
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('OISS', style: TextStyle(fontWeight: FontWeight.bold, letterSpacing: 2)),
        centerTitle: true,
        actions: [
          IconButton(
            icon: const Icon(Icons.share),
            onPressed: () {
              Share.share(
                'Internet share karna ab aur bhi aasan aur secure hai! Download the OISS App (Open Internet Sharing System) now and join the community: https://github.com/MarkanM-Official/OISS',
              );
            },
            tooltip: 'Share App',
          ),
        ],
      ),
      drawer: Drawer(
        child: ListView(
          padding: EdgeInsets.zero,
          children: [
            const DrawerHeader(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  colors: [Color(0xFF312e81), Color(0xFF0f172a)],
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                ),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('OISS Advanced', style: TextStyle(color: Colors.white, fontSize: 24, fontWeight: FontWeight.bold)),
                  SizedBox(height: 8),
                  Text('Open Source | Privacy First', style: TextStyle(color: Colors.grey, fontSize: 14)),
                ],
              ),
            ),
            ListTile(
              leading: const Icon(Icons.router, color: Colors.purple),
              title: const Text('Run as Relay Node'),
              onTap: () {
                Navigator.pop(context); // Close drawer
                Navigator.push(context, MaterialPageRoute(builder: (context) => const RelayScreen()));
              },
            ),
            ListTile(
              leading: const Icon(Icons.extension, color: Colors.orange),
              title: const Text('Plugins & SDK'),
              onTap: () {
                Navigator.pop(context);
                Navigator.push(context, MaterialPageRoute(builder: (context) => const PluginsScreen()));
              },
            ),
            const Divider(),
            ListTile(
              leading: const Icon(Icons.computer, color: Colors.blue),
              title: const Text('Device Connection (Advanced)'),
              subtitle: const Text('Remote Disk & File Control'),
              onTap: () {
                Navigator.pop(context);
                // We will navigate to advanced device connection screen here
                ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("Device Connection feature coming soon for PC builds.")));
              },
            ),
          ],
        ),
      ),
      body: _tabs[_currentIndex],
      bottomNavigationBar: BottomNavigationBar(
        currentIndex: _currentIndex,
        onTap: (index) {
          setState(() {
            _currentIndex = index;
          });
        },
        selectedItemColor: Colors.blueAccent,
        unselectedItemColor: Colors.grey,
        items: const [
          BottomNavigationBarItem(
            icon: Icon(Icons.wifi_tethering),
            label: 'Donate',
          ),
          BottomNavigationBarItem(
            icon: Icon(Icons.wifi),
            label: 'Receive',
          ),
          BottomNavigationBarItem(
            icon: Icon(Icons.dashboard),
            label: 'Profile',
          ),
        ],
      ),
    );
  }
}
