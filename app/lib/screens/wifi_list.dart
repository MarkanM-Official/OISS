import 'package:flutter/material.dart';

class WifiListScreen extends StatefulWidget {
  const WifiListScreen({Key? key}) : super(key: key);

  @override
  _WifiListScreenState createState() => _WifiListScreenState();
}

class _WifiListScreenState extends State<WifiListScreen> {
  @override
  Widget build(BuildContext context) {
    return const Center(
      child: Text(
        "Virtual Wi-Fi List",
        style: TextStyle(fontSize: 24, color: Colors.grey),
      ),
    );
  }
}
