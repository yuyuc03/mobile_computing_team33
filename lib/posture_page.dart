import 'package:flutter/material.dart';
import 'package:flutter_blue_plus/flutter_blue_plus.dart';
import 'package:permission_handler/permission_handler.dart';
import 'notification_service.dart';

class PosturePage extends StatefulWidget {
  const PosturePage({Key? key}) : super(key: key);

  @override
  _PosturePageState createState() => _PosturePageState();
}

class _PosturePageState extends State<PosturePage> {
  bool _goodPosture = true;
  int _goodPostureMinutes = 45;
  int _badPostureMinutes = 15;
  int _currentStreak = 10;
  List<BluetoothDevice> devices = [];
  BluetoothDevice? connectedDevice;
  BluetoothCharacteristic? postureCharacteristic;

  Future<void> scanAndConnect() async {
    // Start scanning
    FlutterBluePlus.startScan(timeout: const Duration(seconds: 5));

    // Listen to scan results
    FlutterBluePlus.scanResults.listen((results) async {
      for (ScanResult r in results) {
        if (r.device.name == "PostureSensor") {
          // Match Arduino BLE name
          print("Found device: ${r.device.name}");

          await FlutterBluePlus.stopScan(); // Stop scanning
          connectedDevice = r.device;

          // Connect to the device
          await connectedDevice!.connect();

          // Discover services
          List<BluetoothService> services =
              await connectedDevice!.discoverServices();

          for (BluetoothService service in services) {
            for (BluetoothCharacteristic characteristic
                in service.characteristics) {
              if (characteristic.uuid
                  .toString()
                  .toUpperCase()
                  .contains("2A37")) {
                // Match characteristic UUID
                postureCharacteristic = characteristic;
                listenToPosture(); // Start listening for posture updates
              }
            }
          }
        }
      }
    });
  }

  void listenToPosture() {
    if (postureCharacteristic != null) {
      postureCharacteristic!.setNotifyValue(true);
      postureCharacteristic!.value.listen((value) {
        if (value.length >= 2) {
          // Assuming the first byte is good probability and the second byte is bad probability
          int goodProbability = value[0];
          int badProbability = value[1];

          String posture = goodProbability > badProbability ? "good" : "bad";
          print("Posture: $posture"); // Output either "good" or "bad"

          // Trigger _simulateBadPosture if posture is bad
          if (posture == "bad") {
            _simulateBadPosture();
          } else {
            setState(() {
              _goodPosture = true;
            });
          }
        } else {
          print("Invalid data received: $value");
        }
      });
    }
  }

  void _simulateBadPosture() async {
    setState(() {
      _goodPosture = false;
      _badPostureMinutes++;
      _currentStreak = 0;
    });
    await sendNotification();
    vibrate();
  }

