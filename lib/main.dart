import 'dart:async';

import 'package:flutter/material.dart';
import 'package:logger/logger.dart';
import 'package:usb_serial/usb_serial.dart';

import 'package:dart_rfid_library/reader_library.dart';
import 'package:dart_rfid_utils/src/uhf_inventory_result.dart';
import 'package:dart_rfid_library/src/reader_uhf/at-proto/pulsar_lr.dart';

void main() {
  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'METRATEC RFID Demo',
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: const Color.fromARGB(255, 39, 0, 106)),
        useMaterial3: true,
      ),
      home: const MyHomePage(title: 'METRATEC RFID Demo'),
    );
  }
}

class MyHomePage extends StatefulWidget {
  const MyHomePage({super.key, required this.title});

  final String title;

  @override
  State<MyHomePage> createState() => _MyHomePageState();
}

class _MyHomePageState extends State<MyHomePage> {
  UsbPort? _port;
  String _status = "Idle";
  List<Widget> _deviceList = [];

  UsbDevice? _device;
  UhfReaderAt? _reader;
  bool _readerConnected = false;
  Logger logger = Logger();

  @override
  void initState() {
    super.initState();

    UsbSerial.usbEventStream!.listen((UsbEvent event) {
      _getDevices();
    });

    _getDevices();
  }

  void _onConnectionError(Object? error, StackTrace stacktrace) {
    print("Connection Error:");
    print(stacktrace);
  }

  Future<bool> _connectTo(UsbDevice? device) async {
    if (_port != null) {
      _port!.close();
      _port = null;
    }

    // function called with empty device --> disconnect everything
    if (device == null) {
      await _reader?.disconnect();
      _reader = null;
      _device = null;
      setState(() {
        _status = "Disconnected";
      });
      return true;
    }

    _device = device;

    // initialize actual device connection
    if (_device != null) {
      UsbSettings usbSettings = UsbSettings(_device!.deviceId!);
      CommInterface commInterface = UsbInterface(usbSettings);

      _reader = ReaderPulsarLR(commInterface);

      try {
        if (await _reader!.connect(onError: _onConnectionError)) {
          logger.i("Reader connected");
          _readerConnected = true;
        }
      } catch (e) {
        print(e);
      }
    }

    setState(() {
      _status = "Connected";
    });
    return true;
  }

  Future<void> doSimpleInventory() async {
    logger.i("Setting antenna and power");
    try {
      // Set the region to ETSI/EU - choose FCC if in the US
      await _reader!.setRegion("ETSI");

      // Choose Antenna one to be active (default), can be 1-4 on PulsarLR
      await _reader!.setInvAntenna(1);

      // The output power in dBm. Can be 0 - 30 on PulsarLR. See product datasheet for other products
      await _reader!.setOutputPower([15]);
    } catch (err) {
      logger.e(err);
    }

    logger.i("Getting inventory");
    try {
      List<UhfInventoryResult>? tagList = await _reader?.inventory();
      tagList?.forEach((tagResult) {
        // Code to be executed for each element on the collection
        logger.i(tagResult.tag.epc);
      });
    } catch (err) {
      logger.e(err);
    }
  }

  Future<void> doMultiplexInventory() async {
    try {
      // configure the reader to multiplexer over antennas during MINV command, here antennas 1, 2 and 3
      // Please make sure that there are antenna connected to each port. Otherwise, you will get an "Operation Error"
      await _reader!.setMuxAntenna([1, 2, 3]);
    } catch (err) {
      logger.e(err);
    }

    logger.i("Getting multiplexed inventory");
    try {
      List<UhfInventoryResult>? tagList = await _reader?.muxInventory();
      tagList?.forEach((tagResult) {
        // Code to be executed for each element on the collection
        logger.i(tagResult.tag.epc);
      });
    } catch (err) {
      logger.e(err);
    }
  }

  void _getDevices() async {
    _deviceList = [];
    List<UsbDevice> devices = await UsbSerial.listDevices();

    // nothing found, make sure everything is disconnected
    if (!devices.contains(_device)) {
      _connectTo(null);
    }

    // build tiles for devices
    devices.forEach((device) {
      //only show Metratec devices
      if (device.manufacturerName == "Metratec GmbH") {
        _deviceList.add(ListTile(
            leading: const Icon(Icons.usb),
            title: Text(device.productName!),
            subtitle: Text(device.manufacturerName!),
            trailing: ElevatedButton(
              child: Text(_device == device ? "Disconnect" : "Connect"),
              onPressed: () {
                _connectTo(_device == device ? null : device).then((res) {
                  _getDevices();
                });
              },
            )));
      }
    });
  }

  @override
  void dispose() {
    super.dispose();
    _connectTo(null);
  }

  Widget inventoryButton() {
    return ListTile(
        //leading: const Icon(Icons.usb),
        title: const Text("Simple Inventory"),
        trailing: ElevatedButton(
            child: const Text("Scan"),
            onPressed: () {
              doSimpleInventory();
            }));
  }

  Widget multiplexInventoryButton() {
    return ListTile(
        //leading: const Icon(Icons.usb),
        title: const Text("Multiplex Inventory"),
        trailing: ElevatedButton(
            child: const Text("Scan"),
            onPressed: () {
              doMultiplexInventory();
            }));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        backgroundColor: Theme.of(context).colorScheme.inversePrimary,
        title: Text(widget.title),
      ),
      body: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.start,
          children: <Widget>[
            Text(_deviceList.isNotEmpty ? "Available devices" : "No serial devices available",
                style: Theme.of(context).textTheme.titleLarge),
            ..._deviceList,
            _readerConnected ? inventoryButton() : const Text(""),
            _readerConnected ? multiplexInventoryButton() : const Text(""),
          ],
        ),
      ),
    );
  }
}
