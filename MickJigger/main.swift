import AppKit

// No storyboards: build the application object and delegate manually.
let app = NSApplication.shared
let delegate = AppDelegate()
app.delegate = delegate
app.run()
