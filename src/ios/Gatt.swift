
import CoreBluetooth
import SystemConfiguration.CaptiveNetwork
import Foundation
import PromiseKit

@objc(Gatt) class Gatt : CDVPlugin,  CBCentralManagerDelegate, CBPeripheralDelegate {
    
    var centralManager : CBCentralManager!
    var blufiManager: BluFiManager?
    var currentDevice : CBPeripheral?
    var devices = [CBPeripheral]()
    
    var currentCDVCommand : CDVInvokedUrlCommand?
    
    private var bluFiServiceUUID = CBUUID(string: "0000ffff-0000-1000-8000-00805f9b34fb")
    private var bluFiDataOutCharsUUID = CBUUID(string: "0000ff01-0000-1000-8000-00805f9b34fb")
    private var bluFiDataInCharsUUID = CBUUID(string: "0000ff02-0000-1000-8000-00805f9b34fb")
    
    fileprivate      var dataOutCharacteristic: CBCharacteristic?
    fileprivate      var dataInCharacteristic: CBCharacteristic?
    
    
    // SEARCH - Search (Scan) for nearby BLE devices
    @objc(search:)
    func search(command: CDVInvokedUrlCommand) {
        var pluginResult = CDVPluginResult(
            status: CDVCommandStatus_ERROR
        )
        
        self.devices = [CBPeripheral]()
        
        let prefix = command.arguments[0] as? String ?? ""
        let timeout = command.arguments[1] as? Int ?? 5000
        
        //Set the scan timeout
        let timeoutInSeconds:Double = Double(timeout) / Double(1000)
        DispatchQueue.main.asyncAfter(deadline: .now() + timeoutInSeconds) {
            self.centralManager.stopScan()
            
            var devices = [[AnyHashable : Any]]()
            for device in self.devices {
                
                let deviceName = device.name ?? ""
                if prefix == "" || deviceName.contains(prefix) {
                    devices.append([
                        "name":device.name,
                        "address":device.identifier.uuidString,
                        "type":device.description
                        ])
                }
            }
            
            //window.cordova.plugins.blufi.search("", 5000, (y) => console.log(y), (n) => console.error(n));
            pluginResult = CDVPluginResult(
                status: CDVCommandStatus_OK,
                messageAs: devices
            )
            self.commandDelegate!.send(
                pluginResult,
                callbackId: command.callbackId
            )
        }
        
        centralManager = CBCentralManager.init(delegate: self, queue: nil)
    }
    
    
    ///////CONNECT - Connect to a BLE device as per passed identifier (name or uuid)
    
    // Connect Handler
    @objc(connect:)
    func connect(command: CDVInvokedUrlCommand) {
        var pluginResult = CDVPluginResult(
            status: CDVCommandStatus_ERROR
        )
        
        let config = command.arguments[0]
        
        if let dictionary = config as? [String: Any] {
            
            if let uuids = dictionary["uuid"] as? [String:String] {
                
                if let serviceUUID = uuids["service"] {
                    self.bluFiServiceUUID = CBUUID(string:serviceUUID)
                }
                
                if let writeUUID = uuids["write"] {
                    self.bluFiDataOutCharsUUID = CBUUID(string:writeUUID)
                }
                
                if let readUUID = uuids["notification"] {
                    self.bluFiDataInCharsUUID = CBUUID(string:readUUID)
                }
            }
            
            if let identifier = dictionary["identifier"] as? String {
                for device in self.devices {
                    if device.name == identifier || device.identifier.uuidString == identifier {
                        self.currentDevice = device
                        self.currentCDVCommand = command
                        self.centralManager.connect(device, options: nil)
                    }
                }
            }
        }
    }
    
    // Connect Delegate Callback
    func centralManager(_ central: CBCentralManager, didConnect peripheral: CBPeripheral) {
        
        if self.currentCDVCommand != nil {
            
            let response : [String:Any] = [
                "connected": true,
                "address": self.currentDevice!.identifier.uuidString,
                "message": "Connected",
                "error": ""
            ]
            
            
            let pluginResult = CDVPluginResult(
                status: CDVCommandStatus_OK,
                messageAs: response
            )
            self.commandDelegate!.send(
                pluginResult,
                callbackId: self.currentCDVCommand!.callbackId
            )
            
        }
        
        peripheral.delegate = self
        peripheral.discoverServices(nil)
        
    }
    
    
    
