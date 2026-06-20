import AppKit

// Use MickJiggerApp (NSApplication subclass) to intercept Carbon hotkey events.
let app = MickJiggerApp.shared
let delegate = AppDelegate()
app.delegate = delegate
app.run()
