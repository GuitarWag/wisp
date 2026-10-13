// wispview - show HTML from stdin in a macOS window, then exit.
//
// Two things this does that QuickLook cannot.
//
// 1. Nothing reaches the disk. The HTML arrives on stdin and goes straight to
//    loadHTMLString, so there is no temporary file to write, to find, or to
//    forget to delete.
// 2. JavaScript is off at the engine. allowsContentJavaScript = false means a
//    script in the source file cannot run, rather than running in a sandbox
//    that a stray Content Security Policy edit could widen.
//
// Build: swiftc -O wispview.swift -o wispview
// Use:   cat page.html | wispview "Title"

import Cocoa
import WebKit

let title = CommandLine.arguments.count > 1 ? CommandLine.arguments[1] : "wisp"
// --selftest opens the window and closes it, so a build can be verified
// without a person watching the screen.
let selftest = CommandLine.arguments.contains("--selftest")

let html = String(data: FileHandle.standardInput.readDataToEndOfFile(), encoding: .utf8) ?? ""
if html.isEmpty { FileHandle.standardError.write("wispview: no HTML on stdin\n".data(using: .utf8)!); exit(2) }

let app = NSApplication.shared
app.setActivationPolicy(.regular)

let cfg = WKWebViewConfiguration()
cfg.defaultWebpagePreferences.allowsContentJavaScript = false

// The page is built from a file somebody else wrote. Markdown carries raw HTML
// through, so the page can hold a link or a meta refresh. A meta refresh needs
// no JavaScript and no Content Security Policy covers it, so without this the
// window would quietly load a remote page. Allow the first in-memory load and
// nothing else. A click on a real link goes to the browser, where the person
// can see where they are going.
final class Nav: NSObject, WKNavigationDelegate {
    private var firstLoadDone = false
    func webView(_ webView: WKWebView,
                 decidePolicyFor action: WKNavigationAction,
                 decisionHandler: @escaping (WKNavigationActionPolicy) -> Void) {
        if !firstLoadDone { firstLoadDone = true; decisionHandler(.allow); return }
        if action.navigationType == .linkActivated,
           let url = action.request.url,
           url.scheme == "http" || url.scheme == "https" {
            NSWorkspace.shared.open(url)
        } else if let url = action.request.url {
            FileHandle.standardError.write("wispview: blocked navigation to \(url)\n".data(using: .utf8)!)
        }
        decisionHandler(.cancel)
    }
}
let nav = Nav()

final class Delegate: NSObject, NSApplicationDelegate, NSWindowDelegate {
    func windowWillClose(_ note: Notification) { NSApp.terminate(nil) }
    func applicationShouldTerminateAfterLastWindowClosed(_ a: NSApplication) -> Bool { true }
}
let delegate = Delegate()
app.delegate = delegate

// Open at a readable size, centred, but let the person resize it.
let frame = NSRect(x: 0, y: 0, width: 900, height: 760)
let win = NSWindow(contentRect: frame,
                   styleMask: [.titled, .closable, .resizable, .miniaturizable],
                   backing: .buffered, defer: false)
win.title = title
win.delegate = delegate
win.center()
win.isReleasedWhenClosed = false

let web = WKWebView(frame: frame, configuration: cfg)
web.autoresizingMask = [.width, .height]
web.navigationDelegate = nav
// baseURL nil keeps the page from reaching the file system or the network.
web.loadHTMLString(html, baseURL: nil)
win.contentView = web

// Escape and Cmd-W both close, the same as QuickLook.
NSEvent.addLocalMonitorForEvents(matching: .keyDown) { e in
    let cmdW = e.modifierFlags.contains(.command) && e.charactersIgnoringModifiers == "w"
    if e.keyCode == 53 || cmdW { NSApp.terminate(nil); return nil }
    return e
}

win.makeKeyAndOrderFront(nil)
app.activate(ignoringOtherApps: true)

if selftest {
    DispatchQueue.main.asyncAfter(deadline: .now() + 1.2) {
        FileHandle.standardError.write("wispview: selftest ok\n".data(using: .utf8)!)
        NSApp.terminate(nil)
    }
}
app.run()