  void _showGoodPostureTips() {
    showDialog(
      context: context,
      builder: (BuildContext dialogContext) {
        return AlertDialog(
          title: Text('How to Maintain Good Posture'),
          content: SingleChildScrollView(
            child: ListBody(
              children: [
                Text("1. Sit upright with shoulders back."),
                Text("2. Keep your feet flat on the floor."),
                Text("3. Your ears should align with your shoulders."),
                Text("4. Avoid slouching forward for long periods."),
                SizedBox(height: 10),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(),
              child: Text('Close'),
            ),
          ],
        );
      },
    );
  }

  Future<void> requestPermissions() async {
    if (await Permission.bluetoothScan.request().isGranted &&
        await Permission.bluetoothConnect.request().isGranted &&
        await Permission.location.request().isGranted) {
      startScan();
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text("Bluetooth permissions are required!")),
      );
    }
  }

  void startScan() async {
    devices.clear();
    setState(() {}); // Ensure UI updates

    FlutterBluePlus.startScan(timeout: const Duration(seconds: 4));

    FlutterBluePlus.scanResults.listen((results) {
      for (ScanResult result in results) {
        if (!devices.any((d) => d.id == result.device.id)) {
          setState(() {
            devices.add(result.device);
          });
        }
      }
    });

    await Future.delayed(const Duration(seconds: 4));
    FlutterBluePlus.stopScan();
  }

  void _showDeviceListDialog() {
    showDialog(
      context: context,
      builder: (BuildContext dialogContext) {
        return AlertDialog(
          title: Text('Available Bluetooth Devices'),
          content: devices.isEmpty
              ? Text('No devices found.')
              : SingleChildScrollView(
                  child: Column(
                    children: devices.map((device) {
                      return ListTile(
                        title: Text(device.name.isNotEmpty
                            ? device.name
                            : "Unknown Device"),
                        subtitle: Text(device.id.toString()),
                        onTap: () {
                          // You can add your logic to connect to the selected device here.
                          Navigator.of(dialogContext).pop();
                        },
                      );
                    }).toList(),
                  ),
                ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(),
              child: Text('Close'),
            ),
          ],
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final screenSize = MediaQuery.of(context).size;
    final isSmallScreen = screenSize.width < 600;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Posture Monitor'),
        centerTitle: true,
      ),
      body: SafeArea(
        child: Column(
          children: [
            ElevatedButton(
              onPressed: () async {
                await requestPermissions();
                _showDeviceListDialog();
              },
              child: const Text("Scan for Devices"),
            ),
            // Expanded(
            //   child: ListView(
            //     children: devices.map((device) {
            //       return ListTile(
            //         title: Text(device.name.isNotEmpty
            //             ? device.name
            //             : "Unknown Device"),
            //         subtitle: Text(device.id.toString()),
            //       );
            //     }).toList(),
            //   ),
            // ),
            // Posture Status Card
            Expanded(
              flex: 3,
              child: Container(
                margin: EdgeInsets.all(screenSize.width * 0.04),
                decoration: BoxDecoration(
                  color:
                      _goodPosture ? Colors.green.shade50 : Colors.red.shade50,
                  borderRadius: BorderRadius.circular(16.0),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.grey.withOpacity(0.3),
                      spreadRadius: 2,
                      blurRadius: 5,
                      offset: const Offset(0, 3),
                    ),
                  ],
                ),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(
                      _goodPosture ? Icons.check_circle : Icons.warning,
                      size: screenSize.width * 0.2,
                      color: _goodPosture ? Colors.green : Colors.red,
                    ),
                    SizedBox(height: screenSize.height * 0.02),
                    Text(
                      _goodPosture ? 'Good Posture!' : 'Bad Posture!',
                      style: TextStyle(
                        fontSize: screenSize.width * 0.06,
                        fontWeight: FontWeight.bold,
                        color: _goodPosture ? Colors.green : Colors.red,
                      ),
                    ),
                    SizedBox(height: screenSize.height * 0.02),
                    Padding(
                      padding: EdgeInsets.symmetric(
                          horizontal: screenSize.width * 0.06),
                      child: Text(
                        _goodPosture
                            ? 'Great job maintaining proper alignment!'
                            : 'Your shoulders are slouching forward. Try sitting up straight and pulling your shoulders back.',
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          fontSize: screenSize.width * 0.04,
                          color: _goodPosture
                              ? Colors.green.shade800
                              : Colors.red.shade800,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),

            // Statistics Section
            Container(
              margin: EdgeInsets.all(screenSize.width * 0.04),
              padding: EdgeInsets.all(screenSize.width * 0.04),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(16.0),
                boxShadow: [
                  BoxShadow(
                    color: Colors.grey.withOpacity(0.2),
                    spreadRadius: 1,
                    blurRadius: 3,
                    offset: const Offset(0, 2),
                  ),
                ],
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceAround,
                children: [
                  _buildStatItem(
                      'Good Posture', '$_goodPostureMinutes min', Colors.green),
                  _buildStatItem(
                      'Bad Posture', '$_badPostureMinutes min', Colors.red),
                  _buildStatItem(
                      'Current Streak', '$_currentStreak min', Colors.blue),
                ],
              ),
            ),

            // Action Buttons
            Padding(
              padding: EdgeInsets.all(screenSize.width * 0.04),
              child: Column(
                children: [
                  SizedBox(
                    width: double.infinity,
                    child: ElevatedButton(
                      onPressed: () {
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(
                              content:
                                  Text('Recalibrating posture detection...')),
                        );
                      },
                      style: ElevatedButton.styleFrom(
                        padding: EdgeInsets.symmetric(
                            vertical: screenSize.height * 0.02),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(30.0),
                        ),
                      ),
                      child: Text('Recalibrate',
                          style: TextStyle(fontSize: screenSize.width * 0.04)),
                    ),
                  ),
                  SizedBox(height: screenSize.height * 0.01),
                  SizedBox(
                    width: double.infinity,
                    child: ElevatedButton(
                      onPressed: _simulateBadPosture,
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.redAccent,
                        padding: EdgeInsets.symmetric(
                            vertical: screenSize.height * 0.02),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(30.0),
                        ),
                      ),
                      child: Text('Simulate Bad Posture',
                          style: TextStyle(fontSize: screenSize.width * 0.04)),
                    ),
                  ),
                  SizedBox(height: screenSize.height * 0.01),
                  SizedBox(
                    width: double.infinity,
                    child: ElevatedButton(
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.black,
                        foregroundColor: Colors.white,
                        padding: EdgeInsets.symmetric(
                            vertical: screenSize.height * 0.02),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(30.0),
                        ),
                      ),
                      onPressed: _showGoodPostureTips,
                      child: Text('Good Posture Tips',
                          style: TextStyle(fontSize: screenSize.width * 0.04)),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildStatItem(String title, String value, Color color) {
    return Column(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        Text(
          title,
          style: TextStyle(
            fontSize: 14,
            color: Colors.grey.shade700,
          ),
        ),
        const SizedBox(height: 8),
        Text(
          value,
          style: TextStyle(
            fontSize: 18,
            fontWeight: FontWeight.bold,
            color: color,
          ),
        ),
      ],
    );
  }
}
