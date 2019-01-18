import Foundation
import CryptoSwift
import PromiseKit
import AwaitKit
import CoreBluetooth

extension Data {
    struct HexEncodingOptions: OptionSet {
        let rawValue: Int
        static let upperCase = HexEncodingOptions(rawValue: 1 << 0)
    }
    
    func toHexString(options: HexEncodingOptions = []) -> String {
        return map { String(format: "%02X", $0) }.joined(separator: " ")
    }
    
}

struct BluFiError: Error {
    var code = 0
    var msg = ""
    public init(_ msg: String) {
        self.msg = msg
    }
    public init(_ code: Int) {
        self.code = code
    }
}

public final class BluFiManager: NSObject, CBPeripheralDelegate {
    
    
    private let DH_P = "cf5cf5c38419a724957ff5dd323b9c45c3cdd261eb740f69aa94b8bb1a5c9640" +
        "9153bd76b24222d03274e4725a5406092e9e82e9135c643cae98132b0d95f7d6" +
        "5347c68afc1e677da90e51bbab5f5cf429c291b4ba39c6b2dc5e8c7231e46aa7" +
    "728e87664532cdf547be20c9a3fa8342be6e34371a27c06f7dc0edddd2f86373"
    
    private let DH_G = "2"
    
    private let DIRECTION_INPUT = 1
    private let DIRECTION_OUTPUT = 0
    private let WRITE_TIMEOUT_SECOND = 30
    private let DEFAULT_PACKAGE_LENGTH = 80
    private let PACKAGE_HEADER_LENGTH = 4
    
    private let ackSem = DispatchSemaphore(value: 0)
    private let readSem = DispatchSemaphore(value: 0)
    private let bleStateSem = DispatchSemaphore(value: 0)
    private let writeLock = DispatchSemaphore(value: 1)
    private var dataRead: [UInt8] = []
    
    private var sendSequence: Int = -1
    private var recvSequence: Int = -1
    
    private var mPackageLengthLimit: Int
    private var requireAck: Bool = false
    private var mNotiData: BlufiNotiData? = nil
    private var secDHKeys: DHKey? = nil
    private var md5SecKey: [UInt8] = []
    private var mEncrypted = false
    private var mChecksum = true
    
    private var device: CBPeripheral?
    private var txCharacteristic:CBCharacteristic?
    private var rxCharacteristic:CBCharacteristic?
    
    private func generateSendSequence() -> Int {
        sendSequence += 1
        print("GENERATE SEND SEQUENCE RESULT : \(sendSequence)")
        return sendSequence
    }
    private func generateReceiveSequence() -> Int {
        recvSequence += 1
        print("GENERATE RECV SEQUENCE RESULT : \(recvSequence)")
        return recvSequence
    }
    
    private func generateAESIV(_ sequence: Int) -> [UInt8] {
        var result: [UInt8] = Array(repeating: 0, count: 16)
        result[0] = UInt8(sequence)
        return result;
    }
    
    private func getTypeValue(type: Int, subtype: Int) -> Int {
        return (subtype << 2) | type
    }
    
    private func getPackageType(typeValue: Int) -> Int {
        return typeValue & 0x3
    }
    
    private func getSubType(typeValue: Int) -> Int {
        return ((typeValue & 0xfc) >> 2)
    }
    
    private func getFrameCtrlValue(encrypt: Bool, checksum: Bool, direction: Int, requireAck: Bool, frag: Bool) -> Int {
        var frame: Int = 0;
        if encrypt {
            frame = frame | (1 << FRAME_CTRL.POSITION_ENCRYPTED);
        }
        if checksum {
            frame = frame | (1 << FRAME_CTRL.POSITION_CHECKSUM);
        }
        if direction == DIRECTION_INPUT {
            frame = frame | (1 << FRAME_CTRL.POSITION_DATA_DIRECTION);
        }
        if requireAck {
            frame = frame | (1 << FRAME_CTRL.POSITION_REQUIRE_ACK);
        }
        if frag {
            frame = frame | (1 << FRAME_CTRL.POSITION_FRAG);
        }
        
        return frame;
    }
    
