import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_ble_lib/flutter_ble_lib.dart';
import 'package:permission_handler/permission_handler.dart';
import 'BleDeviceItem.dart';

void main() {
  runApp(BLEtest());
}

class BLEtest extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: "flutter ble test",
      home: BLEbody(title: "flutter ble test"),
    );
  }
}

class BLEbody extends StatefulWidget {
  BLEbody({Key key, this.title}) : super(key: key);
  final String title;
  @override
  _BLEbodyState createState() => _BLEbodyState();
}

class _BLEbodyState extends State<BLEbody> {
  BleManager _bleManager = BleManager();
  bool _isScanning = false;
  bool _connected = false;
  List<BleDeviceItem> deviceList = [];
  Peripheral _curPeripheral;
  String _statusText = '';

  @override
  void initState() {
    init();
    super.initState();
  }

  void init() async {
    await _bleManager
        .createClient(
            restoreStateIdentifier: "testRSI",
            restoreStateAction: (peripheral) {
              peripheral?.forEach((peripheral) {
                print("Restored peripheral : ${peripheral.name}");
              });
            })
        .catchError((e) => print("Couldn't create BLE client  $e"))
        .then((_) => _checkPermissions()) //BLE 생성 후 퍼미션 체크
        .catchError((e) => print("Permission check error $e"));
  }

  _checkPermissions() async {
    if (Platform.isAndroid) {
      if (await Permission.contacts.request().isGranted) {}
      Map<Permission, PermissionStatus> statuses =
          await [Permission.location].request();
      print(statuses[Permission.location]);
    }
  }

  void scan() async {
    if (!_isScanning) {
      deviceList.clear();
      _bleManager.startPeripheralScan().listen((scanResult) {
        // 페리페럴 항목에 이름이 있으면 그걸 사용하고
        // 없다면 어드버타이지먼트 데이터의 이름을 사용하고 그것 마져 없다면 Unknown으로 표시
        var name = scanResult.peripheral.name ??
            scanResult.advertisementData.localName ??
            "Unknown";

        // 여러가지 정보 확인
        print("Scanned Name ${name}, RSSI ${scanResult.rssi}");
        print(
            "\tidentifier(mac) ${scanResult.peripheral.identifier}"); //mac address
        print("\tservice UUID : ${scanResult.advertisementData.serviceUuids}");
        print(
            "\tmanufacture Data : ${scanResult.advertisementData.manufacturerData}");
        print(
            "\tTx Power Level : ${scanResult.advertisementData.txPowerLevel}");
        print("\t${scanResult.peripheral}");

        //이미 검색된 장치인지 확인 mac 주소로 확인
        var findDevice = deviceList.any((element) {
          if (element.peripheral.identifier ==
              scanResult.peripheral.identifier) {
            //이미 존재하면 기존 값을 갱신.
            element.peripheral = scanResult.peripheral;
            element.advertisementData = scanResult.advertisementData;
            element.rssi = scanResult.rssi;
            return true;
          }
          return false;
        });
        //처음 발견된 장치라면 devicelist에 추가
        if (!findDevice) {
          deviceList.add(BleDeviceItem(name, scanResult.rssi,
              scanResult.peripheral, scanResult.advertisementData));
        }
        //갱신 적용.
        setState(() {});
      });
      //스캔중으로 변수 변경
      setState(() {
        _isScanning = true;
        setBLEState('Scanning');
      });
    } else {
      //스캔중이었다면 스캔 정지
      _bleManager.stopPeripheralScan();
      setState(() {
        _isScanning = false;
        setBLEState('Stop Scan');
      });
    }
  }

  _runWithErrorHandling(runFunction) async {
    try {
      await runFunction();
    } on BleError catch (e) {
      print("BleError caught: ${e.errorCode.value} ${e.reason}");
    } catch (e) {
      if (e is Error) {
        debugPrintStack(stackTrace: e.stackTrace);
      }
      print("${e.runtimeType}: $e");
    }
  }

  // 상태 변경하면서 페이지도 갱신하는 함수
  void setBLEState(txt) {
    setState(() => _statusText = txt);
  }

  connect(index) async {
    if (_connected) {
      //이미 연결상태면 연결 해제후 종료
      await _curPeripheral?.disconnectOrCancelConnection();
      return;
    }

    //선택한 장치의 peripheral 값을 가져온다.
    Peripheral peripheral = deviceList[index].peripheral;

    //해당 장치와의 연결상태를 관촬하는 리스너 실행
    peripheral
        .observeConnectionState(emitCurrentValue: true)
        .listen((connectionState) {
      // 연결상태가 변경되면 해당 루틴을 탐.
      switch (connectionState) {
        case PeripheralConnectionState.connected:
          {
            //연결됨
            _curPeripheral = peripheral;
            setBLEState('connected');
          }
          break;
        case PeripheralConnectionState.connecting:
          {
            setBLEState('connecting');
          } //연결중
          break;
        case PeripheralConnectionState.disconnected:
          {
            //해제됨
            _connected = false;
            print("${peripheral.name} has DISCONNECTED");
            setBLEState('disconnected');
          }
          break;
        case PeripheralConnectionState.disconnecting:
          {
            setBLEState('disconnecting');
          } //해제중
          break;
        default:
          {
            //알수없음...
            print("unkown connection state is: \n $connectionState");
          }
          break;
      }
    });

    _runWithErrorHandling(() async {
      //해당 장치와 이미 연결되어 있는지 확인
      bool isConnected = await peripheral.isConnected();
      if (isConnected) {
        print('device is already connected');
        //이미 연결되어 있기때문에 무시하고 종료..
        return;
      }

      //연결 시작!
      await peripheral.connect().then((_) {
        //연결이 되면 장치의 모든 서비스와 캐릭터리스틱을 검색한다.
        peripheral
            .discoverAllServicesAndCharacteristics()
            .then((_) => peripheral.services())
            .then((services) async {
          print("PRINTING SERVICES for ${peripheral.name}");
          //각각의 서비스의 하위 캐릭터리스틱 정보를 디버깅창에 표시한다.
          for (var service in services) {
            print("Found service ${service.uuid}");
            List<Characteristic> characteristics =
                await service.characteristics();
            for (var characteristic in characteristics) {
              print("${characteristic.uuid}");
            }
          }
          //모든 과정이 마무리되면 연결되었다고 표시
          _connected = true;
          print("${peripheral.name} has CONNECTED");
        });
      });
    });
  }

  list() {
    return ListView.builder(
      itemCount: deviceList.length,
      itemBuilder: (context, index) {
        return ListTile(
          //디바이스 이름과 맥주소 그리고 신호 세기를 표시한다.
          title: Text(deviceList[index].deviceName),
          subtitle: Text(deviceList[index].peripheral.identifier),
          trailing: Text("${deviceList[index].rssi}"),
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.title),
      ),
      body: Center(
        child: Column(
          children: <Widget>[
            Expanded(
              flex: 1,
              child: list(), //리스트 출력
            ),
            Container(
              child: Row(
                children: <Widget>[
                  RaisedButton(
                    //scan 버튼
                    onPressed: scan,
                    child: Icon(
                        _isScanning ? Icons.stop : Icons.bluetooth_searching),
                  ),
                  SizedBox(
                    width: 10,
                  ),
                  Text("State : "), Text(_statusText), //상태 정보 표시
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
