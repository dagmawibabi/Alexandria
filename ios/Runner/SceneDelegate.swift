import Flutter
import UIKit

/// Receives PDF / EPUB / DOCX files opened "in" Alexandria from other apps
/// and hands them to Flutter over the `alexandria/intent` channel.
class SceneDelegate: FlutterSceneDelegate {
  private var channel: FlutterMethodChannel?
  private var initial: [[String: String]] = []

  override func scene(_ scene: UIScene, willConnectTo session: UISceneSession, options connectionOptions: UIScene.ConnectionOptions) {
    super.scene(scene, willConnectTo: session, options: connectionOptions)
    initial = connectionOptions.urlContexts.compactMap { copy($0.url) }
    setUpChannel()
  }

  override func scene(_ scene: UIScene, openURLContexts URLContexts: Set<UIOpenURLContext>) {
    let files = URLContexts.compactMap { copy($0.url) }
    setUpChannel()
    if !files.isEmpty { channel?.invokeMethod("files", arguments: files) }
  }

  private func setUpChannel() {
    guard channel == nil, let controller = window?.rootViewController as? FlutterViewController else { return }
    let c = FlutterMethodChannel(name: "alexandria/intent", binaryMessenger: controller.binaryMessenger)
    c.setMethodCallHandler { [weak self] call, result in
      if call.method == "initialFiles" {
        result(self?.initial ?? [])
        self?.initial = []
      } else {
        result(FlutterMethodNotImplemented)
      }
    }
    channel = c
  }

  private func copy(_ url: URL) -> [String: String]? {
    let scoped = url.startAccessingSecurityScopedResource()
    defer { if scoped { url.stopAccessingSecurityScopedResource() } }
    let dir = FileManager.default.temporaryDirectory.appendingPathComponent("incoming", isDirectory: true)
    try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
    let dest = dir.appendingPathComponent("\(Int(Date().timeIntervalSince1970 * 1000))_\(url.lastPathComponent)")
    do {
      try FileManager.default.copyItem(at: url, to: dest)
      return ["path": dest.path, "name": url.lastPathComponent]
    } catch {
      return nil
    }
  }
}
