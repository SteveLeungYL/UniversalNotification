import Foundation
import SwiftUI
import AppKit
import Atomics

fileprivate class customNSWindow: NSWindow {
    override open func mouseDown(with event: NSEvent) {
        autoreleasepool {
            UniversalNotificationMenuBarExtra.shared.hideAllNotificationWindow(ignoreCounter: true)
        }
    }
}

func runSpawnedCommand(cmd : String, args : String...) -> (output: [String], error: [String], exitCode: Int32) {

    autoreleasepool {
        var outputOut : [String] = []
        var errorOut : [String] = []
        
        let task = Process()
        task.launchPath = cmd
        task.arguments = args
        
        let outpipe = Pipe()
        task.standardOutput = outpipe
        let errpipe = Pipe()
        task.standardError = errpipe
        
        do {
            try task.run()
        } catch {
            //        print("Capture a runCommand exception. \(error)")
            task.waitUntilExit()
            try! outpipe.fileHandleForReading.close()
            try! errpipe.fileHandleForReading.close()
            return (outputOut, errorOut, -1)
        }
        
        let outdata = outpipe.fileHandleForReading.readDataToEndOfFile()
        if var string = String(data: outdata, encoding: .utf8) {
            string = string.trimmingCharacters(in: .newlines)
            outputOut = string.components(separatedBy: "\n")
        }
        
        let errdata = errpipe.fileHandleForReading.readDataToEndOfFile()
        if var string = String(data: errdata, encoding: .utf8) {
            string = string.trimmingCharacters(in: .newlines)
            errorOut = string.components(separatedBy: "\n")
        }
        
        task.waitUntilExit()
        let status = task.terminationStatus
        
        try! outpipe.fileHandleForReading.close()
        try! errpipe.fileHandleForReading.close()
        
        return (outputOut, errorOut, status)
    }
}

class UniversalNotificationMenuBarExtra: NSObject {
    static let shared = UniversalNotificationMenuBarExtra()
    
    private var statusBar: NSStatusBar!
    private var statusBarItem: NSStatusItem!
    
    private var notificationWindowList: [customNSWindow] = [customNSWindow]()
    private var allScreenList: [CGPoint] = [CGPoint]()
    private var allTextField: [NSTextField] = [NSTextField]()
    
    private var fromSoftStr: String = ""
    
    private let windowInvokeCounter = ManagedAtomic<Int>(0)
    
    private var isMultiScreens = -1 // -1: init, 0: single, 1: multiple
    
    func initSetup() {
        statusBar = NSStatusBar.system
        statusBarItem = statusBar.statusItem(withLength: NSStatusItem.squareLength)
        
        if let button = statusBarItem.button {
            // TODO: Use a new icon.
            button.image = (NSImage(systemSymbolName: "rectangle.and.pencil.and.ellipsis", accessibilityDescription: nil))
            button.target = self
            button.action = #selector(exitApplication)
        }
        
        Bundle.main.loadNibNamed("MainMenu", owner: self, topLevelObjects: nil)
        NSApplication.shared.setActivationPolicy(.accessory)
        
        DispatchQueue.global(qos: .background).async {
            self.notificationMainLoop()
        }
        
    }
    
