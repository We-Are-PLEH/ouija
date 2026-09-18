import AppKit
import Foundation

/// Agente de fondo: sin icono en el Dock (LSUIElement) y sin ventanas.
/// Publica un aviso nativo cuando un agente de herdr se bloquea o termina, y al
/// pulsarlo lleva el foco al panel exacto.
final class AppDelegate: NSObject, NSApplicationDelegate {
    private var watcher: Watcher?
    private var notifier: Notifier?

    func applicationDidFinishLaunching(_ notification: Notification) {
        let config = Config.load()
        guard let binary = config.resolvedHerdr() else {
            Log.error("no encuentro el binario de herdr; fija \"herdrPath\" en \(Config.fileURL.path)")
            NSApp.terminate(nil)
            return
        }
        Log.info("herdr en \(binary)")
        let herdr = Herdr(binary: binary)
        let notifier = Notifier(config: config, herdr: herdr)
        notifier.requestAuthorization()
        let watcher = Watcher(config: config, herdr: herdr, notifier: notifier)
        watcher.start()
        self.notifier = notifier
        self.watcher = watcher
    }

    /// `ouija://send?title=…&body=…&open=…` — la via por la que un cron manda un
    /// aviso clicable en vez de un `osascript display notification` que no lleva
    /// a ninguna parte. Con `session` y `pane`, el clic va al panel.
    func application(_ application: NSApplication, open urls: [URL]) {
        for url in urls where url.scheme == "ouija" && url.host == "send" {
            let q = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems ?? []
            func value(_ name: String) -> String? { q.first { $0.name == name }?.value }
            let title = value("title") ?? "Ouija"
            let action: ClickAction
            if let session = value("session"), let pane = value("pane") {
                action = .focus(session: session, pane: pane)
            } else {
                action = .open(target: value("open") ?? "")
            }
            Log.info("aviso por URL: \(title)")
            notifier?.post(
                title: title,
                subtitle: value("subtitle") ?? "",
                body: value("body") ?? "",
                sound: value("sound"),
                thread: value("thread") ?? title,
                action: action
            )
        }
    }
}

let app = NSApplication.shared
let delegate = AppDelegate()
app.delegate = delegate
app.setActivationPolicy(.accessory)
app.run()
