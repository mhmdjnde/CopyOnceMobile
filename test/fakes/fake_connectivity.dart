import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:copy_once/models/clipboard_item.dart';
import 'package:copy_once/services/device_identity.dart';

/// Reports a fixed connection type so the Wi-Fi-only rule can be tested without
/// a real network.
class FakeConnectivity implements Connectivity {
  FakeConnectivity({required this.onWifi});

  bool onWifi;

  @override
  Future<List<ConnectivityResult>> checkConnectivity() async => [
    onWifi ? ConnectivityResult.wifi : ConnectivityResult.mobile,
  ];

  @override
  Stream<List<ConnectivityResult>> get onConnectivityChanged => Stream.value([
    onWifi ? ConnectivityResult.wifi : ConnectivityResult.mobile,
  ]);
}

/// Fixed device identity, so tests do not touch platform-secure storage.
class FakeDeviceIdentity implements DeviceIdentity {
  @override
  Future<String> installId() async => 'test-install-id';

  @override
  Future<String> deviceName() async => 'Test device';

  @override
  DevicePlatform get platform => DevicePlatform.android;
}