    func notificationMainLoop() {
        autoreleasepool {
            
            while true {
                if NSScreen.screens.count <= 1 {
                    if isMultiScreens == -1 || isMultiScreens == 1 {
                        isMultiScreens = 0 // single
                        
                        DispatchQueue.main.sync(execute: {
                            closeAllNotificationWindow()
                            //                        openNewWindow(fromSoft: "Updated Screen")
                            self.openNewNotificationWindow(fromSoft: "Turn OFF")
                        })
                    }
                    _ = DispatchQueue.global().sync(execute: {
                        sleep(10)
                    })
                    continue
                } else {
                    // > 1
                    if isMultiScreens == -1 || isMultiScreens == 0 {
                        isMultiScreens = 1 // multiple screens
                    }
                }
                
                if !checkScreenConfig() {
                    DispatchQueue.main.sync(execute: {
                        closeAllNotificationWindow()
                        openNewNotificationWindow(fromSoft: "Updated Screen")
                    })
                }
                
                
                let (allShout, _, _) = runSpawnedCommand(cmd: "/usr/bin/log", args: "show",
                                                         "--predicate", "(subsystem == \"com.apple.unc\") && (category == \"application\")",
                                                         "--style", "syslog", "--info", "--last", "3s")
                for shout in allShout {
                    if shout.range(of: "Resolved interruption suppression for ") != nil && shout.range(of: "as none") != nil {
                        var tmp = shout.split(separator: "Resolved interruption suppression for ")[1]
                        var tmpSplit = tmp.split(separator: " ")
                        if tmpSplit.count < 2 {
                            print("Error: Found mismatched text from 'Resolved...' and space. ")
                            continue
                        }
                        tmp = tmpSplit[0]
                        
                        let bundleName = String(tmp)
                        let bundleURL = NSWorkspace().urlForApplication(withBundleIdentifier: bundleName)
                        if let bundleURLL = bundleURL {
                            let softName = bundleURLL.absoluteString
                            
                            tmpSplit = softName.split(separator: "/")
                            tmp = tmpSplit[tmpSplit.count-1]
                            tmp = tmp.split(separator: ".")[0]
                            
                            if tmp != "" {
                                self.fromSoftStr = String(tmp)
                                self.fromSoftStr = fromSoftStr.replacingOccurrences(of: "%20", with: " ")
                            }
                        } else {
                            // Cannot find the coresponding app.
                            //                            print("Get Bundle ID but cannot find App name. ")
                            self.fromSoftStr = "Unknown App"
                        }
                        tmp.removeAll(keepingCapacity: false)
                        tmpSplit.removeAll(keepingCapacity: false)
                    }
                }
                
                if self.fromSoftStr != "" {
                    //                    print("Capture new fromSoftStr: \(fromSoftStr)")
                    DispatchQueue.main.sync(execute: {
                        self.showAllNotificationWindow(fromSoft: fromSoftStr)
                    })
                }
                self.fromSoftStr = ""
                
                sleep(2)
            }
        }
    }
    

    
    func checkScreenConfig() -> Bool {
        autoreleasepool {
            var idx = 0
            for curScreen in NSScreen.screens {
                if idx >= self.allScreenList.count ||
                    curScreen.visibleFrame.origin.x != self.allScreenList[idx].x ||
                    curScreen.visibleFrame.origin.y != self.allScreenList[idx].y {
                    return false
                }
                idx += 1
            }
            
            return true
        }
    }
    
    func hideAllNotificationWindow(ignoreCounter: Bool) {
        autoreleasepool {
            //        print("Call hideAllWindow")
            
            if !ignoreCounter && self.windowInvokeCounter.load(ordering: .relaxed) > 1 {
                windowInvokeCounter.wrappingDecrement(by: 1, ordering: .relaxed)
                return
            }
            
            for window in self.notificationWindowList {
                NSAnimationContext.runAnimationGroup({ (context) -> Void in
                    context.duration = 0.5
                    window.animator().alphaValue = 0
                }, completionHandler: {
                    NSApplication.shared.hide(self)
                })
            }
            
            if !ignoreCounter {
                windowInvokeCounter.wrappingDecrement(by: 1, ordering: .relaxed)
            }
            
            return
        }
    }
    
    func showAllNotificationWindow(fromSoft: String) {
        autoreleasepool {
            windowInvokeCounter.wrappingIncrement(by: 1, ordering: .relaxed)
            //        print("showAllWindow")
            
            for tf in self.allTextField {
                NSAnimationContext.runAnimationGroup({ (context) -> Void in
                    context.duration = 0.3
                    tf.stringValue = fromSoft
                    // asks the text view to redraw
                    tf.needsDisplay = true
                    // asks for relayout
                    tf.needsLayout = true
                }, completionHandler: {
                })
            }
            
            for window in self.notificationWindowList {
                window.orderFront(nil)
            }
            for window in self.notificationWindowList {
                NSAnimationContext.runAnimationGroup({ (context) -> Void in
                    context.duration = 0.5
                    window.animator().alphaValue = 1
                }, completionHandler: {
                })
            }
            
            DispatchQueue.main.asyncAfter(deadline: .now() + 8) {
                self.hideAllNotificationWindow(ignoreCounter: false)
            }
            
            return
        }
    }
    
