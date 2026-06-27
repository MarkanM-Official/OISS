import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:device_info_plus/device_info_plus.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:url_launcher/url_launcher.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:open_filex/open_filex.dart';
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'dart:io' show Platform, File;

import '../main.dart'; // To navigate to home screen
import 'home.dart';

class LoginScreen extends StatefulWidget {
  const LoginScreen({Key? key}) : super(key: key);

  @override
  _LoginScreenState createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  bool _isLoading = false;
  double _downloadProgress = 0.0;
  final TextEditingController _tokenController = TextEditingController();
  
  // Replace this with your actual Render backend URL
  final String _backendUrl = "https://oiss.onrender.com"; 

  @override
  void initState() {
    super.initState();
    _checkSavedToken();
    if (!kIsWeb && Platform.isAndroid) {
      _checkForUpdates();
    }
  }

  Future<void> _checkSavedToken() async {
    final prefs = await SharedPreferences.getInstance();
    final token = prefs.getString('auth_token');
    if (token != null && token.isNotEmpty) {
      _tokenController.text = token;
      _verifyTokenWithBackend();
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
    setState(() => _isLoading = true);
    
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
          setState(() {
            _downloadProgress = downloaded / contentLength;
          });
          // To update the dialog specifically, but setState on main screen will also rebuild if mounted correctly.
        },
        onDone: () async {
          Navigator.pop(context); // close progress dialog
          final dir = await getExternalStorageDirectory();
          final file = File('${dir!.path}/oiss_update.apk');
          await file.writeAsBytes(bytes);
          await OpenFilex.open(file.path);
          setState(() => _isLoading = false);
        },
        onError: (e) {
          Navigator.pop(context);
          _showError("Error downloading: $e");
          setState(() => _isLoading = false);
        },
        cancelOnError: true,
      );
    } catch (e) {
      Navigator.pop(context);
      _showError("Error: $e");
      setState(() => _isLoading = false);
    }
  }

  Future<void> _openWebLogin() async {
    final Uri url = Uri.parse('$_backendUrl/app/login');
    if (!await launchUrl(url, mode: LaunchMode.externalApplication)) {
      _showError("Could not launch browser. Please open $_backendUrl/app/login manually.");
    }
  }

  Future<void> _verifyTokenWithBackend() async {
    final String idToken = _tokenController.text.trim();
    if (idToken.isEmpty) {
      _showError("Please paste the token first.");
      return;
    }

    setState(() {
      _isLoading = true;
    });

    try {
      final deviceInfo = DeviceInfoPlugin();
      String deviceName = "Unknown Device";
      
      if (kIsWeb) {
        final webInfo = await deviceInfo.webBrowserInfo;
        deviceName = webInfo.userAgent ?? "Web Browser";
      } else if (Platform.isAndroid) {
        final androidInfo = await deviceInfo.androidInfo;
        deviceName = "${androidInfo.brand} ${androidInfo.model}";
      } else if (Platform.isIOS) {
        final iosInfo = await deviceInfo.iosInfo;
        deviceName = "${iosInfo.name} ${iosInfo.model}";
      } else if (Platform.isWindows) {
        final windowsInfo = await deviceInfo.windowsInfo;
        deviceName = windowsInfo.computerName;
      } else if (Platform.isMacOS) {
        final macInfo = await deviceInfo.macOsInfo;
        deviceName = macInfo.computerName;
      } else if (Platform.isLinux) {
        final linuxInfo = await deviceInfo.linuxInfo;
        deviceName = linuxInfo.prettyName;
      }

      final response = await http.post(
        Uri.parse('$_backendUrl/api/auth/verify_token'),
        headers: {'Content-Type': 'application/json'},
        body: json.encode({
          'id_token': idToken,
          'mac_address': 'managed-by-backend-ip',
          'device_name': deviceName
        }),
      );

      if (response.statusCode == 200) {
        // Save the token for future auto-login
        final prefs = await SharedPreferences.getInstance();
        await prefs.setString('auth_token', idToken);
        
        // Verification successful, navigate to Home
        if (mounted) {
          Navigator.of(context).pushReplacement(
            MaterialPageRoute(builder: (context) => const HomeScreen()),
          );
        }
      } else if (response.statusCode == 401) {
        final prefs = await SharedPreferences.getInstance();
        await prefs.remove('auth_token');
        if (mounted) {
          setState(() {
            _isLoading = false;
            _tokenController.clear();
          });
          _showError("Token Expired. Please get a new token via Web.");
        }
      } else {
        _showError("Backend Verification Failed: ${response.statusCode}");
      }
    } catch (e) {
      _showError("Network Error: $e");
    } finally {
      setState(() {
        _isLoading = false;
      });
    }
  }

  void _showError(String message) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(message),
      backgroundColor: Colors.red,
    ));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      body: Center(
        child: Container(
          padding: const EdgeInsets.all(40),
          decoration: BoxDecoration(
            color: const Color(0xFF1E1E1E),
            borderRadius: BorderRadius.circular(20),
            boxShadow: [
              BoxShadow(
                color: Colors.blueAccent.withOpacity(0.2),
                blurRadius: 30,
                spreadRadius: 5,
              )
            ]
          ),
          width: 400,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Image.asset('assets/icon.png', height: 100),
              const SizedBox(height: 30),
              const Text(
                "Welcome to OISS",
                style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold, color: Colors.white),
              ),
              const SizedBox(height: 10),
              const Text(
                "Sign in securely to access the network.",
                textAlign: TextAlign.center,
                style: TextStyle(color: Colors.grey, fontSize: 14),
              ),
              const SizedBox(height: 40),
              
              ElevatedButton.icon(
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.white,
                  foregroundColor: Colors.black,
                  padding: const EdgeInsets.symmetric(horizontal: 30, vertical: 15),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(10),
                  ),
                ),
                icon: Image.network(
                  'https://upload.wikimedia.org/wikipedia/commons/c/c1/Google_%22G%22_logo.svg',
                  height: 24,
                ),
                label: const Text(
                  "Get Login Token via Web",
                  style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                ),
                onPressed: _openWebLogin,
              ),
              const SizedBox(height: 20),
              TextField(
                controller: _tokenController,
                style: const TextStyle(color: Colors.white),
                decoration: InputDecoration(
                  hintText: "Paste your Token here",
                  hintStyle: const TextStyle(color: Colors.grey),
                  filled: true,
                  fillColor: Colors.black54,
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(10),
                    borderSide: BorderSide.none,
                  ),
                ),
              ),
              const SizedBox(height: 20),
              _isLoading
                  ? const CircularProgressIndicator(color: Colors.blue)
                  : ElevatedButton(
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.blueAccent,
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(horizontal: 40, vertical: 15),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(10),
                        ),
                      ),
                      onPressed: _verifyTokenWithBackend,
                      child: const Text("Verify Token", style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
                    ),
            ],
          ),
        ),
      ),
    );
  }
}
