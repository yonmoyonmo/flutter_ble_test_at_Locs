import 'package:flutter_ble_lib/flutter_ble_lib.dart';

class BleDeviceItem {
  String deviceName;
  Peripheral peripheral;
  int rssi;
  AdvertisementData advertisementData;
  BleDeviceItem(
      this.deviceName, this.rssi, this.peripheral, this.advertisementData);
}
