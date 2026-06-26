import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:web_socket_channel/web_socket_channel.dart';

class SocketService extends ChangeNotifier {
  WebSocketChannel? _channel;
  bool _isConnected = false;
  
  // Callbacks
  Function(String receiverId)? onApprovalRequest;
  Function(String? peer)? onConnected;
  Function()? onRejected;
  Function()? onDonorDisconnected;
  Function(String payload)? onDataReceived;
  Function(String filename, String base64Data)? onFileReceived;
  Function(String error)? onError;
  Function()? onWaitingApproval;
  
  bool get isConnected => _isConnected;

  Future<void> connect(String serverUrl) async {
    try {
      _channel = WebSocketChannel.connect(Uri.parse(serverUrl));
      _isConnected = true;
      notifyListeners();
      
      _channel!.stream.listen(
        (data) {
          final msg = jsonDecode(data);
          _handleMessage(msg);
        },
        onDone: () {
          _isConnected = false;
          notifyListeners();
        },
        onError: (error) {
          _isConnected = false;
          onError?.call(error.toString());
          notifyListeners();
        },
      );
    } catch (e) {
      _isConnected = false;
      onError?.call(e.toString());
      notifyListeners();
    }
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
        onDataReceived?.call(msg['payload']);
        break;
      case 'file_transfer':
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
    }
  }

  void registerAsDonor(String code) {
    _send({'type': 'register_donor', 'code': code});
  }

  void registerAsDonorConfigured(String code, bool isPublic, String name, int maxUsers, double dataLimitMB) {
    _send({
      'type': 'register_donor',
      'code': code,
      'is_public': isPublic,
      'name': name,
      'max_users': maxUsers,
      'data_limit_mb': dataLimitMB
    });
  }

  void joinAsReceiver(String code) {
    _send({'type': 'join', 'code': code});
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
    notifyListeners();
  }
}
