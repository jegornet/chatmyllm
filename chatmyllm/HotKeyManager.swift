//
//  HotKeyManager.swift
//  chatmyllm
//
//  Created by Egor Glukhov on 21. 3. 2026.
//

import AppKit
import Carbon

class HotKeyManager {
    static let shared = HotKeyManager()

    private var hotKeyRef: EventHotKeyRef?
    private var eventHandler: EventHandlerRef?

    private let hotKeySignature = OSType(0x51434854) // 'QCHT'
    private let hotKeyID: UInt32 = 1

    private init() {}

    func register() {
        unregister()

        var eventSpec = EventTypeSpec(eventClass: OSType(kEventClassKeyboard),
                                       eventKind: UInt32(kEventHotKeyPressed))

        let callback: EventHandlerUPP = { (nextHandler, event, userData) -> OSStatus in
            var receivedHotKeyID = EventHotKeyID()
            let status = GetEventParameter(event,
                                          UInt32(kEventParamDirectObject),
                                          UInt32(typeEventHotKeyID),
                                          nil,
                                          MemoryLayout<EventHotKeyID>.size,
                                          nil,
                                          &receivedHotKeyID)

            if status == noErr && receivedHotKeyID.signature == OSType(0x51434854) && receivedHotKeyID.id == 1 {
                DispatchQueue.main.async {
                    QuickChatManager.shared.toggleQuickChat()
                }
                return noErr
            }

            return OSStatus(eventNotHandledErr)
        }

        let selfPtr = Unmanaged.passUnretained(self).toOpaque()
        InstallEventHandler(GetEventDispatcherTarget(),
                           callback,
                           1,
                           &eventSpec,
                           selfPtr,
                           &eventHandler)

        var hotkeyIDStruct = EventHotKeyID(signature: hotKeySignature, id: hotKeyID)
        RegisterEventHotKey(49, UInt32(optionKey), hotkeyIDStruct, GetEventDispatcherTarget(), 0, &hotKeyRef)
    }

    func unregister() {
        if let ref = hotKeyRef {
            UnregisterEventHotKey(ref)
            hotKeyRef = nil
        }
        if let handler = eventHandler {
            RemoveEventHandler(handler)
            eventHandler = nil
        }
    }
}