    private func getPostBytes(type: Int, frameCtrl: Int, sequence: Int, dataLength: Int, data: [UInt8]) -> [UInt8] {
        var byteList = [UInt8]()
        byteList.append(UInt8(type))
        byteList.append(UInt8(frameCtrl))
        byteList.append(UInt8(sequence))
        
        let frameCtrlData = FrameCtrlData(frameCtrlValue: frameCtrl)
        var checksumBytes: [UInt8] = []
        var resultData = data;
        var pkgLen = dataLength
        if frameCtrlData.hasFrag() {
            pkgLen += 2
        }
        byteList.append(UInt8(pkgLen))
        
        if frameCtrlData.isChecksum() {
            
            var checkByteList: [UInt8] = []
            checkByteList.append(UInt8(sequence));
            checkByteList.append(UInt8(pkgLen));
            checkByteList.append(contentsOf: data)
            checksumBytes = CRC.getCRC16(data_p: checkByteList)
        }
        
        if frameCtrlData.isEncrypted() && data.count > 0 {
            do {
                let iv = generateAESIV(sequence)
                let aes = try AES(key: md5SecKey, blockMode: CFB(iv: iv), padding: .noPadding)
                resultData = try aes.encrypt(data)
            } catch {
                resultData = data
            }
            
        }
        byteList.append(contentsOf: resultData)
        if frameCtrlData.isChecksum() {
            byteList.append(contentsOf: checksumBytes)
        }
        return byteList
    }
    
    //DEBUG ONLY - uncomment sequence reset
    private func resetSeq() {
        // sendSequence = -1
        // recvSequence = -1
    }
    
    private func read(_ timeout_sec: Int) -> Promise<BlufiNotiData> {
        return Promise {
            let blufiData: BlufiNotiData = BlufiNotiData()
            while true {
                let timeout = DispatchTime.now() + .seconds(timeout_sec)
                if readSem.wait(timeout: timeout) != .success {
                    return $0.reject(BluFiError("Timeout"))
                }
                
                if dataRead.count < 4 {
                    return $0.reject(BluFiError("Invalid response data"))
                }
                
                let parse = parseNotification(data: dataRead, notification: blufiData)
                if parse < 0 {
                    return $0.reject(BluFiError("Error parse data"))
                } else if parse == 0 {
                    return $0.resolve(blufiData, nil)
                }
            }
        }
    }
    
    // Write raw data without response
    private func writeRaw(_ data: [UInt8]) -> Promise<Bool> {
        return Promise {
            if data.count ==  0 {
                return $0.reject(BluFiError("Invalid write data"))
            }
            let needWrite = Data.init(bytes: UnsafePointer<UInt8>(data), count: data.count)
            writeLock.wait()
            writeToBluetooth(data:needWrite)
            writeLock.signal()
            return $0.resolve(true, nil)
        }
    }
    
    // Write raw data and wait for response
    private func write(_ data: [UInt8], _ timeoutSec: Int, _ needResponse: Bool) -> Promise<BlufiNotiData> {
        return async {
            try await(self.writeRaw(data))
            if self.requireAck {
                let bluFiData = try await(self.read(timeoutSec))
                let ackSeq = self.getAckSeq(bluFiData)
                if ackSeq != self.sendSequence - 1 {
                    throw BluFiError("Invalid ACK Seq, send seq = \(self.sendSequence), ack Seq = \(ackSeq)")
                }
            }
            if !needResponse {
                return BlufiNotiData()
            }
            return try await(self.read(timeoutSec))
        }
    }
    
