//
//  HotKeyCenter.swift
//  switchr
//
//  Registers a global hotkey via Carbon. Unlike an NSEvent global monitor,
//  RegisterEventHotKey consumes the keystroke (the frontmost app never sees
//  it) and requires no special permissions.
//

import AppKit
import Carbon.HIToolbox

final class HotKeyCenter {
    static let shared = HotKeyCenter()

    private var hotKeyRef: EventHotKeyRef?
    private var eventHandlerRef: EventHandlerRef?
    private var handler: (() -> Void)?

    private init() {}

    func register(keyCode: UInt32, modifiers: UInt32, handler: @escaping () -> Void) {
        unregister()
        self.handler = handler

        if eventHandlerRef == nil {
            var eventType = EventTypeSpec(
                eventClass: OSType(kEventClassKeyboard),
                eventKind: UInt32(kEventHotKeyPressed)
            )
            InstallEventHandler(
                GetEventDispatcherTarget(),
                hotKeyEventCallback,
                1,
                &eventType,
                nil,
                &eventHandlerRef
            )
        }

        let hotKeyID = EventHotKeyID(signature: OSType(0x5357_4348), id: 1) // 'SWCH'
        RegisterEventHotKey(
            keyCode,
            modifiers,
            hotKeyID,
            GetEventDispatcherTarget(),
            0,
            &hotKeyRef
        )
    }

    func unregister() {
        if let hotKeyRef {
            UnregisterEventHotKey(hotKeyRef)
            self.hotKeyRef = nil
        }
        handler = nil
    }

    fileprivate func fire() {
        handler?()
    }
}

// Carbon delivers hotkey events on the main thread, but a C function pointer
// cannot carry actor isolation, so we hop back explicitly.
private nonisolated func hotKeyEventCallback(
    _ callRef: EventHandlerCallRef?,
    _ event: EventRef?,
    _ userData: UnsafeMutableRawPointer?
) -> OSStatus {
    MainActor.assumeIsolated {
        HotKeyCenter.shared.fire()
    }
    return noErr
}
