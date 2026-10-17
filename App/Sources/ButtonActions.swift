import Foundation

/// System-wide media control through the private MediaRemote framework (what Control
/// Center uses). Works on whatever app is playing, if iOS lets a sideloaded app call it.
enum MediaControl {
    enum Command: UInt32 {
        case play = 0, pause = 1, togglePlayPause = 2, next = 4, previous = 5
    }

    private typealias SendCommand = @convention(c) (UInt32, CFDictionary?) -> Bool

    private static let handle = dlopen("/System/Library/PrivateFrameworks/MediaRemote.framework/MediaRemote", RTLD_NOW)

    private static func symbol<T>(_ name: String, as type: T.Type) -> T? {
        guard let handle, let pointer = dlsym(handle, name) else { return nil }
        return unsafeBitCast(pointer, to: type)
    }

    private static let sendCommand = symbol("MRMediaRemoteSendCommand", as: SendCommand.self)

    @discardableResult
    static func send(_ command: Command) -> String {
        guard let sendCommand else { return "MediaRemote not available" }
        return sendCommand(command.rawValue, nil) ? "\(command) sent" : "\(command) REFUSED by iOS"
    }
}

/// What each handlebar button does.
enum ButtonActions {
    static func handle(_ function: ButtonFunction, log: @escaping (String) -> Void) {
        switch function {
        case .select, .back:
            log(MediaControl.send(.togglePlayPause))
        case .next:
            log(MediaControl.send(.next))
        case .previous:
            log(MediaControl.send(.previous))
        default:
            break
        }
    }
}