    // Write data frame and wait for response
    private func writeFrame(_ type: Int, _ data: [UInt8], _ timeoutSec: Int,  _ needResponse: Bool) -> Promise<BlufiNotiData> {
        return async {
            var dataRemain = data
            repeat {
                
                var postDataLengthLimit = self.mPackageLengthLimit - self.PACKAGE_HEADER_LENGTH;
                if self.mChecksum {
                    postDataLengthLimit -= 2
                }
                
                if dataRemain.count > postDataLengthLimit {
                    let frameCtrl = self.getFrameCtrlValue(encrypt: self.mEncrypted,
                                                           checksum: self.mChecksum,
                                                           direction: self.DIRECTION_OUTPUT,
                                                           requireAck: self.requireAck,
                                                           frag: true)
                    let sequence = self.generateSendSequence()
                    let totleLen = dataRemain.count
                    let totleLen1 = totleLen & 0xff
                    let totleLen2 = (totleLen >> 8) & 0xff
                    var partToWrite = dataRemain[0..<postDataLengthLimit]
                    let partRemain = dataRemain[postDataLengthLimit...]
                    
                    partToWrite.insert(UInt8(totleLen2), at: 0)
                    partToWrite.insert(UInt8(totleLen1), at: 0)
                    
                    
                    let postBytes = self.getPostBytes(type: type,
                                                      frameCtrl: frameCtrl,
                                                      sequence: sequence,
                                                      dataLength: postDataLengthLimit,
                                                      data: Array(partToWrite))
                    _ = try await(self.write(postBytes, timeoutSec, false))
                    dataRemain = Array(partRemain)
                } else {
                    let frameCtrl = self.getFrameCtrlValue(encrypt: self.mEncrypted,
                                                           checksum: self.mChecksum,
                                                           direction: self.DIRECTION_OUTPUT,
                                                           requireAck: self.requireAck,
                                                           frag: false)
                    let sequence = self.generateSendSequence()
                    
                    let postBytes = self.getPostBytes(type: type,
                                                      frameCtrl: frameCtrl,
                                                      sequence: sequence,
                                                      dataLength: dataRemain.count,
                                                      data: dataRemain)
                    let result = try await(self.write(postBytes, timeoutSec, needResponse))
                    return result;
                }
            } while true
        }
        
    }
    
    
    public func negotiate() -> Promise<Bool> {
        return async {
            /* 1. Write package length */
            let type = self.getTypeValue(type: Type.Data.PACKAGE_VALUE, subtype: Type.Data.SUBTYPE_NEG)
            self.secDHKeys = DHKeyExchange.genDHExchangeKeys(generator: self.DH_G, primeNumber: self.DH_P)
            let pKey = DHKey.hexStringToBytes(self.DH_P)
            let gKey = DHKey.hexStringToBytes(self.DH_G)
            let kKey = self.secDHKeys!.publicKeyAsArray()
            let pgkLength = pKey.count + gKey.count + kKey.count + 6
            let pgkLen1 = UInt8((pgkLength >> 8) & 0xff)
            let pgkLen2 = UInt8(pgkLength & 0xff)
            
            var dataList: [UInt8] = [UInt8(NEG_SET_SEC.TOTAL_LEN), pgkLen1, pgkLen2]
            _ = try await(self.writeFrame(type, dataList, self.WRITE_TIMEOUT_SECOND, false))
            
            /* Write package data */
            dataList = [UInt8(NEG_SET_SEC.ALL_DATA)]
            dataList.append(UInt8((pKey.count >> 8) & 0xff))
            dataList.append(UInt8(pKey.count & 0xff))
            dataList.append(contentsOf: pKey)
            
            dataList.append(UInt8((gKey.count >> 8) & 0xff))
            dataList.append(UInt8(gKey.count & 0xff))
            dataList.append(contentsOf: gKey)
            
            dataList.append(UInt8((kKey.count >> 8) & 0xff))
            dataList.append(UInt8(kKey.count & 0xff))
            dataList.append(contentsOf: kKey)
            let respData = try await(self.writeFrame(type, dataList, self.WRITE_TIMEOUT_SECOND, true))
            
            /* Read and parse response, process security data */
            if !self.validPackage(respData, Type.Data.PACKAGE_VALUE, Type.Data.SUBTYPE_NEG) {
                self.resetSeq()
                throw BluFiError("Invalid response")
            }
            
            let data = respData.getDataArray()
            let keyStr = data.map{String(format: "%02X", $0)}.joined(separator: "")
            let privatedDHKey = (self.secDHKeys?.privateKey)!
            
            let cryptoDHKey = DHKeyExchange.genDHCryptoKey(
                privateDHKey: privatedDHKey,
                serverPublicDHKey: keyStr,
                primeNumber: self.DH_P)
            let md5 = MD5()
            self.md5SecKey = md5.calculate(for: DHKey.hexStringToBytes(cryptoDHKey))
            self.mEncrypted = true
            self.mChecksum = true
            
            /* Set security */
            let secType = self.getTypeValue(type: Type.Ctrl.PACKAGE_VALUE, subtype: Type.Ctrl.SUBTYPE_SET_SEC_MODE)
            var secData = 0
            // data checksum
            secData = secData | 1
            
            // data Encrypt
            secData = secData | (1 << 1)
            
            let postData: [UInt8] = [UInt8(secData)]
            _ = try await(self.writeFrame(secType, postData, self.WRITE_TIMEOUT_SECOND, false))
            return true
        }
    }
    
