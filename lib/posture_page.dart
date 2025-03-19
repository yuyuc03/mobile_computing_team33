import 'dart:typed_data';
import 'dart:async';

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
  static const String serviceUuid = "1234";
  static const String characteristicUuid = "ABCD";
  static const int notificationInterval = 15; // seconds between notifications
  BluetoothDevice? _connectedDevice;
  double _goodProb = 0.0;
  double _badProb = 0.0;
  bool _isConnected = false;
  bool _isScanning = false;
  bool _isConnecting = false;
  bool _goodPosture = true;
  int _goodPostureMinutes = 0;
  int _badPostureMinutes = 0;
  int _currentStreak = 0;
  List<BluetoothDevice> devices = [];
  BluetoothDevice? connectedDevice;
  BluetoothCharacteristic? postureCharacteristic;

  // Timer variables
  Timer? _goodPostureTimer;
  Timer? _badPostureTimer;
  Timer? _streakTimer;

  // Timer durations in seconds
  int _goodPostureDuration = 0;
  int _badPostureDuration = 0;
  int _streakDuration = 0;

  // Add this variable at the top with other variables
  bool _hasReceivedData = false;

  @override
  void initState() {
    super.initState();
    _checkPermissions();
  }

  @override
  void dispose() {
    _goodPostureTimer?.cancel();
    _badPostureTimer?.cancel();
    _streakTimer?.cancel();
    super.dispose();
  }

  Future<void> _checkPermissions() async {
    await [
      Permission.bluetoothConnect,
      Permission.bluetoothScan,
      Permission.location
    ].request();
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
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text("Bluetooth permissions are required!")),
      );
    }
  }

  Future<void> startScan() async {
    setState(() {
      _isScanning = true;
      devices.clear();
    });

    // Show a snackbar to indicate scanning has started
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text("Scanning for devices...")),
    );

    // Listen for scan results and add unique devices
    FlutterBluePlus.scanResults.listen((results) {
      for (ScanResult result in results) {
        if (!devices.any((d) => d.remoteId == result.device.remoteId)) {
          setState(() {
            devices.add(result.device);
          });
        }
      }
    });

    try {
      await FlutterBluePlus.startScan(timeout: const Duration(seconds: 8));

      // Wait for the scan to complete
      await Future.delayed(const Duration(seconds: 8));

      // Stop scanning
      await FlutterBluePlus.stopScan();
    } catch (e) {
      print("Error during Bluetooth scan: $e");
    } finally {
      setState(() {
        _isScanning = false;
      });

      // Now show the dialog after the scan completes
      _showDeviceListDialog(devices);
    }
  }

  void _showDeviceListDialog(List<BluetoothDevice> devices) {
    // Filter out devices with empty platform names
    List<BluetoothDevice> validDevices =
        devices.where((device) => device.platformName.isNotEmpty).toList();

    showDialog(
      context: context,
      builder: (BuildContext dialogContext) {
        return AlertDialog(
          title: Text('Available Bluetooth Devices'),
          content: validDevices.isEmpty
              ? Text('No devices found. Try scanning again.')
              : SingleChildScrollView(
                  child: Column(
                    children: validDevices.map((device) {
                      return ListTile(
                        title: Text(device.platformName),
                        subtitle: Text(device.remoteId.toString()),
                        onTap: () {
                          _connectToDevice(device);
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
            TextButton(
                onPressed: () {
                  Navigator.of(dialogContext).pop();
                  startScan();
                },
                child: Text("Rescan"))
          ],
        );
      },
    );
  }

  void _disconnect() async {
    if (_connectedDevice != null) {
      await _connectedDevice!.disconnect();
      setState(() {
        _isConnected = false;
        _goodProb = 0.0;
        _badProb = 0.0;
      });
    }
  }

  Future<void> setupNotifications(List<BluetoothService> services) async {
    try {
      BluetoothService? targetService = services.firstWhere(
        (s) => s.uuid.toString().toLowerCase() == serviceUuid.toLowerCase(),
      );

      postureCharacteristic = targetService.characteristics.firstWhere(
        (c) =>
            c.uuid.toString().toLowerCase() == characteristicUuid.toLowerCase(),
      );

      // Enable notifications
      postureCharacteristic!.setNotifyValue(true);

      // Listen for updates
      postureCharacteristic!.lastValueStream.listen((value) {
        print("The received value is " + value.toString());
        if (value.isNotEmpty) {
          // Convert the received bytes to string
          String posture = String.fromCharCodes(value);
          print("Received posture: $posture");

          setState(() {
            _hasReceivedData = true;
            bool wasPreviouslyGood = _goodPosture;
            _goodPosture = posture == "Good";

            if (_goodPosture) {
              if (!wasPreviouslyGood) {
                // Switching to good posture
                _stopBadPostureTimer();
                _startGoodPostureTimers();
              }
            } else {
              if (wasPreviouslyGood) {
                // Switching to bad posture
                _stopGoodPostureTimers();
                _startBadPostureTimer();
                sendNotification();
                vibrate();
              }
            }
          });
        }
      });
    } catch (e) {
      print("Error setting up notifications: $e");
    }
  }

  Future<void> _connectToDevice(BluetoothDevice device) async {
    setState(() {
      _isScanning = true;
      _isConnecting = true;
    });

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text("Connecting to ${device.platformName}...")),
    );

    try {
      // Only use timeout, remove autoConnect
      await device.connect(
        timeout: Duration(seconds: 60),
      );

      // Add delay before discovering services
      //await Future.delayed(Duration(seconds: 2));

      // Find the service and characteristic for posture data
      List<BluetoothService> services = await device.discoverServices();

      // First perform the async operation
      await setupNotifications(services);

      // Then update the state synchronously
      setState(() {
        connectedDevice = device;
        _isConnected = true;
        _isScanning = false;
        _isConnecting = false;
      });

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text("Connected to ${device.platformName}")),
      );
      _showConnectionSuccessDialog();
    } on FlutterBluePlusException catch (e) {
      print("FlutterBluePlus error: ${e.description}");
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content:
              Text("Connection error: ${e.description}. Please try again."),
          duration: Duration(seconds: 5),
        ),
      );
      setState(() {
        _isScanning = false;
        _isConnecting = false;
      });
    } catch (e) {
      print("Error connecting to device: $e");
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text("Failed to connect: ${e.toString()}"),
          duration: Duration(seconds: 5),
        ),
      );
      setState(() {
        _isScanning = false;
        _isConnecting = false;
      });
    }
  }

  void _showConnectionSuccessDialog() {
    showDialog(
      context: context,
      builder: (BuildContext context) {
        return AlertDialog(
          title: Text("Connection Successful"),
          content: Text("Your device is now connected."),
          actions: [
            TextButton(
              onPressed: () {
                Navigator.pop(context);
              },
              child: Text("Continue"),
            ),
          ],
        );
      },
    );
  }

  void _startGoodPostureTimers() {
    _goodPostureTimer?.cancel();
    _streakTimer?.cancel();

    _goodPostureTimer = Timer.periodic(Duration(seconds: 1), (timer) {
      setState(() {
        _goodPostureDuration++;
      });
    });

    _streakTimer = Timer.periodic(Duration(seconds: 1), (timer) {
      setState(() {
        _streakDuration++;
      });
    });
  }

  void _startBadPostureTimer() {
    _badPostureTimer?.cancel();

    _badPostureTimer = Timer.periodic(Duration(seconds: 1), (timer) {
      setState(() {
        _badPostureDuration++;

        // Send notification every 15 seconds of bad posture
        if (_badPostureDuration % notificationInterval == 0) {
          sendNotification();
          vibrate();
        }
      });
    });
  }

  void _stopGoodPostureTimers() {
    _goodPostureTimer?.cancel();
    _streakTimer?.cancel();
    _streakDuration = 0; // Reset streak
    _currentStreak = 0;
  }

  void _stopBadPostureTimer() {
    _badPostureTimer?.cancel();
  }

  void _handleRecalibrate() {
    // Stop all timers
    _stopBadPostureTimer();
    _stopGoodPostureTimers();

    // Show initial snackbar
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content:
            Text('Recalibrating posture detection, you have 10 seconds...'),
        duration: Duration(seconds: 10), // Show for 10 seconds
      ),
    );

    // Wait 10 seconds before restarting timers
    Future.delayed(Duration(seconds: 10), () {
      setState(() {
        // After 10 seconds, start appropriate timer based on current posture
        if (_goodPosture) {
          _startGoodPostureTimers();
        } else {
          _startBadPostureTimer();
        }
      });
    });
  }

  // Update the helper function to format time as MM:SS
  String _formatTime(int seconds) {
    int minutes = seconds ~/ 60;
    int remainingSeconds = seconds % 60;
    // Pad with leading zeros if needed
    String minutesStr = minutes.toString().padLeft(2, '0');
    String secondsStr = remainingSeconds.toString().padLeft(2, '0');
    return '$minutesStr:$secondsStr';
  }

  @override
  Widget build(BuildContext context) {
    final screenSize = MediaQuery.of(context).size;

    return Stack(
      children: [
        // Main content
        _isConnected
            ? Scaffold(
                appBar: AppBar(
                  title: const Text('Posture Monitor'),
                  centerTitle: true,
                ),
                body: SafeArea(
                  child: Column(
                    children: [
                      Expanded(
                        flex: 3,
                        child: Container(
                          margin: EdgeInsets.all(screenSize.width * 0.04),
                          decoration: BoxDecoration(
                            color: !_hasReceivedData
                                ? Colors.grey.shade50
                                : _goodPosture
                                    ? Colors.green.shade50
                                    : Colors.red.shade50,
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
                                !_hasReceivedData
                                    ? Icons.hourglass_empty
                                    : _goodPosture
                                        ? Icons.check_circle
                                        : Icons.warning,
                                size: screenSize.width * 0.2,
                                color: !_hasReceivedData
                                    ? Colors.grey
                                    : _goodPosture
                                        ? Colors.green
                                        : Colors.red,
                              ),
                              SizedBox(height: screenSize.height * 0.02),
                              Text(
                                !_hasReceivedData
                                    ? 'No Data Yet'
                                    : _goodPosture
                                        ? 'Good Posture!'
                                        : 'Bad Posture!',
                                style: TextStyle(
                                  fontSize: screenSize.width * 0.06,
                                  fontWeight: FontWeight.bold,
                                  color: !_hasReceivedData
                                      ? Colors.grey
                                      : _goodPosture
                                          ? Colors.green
                                          : Colors.red,
                                ),
                              ),
                              SizedBox(height: screenSize.height * 0.02),
                              Padding(
                                padding: EdgeInsets.symmetric(
                                    horizontal: screenSize.width * 0.06),
                                child: Text(
                                  !_hasReceivedData
                                      ? 'Waiting for posture data from device...'
                                      : _goodPosture
                                          ? 'Great job maintaining proper alignment!'
                                          : 'Your shoulders are slouching forward. Try sitting up straight and pulling your shoulders back.',
                                  textAlign: TextAlign.center,
                                  style: TextStyle(
                                    fontSize: screenSize.width * 0.04,
                                    color: !_hasReceivedData
                                        ? Colors.grey.shade800
                                        : _goodPosture
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
                                'Good Posture',
                                _formatTime(_goodPostureDuration),
                                Colors.green),
                            _buildStatItem('Bad Posture',
                                _formatTime(_badPostureDuration), Colors.red),
                            _buildStatItem('Current Streak',
                                _formatTime(_streakDuration), Colors.blue),
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
                                onPressed: _handleRecalibrate,
                                style: ElevatedButton.styleFrom(
                                  padding: EdgeInsets.symmetric(
                                      vertical: screenSize.height * 0.02),
                                  shape: RoundedRectangleBorder(
                                    borderRadius: BorderRadius.circular(30.0),
                                  ),
                                ),
                                child: Text('Recalibrate',
                                    style: TextStyle(
                                        fontSize: screenSize.width * 0.04)),
                              ),
                            ),
                            SizedBox(height: screenSize.height * 0.01),
                            // SizedBox(
                            //   width: double.infinity,
                            //   child: ElevatedButton(
                            //     onPressed: _simulateBadPosture,
                            //     style: ElevatedButton.styleFrom(
                            //       backgroundColor: Colors.redAccent,
                            //       padding: EdgeInsets.symmetric(
                            //           vertical: screenSize.height * 0.02),
                            //       shape: RoundedRectangleBorder(
                            //         borderRadius: BorderRadius.circular(30.0),
                            //       ),
                            //     ),
                            //     child: Text('Simulate Bad Posture',
                            //         style: TextStyle(
                            //             fontSize: screenSize.width * 0.04)),
                            //   ),
                            // ),
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
                                    style: TextStyle(
                                        fontSize: screenSize.width * 0.04)),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              )
            : Scaffold(
                appBar: AppBar(title: Text("Bluetooth Connection")),
                body: Center(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Padding(
                        padding: EdgeInsets.symmetric(
                            horizontal: 20.0, vertical: 10.0),
                        child: Text(
                          "You need to be connected to Arduino in order to use our posture monitor",
                          textAlign: TextAlign.center,
                          style: TextStyle(
                              fontSize: 16, fontWeight: FontWeight.bold),
                        ),
                      ),
                      Text(
                        "Bluetooth Device: ${_isConnected ? "Connected" : "Not Connected"}",
                        style: TextStyle(
                            fontSize: 18,
                            fontWeight: FontWeight.bold,
                            color: _isConnected ? Colors.green : Colors.red),
                      ),
                      SizedBox(height: 20),
                      _isScanning
                          ? Container() // Empty container because we'll show loading in overlay
                          : ElevatedButton(
                              onPressed: () {
                                requestPermissions().then((_) => startScan());
                              },
                              style: ElevatedButton.styleFrom(
                                padding: EdgeInsets.symmetric(
                                    horizontal: 40, vertical: 12),
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(30.0),
                                ),
                              ),
                              child: Text("Connect to Device",
                                  style: TextStyle(fontSize: 16)),
                            ),
                    ],
                  ),
                ),
              ),

        // Loading overlay
        if (_isScanning)
          Container(
            width: double.infinity,
            height: double.infinity,
            color: Colors.black.withOpacity(0.5),
            child: Center(
              child: Card(
                elevation: 10,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(15),
                ),
                child: Padding(
                  padding:
                      const EdgeInsets.symmetric(vertical: 30, horizontal: 40),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      CircularProgressIndicator(
                        valueColor: AlwaysStoppedAnimation<Color>(Colors.blue),
                        strokeWidth: 3,
                      ),
                      SizedBox(height: 20),
                      Text(
                        _isConnecting
                            ? "Connecting to device..."
                            : "Scanning for devices...",
                        style: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      SizedBox(height: 8),
                      Text(
                        _isConnecting
                            ? "Please wait while we connect to your device"
                            : "Please wait while we search for nearby Bluetooth devices",
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          fontSize: 14,
                          color: Colors.grey[700],
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
      ],
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
          key: ValueKey(value),
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
