import UIKit
import Firebase
import FirebaseCore
import FirebaseAuth
import UserNotifications
import OneSignalFramework

// MARK: - App Delegate for OneSignal

class AppDelegate: NSObject, UIApplicationDelegate, UNUserNotificationCenterDelegate {
    
    func application(_ application: UIApplication, didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey : Any]? = nil) -> Bool {
        // Configure Firebase first
        if FirebaseApp.app() == nil {
            FirebaseApp.configure()
            print("DEBUG: Firebase configured in AppDelegate")
        }
        
        // Initialize OneSignal
        OneSignal.initialize("6495d27c-74bd-4f3d-9843-9d59aa4d0c7b", withLaunchOptions: launchOptions)
        print("DEBUG: OneSignal initialized")
        
        // Request notification permissions
        OneSignal.Notifications.requestPermission({ accepted in
            print("DEBUG: OneSignal notification permission: \(accepted)")
        }, fallbackToSettings: true)
        
        // Set notification delegate
        UNUserNotificationCenter.current().delegate = self
        
        return true
    }
    
        // Handle OAuth redirect
        func application(_ app: UIApplication, open url: URL, options: [UIApplication.OpenURLOptionsKey : Any] = [:]) -> Bool {
            // Post notification with URL so any listener (e.g., FreshserviceOAuthManager) can handle it
            NotificationCenter.default.post(name: .freshserviceOAuthRedirect, object: url)
            return true
        }
    
    // MARK: - UNUserNotificationCenterDelegate
    
    // Handle notification when app is in foreground
    func userNotificationCenter(_ center: UNUserNotificationCenter, willPresent notification: UNNotification, withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void) {
        // Show notification with alert style even when app is in foreground
        completionHandler([.alert, .sound, .badge])
    }
    
    // Handle notification tap
    func userNotificationCenter(_ center: UNUserNotificationCenter, didReceive response: UNNotificationResponse, withCompletionHandler completionHandler: @escaping () -> Void) {
        let userInfo = response.notification.request.content.userInfo
        print("DEBUG: Notification tapped with userInfo: \(userInfo)")
        // TODO: Navigate to specific channel if channelId is in userInfo
        completionHandler()
    }
}
