import AppKit

#if canImport(Carbon)
@preconcurrency import Carbon

final class GlobalHotkeys {
    enum KeyCode: UInt32 { case left = 123, right = 124 }
    struct Modifiers: OptionSet {
        let rawValue: UInt32
        init(rawValue: UInt32) { self.rawValue = rawValue }
        static let command = Modifiers(rawValue: UInt32(cmdKey))
        static let option  = Modifiers(rawValue: UInt32(optionKey))
        static let control = Modifiers(rawValue: UInt32(controlKey))
        static let shift   = Modifiers(rawValue: UInt32(shiftKey))
    }

    private var hotKeys: [UInt32: EventHotKeyRef] = [:]
    private var callbacks: [UInt32: () -> Void] = [:]
    private var eventHandler: EventHandlerRef?
    private var nextID: UInt32 = 1

    deinit { unregisterAll() }

    @discardableResult
    func register(keyCode: KeyCode, modifiers: Modifiers, _ action: @escaping () -> Void) -> Bool {
        return registerRaw(keyCode: keyCode.rawValue, modifiers: modifiers, action)
    }

    @discardableResult
    func registerRaw(keyCode: UInt32, modifiers: Modifiers, _ action: @escaping () -> Void) -> Bool {
        let hkID = EventHotKeyID(signature: OSType(0x474C4E44 as UInt32) /* 'GLND' */, id: nextID)
        var ref: EventHotKeyRef?
        // Register against the Event Dispatcher to receive when app is inactive
        let status = RegisterEventHotKey(keyCode, modifiers.rawValue, hkID, GetEventDispatcherTarget(), 0, &ref)
        guard status == noErr, let ref else { return false }
        hotKeys[nextID] = ref
        callbacks[nextID] = action
        nextID &+= 1
        installHandlerIfNeeded()
        return true
    }

    func unregisterAll() {
        for (_, ref) in hotKeys { UnregisterEventHotKey(ref) }
        hotKeys.removeAll()
        callbacks.removeAll()
        if let h = eventHandler { RemoveEventHandler(h) }
        eventHandler = nil
    }

    private func installHandlerIfNeeded() {
        guard eventHandler == nil else { return }
        var eventType = EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed))
        let handler: EventHandlerUPP = { (next, event, userData) -> OSStatus in
            guard let userData else { return noErr }
            let mgr = Unmanaged<GlobalHotkeys>.fromOpaque(userData).takeUnretainedValue()
            var hkID = EventHotKeyID()
            let size = MemoryLayout<EventHotKeyID>.size
            let err = GetEventParameter(event, EventParamName(kEventParamDirectObject), EventParamType(typeEventHotKeyID), nil, size, nil, &hkID)
            guard err == noErr else { return OSStatus(eventNotHandledErr) }
            // Only handle our own signature 'GLND'; otherwise let other handlers process
            let ourSig: OSType = OSType(0x474C4E44 as UInt32) // 'GLND'
            guard hkID.signature == ourSig else { return OSStatus(eventNotHandledErr) }
            guard let cb = mgr.callbacks[hkID.id] else { return OSStatus(eventNotHandledErr) }
            // Carbon delivers on main; invoke directly
            assert(Thread.isMainThread)
            cb()
            return noErr
        }
        let selfPtr = Unmanaged.passUnretained(self).toOpaque()
        // Install on dispatcher for global delivery
        InstallEventHandler(GetEventDispatcherTarget(), handler, 1, &eventType, selfPtr, &eventHandler)
    }
}

#else

// 安全降级：若 Carbon 不可用，提供空实现确保可编译
final class GlobalHotkeys {
    enum KeyCode: UInt32 { case left = 123, right = 124 }
    struct Modifiers: OptionSet { let rawValue: UInt32; init(rawValue: UInt32){ self.rawValue = rawValue }
        static let command = Modifiers(rawValue: 1<<0)
        static let option  = Modifiers(rawValue: 1<<1)
        static let control = Modifiers(rawValue: 1<<2)
        static let shift   = Modifiers(rawValue: 1<<3)
    }
    @discardableResult
    func register(keyCode: KeyCode, modifiers: Modifiers, _ action: @escaping () -> Void) -> Bool { return false }
    @discardableResult
    func registerRaw(keyCode: UInt32, modifiers: Modifiers, _ action: @escaping () -> Void) -> Bool { return false }
    func unregisterAll() {}
}

#endif
