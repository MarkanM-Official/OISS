import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:share_plus/share_plus.dart';
import 'package:url_launcher/url_launcher.dart';

import 'dart:convert';
import 'dart:io' show Platform, File;
import 'package:http/http.dart' as http;
import 'package:package_info_plus/package_info_plus.dart';
import 'package:open_filex/open_filex.dart';
import 'package:path_provider/path_provider.dart';
import 'package:flutter/foundation.dart' show kIsWeb;

import 'donor_setup.dart';

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
  double _downloadProgress = 0.0;
  bool _isDownloading = false;

  final List<Widget> _tabs = [
    const DonorSetupScreen(),
    const WifiListScreen(), // Replacing ReceiverScreen
    const DonorProfileScreen(), // New Dashboard
  ];

  @override
  void initState() {
    super.initState();
    _initGlobalSocket();
    if (!kIsWeb && Platform.isAndroid) {
      _checkForUpdates();
    }
  }

  Future<void> _checkForUpdates() async {
    try {
      final response = await http.get(Uri.parse('https://api.github.com/repos/MarkanM-Official/OISS/releases/latest'));
      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        final latestTag = data['tag_name'] as String; // e.g. "v1.0.123"
        final latestVersion = latestTag.replaceAll('v', '');
        
        final packageInfo = await PackageInfo.fromPlatform();
        final currentVersion = packageInfo.version; 

        if (_isNewer(latestVersion, currentVersion)) {
           _showUpdateDialog(latestVersion);
        }
      }
    } catch (e) {
      debugPrint("Update check failed: $e");
    }
  }

  bool _isNewer(String latest, String current) {
    List<int> l = latest.split('.').map((e) => int.tryParse(e) ?? 0).toList();
    List<int> c = current.split('.').map((e) => int.tryParse(e) ?? 0).toList();
    for (int i = 0; i < 3; i++) {
      int lv = i < l.length ? l[i] : 0;
      int cv = i < c.length ? c[i] : 0;
      if (lv > cv) return true;
      if (lv < cv) return false;
    }
    return false;
  }

  void _showUpdateDialog(String newVersion) {
    if (!mounted) return;
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => AlertDialog(
        title: const Text('Update Available'),
        content: Text('OISS version $newVersion is available! Please update to continue.'),
        actions: [
          ElevatedButton(
            onPressed: () {
              Navigator.pop(context);
              _downloadAndInstallUpdate();
            },
            child: const Text('Update Now'),
          )
        ],
      ),
    );
  }

  Future<void> _downloadAndInstallUpdate() async {
    if (!mounted) return;
    setState(() => _isDownloading = true);
    
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setDialogState) {
            return AlertDialog(
              title: const Text('Downloading Update'),
              content: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  LinearProgressIndicator(value: _downloadProgress > 0 ? _downloadProgress : null),
                  const SizedBox(height: 10),
                  Text('${(_downloadProgress * 100).toStringAsFixed(1)}% Completed'),
                ],
              ),
            );
          },
        );
      },
    );

    try {
      final url = 'https://github.com/MarkanM-Official/OISS/releases/latest/download/app-release.apk';
      final client = http.Client();
      final request = http.Request('GET', Uri.parse(url));
      final response = await client.send(request);
      
      final contentLength = response.contentLength ?? 1;
      int downloaded = 0;
      List<int> bytes = [];
      
      response.stream.listen(
        (List<int> newBytes) {
          bytes.addAll(newBytes);
          downloaded += newBytes.length;
          if (mounted) {
            setState(() {
              _downloadProgress = downloaded / contentLength;
            });
          }
        },
        onDone: () async {
          if (mounted) {
            Navigator.pop(context); // close progress dialog
            setState(() => _isDownloading = false);
          }
          final dir = await getExternalStorageDirectory();
          final file = File('${dir!.path}/oiss_update.apk');
          await file.writeAsBytes(bytes);
          await OpenFilex.open(file.path);
        },
        onError: (e) {
          if (mounted) {
            Navigator.pop(context);
            ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text("Error downloading: $e")));
            setState(() => _isDownloading = false);
          }
        },
        cancelOnError: true,
      );
    } catch (e) {
      if (mounted) {
        Navigator.pop(context);
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text("Error: $e")));
        setState(() => _isDownloading = false);
      }
    }
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
            DrawerHeader(
              decoration: const BoxDecoration(
                gradient: LinearGradient(
                  colors: [Color(0xFF312e81), Color(0xFF0f172a)],
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                ),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text('OISS', style: TextStyle(color: Colors.white, fontSize: 24, fontWeight: FontWeight.bold)),
                  const SizedBox(height: 8),
                  InkWell(
                    onTap: () {
                      final Uri url = Uri.parse('https://markanm.com');
                      launchUrl(url, mode: LaunchMode.externalApplication);
                    },
                    child: RichText(
                      text: const TextSpan(
                        text: 'Powered by ',
                        style: TextStyle(color: Colors.white70, fontSize: 14),
                        children: [
                          TextSpan(
                            text: 'MarkanM',
                            style: TextStyle(color: Colors.lightBlueAccent, fontSize: 14),
                          )
                        ],
                      ),
                    ),
                  ),
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