    public func writeCustomData(_ data: [UInt8], _ needResponse: Bool) -> Promise<[UInt8]> {
        return async {
            let type = self.getTypeValue(type: Type.Data.PACKAGE_VALUE, subtype: Type.Data.SUBTYPE_CUSTOM_DATA)
            let respData = try await(self.writeFrame(type, data, self.WRITE_TIMEOUT_SECOND, needResponse))
            if !needResponse {
                return []
            }
            if !self.validPackage(respData, Type.Data.PACKAGE_VALUE, Type.Data.SUBTYPE_CUSTOM_DATA) {
                self.resetSeq()
                throw BluFiError("Invalid response for custom data")
            }
            
            return respData.getDataArray()
        }
    }
    
    public func getWiFiScanList() -> Promise<[WiFiEntry]> {
        return async {
            let type = self.getTypeValue(type: Type.Ctrl.PACKAGE_VALUE, subtype: Type.Ctrl.SUBTYPE_GET_WIFI_LIST)
            let respData = try await(self.writeFrame(type, [], self.WRITE_TIMEOUT_SECOND, true))
            
            if !self.validPackage(respData, Type.Data.PACKAGE_VALUE, Type.Data.SUBTYPE_WIFI_LIST) {
                self.resetSeq()
                throw BluFiError("Invalid response for getWiFiScanList")
            }
            let arrList = respData.getDataArray()
            var strList = [WiFiEntry]()
            var idx = 0
            while idx <  arrList.count {
                let len = Int(arrList[idx+0])
                let rssi = Int8(bitPattern: arrList[idx+1])
                let offsetBegin = idx + 2
                let offsetEnd = idx + len + 1
                if offsetEnd > arrList.count {
                    throw BluFiError("Invalid wifi list array len")
                }
                let nameArr = Array(arrList[offsetBegin..<offsetEnd])
                let name = String(bytes: nameArr, encoding: .utf8)
                strList.append(WiFiEntry(name!, rssi))
                idx = offsetEnd
            }
            return strList
        }
    }
    
    public func getDeviceVersion() -> Promise<[UInt8]> {
        return async {
            let type = self.getTypeValue(type: Type.Ctrl.PACKAGE_VALUE, subtype: Type.Ctrl.SUBTYPE_GET_VERSION)
            let respData = try await(self.writeFrame(type, [], self.WRITE_TIMEOUT_SECOND, true))
            
            if !self.validPackage(respData, Type.Data.PACKAGE_VALUE, Type.Data.SUBTYPE_VERSION) {
                self.resetSeq()
                throw BluFiError("Invalid response for getDeviceVersion")
            }
            let versionData = respData.getDataArray()
            if versionData.count != 2 {
                throw BluFiError("Invalid version format")
            }
            return versionData
        }
    }
    
