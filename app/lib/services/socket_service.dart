import 'dart:convert';
import 'dart:async';
import 'dart:io';
import 'dart:typed_data';
import 'package:flutter/services.dart';
import 'package:flutter/foundation.dart';
import 'package:web_socket_channel/web_socket_channel.dart';

class SocketService extends ChangeNotifier {
  WebSocketChannel? _channel;
  bool _isConnected = false;
  
  // Speed tracking
  int _bytesReceivedSinceLastTick = 0;
  double _currentSpeedMBps = 0.0;
  Timer? _speedTimer;

  // Proxy state
  ServerSocket? _proxyServer;
  final Map<int, Socket> _proxyConnections = {};
  int _nextProxyConnId = 1;
  final Map<int, bool> _proxyConnectedStatus = {};
  
  // Donor proxy connections
  final Map<int, Socket> _donorProxyConnections = {};

  double get currentSpeedMBps => _currentSpeedMBps;

  
  // Callbacks
  Function(String receiverId)? onApprovalRequest;
  Function(String? peer)? onConnected;
  Function()? onRejected;
  Function()? onDonorDisconnected;
  Function(String payload)? onDataReceived;
  Function(String filename, String base64Data)? onFileReceived;
  Function(String error)? onError;
  Function()? onWaitingApproval;
  Function(String message)? onAdminNotification;
  
  bool get isConnected => _isConnected;

  Future<void> connect(String serverUrl) async {
    if (_isConnected && _channel != null) return;
    
    try {
      _channel = WebSocketChannel.connect(Uri.parse(serverUrl));
      _isConnected = true;
      _startSpeedTimer();
      notifyListeners();
      
      _channel!.stream.listen(
        (data) {
          final msg = jsonDecode(data);
          _handleMessage(msg);
        },
        onDone: () {
          _isConnected = false;
          _stopSpeedTimer();
          notifyListeners();
        },
        onError: (error) {
          _isConnected = false;
          _stopSpeedTimer();
          onError?.call(error.toString());
          notifyListeners();
        },
      );
    } catch (e) {
      _isConnected = false;
      _stopSpeedTimer();
      onError?.call(e.toString());
      notifyListeners();
    }
  }

  void _startSpeedTimer() {
    _speedTimer?.cancel();
    _bytesReceivedSinceLastTick = 0;
    _currentSpeedMBps = 0.0;
    _speedTimer = Timer.periodic(const Duration(seconds: 1), (timer) {
      _currentSpeedMBps = _bytesReceivedSinceLastTick / (1024 * 1024);
      _bytesReceivedSinceLastTick = 0;
      notifyListeners();
    });
  }

  void _stopSpeedTimer() {
    _speedTimer?.cancel();
    _speedTimer = null;
    _currentSpeedMBps = 0.0;
  }

  void _handleMessage(Map<String, dynamic> msg) {
    final type = msg['type'];
    
    switch (type) {
      case 'approval_request':
        onApprovalRequest?.call(msg['receiver_id']);
        break;
      case 'waiting_approval':
        onWaitingApproval?.call();
        break;
      case 'connected':
        onConnected?.call(msg['peer']); 
        break;
      case 'rejected':
        onRejected?.call();
        break;
      case 'donor_disconnected':
        onDonorDisconnected?.call();
        break;
      case 'data':
        _bytesReceivedSinceLastTick += (msg['payload'] as String).length;
        onDataReceived?.call(msg['payload']);
        break;
      case 'file_transfer':
        _bytesReceivedSinceLastTick += (msg['payload'] as String).length;
        onFileReceived?.call(msg['filename'] ?? 'unknown_file', msg['payload']);
        break;
      case 'error':
        onError?.call(msg['message'] ?? 'Unknown error');
        break;
      case 'relay_forward':
        _send({
          'type': 'relay_forwarded',
          'target_id': msg['target_id'],
          'payload': msg['payload']
        });
        break;
      case 'admin_notification':
        onAdminNotification?.call(msg['message'] ?? 'Admin Notification');
        break;
      case 'proxy_connect':
        _handleProxyConnect(msg);
        break;
      case 'proxy_connected':
        int connId = msg['conn_id'];
        bool isConnect = msg['is_connect'] ?? false;
        if (_proxyConnections.containsKey(connId)) {
          _proxyConnectedStatus[connId] = true;
          if (isConnect) {
            _proxyConnections[connId]!.add(Uint8List.fromList([
              0x05, 0x00, 0x00, 0x01, 
              0x00, 0x00, 0x00, 0x00, 
              0x00, 0x00
            ]));
          }
        }
        break;
      case 'proxy_data':
        int connId = msg['conn_id'];
        Uint8List payload = base64Decode(msg['payload']);
        _bytesReceivedSinceLastTick += payload.length;
        if (_proxyConnections.containsKey(connId)) {
          _proxyConnections[connId]!.add(payload);
        } else if (_donorProxyConnections.containsKey(connId)) {
          _donorProxyConnections[connId]!.add(payload);
        }
        break;
      case 'proxy_disconnect':
        int connId = msg['conn_id'];
        if (_proxyConnections.containsKey(connId)) {
          _proxyConnections[connId]!.destroy();
          _proxyConnections.remove(connId);
        }
        if (_donorProxyConnections.containsKey(connId)) {
          _donorProxyConnections[connId]!.destroy();
          _donorProxyConnections.remove(connId);
        }
        break;
    }
  }