    /////// DISCONNECT - Disconnect from currently connected BLE device
    
    // Disconnect Handler
    @objc(disconnect:)
    func disconnect(command: CDVInvokedUrlCommand) {
        
        if self.currentDevice != nil {
            self.currentCDVCommand = command
            self.centralManager.cancelPeripheralConnection(self.currentDevice!)
        } else {
            
            let response : [String:Any] = [
                "connected": false,
                "address": "",
                "message": "Cannot disconnect",
                "error": "No device connected"
            ]
            
            let pluginResult = CDVPluginResult(
                status: CDVCommandStatus_ERROR,
                messageAs: response
            )
            
            self.commandDelegate!.send(
                pluginResult,
                callbackId: command.callbackId
            )
        }
    }
    
    // Disconnect Delegate Callback
    func centralManager(_ central: CBCentralManager, didDisconnectPeripheral peripheral: CBPeripheral, error: Error?) {
        
        if self.currentCDVCommand != nil {
            let response : [String:Any] = [
                "connected": false,
                "address": self.currentDevice!.identifier.uuidString,
                "message": "Device disconnected",
                "error" : error.debugDescription ?? ""
            ]
            
            let pluginResult = CDVPluginResult(
                status: CDVCommandStatus_OK,
                messageAs: response
            )
            self.commandDelegate!.send(
                pluginResult,
                callbackId: self.currentCDVCommand!.callbackId
            )
            
            self.currentDevice = nil;
        }
        
    }
    
    
    
    
    /////// SCAN - Scan for available WiFi networks
    
    // Scan handler
    @objc(scan:)
    func scan(command: CDVInvokedUrlCommand) {
        var pluginResult = CDVPluginResult(
            status: CDVCommandStatus_ERROR
        )
        
        self.blufiManager?.getWiFiScanList().done({ (list) in
            
            var scanResult = [[AnyHashable : Any]]()
            for result in list {
                scanResult.append([
                    "ssid":result.ssid,
                    "rssi":result.rssi
                    ])
            }
            
            pluginResult = CDVPluginResult(
                status: CDVCommandStatus_OK,
                messageAs: scanResult
            )
            self.commandDelegate!.send(
                pluginResult,
                callbackId: command.callbackId
            )
            
        })
    }
    
    
    /////// NEGOTIATE - Negotiate encryption with BluFi device
    
    // Negiotiate Handler
    @objc(negotiate:)
    func negotiate(command: CDVInvokedUrlCommand) {
        var pluginResult = CDVPluginResult(
            status: CDVCommandStatus_ERROR
        )
        
        self.blufiManager?.negotiate().done({ (result) in
            
            let response : [String:Any] = [
                "complete": true,
                "error" : "",
                "message": "Security negotiation complete"
            ]
            
            pluginResult = CDVPluginResult(
                status: CDVCommandStatus_OK,
                messageAs: response
            )
            self.commandDelegate!.send(
                pluginResult,
                callbackId: command.callbackId
            )
            
        }).catch({ (error) in
            
            let response : [String:Any] = [
                "complete": false,
                "error" : error.localizedDescription,
                "message": "Security negotiation failed"
            ]
            
            pluginResult = CDVPluginResult(
                status: CDVCommandStatus_ERROR,
                messageAs: response
            )
            self.commandDelegate!.send(
                pluginResult,
                callbackId: command.callbackId
            )
        })
        
    }
    
    
    
    /////// VERSION - Get the version from the connected BLE device
    
