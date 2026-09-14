//
//  BackgroundAudioManager.swift
//  zsignapp
//
//  Created by Sato on 26/10/25.
import AVFoundation
import UIKit

class BackgroundAudioManager: NSObject {
    static let shared = BackgroundAudioManager()
    
    private let engine = AVAudioEngine()
    private var silenceNode: AVAudioSourceNode?
    private var backgroundTask: UIBackgroundTaskIdentifier = .invalid
    private var isInitialized = false
    private var timer: Timer?
    
    // MARK: - Initialization
    override private init() {
        super.init()
        setupAudioSession()
        setupAudioEngine()
        setupNotifications()
        isInitialized = true
    }
    
    deinit {
        NotificationCenter.default.removeObserver(self)
        cleanupResources()
    }
    
    private func cleanupResources() {
        timer?.invalidate()
        timer = nil
        stopEngine()
        endBackgroundTask()
    }
    
    private func setupAudioEngine() {
        let silence = AVAudioSourceNode { _, _, frameCount, audioBufferList -> OSStatus in
            let ablPointer = UnsafeMutableAudioBufferListPointer(audioBufferList)
            for buffer in ablPointer {
                memset(buffer.mData, 0, Int(buffer.mDataByteSize))
            }
            return noErr
        }
        silenceNode = silence
        engine.attach(silence)
        engine.connect(silence, to: engine.mainMixerNode, format: nil)
        engine.prepare()
    }
    
    private func setupNotifications() {
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(appDidEnterBackground),
            name: UIApplication.didEnterBackgroundNotification,
            object: nil
        )
    }
    
    @objc private func appDidEnterBackground() {
        if UserDefaults.standard.bool(forKey: "zsignapp.backgroundAudioEnabled") {
            startBackgroundAudio()
        }
    }
    
    private func setupAudioSession() {
        do {
            let audioSession = AVAudioSession.sharedInstance()
            
            try audioSession.setCategory(
                .playback,
                mode: .default,
                options: [
                    .mixWithOthers,
                    .allowBluetooth,
                    .allowAirPlay
                ]
            )
            
            try audioSession.setActive(true)
            
            NotificationCenter.default.addObserver(
                self,
                selector: #selector(handleAudioSessionInterruption),
                name: AVAudioSession.interruptionNotification,
                object: nil
            )
            
            NotificationCenter.default.addObserver(
                self,
                selector: #selector(handleAudioRouteChange),
                name: AVAudioSession.routeChangeNotification,
                object: nil
            )
            
        } catch {
        }
    }
    
    @objc private func handleAudioSessionInterruption(notification: Notification) {
        guard let info = notification.userInfo,
              let typeValue = info[AVAudioSessionInterruptionTypeKey] as? UInt,
              let type = AVAudioSession.InterruptionType(rawValue: typeValue) else {
            return
        }
        
        switch type {
        case .began:
            pauseEngine()
            
        case .ended:
            if UserDefaults.standard.bool(forKey: "zsignapp.backgroundAudioEnabled") {
                if let optionsValue = info[AVAudioSessionInterruptionOptionKey] as? UInt {
                    let options = AVAudioSession.InterruptionOptions(rawValue: optionsValue)
                    if options.contains(.shouldResume) {
                        resumeEngine()
                    }
                }
            }
            
        @unknown default:
            break
        }
    }
    
    @objc private func handleAudioRouteChange(notification: Notification) {
        guard let info = notification.userInfo,
              let reasonValue = info[AVAudioSessionRouteChangeReasonKey] as? UInt,
              let reason = AVAudioSession.RouteChangeReason(rawValue: reasonValue) else {
            return
        }
        
        switch reason {
        case .oldDeviceUnavailable:
            if UserDefaults.standard.bool(forKey: "zsignapp.backgroundAudioEnabled") {
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                    self.startBackgroundAudio()
                }
            }
        default:
            break
        }
    }
    
    // MARK: - Engine Control
    private func startEngine() {
        guard !engine.isRunning else { return }
        
        do {
            try engine.start()
        } catch {
        }
    }
    
    private func pauseEngine() {
        engine.pause()
    }
    
    private func resumeEngine() {
        do {
            try engine.start()
        } catch {
        }
    }
    
    private func stopEngine() {
        if engine.isRunning {
            engine.stop()
        }
    }
    
    // MARK: - Public Methods
    
    /// Start background audio to keep app active
    /// - Parameter force: If true, bypass user setting check (used for downloads)
    func startBackgroundAudio(force: Bool = false) {
        guard isInitialized else {
            return
        }
        
        // ✅ THAY ĐỔI CHÍNH:
        // - force = true: Luôn start (dành cho downloads)
        // - force = false: Kiểm tra user setting (default behavior)
        let shouldStart = force || UserDefaults.standard.bool(forKey: "zsignapp.backgroundAudioEnabled")
        
        guard shouldStart else {
            return
        }
        
        // Nếu đã chạy thì không cần làm gì
        if engine.isRunning {
            return
        }
        
        do {
            try AVAudioSession.sharedInstance().setActive(true)
            registerBackgroundTask()
            startEngine()
            startKeepAliveTimer()
            
        } catch {
        }
    }
    
    func stopBackgroundAudio() {
        timer?.invalidate()
        timer = nil
        stopEngine()
        endBackgroundTask()
    }
    
    // MARK: - Keep Alive Timer
    private func startKeepAliveTimer() {
        timer?.invalidate()
        
        timer = Timer.scheduledTimer(withTimeInterval: 25.0, repeats: true) { [weak self] _ in
            guard let self = self,
                  UserDefaults.standard.bool(forKey: "zsignapp.backgroundAudioEnabled"),
                  UIApplication.shared.applicationState == .background else {
                return
            }
            
            if !self.engine.isRunning {
                self.startEngine()
            }
            
            self.registerBackgroundTask()
        }
    }
    
    private func registerBackgroundTask() {
        if backgroundTask != .invalid {
            UIApplication.shared.endBackgroundTask(backgroundTask)
        }
        
        backgroundTask = UIApplication.shared.beginBackgroundTask(withName: "BackgroundAudio") { [weak self] in
            guard let self = self else { return }
            
            self.endBackgroundTask()
            
            if UserDefaults.standard.bool(forKey: "zsignapp.backgroundAudioEnabled"),
               UIApplication.shared.applicationState == .background {
                self.registerBackgroundTask()
            }
        }
    }
    
    private func endBackgroundTask() {
        if backgroundTask != .invalid {
            UIApplication.shared.endBackgroundTask(backgroundTask)
            backgroundTask = .invalid
        }
    }
    
    var isAudioPlaying: Bool {
        return engine.isRunning
    }
    
    var backgroundTimeRemaining: TimeInterval {
        return UIApplication.shared.backgroundTimeRemaining
    }
}
