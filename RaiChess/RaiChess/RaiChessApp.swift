// ===============================
// File: RaiChessApp.swift
// ===============================
import SwiftUI

@main
struct RaiChessApp: App {
    var body: some Scene {
        WindowGroup {
            GameViewRoot()   // 🔥 вместо прямого GameView
        }
    }
}
