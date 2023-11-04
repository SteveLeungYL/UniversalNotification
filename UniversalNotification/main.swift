//
//  main.swift
//  UniversalNotification
//
//  Created by Yu Liang on 10/31/23.
//

import Foundation
import AppKit

let appDelegate = NSAppDelegate()
let app = NSApplication.shared

app.delegate = appDelegate
app.run()

class NSAppDelegate: NSObject, NSApplicationDelegate {
    private let compact = UniversalNotificationMenuBarExtra.shared
    
    func applicationDidFinishLaunching(_ notification: Notification) {
        self.compact.initSetup()
    }
    
    func applicationDidResignActive(_ notification: Notification) {
        NSApplication.shared.hide(self)
    }
}