  void _handleProxyConnect(Map<String, dynamic> msg) {
    int connId = msg['conn_id'];
    String target = msg['target'];
    String? initialData = msg['initial_data'];
    
    List<String> targetParts = target.split(':');
    if (targetParts.length == 2) {
      String host = targetParts[0];
      int port = int.tryParse(targetParts[1]) ?? 443;
      
      Socket.connect(host, port).then((Socket socket) {
        _donorProxyConnections[connId] = socket;
        
        _send({
          'type': 'proxy_connected',
          'conn_id': connId,
          'is_connect': msg['is_connect'] ?? false
        });
        
        if (initialData != null) {
          socket.add(base64Decode(initialData));
        }
        
        socket.listen((Uint8List data) {
          _send({
            'type': 'proxy_data',
            'conn_id': connId,
            'payload': base64Encode(data)
          });
          _bytesReceivedSinceLastTick += data.length;
        }, onDone: () {
          _send({'type': 'proxy_disconnect', 'conn_id': connId});
          _donorProxyConnections.remove(connId);
        }, onError: (e) {
          _send({'type': 'proxy_disconnect', 'conn_id': connId});
          _donorProxyConnections.remove(connId);
        });
      }).catchError((e) {
        _send({'type': 'proxy_disconnect', 'conn_id': connId});
      });
    }
  }

  Future<void> startLocalProxy() async {
    if (_proxyServer != null) return;
    try {
      _proxyServer = await ServerSocket.bind(InternetAddress.loopbackIPv4, 1080);
      _proxyServer!.listen((Socket clientSocket) {
        int connId = _nextProxyConnId++;
        _proxyConnections[connId] = clientSocket;
        _proxyConnectedStatus[connId] = false;
        
        int state = 0; // 0: wait greeting, 1: wait connect, 2: forwarding
        
        clientSocket.listen((Uint8List data) {
          if (state == 0) {
            if (data.isNotEmpty && data[0] == 0x05) {
              clientSocket.add(Uint8List.fromList([0x05, 0x00]));
              state = 1;
            } else {
              clientSocket.destroy();
            }
          } else if (state == 1) {
            if (data.length > 4 && data[0] == 0x05 && data[1] == 0x01) {
              int addrType = data[3];
              String targetHost = "";
              int port = 0;
              int offset = 4;
              
              if (addrType == 0x01) {
                targetHost = "${data[4]}.${data[5]}.${data[6]}.${data[7]}";
                offset = 8;
              } else if (addrType == 0x03) {
                int len = data[4];
                targetHost = String.fromCharCodes(data.sublist(5, 5 + len));
                offset = 5 + len;
              } else if (addrType == 0x04) {
                clientSocket.destroy();
                return;
              }
              
              port = (data[offset] << 8) | data[offset + 1];
              
              _send({
                'type': 'proxy_connect',
                'conn_id': connId,
                'target': '$targetHost:$port',
                'is_connect': true
              });
              
              state = 2;
            } else {
              clientSocket.destroy();
            }
          } else {
            _send({
              'type': 'proxy_data',
              'conn_id': connId,
              'payload': base64Encode(data)
            });
            _bytesReceivedSinceLastTick += data.length;
          }
        }, onDone: () {
          _send({'type': 'proxy_disconnect', 'conn_id': connId});
          _proxyConnections.remove(connId);
        }, onError: (e) {
          _send({'type': 'proxy_disconnect', 'conn_id': connId});
          _proxyConnections.remove(connId);
        });
      });
    } catch (e) {
      print("Proxy Error: $e");
    }
  }

  void stopLocalProxy() {
    _proxyServer?.close();
    _proxyServer = null;
    for (var socket in _proxyConnections.values) {
      socket.destroy();
    }
    _proxyConnections.clear();
    for (var socket in _donorProxyConnections.values) {
      socket.destroy();
    }
    _donorProxyConnections.clear();
  }

  void registerAsDonor(String code) {
    _send({'type': 'register_donor', 'code': code});
  }

  void registerAsDonorConfigured(Map<String, dynamic> config) {
    var payload = {'type': 'register_donor'};
    payload.addAll(config);
    _send(payload);
  }

  void joinAsReceiver(String code, {String password = ""}) {
    _send({'type': 'join', 'code': code, 'password': password});
  }

  void registerAsRelay() {
    _send({'type': 'register_relay'});
  }

  void sendFile(String filename, String base64Data, {String? receiverId}) {
    final msg = {
      'type': 'file_transfer',
      'filename': filename,
      'payload': base64Data
    };
    if (receiverId != null) {
      msg['receiver_id'] = receiverId;
    }
    _send(msg);
  }

  void approveReceiver(String receiverId) {
    _send({'type': 'approve', 'receiver_id': receiverId});
  }

  void rejectReceiver(String receiverId) {
    _send({'type': 'reject', 'receiver_id': receiverId});
  }

  void sendData(String payload, {String? receiverId}) {
    final msg = {'type': 'data', 'payload': payload};
    if (receiverId != null) {
      msg['receiver_id'] = receiverId;
    }
    _send(msg);
  }

  void _send(Map<String, dynamic> data) {
    if (_isConnected && _channel != null) {
      _channel!.sink.add(jsonEncode(data));
    }
  }

  void disconnect() {
    _channel?.sink.close();
    _isConnected = false;
    _stopSpeedTimer();
    stopLocalProxy();
    
    // Attempt to stop the VPN if it's running
    try {
      const MethodChannel('com.oiss.vpn/control').invokeMethod('stopVpn');
    } catch (_) {}
    
    notifyListeners();
  }
}
