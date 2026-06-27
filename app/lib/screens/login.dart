import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:device_info_plus/device_info_plus.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:url_launcher/url_launcher.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'dart:io' show Platform;

import '../main.dart'; // To navigate to home screen
import 'home.dart';

class LoginScreen extends StatefulWidget {
  const LoginScreen({Key? key}) : super(key: key);

  @override
  _LoginScreenState createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  bool _isLoading = false;
  final TextEditingController _tokenController = TextEditingController();
  
  // Replace this with your actual Render backend URL
  final String _backendUrl = "https://oiss.onrender.com"; 

  @override
  void initState() {
    super.initState();
    _checkSavedToken();
  }

  Future<void> _checkSavedToken() async {
    final prefs = await SharedPreferences.getInstance();
    final token = prefs.getString('auth_token');
    if (token != null && token.isNotEmpty) {
      _tokenController.text = token;
      _verifyTokenWithBackend();
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
