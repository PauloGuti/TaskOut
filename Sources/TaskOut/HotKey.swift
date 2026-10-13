import Carbon.HIToolbox

/// Atajo global (funciona aunque otra app esté activa, sin pedir permisos de accesibilidad).
final class HotKey {
    private var ref: EventHotKeyRef?
    var onPress: (() -> Void)?

    @discardableResult
    func register(keyCode: Int, modifiers: Int) -> Bool {
        var spec = EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed))
        InstallEventHandler(GetApplicationEventTarget(), { _, _, userData in
            guard let userData else { return noErr }
            let me = Unmanaged<HotKey>.fromOpaque(userData).takeUnretainedValue()
            DispatchQueue.main.async { me.onPress?() }
            return noErr
        }, 1, &spec, Unmanaged.passUnretained(self).toOpaque(), nil)
        let id = EventHotKeyID(signature: OSType(0x544B4F54), id: 1)
        return RegisterEventHotKey(UInt32(keyCode), UInt32(modifiers), id, GetApplicationEventTarget(), 0, &ref) == noErr
    }
}
