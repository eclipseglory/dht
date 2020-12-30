import 'dart:io';
import 'dart:typed_data';

class PeerValue {
  final InternetAddress address;
  final int port;
  List<int> _bytes;
  String _contactEncodingStr;
  PeerValue(this.address, this.port, [this._bytes]);

  /// Contact information for peers is encoded as a 6-byte string.
  /// Also known as "Compact IP-address/port info" the 4-byte IP address
  /// is in network byte order with the 2 byte port in network byte order
  /// concatenated onto the end.
  List<int> get bytes {
    if (_bytes == null) {
      _bytes = List<int>(6);
      var ip = address.address;
      var s = ip.split('.');
      for (var i = 0; i < 4; i++) {
        _bytes[i] = int.parse(s[i]);
      }
      var u16 = Uint16List(1);
      var v = ByteData.view(u16.buffer)..setUint16(0, port);
      _bytes[4] = v.getUint8(0);
      _bytes[5] = v.getUint8(1);
    }
    return _bytes;
  }

  String get ip => address.address;

  String toContactEncodingString() {
    _contactEncodingStr ??= String.fromCharCodes(bytes);
    return _contactEncodingStr;
  }

  @override
  String toString() {
    return 'Address[${ip}:${port}]';
  }

  static PeerValue parse(List<int> message, [int offset = 0]) {
    if (message.length - offset < 6) {
      throw 'Error bytes length, should be 6 bytes';
    }
    var ip = '';
    for (var i = 0; i < 4; i++) {
      ip += message[i + offset].toString();
      if (i != 3) {
        ip += '.';
      }
    }
    var v = ByteData.view(Uint8List.fromList(message).buffer, 4 + offset, 2);
    var port = v.getUint16(0);
    var bytes = List<int>(6);
    List.copyRange<int>(bytes, 0, message, offset, offset + 6);
    var address = InternetAddress.tryParse(ip);
    if (address != null) return PeerValue(address, port, bytes);
    return null;
  }
}