    public func getDeviceStatus() -> Promise<[UInt8]> {
        return async {
            let type = self.getTypeValue(type: Type.Ctrl.PACKAGE_VALUE, subtype: Type.Ctrl.SUBTYPE_GET_WIFI_STATUS)
            let respData = try await(self.writeFrame(type, [], self.WRITE_TIMEOUT_SECOND, true))
            if !self.validPackage(respData, Type.Data.PACKAGE_VALUE, Type.Data.SUBTYPE_WIFI_CONNECTION_STATE) {
                self.resetSeq()
                throw BluFiError("Invalid response for getDeviceStatus")
            }
            return respData.getDataArray()
        }
    }
    
    
    
    public func setWiFiSta(_ ssid: String, _ password: String) -> Promise<[UInt8]> {
        return async {
            
            var  type = self.getTypeValue(type: Type.Ctrl.PACKAGE_VALUE, subtype: Type.Ctrl.SUBTYPE_SET_OP_MODE)
            _ = try await(self.writeFrame(type, [UInt8(OP_MODE.STA)], self.WRITE_TIMEOUT_SECOND, false))
            
            type = self.getTypeValue(type: Type.Data.PACKAGE_VALUE, subtype: Type.Data.SUBTYPE_STA_WIFI_SSID)
            _ = try await(self.writeFrame(type, [UInt8](ssid.utf8), self.WRITE_TIMEOUT_SECOND, false))
            
            type = self.getTypeValue(type: Type.Data.PACKAGE_VALUE, subtype: Type.Data.SUBTYPE_STA_WIFI_PASSWORD)
            _ = try await(self.writeFrame(type, [UInt8](password.utf8), self.WRITE_TIMEOUT_SECOND, false))
            
            type = self.getTypeValue(type: Type.Ctrl.PACKAGE_VALUE, subtype: Type.Ctrl.SUBTYPE_CONNECT_WIFI)
            let respData = try await(self.writeFrame(type, [UInt8](password.utf8), self.WRITE_TIMEOUT_SECOND, true))
            
            if !self.validPackage(respData, Type.Data.PACKAGE_VALUE, Type.Data.SUBTYPE_WIFI_CONNECTION_STATE) {
                self.resetSeq()
                throw BluFiError("Invalid response for WiFi status")
            }
            let dataArray = respData.getDataArray()
            if dataArray.count < 3 {
                throw BluFiError("Invalid data size")
            }
            return respData.getDataArray()
        }
    }
    
    
    public func setWiFiAP(_ ssid: String, _ password: String, _ channel: String, _ maxConnections: String, _ security: String) -> Promise<[UInt8]> {
        return async {
            
            var  type = self.getTypeValue(type: Type.Ctrl.PACKAGE_VALUE, subtype: Type.Ctrl.SUBTYPE_SET_OP_MODE)
            _ = try await(self.writeFrame(type, [UInt8(OP_MODE.SOFTAP)], self.WRITE_TIMEOUT_SECOND, false))
            
            
            type = self.getTypeValue(type: Type.Data.PACKAGE_VALUE, subtype: Type.Data.SUBTYPE_SOFTAP_WIFI_SSID)
            _ = try await(self.writeFrame(type, [UInt8](ssid.utf8), self.WRITE_TIMEOUT_SECOND, false))
            
            if security != "open" {
                type = self.getTypeValue(type: Type.Data.PACKAGE_VALUE, subtype: Type.Data.SUBTYPE_SOFTAP_WIFI_PASSWORD)
                _ = try await(self.writeFrame(type, [UInt8](password.utf8), self.WRITE_TIMEOUT_SECOND, false))
            }
            
            if Int(channel)! > 0 {
                type = self.getTypeValue(type: Type.Data.PACKAGE_VALUE, subtype: Type.Data.SUBTYPE_SOFTAP_CHANNEL)
                _ = try await(self.writeFrame(type, [UInt8(channel)!], self.WRITE_TIMEOUT_SECOND, false))
            }
            
            if Int(maxConnections)! > 0 {
                type = self.getTypeValue(type: Type.Data.PACKAGE_VALUE, subtype: Type.Data.SUBTYPE_SOFTAP_MAX_CONNECTION_COUNT)
                _ = try await(self.writeFrame(type, [UInt8(maxConnections)!], self.WRITE_TIMEOUT_SECOND, false))
            }
            
            
            var softAPSecurity = SOFTAP_SECURITY.OPEN
            switch security {
            case "open" : softAPSecurity = SOFTAP_SECURITY.OPEN
            case "wpa-psk" : softAPSecurity = SOFTAP_SECURITY.WPA
            case "wpa2-psk" : softAPSecurity = SOFTAP_SECURITY.WPA2
            case "wpa-wap2-psk" : softAPSecurity = SOFTAP_SECURITY.WPA_WPA2
            default:softAPSecurity = SOFTAP_SECURITY.OPEN
            }
            
            type = self.getTypeValue(type: Type.Data.PACKAGE_VALUE, subtype: Type.Data.SUBTYPE_SOFTAP_AUTH_MODE)
            _ = try await(self.writeFrame(type, [UInt8(softAPSecurity)], self.WRITE_TIMEOUT_SECOND, false))
            
            
            type = self.getTypeValue(type: Type.Ctrl.PACKAGE_VALUE, subtype: Type.Ctrl.SUBTYPE_GET_WIFI_STATUS)
            let respData = try await(self.writeFrame(type, [UInt8](password.utf8), self.WRITE_TIMEOUT_SECOND, true))
            
            if !self.validPackage(respData, Type.Data.PACKAGE_VALUE, Type.Data.SUBTYPE_WIFI_CONNECTION_STATE) {
                self.resetSeq()
                throw BluFiError("Invalid response for WiFi status")
            }
            let dataArray = respData.getDataArray()
            if dataArray.count < 3 {
                throw BluFiError("Invalid data size")
            }
            return respData.getDataArray()
        }
    }
    
    
    public func setWifiStaSoftAP(_ sta_ssid:String, _ sta_password:String, _ ap_ssid:String, _ ap_password:String, _ ap_channel:String, _ ap_maxConnections:String, _ ap_security:String) -> Promise<[UInt8]> {
        return async {
            
            var  type = self.getTypeValue(type: Type.Ctrl.PACKAGE_VALUE, subtype: Type.Ctrl.SUBTYPE_SET_OP_MODE)
            _ = try await(self.writeFrame(type, [UInt8(OP_MODE.STASOFTAP)], self.WRITE_TIMEOUT_SECOND, false))
            
            type = self.getTypeValue(type: Type.Data.PACKAGE_VALUE, subtype: Type.Data.SUBTYPE_STA_WIFI_SSID)
            _ = try await(self.writeFrame(type, [UInt8](sta_ssid.utf8), self.WRITE_TIMEOUT_SECOND, false))
            
            type = self.getTypeValue(type: Type.Data.PACKAGE_VALUE, subtype: Type.Data.SUBTYPE_STA_WIFI_PASSWORD)
            _ = try await(self.writeFrame(type, [UInt8](sta_password.utf8), self.WRITE_TIMEOUT_SECOND, false))
            
            type = self.getTypeValue(type: Type.Ctrl.PACKAGE_VALUE, subtype: Type.Ctrl.SUBTYPE_CONNECT_WIFI)
            _ = try await(self.writeFrame(type, [UInt8](sta_password.utf8), self.WRITE_TIMEOUT_SECOND, false))
            
            type = self.getTypeValue(type: Type.Data.PACKAGE_VALUE, subtype: Type.Data.SUBTYPE_SOFTAP_WIFI_SSID)
            _ = try await(self.writeFrame(type, [UInt8](ap_ssid.utf8), self.WRITE_TIMEOUT_SECOND, false))
            
            if ap_security != "open" {
                type = self.getTypeValue(type: Type.Data.PACKAGE_VALUE, subtype: Type.Data.SUBTYPE_SOFTAP_WIFI_PASSWORD)
                _ = try await(self.writeFrame(type, [UInt8](ap_password.utf8), self.WRITE_TIMEOUT_SECOND, false))
            }
            
            if Int(ap_channel)! > 0 {
                type = self.getTypeValue(type: Type.Data.PACKAGE_VALUE, subtype: Type.Data.SUBTYPE_SOFTAP_CHANNEL)
                _ = try await(self.writeFrame(type, [UInt8(ap_channel)!], self.WRITE_TIMEOUT_SECOND, false))
            }
            
            if Int(ap_maxConnections)! > 0 {
                type = self.getTypeValue(type: Type.Data.PACKAGE_VALUE, subtype: Type.Data.SUBTYPE_SOFTAP_MAX_CONNECTION_COUNT)
                _ = try await(self.writeFrame(type, [UInt8(ap_maxConnections)!], self.WRITE_TIMEOUT_SECOND, false))
            }
            
            var softAPSecurity = SOFTAP_SECURITY.OPEN
            switch ap_security {
            case "open" : softAPSecurity = SOFTAP_SECURITY.OPEN
            case "wpa-psk" : softAPSecurity = SOFTAP_SECURITY.WPA
            case "wpa2-psk" : softAPSecurity = SOFTAP_SECURITY.WPA2
            case "wpa-wap2-psk" : softAPSecurity = SOFTAP_SECURITY.WPA_WPA2
            default:softAPSecurity = SOFTAP_SECURITY.OPEN
            }
            
            type = self.getTypeValue(type: Type.Data.PACKAGE_VALUE, subtype: Type.Data.SUBTYPE_SOFTAP_AUTH_MODE)
            _ = try await(self.writeFrame(type, [UInt8(softAPSecurity)], self.WRITE_TIMEOUT_SECOND, false))
            
            
            type = self.getTypeValue(type: Type.Ctrl.PACKAGE_VALUE, subtype: Type.Ctrl.SUBTYPE_GET_WIFI_STATUS)
            let respData = try await(self.writeFrame(type, [UInt8](ap_password.utf8), self.WRITE_TIMEOUT_SECOND, true))
            
            if !self.validPackage(respData, Type.Data.PACKAGE_VALUE, Type.Data.SUBTYPE_WIFI_CONNECTION_STATE) {
                self.resetSeq()
                throw BluFiError("Invalid response for WiFi status")
            }
            let dataArray = respData.getDataArray()
            if dataArray.count < 3 {
                throw BluFiError("Invalid data size")
            }
            
            return respData.getDataArray()
        }
    }
    
    
    private func getAckSeq(_ bluFiData: BlufiNotiData) -> Int {
        let pkgType = bluFiData.getPkgType()
        let subType = bluFiData.getSubType()
        let data = bluFiData.getDataArray()
        if (data.count < 1) {
            return -1
        }
        if pkgType == Type.Ctrl.PACKAGE_VALUE &&
            subType == Type.Ctrl.SUBTYPE_ACK {
            return Int(data[0] & 0xff)
        }
        return -1
    }
    
