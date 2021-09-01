//
//  Copyright © 2019 Gnosis Ltd. All rights reserved.
//

import Foundation
import Starscream

class WebSocketConnection {
    let url: WCURL
    private let socket: WebSocket
    private let onConnect: (() -> Void)?
    private let onDisconnect: ((Error?) -> Void)?
    private let onTextReceive: ((String) -> Void)?
    // needed to keep connection alive
    private var pingTimer: Timer?
    // TODO: make injectable on server creation
    private let pingInterval: TimeInterval = 30

    private var requestSerializer: RequestSerializer = JSONRPCSerializer()
    private var responseSerializer: ResponseSerializer = JSONRPCSerializer()

    // serial queue for receiving the calls.
    private let serialCallbackQueue: DispatchQueue

    var isOpen: Bool

    init(url: WCURL,
         onConnect: (() -> Void)?,
         onDisconnect: ((Error?) -> Void)?,
         onTextReceive: ((String) -> Void)?) {
        self.url = url
        self.onConnect = onConnect
        self.onDisconnect = onDisconnect
        self.onTextReceive = onTextReceive
        self.isOpen = false
        serialCallbackQueue = DispatchQueue(label: "org.walletconnect.swift.connection-\(url.bridgeURL)-\(url.topic)")
        socket = WebSocket(request: URLRequest(url: url.bridgeURL))//url: url.bridgeURL)
        socket.delegate = self
        socket.callbackQueue = serialCallbackQueue
    }

    func open() {
        socket.connect()
    }

    func close() {
        socket.disconnect()
    }

    func send(_ text: String) {
        guard self.isOpen else { return }
        socket.write(string: text)
        log(text)
    }

    private func log(_ text: String) {
        if let request = try? requestSerializer.deserialize(text, url: url).json().string {
            LogService.shared.log("WC: ==> \(request)")
        } else if let response = try? responseSerializer.deserialize(text, url: url).json().string {
            LogService.shared.log("WC: ==> \(response)")
        } else {
            LogService.shared.log("WC: ==> \(text)")
        }
    }
}

extension WebSocketConnection: WebSocketDelegate {
    func didReceive(event: WebSocketEvent, client: WebSocket) {
        print("didReceive event: \(event)")
        switch event {
            case .connected(let dictionary):
                print (dictionary)
                self.isOpen = true
                
                self.pingTimer = Timer.scheduledTimer(withTimeInterval: self.pingInterval, repeats: true) { [weak self] _ in
                    LogService.shared.log("WC: ==> ping")
                    self?.socket.write(ping: Data())
                }
                self.onConnect?()
        case .disconnected(let stringValue, let intValue):
            print ((stringValue, intValue))
            
            self.isOpen = false
            pingTimer?.invalidate()
            self.onDisconnect?(nil)
            
        case .text(let message):
            onTextReceive?(message)
        case .binary(let data):
            print (data)
        case .pong(let data):
            print (data?.count ?? 0)
        case .ping(let data):
            print (data?.count ?? 0)
        case .error(let error):
            self.isOpen = false
            pingTimer?.invalidate()
            print (error?.localizedDescription ?? "")
            self.onDisconnect?(error)
        case .viabilityChanged( let boolValue):
            print (boolValue)
        case .reconnectSuggested(let boolValue):
            print (boolValue)
        case .cancelled:
            self.isOpen = false
            pingTimer?.invalidate()
            
            self.onDisconnect?(nil)
        }
    }
}
