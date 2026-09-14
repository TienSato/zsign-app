//
//  AutoSignProgressManager.swift
//  zsignapp
//  Created by Sato on 31/10/25.

import Foundation
import SwiftUI

@MainActor
class AutoSignProgressManager: ObservableObject {
    static let shared = AutoSignProgressManager()
    
    @Published var isProcessing = false
    @Published var currentStep: String = ""
    @Published var progress: Double = 0.0
    @Published var currentAppName: String = ""
    
    private init() {}
    
    func start(appName: String) {
        isProcessing = true
        currentAppName = appName
        progress = 0.0
        currentStep = "Preparing..."
    }
    
    func updateProgress(_ value: Double, step: String) {
        progress = value
        currentStep = step
    }
    
    func finish() {
        progress = 1.0
        currentStep = "Done!"
        
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
            self.isProcessing = false
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                self.reset()
            }
        }
    }
    
    func fail(error: String) {
        currentStep = L("Error:") + " \(error)"
        progress = 0.0
        
        DispatchQueue.main.asyncAfter(deadline: .now() + 3.0) {
            self.isProcessing = false
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                self.reset()
            }
        }
    }
    
    private func reset() {
        currentStep = ""
        progress = 0.0
        currentAppName = ""
    }
}