    private func validPackage(_ blufiData: BlufiNotiData, _ type: Int, _ subType: Int) -> Bool {
        let pkgType = blufiData.getPkgType()
        let sType = blufiData.getSubType()
        if pkgType != type || subType != sType {
            return false
        }
        return true
    }
    
    
    
    public init(peripheral:CBPeripheral, txCharacteristic:CBCharacteristic, rxCharacteristic:CBCharacteristic) {
        
        self.device = peripheral;
        self.txCharacteristic =  txCharacteristic;
        self.rxCharacteristic =  rxCharacteristic;
        
        self.mPackageLengthLimit = DEFAULT_PACKAGE_LENGTH
        
        super.init()
        self.device!.delegate = self;
        
    }
    
    private func writeToBluetooth(data:Data) {
        self.device!.writeValue(data, for: self.txCharacteristic!, type: CBCharacteristicWriteType.withResponse)
    }
    
    
    public func readFromBluetooth(_ data: Data) -> Void {
        let resultBytes:[UInt8] = Array(UnsafeBufferPointer(start: (data as NSData).bytes.bindMemory(to: UInt8.self, capacity: data.count), count: data.count))
        dataRead = resultBytes
        readSem.signal()
    }
    
    public func peripheral(_ peripheral: CBPeripheral, didWriteValueFor characteristic: CBCharacteristic, error: Error?) {
        
        if let error = error {
            print("error: \(error)")
            return
        }
        
        let data = characteristic.value
        
        self.device!.readValue(for:self.rxCharacteristic!)
        self.device!.setNotifyValue(true, for: self.rxCharacteristic!)
        
    }
    
    
    public func peripheral(_ peripheral: CBPeripheral, didUpdateValueFor characteristic: CBCharacteristic, error: Error?) {
        
        if let error = error {
            print("error: \(error)")
            return
        }
        
        let data = characteristic.value
        
        if data != nil && data!.count > 1 {
            let resultBytes:[UInt8] = Array(UnsafeBufferPointer(start: (data! as NSData).bytes.bindMemory(to: UInt8.self, capacity: data!.count), count: data!.count))
            dataRead = resultBytes
            readSem.signal()
        }
    }
    
    
    public func peripheral(_ peripheral: CBPeripheral, didUpdateNotificationStateFor characteristic: CBCharacteristic, error: Error?) {
        
        if let error = error {
            print("error: \(error)")
            return
        }
        
        let data = characteristic.value
        
        if data != nil && data!.count > 1 {
            let resultBytes:[UInt8] = Array(UnsafeBufferPointer(start: (data! as NSData).bytes.bindMemory(to: UInt8.self, capacity: data!.count), count: data!.count))
            dataRead = resultBytes
            readSem.signal()
        }
    }
    