    func closeAllNotificationWindow() {
        autoreleasepool {
            
            for window in self.notificationWindowList {
                NSApplication.shared.hide(self)
                window.close()
            }
            notificationWindowList.removeAll()
            allScreenList.removeAll()
            allTextField.removeAll()
            
            windowInvokeCounter.store(0, ordering: .relaxed)
            
            return
        }
    }
    
    func openNewNotificationWindow(fromSoft: String) {
        // TODO: Very Ugly UI.
        autoreleasepool {
            windowInvokeCounter.wrappingIncrement(by: 1, ordering: .relaxed)
            
            for curScreen in NSScreen.screens {
                
                let screenFrame = curScreen.visibleFrame
                let screenEdge = curScreen.visibleFrame.origin
                
                allScreenList.append(screenEdge)
                
                let window: customNSWindow = {
                    customNSWindow(contentRect: NSRect(x: 0, y: 0, width: 300, height: 40),
                                   styleMask: NSWindow.StyleMask.titled,
                                   backing: NSWindow.BackingStoreType.buffered,
                                   defer: true
                    )
                }()
                //            window.styleMask.insert(NSWindow.StyleMask.fullSizeContentView)
                window.alphaValue = 0
                
                
                // Calculate the position of the window to
                // place it centered below of the status item
                let windowFrame = window.frame
                let windowSize = windowFrame.size
                let windowTopLeftPosition: CGPoint
                
                windowTopLeftPosition = CGPoint(x: screenEdge.x + screenFrame.width/2 - windowSize.width/2,
                                                y: screenEdge.y + screenFrame.height)
                
                window.setFrameTopLeftPoint(windowTopLeftPosition)
                
                self.notificationWindowList.append(window)
                
                let cell = NSTableCellView()
                cell.frame = NSRect(x: 0, y: 0, width: window.frame.width, height: window.frame.height-35)
                cell.enclosingScrollView?.borderType = .noBorder
                cell.textField?.isHighlighted = false
                cell.imageView?.isHighlighted = false
                let tf = NSTextField()
                tf.textColor = .white // TODO:: Dark Mode Support.
                tf.frame = cell.frame
                tf.font = NSFont(name: tf.font!.fontName, size: 30)
                tf.stringValue = fromSoft
                tf.alignment = .center
                tf.isEditable = false
                tf.isBordered = false
                tf.backgroundColor = .clear
                
                allTextField.append(tf)
                
                let stringHeight: CGFloat = tf.attributedStringValue.size().height
                let frame = tf.frame
                var titleRect:  NSRect = tf.cell!.titleRect(forBounds: frame)
                
                titleRect.size.height = stringHeight + ( stringHeight - (tf.font!.ascender + tf.font!.descender ) )
                titleRect.origin.y = frame.size.height / 2  - tf.lastBaselineOffsetFromBottom - tf.font!.xHeight / 2
                tf.frame = titleRect
                window.contentView?.addSubview(tf)
                
                window.windowStyleConfigure()
                window.orderFront(nil)
                
                NSAnimationContext.runAnimationGroup({ (context) -> Void in
                    context.duration = 0.5
                    window.animator().alphaValue = 1
                }, completionHandler: {
                })
                
            }
            
            DispatchQueue.main.asyncAfter(deadline: .now() + 8) {
                self.hideAllNotificationWindow(ignoreCounter: false)
            }
            
        }
    }
    
    @objc func exitApplication() {
        exit(0)
    }
    
}

fileprivate extension NSWindow {
    func windowStyleConfigure() {
        autoreleasepool {
            self.titlebarAppearsTransparent = true
            self.titleVisibility = .hidden
            self.collectionBehavior = [.transient, .ignoresCycle, .canJoinAllApplications, .canJoinAllSpaces]
            self.isReleasedWhenClosed = false
            self.isOpaque = false
            self.backgroundColor = NSColor.clear
            self.backgroundColor = NSColor(red: 0, green: 0, blue: 1, alpha: 1.0)
        }
    }
}
