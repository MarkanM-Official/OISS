import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'screens/home.dart';
import 'services/socket_service.dart';

void main() {
  runApp(
    MultiProvider(
      providers: [
        ChangeNotifierProvider(create: (_) => SocketService()),
      ],
      child: const OissApp(),
    ),
  );
}

class OissApp extends StatelessWidget {
  const OissApp({Key? key}) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'GCIS - Open Internet Sharing',
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: Colors.green),
        useMaterial3: true,
        fontFamily: 'Roboto', // Modern, clean default
      ),
      home: const HomeScreen(),
      debugShowCheckedModeBanner: false,
    );
  }
}