    private func parseNotification(data: [UInt8], notification: BlufiNotiData) -> Int {
        
        
        if data == nil {
            print("parseNotification data is NIL - Returning -1")
            return -1
        }
        
        if data.count < 4 {
            print("parseNotification data length less than 4")
            return -2;
        }
        
        let sequence = Int(data[2])
        let recvSeq = generateReceiveSequence()
        
        
        if sequence != recvSeq {
            print("wrong recvSEQ=\(sequence), appSEQ=\(recvSeq)")
            return -3
        }
        
        let type = Int(data[0])
        let pkgType = getPackageType(typeValue: type)
        let subType = getSubType(typeValue: type)
        
        notification.setType(typeValue: type)
        notification.setPkgType(pkgType: pkgType)
        notification.setSubType(subType: subType)
        
        let frameCtrl = Int(data[1])
        notification.setFrameCtrl(frameCtrl: frameCtrl)
        let frameCtrlData = FrameCtrlData(frameCtrlValue: frameCtrl)
        let dataLength = Int(data[3])
        var dataOffset = 4
        let cryptedDataBytes = Array(data[dataOffset..<dataOffset + dataLength])
        var dataBytes = cryptedDataBytes
        
        if frameCtrlData.isEncrypted() {
            do {
                let iv = generateAESIV(sequence)
                let aes = try AES(key: md5SecKey, blockMode: CFB(iv: iv), padding: .noPadding)
                dataBytes = try aes.decrypt(cryptedDataBytes)
            } catch {
                print("Error decrypt data")
            }
        }

        if frameCtrlData.hasFrag() {
            dataOffset = 2
        } else {
            dataOffset = 0
        }
        
        if frameCtrlData.isChecksum() {
            let respChecksum1 = data[data.count - 2]
            let respChecksum2 = data[data.count - 1]
            
            var checkByteList: [UInt8] = []
            checkByteList.append(UInt8(sequence));
            checkByteList.append(UInt8(dataLength));
            checkByteList.append(contentsOf: Array(dataBytes))
            let checksumBytes = CRC.getCRC16(data_p: checkByteList)
            if respChecksum1 != checksumBytes[0] || respChecksum2 != checksumBytes[1] {
                print("Invalid checksum, calc: \(checksumBytes.toHexString()) from data: \(String(format: "%02hhX", respChecksum1)) \(String(format: "%02hhX", respChecksum2))")
                return -1
            }
        }
        
        
        var notificationData = dataBytes
        if dataOffset > 0 {
            notificationData = Array(dataBytes[dataOffset...])
        }
        
        notification.addData(bytes: notificationData)
        return frameCtrlData.hasFrag() ? 1 : 0
    }
}



