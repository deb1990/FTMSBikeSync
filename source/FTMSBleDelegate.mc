// FTMSBleDelegate.mc
// BLE delegate for the FTMS Indoor Bike Data profile.
//
// API notes (SDK 8.x):
//   - longToUuid() takes TWO Long params (mostSigBits, leastSigBits)
//   - 16-bit BLE UUIDs expand to 128-bit via base UUID 00000000-0000-1000-8000-00805F9B34FB
//   - onScanResults receives a Lang.Iterator (call .next() to walk it)
//   - pairDevice() takes a ScanResult (not a Device)
//   - CCCD UUID via BluetoothLowEnergy.cccdUuid()

import Toybox.BluetoothLowEnergy;
import Toybox.Application;
import Toybox.Lang;
import Toybox.System;

// ---------------------------------------------------------------------------
// Connection state enum
// ---------------------------------------------------------------------------
enum {
    STATE_SCANNING      = 0,
    STATE_CONNECTING    = 1,
    STATE_CONNECTED     = 2,
    STATE_RECONNECTING  = 3
}

const STORAGE_KEY_DEVICE_NAME = "lastFtmsDeviceName";

class FTMSBleDelegate extends BluetoothLowEnergy.BleDelegate {

    // UUIDs initialised lazily inside the class so longToUuid() is not
    // called at module-load time (which crashes the simulator).
    var FTMS_SERVICE_UUID;
    var FTMS_CHAR_UUID;

    // -----------------------------------------------------------------------
    // Public live metrics (read by FTMSDataField each second)
    // -----------------------------------------------------------------------
    var speedKph   = 0.0f;
    var cadenceRpm = 0.0f;
    var distanceM  = 0;
    var powerW     = 0;

    // -----------------------------------------------------------------------
    // Private state
    // -----------------------------------------------------------------------
    var _state = STATE_SCANNING;

    // -----------------------------------------------------------------------
    // Constructor
    // -----------------------------------------------------------------------
    function initialize() {
        BleDelegate.initialize();
        // Initialise UUIDs here so longToUuid() runs after the BLE module is ready
        FTMS_SERVICE_UUID = BluetoothLowEnergy.longToUuid(0x0000182600001000l, 0x800000805F9B34FBl);
        FTMS_CHAR_UUID    = BluetoothLowEnergy.longToUuid(0x00002AD200001000l, 0x800000805F9B34FBl);
        _registerProfile();
        BluetoothLowEnergy.setDelegate(self);
        _startScan();
    }

    // -----------------------------------------------------------------------
    // State accessor
    // -----------------------------------------------------------------------
    function getState() {
        return _state;
    }

    // -----------------------------------------------------------------------
    // Register FTMS GATT profile so the SDK knows what to discover
    // -----------------------------------------------------------------------
    function _registerProfile() {
        BluetoothLowEnergy.registerProfile({
            :uuid => FTMS_SERVICE_UUID,
            :characteristics => [
                {
                    :uuid => FTMS_CHAR_UUID,
                    :descriptors => [ BluetoothLowEnergy.cccdUuid() ]
                }
            ]
        });
    }

    // -----------------------------------------------------------------------
    // Start scanning
    // -----------------------------------------------------------------------
    function _startScan() {
        _state = STATE_SCANNING;
        BluetoothLowEnergy.setScanState(BluetoothLowEnergy.SCAN_STATE_SCANNING);
    }

    // -----------------------------------------------------------------------
    // onScanResults — called with an Iterator of ScanResult objects
    // -----------------------------------------------------------------------
    function onScanResults(scanResults as Iterator) as Void {
        if (_state != STATE_SCANNING) {
            return;
        }

        var savedName  = Application.Storage.getValue(STORAGE_KEY_DEVICE_NAME);
        var bestResult = null;

        for (var result = scanResults.next(); result != null; result = scanResults.next()) {
            if (!(result instanceof BluetoothLowEnergy.ScanResult)) {
                continue;
            }

            // Only consider devices advertising the FTMS service
            if (!_hasFtmsService(result.getServiceUuids())) {
                continue;
            }

            // Prefer previously-seen device by name
            if (savedName != null) {
                var deviceName = result.getDeviceName();
                if (deviceName != null && deviceName.equals(savedName)) {
                    bestResult = result;
                    break;
                }
            }

            if (bestResult == null) {
                bestResult = result; // fallback: first FTMS device found
            }
        }

        if (bestResult != null) {
            _state = STATE_CONNECTING;
            BluetoothLowEnergy.setScanState(BluetoothLowEnergy.SCAN_STATE_OFF);
            BluetoothLowEnergy.pairDevice(bestResult);
        }
    }

