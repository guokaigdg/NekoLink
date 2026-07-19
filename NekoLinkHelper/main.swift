import Foundation

final class HelperListenerDelegate: NSObject, NSXPCListenerDelegate {
    func listener(_ listener: NSXPCListener,
                  shouldAcceptNewConnection newConnection: NSXPCConnection) -> Bool {
        let exported = HelperService()
        let interface = NSXPCInterface(with: HelperProtocol.self)
        newConnection.exportedInterface = interface
        newConnection.exportedObject = exported
        newConnection.invalidationHandler = nil
        newConnection.interruptionHandler = nil
        newConnection.resume()
        return true
    }
}

let listener = NSXPCListener(machServiceName: HelperConstants.machServiceName)
let delegate = HelperListenerDelegate()
listener.delegate = delegate
listener.resume()

// 阻塞 main thread
RunLoop.main.run()
