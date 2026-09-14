//
//  AppNotification.swift
//  zsignapp
//

import Foundation
import SwiftUI

// MARK: - Models

struct NotificationResponse: Codable {
    let enabled: Bool
    let notification: AppNotification?
}

struct AppNotification: Codable, Identifiable {
    let id: String
    let title: String
    let message: String
    let type: NotificationType
    let priority: NotificationPriority
    let buttons: [NotificationButton]
    let dismissible: Bool
    let showOnce: Bool
    
    enum NotificationType: String, Codable {
        case update
        case warning
        case info
        case error
        case success
    }
    
    enum NotificationPriority: String, Codable {
        case low
        case medium
        case high
        case critical
    }
}

struct NotificationButton: Codable, Identifiable {
    let title: String
    let style: ButtonStyle
    let action: ButtonAction
    
    var id: String { title }
    
    enum ButtonStyle: String, Codable {
        case primary
        case secondary
        case cancel
        case destructive
    }
}

struct ButtonAction: Codable {
    let type: ActionType
    let value: String?
    
    enum ActionType: String, Codable {
        case url
        case dismiss
        case openSettings
    }
}

// MARK: - Manager

class NotificationManager: ObservableObject {
    static let shared = NotificationManager()
    
    @Published var currentNotification: AppNotification?
    @Published var shouldShowNotification = false
    
    private let apiURL = "https://sign.zsign.app/notifications.json"
    private let shownNotificationsKey = "shownNotifications"
    
    private init() {}
    
    func fetchNotification() async {
        do {
            guard let url = URL(string: apiURL) else { return }
            
            let (data, _) = try await URLSession.shared.data(from: url)
            let response = try JSONDecoder().decode(NotificationResponse.self, from: data)
            
            await MainActor.run {
                if response.enabled, let notification = response.notification {
                    if notification.showOnce {
                        let shownIDs = getShownNotificationIDs()
                        if !shownIDs.contains(notification.id) {
                            self.currentNotification = notification
                            self.shouldShowNotification = true
                        }
                    } else {
                        self.currentNotification = notification
                        self.shouldShowNotification = true
                    }
                }
            }
            
        } catch {
            print("Failed to fetch notification: \(error)")
        }
    }
    
    func markAsShown() {
        guard let notification = currentNotification else { return }
        
        var shownIDs = getShownNotificationIDs()
        if !shownIDs.contains(notification.id) {
            shownIDs.append(notification.id)
            UserDefaults.standard.set(shownIDs, forKey: shownNotificationsKey)
        }
    }
    
    private func getShownNotificationIDs() -> [String] {
        return UserDefaults.standard.stringArray(forKey: shownNotificationsKey) ?? []
    }
    
    func dismissNotification() {
        shouldShowNotification = false
        markAsShown()
    }
    
    func handleAction(_ action: ButtonAction) {
        switch action.type {
        case .url:
            if let urlString = action.value,
               let url = URL(string: urlString) {
                UIApplication.shared.open(url)
            }
            dismissNotification()
            
        case .dismiss:
            dismissNotification()
            
        case .openSettings:
            if let url = URL(string: UIApplication.openSettingsURLString) {
                UIApplication.shared.open(url)
            }
            dismissNotification()
        }
    }
}

// MARK: - View

struct NotificationView: View {
    @ObservedObject var manager = NotificationManager.shared
    let notification: AppNotification
    
    var body: some View {
        VStack(spacing: 20) {
            Image(systemName: iconName)
                .font(.system(size: 60))
                .foregroundColor(iconColor)
            
            Text(notification.title)
                .font(.title2)
                .fontWeight(.bold)
                .multilineTextAlignment(.center)
            
            Text(notification.message)
                .font(.body)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal)
            
            VStack(spacing: 12) {
                ForEach(notification.buttons) { button in
                    Button {
                        manager.handleAction(button.action)
                    } label: {
                        Text(button.title)
                            .fontWeight(button.style == .primary ? .semibold : .regular)
                            .frame(maxWidth: .infinity)
                            .padding()
                            .background(backgroundColor(for: button.style))
                            .foregroundColor(foregroundColor(for: button.style))
                            .cornerRadius(12)
                    }
                }
            }
            .padding(.horizontal)
        }
        .padding()
    }
    
    private var iconName: String {
        switch notification.type {
        case .update: return "arrow.down.circle.fill"
        case .warning: return "exclamationmark.triangle.fill"
        case .info: return "info.circle.fill"
        case .error: return "xmark.circle.fill"
        case .success: return "checkmark.circle.fill"
        }
    }
    
    private var iconColor: Color {
        switch notification.type {
        case .update: return .accentColor
        case .warning: return .orange
        case .info: return .accentColor
        case .error: return .red
        case .success: return .green
        }
    }
    
    private func backgroundColor(for style: NotificationButton.ButtonStyle) -> Color {
        switch style {
        case .primary: return .accentColor
        case .secondary: return Color(.systemGray5)
        case .cancel: return Color(.systemGray6)
        case .destructive: return .red
        }
    }
    
    private func foregroundColor(for style: NotificationButton.ButtonStyle) -> Color {
        switch style {
        case .primary: return .white
        case .secondary: return .primary
        case .cancel: return .secondary
        case .destructive: return .white
        }
    }
}