    // Version handler
    @objc(version:)
    func version(command: CDVInvokedUrlCommand) {
        var pluginResult = CDVPluginResult(
            status: CDVCommandStatus_ERROR
        )
        
        self.blufiManager?.getDeviceVersion().done({ (version) in
            
            let response : [String:Any] = [
                "version": String(version[0]) + "." + String(version[1]),
                "error" : "",
                "message": "Get version successful"
            ]
            
            pluginResult = CDVPluginResult(
                status: CDVCommandStatus_OK,
                messageAs: response
            )
            self.commandDelegate!.send(
                pluginResult,
                callbackId: command.callbackId
            )
            
        }).catch({ (error) in
            
            let response : [String:Any] = [
                "version": "",
                "error" : error.localizedDescription,
                "message": "Get version failed"
            ]
            
            pluginResult = CDVPluginResult(
                status: CDVCommandStatus_ERROR,
                messageAs: response
            )
            self.commandDelegate!.send(
                pluginResult,
                callbackId: command.callbackId
            )
        })
    }
    
    
    
    /////// STATUS - Get the current WiFi status of the connected BLE device
    
    // Status handler
    @objc(status:)
    func status(command: CDVInvokedUrlCommand) {
        var pluginResult = CDVPluginResult(
            status: CDVCommandStatus_ERROR
        )
        
        self.blufiManager?.getDeviceStatus().done({ (status) in
            
            let byteOpMode = status[0];
            let byteStationConnectionState = status[1]
            let byteSoftAPConnectionCount = status[2]
            
            var labelOpMode = ""
            switch byteOpMode {
            case 0 : labelOpMode = "None"
            case 1 : labelOpMode = "Station"
            case 2 : labelOpMode = "SoftAP"
            case 3 : labelOpMode = "Station/SoftAP"
            default: labelOpMode = "Unknown"
            }
            
            var labelStationConnectionState = ""
            switch byteStationConnectionState {
            case 0 : labelStationConnectionState = "Connected"
            default: labelStationConnectionState = "Disconnected"
            }
            
            let labelSoftAPConnectionCount = String(byteSoftAPConnectionCount)
            
            var labelSoftAPSSID = ""
            if status.indices.contains(3) {
                labelSoftAPSSID = String(status[3])
            }
            
            let response : [String:Any] = [
                "opMode": labelOpMode,
                "stationState": labelStationConnectionState,
                "connectionCount": labelSoftAPConnectionCount,
                "softAPSSID": labelSoftAPSSID,
                "error": "",
                "message": "Get status successful"
            ]
            
            pluginResult = CDVPluginResult(
                status: CDVCommandStatus_OK,
                messageAs: response
            )
            self.commandDelegate!.send(
                pluginResult,
                callbackId: command.callbackId
            )
            
        }).catch({ (error) in
            
            let response : [String:Any] = [
                "opMode": "",
                "stationState": "",
                "connectionCount": "",
                "softAPSSID": "",
                "error": error.localizedDescription,
                "message": "Get status failed"
            ]
            
            pluginResult = CDVPluginResult(
                status: CDVCommandStatus_ERROR,
                messageAs: response
            )
            self.commandDelegate!.send(
                pluginResult,
                callbackId: command.callbackId
            )
        })
    }
    
    
    /////// SEND - Send custom data to connected device
    
    // Send handler
    @objc(send:)
    func send(command: CDVInvokedUrlCommand) {
        var pluginResult = CDVPluginResult(
            status: CDVCommandStatus_ERROR
        )
        
        
        let data:String = command.arguments[0] as? String ?? ""
        let rawData:[UInt8] = Array(data.utf8)
        
        
        self.blufiManager?.writeCustomData(rawData, false).done({ (result) in
            
            let response : [String:Any] = [
                "complete": true,
                "error" : "",
                "message": "Send custom data complete"
            ]
            
            pluginResult = CDVPluginResult(
                status: CDVCommandStatus_OK,
                messageAs: response
            )
            self.commandDelegate!.send(
                pluginResult,
                callbackId: command.callbackId
            )
            
        }).catch({ (error) in
            
            let response : [String:Any] = [
                "complete": false,
                "error" : error.localizedDescription,
                "message": "Send custom data failed"
            ]
            
            pluginResult = CDVPluginResult(
                status: CDVCommandStatus_ERROR,
                messageAs: response
            )
            self.commandDelegate!.send(
                pluginResult,
                callbackId: command.callbackId
            )
        })
    }
    
    
    
