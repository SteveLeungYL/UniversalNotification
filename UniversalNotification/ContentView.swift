import Foundation
import SwiftUI
import AppKit
import Atomics

func runCommand(cmd : String, args : String...) -> (output: [String], error: [String], exitCode: Int32) {

    var output : [String] = []
    var error : [String] = []

    let task = Process()
    task.launchPath = cmd
    task.arguments = args

    let outpipe = Pipe()
    task.standardOutput = outpipe
    let errpipe = Pipe()
    task.standardError = errpipe

    task.launch()

    let outdata = outpipe.fileHandleForReading.readDataToEndOfFile()
    if var string = String(data: outdata, encoding: .utf8) {
        string = string.trimmingCharacters(in: .newlines)
        output = string.components(separatedBy: "\n")
    }

    let errdata = errpipe.fileHandleForReading.readDataToEndOfFile()
    if var string = String(data: errdata, encoding: .utf8) {
        string = string.trimmingCharacters(in: .newlines)
        error = string.components(separatedBy: "\n")
    }

    task.waitUntilExit()
    let status = task.terminationStatus

    return (output, error, status)
}

extension NSWindow.StyleMask {
    static var defaultWindow: NSWindow.StyleMask {
        var styleMask: NSWindow.StyleMask = .init()
        styleMask.formUnion(.titled)
        styleMask.formUnion(.fullSizeContentView)
        return styleMask
    }
}

class MenuBarExtraCompact: NSObject {
    static let shared = MenuBarExtraCompact()
    
    private var statusBar: NSStatusBar!
    private var statusBarItem: NSStatusItem!
    
    private var notiWindowList: [NSWindow] = [NSWindow]()
    
    private var hostingViewController: NSHostingController<AnyView>? = nil
    
    private var fromSoftStr: String = ""
    
    private let windowCounter = ManagedAtomic<Int>(0)
    
    func setup() {
        statusBar = NSStatusBar.system
        statusBarItem = statusBar.statusItem(withLength: NSStatusItem.squareLength)
        
        if let button = statusBarItem.button {
            button.image = (NSImage(systemSymbolName: "rectangle.and.pencil.and.ellipsis", accessibilityDescription: nil))
            button.target = self
            button.action = #selector(exitApplication)
        }
        
        Bundle.main.loadNibNamed("MainMenu", owner: self, topLevelObjects: nil)
        NSApplication.shared.setActivationPolicy(.accessory)
        
        DispatchQueue.global(qos: .background).async {
            self.notificationLoopFunction()
        }
        
    }
    
    func notificationLoopFunction() {
        self.fromSoftStr = ""
        while true {
            let (allShout, _, _) = runCommand(cmd: "/usr/bin/log", args: "show",
//                                                     "--predicate", "'(subsystem == \"com.apple.unc\") && (category == \"application\")'",
                                                     "--style", "syslog", "--info", "--last", "3s")
//            print(stderr)
            for shout in allShout {
                if shout.range(of: "Presenting <NotificationRecord app:\"") != nil {
                    var tmp = shout.split(separator: "NotificationRecord app:\"")[1]
                    tmp = tmp.split(separator: "\"")[0]
                    tmp = tmp.split(separator: ".")[2]
                    if tmp != "" {
                        self.fromSoftStr = String(tmp)
                    }
                }
            }
            
            if self.fromSoftStr != "" {
                DispatchQueue.main.sync(execute: {
                    self.openMainWindow(fromSoft: self.fromSoftStr)
                })
            }
            self.fromSoftStr = ""
            sleep(2)
        }
    }
    
    @objc func exitApplication() {
        exit(0)
    }
    
    @objc func closeMainWindow(ignoreCounter: Bool) {
        
        if !ignoreCounter && self.windowCounter.load(ordering: .relaxed) > 1 {
            windowCounter.wrappingDecrement(by: 1, ordering: .relaxed)
            return
        }
        
        for window in self.notiWindowList {
            NSAnimationContext.runAnimationGroup({ (context) -> Void in
                context.duration = 0.5
                window.animator().alphaValue = 0
            }, completionHandler: {
                if ignoreCounter {
                    NSApplication.shared.hide(self)
                }
            })
        }
        notiWindowList.removeAll()
        
        if !ignoreCounter {
            windowCounter.wrappingDecrement(by: 1, ordering: .relaxed)
        }
        
        return
    }
    
    @objc func openMainWindow(fromSoft: String) {
        
        windowCounter.wrappingIncrement(by: 1, ordering: .relaxed)
        
        for curScreen in NSScreen.screens {
            
            let screenFrame = curScreen.visibleFrame
            let screenEdge = curScreen.visibleFrame.origin
            
            let window: NSWindow = {
                NSWindow(contentRect: NSRect(x: 0, y: 0, width: 300, height: 40),
                         styleMask: NSWindow.StyleMask.titled,
                         backing: NSWindow.BackingStoreType.buffered,
                         defer: true
                )
            }()
            window.alphaValue = 0
            
            
            // Calculate the position of the window to
            // place it centered below of the status item
            let windowFrame = window.frame
            let windowSize = windowFrame.size
            let windowTopLeftPosition: CGPoint
            
            windowTopLeftPosition = CGPoint(x: screenEdge.x + screenFrame.width/2 - windowSize.width/2,
                                            y: screenEdge.y + screenFrame.height)
            
            window.setFrameTopLeftPoint(windowTopLeftPosition)
            
            self.notiWindowList.append(window)
            
            let cell = NSTableCellView()
            cell.frame = NSRect(x: 0, y: 0, width: 300, height: 40)
            let tf = NSTextField()
            tf.frame = cell.frame
            tf.font = NSFont(name: tf.font!.fontName, size: 30)
            tf.stringValue = fromSoft
            tf.alignment = .center
            tf.isEditable = false

            let stringHeight: CGFloat = tf.attributedStringValue.size().height
            let frame = tf.frame
            var titleRect:  NSRect = tf.cell!.titleRect(forBounds: frame)

            titleRect.size.height = stringHeight + ( stringHeight - (tf.font!.ascender + tf.font!.descender ) )
            titleRect.origin.y = frame.size.height / 2  - tf.lastBaselineOffsetFromBottom - tf.font!.xHeight / 2
            tf.frame = titleRect
            window.contentView?.addSubview(tf)
            
            window.configure()
            window.orderFront(nil)
            
            NSAnimationContext.runAnimationGroup({ (context) -> Void in
                context.duration = 0.5
                window.animator().alphaValue = 1
            }, completionHandler: {
            })

        }
        
        DispatchQueue.main.asyncAfter(deadline: .now() + 8) {
            self.closeMainWindow(ignoreCounter: false)
        }
        
    }
    
}

fileprivate extension NSWindow {
    func configure() {
        self.titlebarAppearsTransparent = true
        self.titleVisibility = .hidden
        self.collectionBehavior = [.transient, .ignoresCycle, .canJoinAllApplications, .canJoinAllSpaces]
        self.isReleasedWhenClosed = false
        self.isOpaque = false
        self.backgroundColor = NSColor.clear
        self.backgroundColor = NSColor(red: 0, green: 0, blue: 1, alpha: 0.95)
    }
}
