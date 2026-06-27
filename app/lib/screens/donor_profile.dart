import 'package:flutter/material.dart';

class DonorProfileScreen extends StatefulWidget {
  const DonorProfileScreen({Key? key}) : super(key: key);

  @override
  _DonorProfileScreenState createState() => _DonorProfileScreenState();
}

class _DonorProfileScreenState extends State<DonorProfileScreen> {
  @override
  Widget build(BuildContext context) {
    return const Center(
      child: Text(
        "Donor Dashboard / Profile",
        style: TextStyle(fontSize: 24, color: Colors.grey),
      ),
    );
  }
}