    /////// CONFIGURE - Configure the WiFi on the connected device
    
    // Configure handler
    @objc(configure:)
    func configure(command: CDVInvokedUrlCommand) {
        
        let config = command.arguments[0]
        
        if let dictionary = config as? [String: Any] {
            if let mode = dictionary["mode"] as? String {
                if let modeConfig = dictionary["config"] as? [String: Any] {
                    
                    if mode == "station" {
                        
                        let ssid = modeConfig["ssid"] as? String
                        let password = modeConfig["password"] as? String
                        
                        self.setStation(ssid!, password!, command)
                        
                    } else if mode == "softap" {
                        
                        let ssid = modeConfig["ssid"] as? String
                        let password = modeConfig["password"] as? String
                        let security = modeConfig["security"] as? String
                        let channel = modeConfig["channel"] as? String
                        let maxConnections = modeConfig["maxConnections"] as? String
                        
                        self.setSoftAP(ssid!, password!, channel!, maxConnections!, security!, command)
                        
                        
                    } else if mode == "stasoftap" {
                        
                        let stationModeConfig = modeConfig["station"] as? [String:String]
                        let softAPModeConfig = modeConfig["softap"] as? [String:String]
                        
                        let sta_ssid = stationModeConfig!["ssid"] as? String
                        let sta_password = stationModeConfig!["password"] as? String
                        
                        let ap_ssid = softAPModeConfig!["ssid"] as? String
                        let ap_password = softAPModeConfig!["password"] as? String
                        let ap_security = softAPModeConfig!["security"] as? String
                        let ap_channel = softAPModeConfig!["channel"] as? String
                        let ap_maxConnections = softAPModeConfig!["maxConnections"] as? String
                        
                        self.setStaSoftAP(sta_ssid!, sta_password!, ap_ssid!, ap_password!, ap_channel!, ap_maxConnections!, ap_security!, command)
                     
                    }
                }
            }
        }
    }
    
    
    private func setStation(_ ssid:String, _ password:String, _ command:CDVInvokedUrlCommand) {
        
        self.blufiManager?.setWiFiSta(ssid, password).done({ (result) in
            
            let response : [String:Any] = [
                "complete": true,
                "error" : "",
                "message": "Configuration complete"
            ]
            
            let pluginResult = CDVPluginResult(
                status: CDVCommandStatus_OK,
                messageAs: response
            )
            self.commandDelegate!.send(
                pluginResult,
                callbackId: command.callbackId
            )
            
            //BOUNCE THE CONNECTION - IOS COREBLUETOOTH BUG
            self.currentCDVCommand = nil;
            self.centralManager.cancelPeripheralConnection(self.currentDevice!)
            self.centralManager.connect(self.currentDevice!, options: nil)
            
            
        }).catch({ (error) in
            
            let response : [String:Any] = [
                "complete": false,
                "error" : error.localizedDescription,
                "message": "Configuration failed"
            ]
            
            let pluginResult = CDVPluginResult(
                status: CDVCommandStatus_ERROR,
                messageAs: response
            )
            self.commandDelegate!.send(
                pluginResult,
                callbackId: command.callbackId
            )
        })
        
        
        
    }
    
    
    private func setSoftAP(_ ssid:String, _ password:String, _ channel:String, _ maxConnections:String, _ security:String, _ command:CDVInvokedUrlCommand) {
        
        self.blufiManager?.setWiFiAP(ssid, password, channel, maxConnections, security).done({ (result) in
            
            let response : [String:Any] = [
                "complete": true,
                "error" : "",
                "message": "Configuration complete"
            ]
            
            let pluginResult = CDVPluginResult(
                status: CDVCommandStatus_OK,
                messageAs: response
            )
            self.commandDelegate!.send(
                pluginResult,
                callbackId: command.callbackId
            )
            
            //BOUNCE THE CONNECTION - IOS COREBLUETOOTH BUG
            self.currentCDVCommand = nil;
            self.centralManager.cancelPeripheralConnection(self.currentDevice!)
            self.centralManager.connect(self.currentDevice!, options: nil)
            
            
        }).catch({ (error) in
            
            let response : [String:Any] = [
                "complete": false,
                "error" : error.localizedDescription,
                "message": "Configuration failed"
            ]
            
            let pluginResult = CDVPluginResult(
                status: CDVCommandStatus_ERROR,
                messageAs: response
            )
            self.commandDelegate!.send(
                pluginResult,
                callbackId: command.callbackId
            )
        })
        
        
        
    }
    
    
    private func setStaSoftAP(_ sta_ssid:String, _ sta_password:String, _ ap_ssid:String, _ ap_password:String, _ ap_channel:String, _ ap_maxConnections:String, _ ap_security:String, _ command:CDVInvokedUrlCommand) {
        
        
        self.blufiManager?.setWifiStaSoftAP(sta_ssid, sta_password, ap_ssid, ap_password, ap_channel, ap_maxConnections, ap_security).done({ (result) in
            
            //Give the little chip time to configure :}
            sleep(5)
            
            let response : [String:Any] = [
                "complete": true,
                "error" : "",
                "message": "Configuration complete"
            ]
            
            let pluginResult = CDVPluginResult(
                status: CDVCommandStatus_OK,
                messageAs: response
            )
            self.commandDelegate!.send(
                pluginResult,
                callbackId: command.callbackId
            )
            
            
            //BOUNCE THE CONNECTION - IOS COREBLUETOOTH BUG
            self.currentCDVCommand = nil;
            self.centralManager.cancelPeripheralConnection(self.currentDevice!)
            self.centralManager.connect(self.currentDevice!, options: nil)
            
            
        }).catch({ (error) in
            
            let response : [String:Any] = [
                "complete": false,
                "error" : error.localizedDescription,
                "message": "Configuration failed"
            ]
            
            let pluginResult = CDVPluginResult(
                status: CDVCommandStatus_ERROR,
                messageAs: response
            )
            self.commandDelegate!.send(
                pluginResult,
                callbackId: command.callbackId
            )
        })
        
        
        
    }
    
    
    
