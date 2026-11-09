import AppKit

let app = NSApplication.shared
if let running = SingleInstance.runningInstance() {
    FileHandle.standardError.write(Data("tinyStats is already running (PID \(running)).\n".utf8))
    exit(0)
}
let delegate = App()
app.delegate = delegate
app.setActivationPolicy(.accessory)
app.run()
