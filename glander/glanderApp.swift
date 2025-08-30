//
//  glanderApp.swift
//  glander
//
//  Created by 符镇岳 on 2025/8/30.
//

import SwiftUI
import AppKit

@main
struct glanderApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate
    var body: some Scene {
        // Use AppDelegate to manage all windows.
        // Expose preferences via a native Settings scene for convenience.
        Settings {
            PreferencesView()
                .frame(width: 440, height: 260)
        }
    }
}