    /////// DELEGATES - CoreBluetooth related delegate functions
    
    // Delegate Callback - CBCentralManagerDelegate state update
    func centralManagerDidUpdateState(_ central: CBCentralManager) {
        if central.state == CBManagerState.poweredOn{
            central.scanForPeripherals(withServices: nil, options: nil)
        }
    }
    
    // Delegate Callback - CBCentralManagerDelegate has found a device during search
    func centralManager(_ central: CBCentralManager, didDiscover peripheral: CBPeripheral, advertisementData: [String : Any], rssi RSSI: NSNumber) {
        var foundDevice:Bool = false
        for device in self.devices {
            if device.name == peripheral.name {
                foundDevice = true
                break
            }
        }
        if !foundDevice {
            self.devices.append(peripheral)
        }
    }
    
    // Delegate Callback - Did Discover Services For Peripheral
    func peripheral(_ peripheral: CBPeripheral, didDiscoverServices error: Error?) {
        if let services  = peripheral.services {
            for service in services {
                peripheral.discoverCharacteristics(nil, for: service)
            }
        }
    }
    
    // Delegate Callback - Did Discover Characteristics For Peripheral
    func peripheral(_ peripheral: CBPeripheral, didDiscoverCharacteristicsFor service: CBService, error: Error?) {
        
        if ((error) != nil) {
            print("Error discovering services: \(error!.localizedDescription)")
            return
        }
        
        guard let characteristics = service.characteristics else {
            return
        }
        
        for characteristic in characteristics {
            if characteristic.uuid == self.bluFiDataOutCharsUUID {
                self.dataOutCharacteristic = characteristic
            }
            else if characteristic.uuid == self.bluFiDataInCharsUUID {
                self.dataInCharacteristic = characteristic
            }
        }
        
        self.blufiManager = BluFiManager(peripheral:self.currentDevice!, txCharacteristic:self.dataOutCharacteristic!, rxCharacteristic:self.dataInCharacteristic!)
        self.blufiManager?.negotiate().done({ (result) in })
    }
    
    
}
