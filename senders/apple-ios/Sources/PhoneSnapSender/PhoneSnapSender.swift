import Foundation

#if DEBUG && canImport(UIKit)
import UIKit
#endif

public enum PhoneSnapSender {
    public static func start(uploadURL: URL, token: String) {
        SharedPhoneSnapSender.shared.start(uploadURL: uploadURL, token: token)
    }

    public static func stop() {
        SharedPhoneSnapSender.shared.stop()
    }
}

private final class SharedPhoneSnapSender {
    static let shared = SharedPhoneSnapSender()

    private init() {}

    #if DEBUG && canImport(UIKit)
    private var observer: NSObjectProtocol?
    private var uploadURL: URL?
    private var token: String?
    private let uploadQueue = DispatchQueue(label: "phonesnap.sender.upload")

    func start(uploadURL: URL, token: String) {
        DispatchQueue.main.async {
            self.uploadURL = uploadURL
            self.token = token

            if self.observer == nil {
                self.observer = NotificationCenter.default.addObserver(
                    forName: UIApplication.userDidTakeScreenshotNotification,
                    object: nil,
                    queue: .main
                ) { [weak self] _ in
                    self?.handleScreenshot()
                }
            }
        }
    }

    func stop() {
        DispatchQueue.main.async {
            if let observer = self.observer {
                NotificationCenter.default.removeObserver(observer)
            }
            self.observer = nil
            self.uploadURL = nil
            self.token = nil
        }
    }

    private func handleScreenshot() {
        guard let uploadURL, let token, let window = Self.activeWindow() else {
            return
        }

        let bounds = window.bounds
        guard bounds.width > 0, bounds.height > 0 else {
            return
        }

        let renderer = UIGraphicsImageRenderer(bounds: bounds)
        let image = renderer.image { _ in
            window.drawHierarchy(in: bounds, afterScreenUpdates: true)
        }

        guard let pngData = image.pngData() else {
            return
        }

        upload(data: pngData, to: uploadURL, token: token)
    }

    private func upload(data: Data, to uploadURL: URL, token: String) {
        uploadQueue.async {
            var request = URLRequest(url: uploadURL)
            request.httpMethod = "POST"
            request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
            request.setValue("image/png", forHTTPHeaderField: "Content-Type")
            request.httpBody = data

            URLSession.shared.dataTask(with: request).resume()
        }
    }

    private static func activeWindow() -> UIWindow? {
        let foregroundScenes = UIApplication.shared.connectedScenes
            .compactMap { $0 as? UIWindowScene }
            .filter { $0.activationState == .foregroundActive }

        for scene in foregroundScenes {
            if let keyWindow = scene.windows.first(where: { $0.isKeyWindow }) {
                return keyWindow
            }
            if let visibleWindow = scene.windows.first(where: { !$0.isHidden && $0.alpha > 0 }) {
                return visibleWindow
            }
        }

        return nil
    }
    #else
    func start(uploadURL: URL, token: String) {}
    func stop() {}
    #endif
}