    // Check whether a UUID iterator contains the FTMS service UUID
    function _hasFtmsService(uuidIter as Iterator) as Boolean {
        for (var uuid = uuidIter.next(); uuid != null; uuid = uuidIter.next()) {
            if (uuid.equals(FTMS_SERVICE_UUID)) {
                return true;
            }
        }
        return false;
    }

    // -----------------------------------------------------------------------
    // onConnectedStateChanged
    // -----------------------------------------------------------------------
    function onConnectedStateChanged(device as BluetoothLowEnergy.Device, state as BluetoothLowEnergy.ConnectionState) as Void {
        if (state == BluetoothLowEnergy.CONNECTION_STATE_CONNECTED) {
            // Persist device name for future sessions
            var name = device.getName();
            if (name != null) {
                Application.Storage.setValue(STORAGE_KEY_DEVICE_NAME, name);
            }
            _enableNotifications(device);

        } else if (state == BluetoothLowEnergy.CONNECTION_STATE_DISCONNECTED) {
            _zeroMetrics();
            _state = STATE_RECONNECTING;
            _startScan();
        }
    }

    // Walk GATT tree and enable notifications on Indoor Bike Data characteristic
    function _enableNotifications(device as BluetoothLowEnergy.Device) as Void {
        var service = device.getService(FTMS_SERVICE_UUID);
        if (service == null) {
            System.println("FTMSBleDelegate: FTMS service not found");
            return;
        }

        var characteristic = service.getCharacteristic(FTMS_CHAR_UUID);
        if (characteristic == null) {
            System.println("FTMSBleDelegate: Indoor Bike Data characteristic not found");
            return;
        }

        var cccd = characteristic.getDescriptor(BluetoothLowEnergy.cccdUuid());
        if (cccd == null) {
            System.println("FTMSBleDelegate: CCCD not found");
            return;
        }

        // Write 0x0001 to enable notifications
        cccd.requestWrite([ 0x01, 0x00 ]b);
    }

    // -----------------------------------------------------------------------
    // onDescriptorWrite — confirm notifications enabled
    // -----------------------------------------------------------------------
    function onDescriptorWrite(descriptor as BluetoothLowEnergy.Descriptor, status as BluetoothLowEnergy.Status) as Void {
        if (status == BluetoothLowEnergy.STATUS_SUCCESS) {
            _state = STATE_CONNECTED;
        } else {
            System.println("FTMSBleDelegate: CCCD write failed, status=" + status);
            _zeroMetrics();
            _state = STATE_RECONNECTING;
            _startScan();
        }
    }

    // -----------------------------------------------------------------------
    // onCharacteristicChanged — parse and store incoming metrics
    // -----------------------------------------------------------------------
    function onCharacteristicChanged(characteristic as BluetoothLowEnergy.Characteristic, data as ByteArray) as Void {
        var parsed = FTMSParser.parse(data);

        speedKph = parsed[:speedKph];

        if (parsed[:cadenceRpm] != null) {
            cadenceRpm = parsed[:cadenceRpm];
        }
        if (parsed[:distanceM] != null) {
            distanceM = parsed[:distanceM];
        }
        if (parsed[:powerW] != null) {
            powerW = parsed[:powerW];
        }
    }

    // -----------------------------------------------------------------------
    // Zero all metrics on disconnect
    // -----------------------------------------------------------------------
    function _zeroMetrics() as Void {
        speedKph   = 0.0f;
        cadenceRpm = 0.0f;
        distanceM  = 0;
        powerW     = 0;
    }

}
