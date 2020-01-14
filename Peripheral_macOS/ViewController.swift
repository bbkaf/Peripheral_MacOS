//
//  ViewController.swift
//  Peripheral_macOS
//
//  Created by HankTseng on 2020/1/13.
//  Copyright © 2020 HyerDesign. All rights reserved.
//

import Cocoa
import CoreBluetooth

class ViewController: NSViewController, CBPeripheralManagerDelegate {

    enum SendDataError: Error {
        case CharacteristicNotFound
    }

    let UUID_SERVICE = "A001"

    let UUID_CHARACTERISTIC = "C001"

    var peripheralManager = CBPeripheralManager()

    var charDic = [String: CBMutableCharacteristic]()

    @IBOutlet var textView: NSTextView!

    @IBOutlet weak var textField: NSTextField!



    override func viewDidLoad() {
        super.viewDidLoad()
        let queue = DispatchQueue.global()

        // queue 代表 CBPeripheralManagerDelegate 回來的 delegate method 要在哪個queue執行，寫nil到表在mainthread
        //觸發 1# method
        peripheralManager = CBPeripheralManager(delegate: self, queue: queue)
    }

    @IBAction func snedClick(_ sender: NSButton) {
        let string = textField.stringValue
        if self.textView.string ?? "" == "" {
            self.textView.string = string
        } else {
            self.textView.string += "\n\(string)"
        }
        do {
            try self.sendData(string.data(using: .utf8)!, uuidString: UUID_CHARACTERISTIC)
        } catch {
            print(error)
        }
        self.textField.stringValue = ""
    }

    override var representedObject: Any? {
        didSet {
        }
    }

    //MARK: - 1# method (delegate method)
    func peripheralManagerDidUpdateState(_ peripheral: CBPeripheralManager) {
        //先判斷藍牙是否開啟，如果不是藍芽4.x也會回傳電源未開啟
        guard peripheral.state == .poweredOn else {
            //iOS預設會跳警告訊息
            return
        }

        var service: CBMutableService
        var characteristic: CBMutableCharacteristic
        var charArray = [CBCharacteristic]()

        //設定service, primary 主要or次要服務
        service = CBMutableService(type: CBUUID(string: UUID_SERVICE), primary: true)

        //設定characteristic
        /*
         properties:
         .notifyEncryptionRequired: peripheral送加密資料到central, 加密就會先跳配對
         .notify: peripheral送資料到central,
         write: 讓central端送到peripheral, peripheral端收到資料要回傳給central端, central才會在送第二筆資料，不然central端會卡住
         writeWithoutResponse: 讓central端有資料就送到Peripheral端，不管central端有沒有回應，central端不會被卡住
         */

        /*
         permissions:
         對剛剛properties的write or notify 做設定，當只有一個餐數的時候，可以不用awrray
         writeEncryptionRequired: central端送資料到Peripheral端要加密，會先跳配對
         */
        characteristic = CBMutableCharacteristic(type: CBUUID(string: UUID_CHARACTERISTIC),
                                                 properties: [.notifyEncryptionRequired, .writeWithoutResponse],
                                                 value: nil,
                                                 permissions: .writeEncryptionRequired)

        charArray.append(characteristic)
        charDic[UUID_CHARACTERISTIC] = characteristic

        //一個 service可以包含很多characteristic
        service.characteristics = charArray

        //觸發 2# method, 整個GATT設定完成
        peripheralManager.add(service)

    }

    //MARK: - 2# method (delegate method)
    func peripheralManager(_ peripheral: CBPeripheralManager, didAdd service: CBService, error: Error?) {
        guard error == nil else {
            print("ERROR: {\(#file), \(#function)}\n")
            print(error!.localizedDescription)
            return
        }

        //為藍芽裝置命名，iOS, macOS 時常失效，會取到設定裡設定的裝置名稱
        let deviceName = "peripheral_macOS"

        //開始廣播，讓Central端可以掃描到Peripheral端資訊，廣播的內容有這個裝置的service，以及Peripheral的名字
        //觸發3# method
        peripheralManager.startAdvertising([CBAdvertisementDataServiceUUIDsKey: [service.uuid],
                                            CBAdvertisementDataLocalNameKey: ""])

    }

    //MARK: - 3# method (delegate method)
    func peripheralManagerDidStartAdvertising(_ peripheral: CBPeripheralManager, error: Error?) {
        print("start Advertising")
    }

    //MARK: - 處理接受訂閱與取消訂閱
    //Peripheral端透過notify主動把資料送到Central端，但是Central端不一定要會真的接收到
    //，Central端必須向peripheral端訂閱資料這麼一來Peripheral端notify到Central端的資料才會真正被收到
    //，意思是Peripheral端只要在資料有被Central端訂閱的時候再notify就好，智慧手環只在有手機訂閱他的步數or心律等資料時，手環才推送(notify)相關資料

    //MARK: - 處理受到訂閱 (delegate method)
    func peripheralManager(_ peripheral: CBPeripheralManager, central: CBCentral, didSubscribeTo characteristic: CBCharacteristic) {
        //這邊會處理訂閱後的狀況，這個例子來說有Central訂閱了，那我(Peripheral)就停止推送廣告封包，以避免其他Central端繼續掃描到此Peripheral進行配對，
        //停止廣告封包的時機看每個專案的設計
        if peripheral.isAdvertising {
            peripheral.stopAdvertising()
        }
        if characteristic.uuid.uuidString == UUID_CHARACTERISTIC {

        }
    }

    //MARK: - 處理被取消訂閱 (delegate method)
    func peripheralManager(_ peripheral: CBPeripheralManager, central: CBCentral, didUnsubscribeFrom characteristic: CBCharacteristic) {
        if characteristic.uuid.uuidString == UUID_CHARACTERISTIC {

        }
    }

    //MARK: - 送資料到Central (custom method)
    func sendData(_ data: Data, uuidString: String) throws {
        guard let characteristic = charDic[uuidString] else {
            throw SendDataError.CharacteristicNotFound
        }
        //onSubscribedCentrals: 選擇要推送給那個central端，寫nil就是都送
        peripheralManager.updateValue(data, for: characteristic, onSubscribedCentrals: nil)

    }

    //MARK: - 讀取 Central端送來的資料 (delegate method)
    func peripheralManager(_ peripheral: CBPeripheralManager, didReceiveWrite requests: [CBATTRequest]) {
        guard let at = requests.first else {
            return
        }

        guard let data = at.value else {
            return
        }

        //當 Characteristic的properties裡面是.write時要傳'已讀'給Central不然Central會卡住
        //，若是.writeWithoutResponse，則不需要.respond(to...
        //peripheral.respond(to: at, withResult: .success)

        //回到主線程，因為我們設定藍芽回傳delegate mothod用global queue處理
        DispatchQueue.main.async {
            let string = String(data: data, encoding: .utf8) ?? "error string"
            if self.textView.string ?? "" == "" {
                self.textView.string = string
            } else {
                self.textView.string += "\n\(string)"
            }
            print("didReceiveWrite from central: " + string)
        }
    }

    //MARK: - 回覆Central要求的資料 (delegate method)
    func peripheralManager(_ peripheral: CBPeripheralManager, didReceiveRead request: CBATTRequest) {
        if request.characteristic.uuid.uuidString == "" {
            let data = "heartRate: 62".data(using: .utf8)
            request.value = data
        }
        peripheral.respond(to: request, withResult: .success)
    }

}


