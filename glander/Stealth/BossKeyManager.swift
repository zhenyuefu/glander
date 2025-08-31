import AppKit

#if canImport(Carbon)
@preconcurrency import Carbon

@MainActor final class BossKeyManager {
    private var hotKeyRef: EventHotKeyRef?
    private var eventHandler: EventHandlerRef?
    private var callback: (() -> Void)?

    // No deinit cleanup; explicit callers handle unregister on app shutdown.

    enum KeyCode: UInt32 { case h = 4 /* kVK_ANSI_H */; case space = 49 }

    struct Modifiers: OptionSet {
        let rawValue: UInt32
        init(rawValue: UInt32) { self.rawValue = rawValue }
        static let command = Modifiers(rawValue: UInt32(cmdKey))
        static let option  = Modifiers(rawValue: UInt32(optionKey))
        static let control = Modifiers(rawValue: UInt32(controlKey))
        static let shift   = Modifiers(rawValue: UInt32(shiftKey))
    }

    func register(keyCode: KeyCode, modifiers: Modifiers, _ action: @escaping () -> Void) {
        unregister()
        callback = action
        // Use a distinct signature for boss key to avoid handler clashes
        let hotKeyID = EventHotKeyID(signature: OSType(0x424F5353 as UInt32), id: UInt32(1)) // 'BOSS'
        let status = RegisterEventHotKey(keyCode.rawValue, modifiers.rawValue, hotKeyID, GetEventDispatcherTarget(), 0, &hotKeyRef)
        guard status == noErr, hotKeyRef != nil else {
            #if DEBUG
            print("[BossKey] RegisterEventHotKey failed: status=\(status)")
            #endif
            return
        }
        var eventType = EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed))
        let handler: EventHandlerUPP = { (_, event, userData) -> OSStatus in
            guard let userData else { return noErr }
            let mgr = Unmanaged<BossKeyManager>.fromOpaque(userData).takeUnretainedValue()
            var hkID = EventHotKeyID()
            let size = MemoryLayout<EventHotKeyID>.size
            let err = GetEventParameter(event, EventParamName(kEventParamDirectObject), EventParamType(typeEventHotKeyID), nil, size, nil, &hkID)
            guard err == noErr else { return OSStatus(eventNotHandledErr) }
            // Only respond to our 'BOSS' signature
            let bossSig: OSType = OSType(0x424F5353 as UInt32)
            guard hkID.signature == bossSig else { return OSStatus(eventNotHandledErr) }
            // Invoke directly on main runloop
            assert(Thread.isMainThread)
            mgr.callback?()
            return noErr
        }
        let selfPtr = Unmanaged.passUnretained(self).toOpaque()
        InstallEventHandler(GetEventDispatcherTarget(), handler, 1, &eventType, selfPtr, &eventHandler)
    }

    func unregister() {
        if let ref = hotKeyRef { UnregisterEventHotKey(ref) }
        hotKeyRef = nil
        if let handler = eventHandler { RemoveEventHandler(handler) }
        eventHandler = nil
        callback = nil
    }

    // No additional teardown method needed; deinit is isolated.
}
#else
// 安全降级：若 Carbon 不可用，提供空实现确保可编译
@MainActor final class BossKeyManager {
    enum KeyCode: UInt32 { case h = 4; case space = 49 }
    struct Modifiers: OptionSet { let rawValue: UInt32; init(rawValue: UInt32){ self.rawValue = rawValue }
        static let command = Modifiers(rawValue: 1<<0)
        static let option  = Modifiers(rawValue: 1<<1)
        static let control = Modifiers(rawValue: 1<<2)
        static let shift   = Modifiers(rawValue: 1<<3)
    }
    func register(keyCode: KeyCode, modifiers: Modifiers, _ action: @escaping () -> Void) {
        // no-op; 需要时在 Xcode 中链接 Carbon.framework 以启用
    }
    func unregister() {}
}
#endif
