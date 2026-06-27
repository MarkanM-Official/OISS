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
  
  String _deviceType = "unknown";
  
  String? _connectedPeer;
  String? get connectedPeer => _connectedPeer;
  
  // Speed tracking
  int _bytesReceivedSinceLastTick = 0;
  double _currentSpeedMBps = 0.0;
  Timer? _speedTimer;

  // Proxy state
  ServerSocket? _proxyServer;
  final Map<String, Socket> _proxyConnections = {};
  int _nextProxyConnId = 1;
  final Map<String, bool> _proxyConnectedStatus = {};
  
  // Donor proxy connections
  final Map<String, Socket> _donorProxyConnections = {};
  final Map<String, String> _donorConnToReceiver = {};
  final Map<String, List<Uint8List>> _donorPendingData = {};

  double get currentSpeedMBps => _currentSpeedMBps;

  
  // Callbacks
  Function(String receiverId)? onApprovalRequest;
  Function(String? peer)? onConnected;
  Function()? onDisconnected;
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
      await _channel!.ready;
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
        _connectedPeer = msg['peer'];
        onConnected?.call(msg['peer']); 
        break;
      case 'disconnected':
        _connectedPeer = null;
        onDisconnected?.call();
        break;
      case 'rejected':
        onRejected?.call();
        break;
      case 'donor_disconnected':
        _connectedPeer = null;
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
        String connId = msg['conn_id'].toString();
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
        String connId = msg['conn_id'].toString();
        Uint8List payload = base64Decode(msg['payload']);
        _bytesReceivedSinceLastTick += payload.length;
        if (_proxyConnections.containsKey(connId)) {
          _proxyConnections[connId]!.add(payload);
        } else if (_donorProxyConnections.containsKey(connId)) {
          _donorProxyConnections[connId]!.add(payload);
        } else if (_donorConnToReceiver.containsKey(connId)) {
          // Socket is still connecting, buffer the data!
          _donorPendingData.putIfAbsent(connId, () => []).add(payload);
        }
        break;
      case 'proxy_disconnect':
        String connId = msg['conn_id'].toString();
        if (_proxyConnections.containsKey(connId)) {
          _proxyConnections[connId]!.destroy();
          _proxyConnections.remove(connId);
        }
        if (_donorProxyConnections.containsKey(connId)) {
          _donorProxyConnections[connId]!.destroy();
          _donorProxyConnections.remove(connId);
        }
        _donorPendingData.remove(connId);
        break;
    }
  }

  void _handleProxyConnect(Map<String, dynamic> msg) {
    String connId = msg['conn_id'].toString();
    String target = msg['target'];
    String? initialData = msg['initial_data'];
    String? receiverId = msg['receiver_id'];
    
    if (receiverId != null) {
      _donorConnToReceiver[connId] = receiverId;
    }
    
    List<String> targetParts = target.split(':');
    if (targetParts.length == 2) {
      String host = targetParts[0];
      int port = int.tryParse(targetParts[1]) ?? 443;
      
      Socket.connect(host, port).then((Socket socket) {
        _donorProxyConnections[connId] = socket;
        
        _send({
          'type': 'proxy_connected',
          'conn_id': connId,
          'is_connect': msg['is_connect'] ?? false,
          if (receiverId != null) 'receiver_id': receiverId
        });
        
        if (initialData != null) {
          socket.add(base64Decode(initialData));
        }
        
        if (_donorPendingData.containsKey(connId)) {
          for (var p in _donorPendingData[connId]!) {
            socket.add(p);
          }
          _donorPendingData.remove(connId);
        }
        
        socket.listen((Uint8List data) {
          _send({
            'type': 'proxy_data',
            'conn_id': connId,
            'payload': base64Encode(data),
            if (receiverId != null) 'receiver_id': receiverId
          });
          _bytesReceivedSinceLastTick += data.length;
        }, onDone: () {
          _send({'type': 'proxy_disconnect', 'conn_id': connId, if (receiverId != null) 'receiver_id': receiverId});
          _donorProxyConnections.remove(connId);
          _donorConnToReceiver.remove(connId);
          _donorPendingData.remove(connId);
        }, onError: (e) {
          _send({'type': 'proxy_disconnect', 'conn_id': connId, if (receiverId != null) 'receiver_id': receiverId});
          _donorProxyConnections.remove(connId);
          _donorConnToReceiver.remove(connId);
          _donorPendingData.remove(connId);
        });
      }).catchError((e) {
        _send({'type': 'proxy_disconnect', 'conn_id': connId, if (receiverId != null) 'receiver_id': receiverId});
        _donorConnToReceiver.remove(connId);
        _donorPendingData.remove(connId);
      });
    }
  }

  Future<void> startLocalProxy() async {
    if (_proxyServer != null) return;
    try {
      _proxyServer = await ServerSocket.bind(InternetAddress.loopbackIPv4, 1081);
      
      String sessionPrefix = DateTime.now().millisecondsSinceEpoch.toString();
      
      _proxyServer!.listen((Socket clientSocket) {
        String connId = '${sessionPrefix}_${_nextProxyConnId++}';
        _proxyConnections[connId] = clientSocket;
        _proxyConnectedStatus[connId] = false;
        
        int state = 0; // 0: wait greeting, 1: wait connect, 2: forwarding
        List<int> buffer = [];
        
        clientSocket.listen((Uint8List data) {
          if (state == 2) {
            _send({
              'type': 'proxy_data',
              'conn_id': connId,
              'payload': base64Encode(data)
            });
            _bytesReceivedSinceLastTick += data.length;
            return;
          }
          
          buffer.addAll(data);
          
          while (buffer.isNotEmpty && state != 2) {
            if (state == 0) {
              if (buffer.length >= 2) {
                int numMethods = buffer[1];
                if (buffer.length >= 2 + numMethods) {
                  buffer.removeRange(0, 2 + numMethods);
                  clientSocket.add(Uint8List.fromList([0x05, 0x00]));
                  state = 1;
                } else {
                  break; // wait for more data
                }
              } else {
                break;
              }
            } else if (state == 1) {
              if (buffer.length >= 4) {
                int addrType = buffer[3];
                int offset = 4;
                String targetHost = "";
                
                if (addrType == 0x01) { // IPv4
                  if (buffer.length >= 4 + 4 + 2) {
                    targetHost = "${buffer[4]}.${buffer[5]}.${buffer[6]}.${buffer[7]}";
                    offset = 8;
                  } else { break; }
                } else if (addrType == 0x03) { // Domain
                  if (buffer.length >= 5) {
                    int len = buffer[4];
                    if (buffer.length >= 5 + len + 2) {
                      targetHost = String.fromCharCodes(buffer.sublist(5, 5 + len));
                      offset = 5 + len;
                    } else { break; }
                  } else { break; }
                } else if (addrType == 0x04) { // IPv6 (ignore for now)
                  if (buffer.length >= 4 + 16 + 2) {
                    targetHost = "ipv6-unsupported";
                    offset = 4 + 16;
                  } else { break; }
                } else {
                  clientSocket.destroy();
                  return;
                }
                
                int port = (buffer[offset] << 8) | buffer[offset + 1];
                offset += 2;
                
                buffer.removeRange(0, offset);
                
                _send({
                  'type': 'proxy_connect',
                  'conn_id': connId,
                  'target': '$targetHost:$port',
                  'is_connect': true
                });
                
                state = 2;
              } else {
                break;
              }
            }
          }
          
          if (state == 2 && buffer.isNotEmpty) {
            _send({
              'type': 'proxy_data',
              'conn_id': connId,
              'payload': base64Encode(buffer)
            });
            _bytesReceivedSinceLastTick += buffer.length;
            buffer.clear();
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
    _donorConnToReceiver.clear();
    _donorPendingData.clear();
  }

  void registerAsDonor(String code) {
    _send({'type': 'register_donor', 'code': code});
  }

  void registerAsDonorConfigured(Map<String, dynamic> config) {
    Map<String, dynamic> payload = {'type': 'register_donor'};
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

  void approveReceiver(String receiverId, [Map<String, bool>? permissions]) {
    _send({
      'type': 'approve',
      'receiver_id': receiverId,
      'permissions': permissions ?? {"internet": true, "files": false, "disk": false}
    });
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
    _channel = null;
    _connectedPeer = null;
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
