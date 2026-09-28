import 'package:flutter_test/flutter_test.dart';
import 'package:ai_connect_africa/collaboration/sync/sync_address.dart';
import 'package:ai_connect_africa/collaboration/sync/class_share_server.dart'
    show kDefaultSyncPort;

void main() {
  test('bare IPv4 uses the default sync port', () {
    expect(
      parseTeacherAddress(' 192.168.43.1 '),
      (address: '192.168.43.1', port: kDefaultSyncPort),
    );
  });

  test('explicit port and pasted URL forms', () {
    expect(
      parseTeacherAddress('10.0.0.5:9000'),
      (address: '10.0.0.5', port: 9000),
    );
    expect(
      parseTeacherAddress('http://10.0.0.5:8765/'),
      (address: '10.0.0.5', port: 8765),
    );
  });

  test('rejects things that are not addresses', () {
    expect(parseTeacherAddress(''), isNull);
    expect(parseTeacherAddress('999.1.1.1'), isNull);
    expect(parseTeacherAddress('10.0.0.5:0'), isNull);
    expect(parseTeacherAddress('10.0.0.5:abc'), isNull);
    expect(parseTeacherAddress('not an address'), isNull);
  });
}
