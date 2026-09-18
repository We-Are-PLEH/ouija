import AppKit
import UserNotifications

/// Que hacer cuando se pulsa una notificacion.
enum ClickAction {
    /// Llevar el foco al panel exacto de un agente de herdr.
    case focus(session: String, pane: String)
    /// Abrir una ruta o una URL (lo usan los avisos que manda `ouija send`).
    case open(target: String)

    var userInfo: [String: Any] {
        switch self {
        case .focus(let session, let pane): return ["kind": "focus", "session": session, "pane": pane]
        case .open(let target):             return ["kind": "open", "target": target]
        }
    }

    init?(userInfo: [AnyHashable: Any]) {
        switch userInfo["kind"] as? String {
        case "focus":
            guard let s = userInfo["session"] as? String, let p = userInfo["pane"] as? String else { return nil }
            self = .focus(session: s, pane: p)
        case "open":
            guard let t = userInfo["target"] as? String else { return nil }
            self = .open(target: t)
        default: return nil
        }
    }
}

/// Publica notificaciones nativas y ejecuta la accion al pulsarlas.
///
/// `UNUserNotificationCenter` es lo que hace posible el clic: `osascript display
/// notification` no admite handler, y por eso un aviso hecho asi no lleva a
/// ninguna parte.
final class Notifier: NSObject, UNUserNotificationCenterDelegate {
    /// Categoria de los avisos que apuntan a un panel: son los unicos que pueden
    /// llevar campo de respuesta.
    private static let agentCategory = "ouija.agent"
    private static let replyAction = "ouija.reply"

    private let config: Config
    private let herdr: Herdr

    init(config: Config, herdr: Herdr) {
        self.config = config
        self.herdr = herdr
        super.init()
        let center = UNUserNotificationCenter.current()
        center.delegate = self
        if config.replyEnabled {
            let reply = UNTextInputNotificationAction(
                identifier: Self.replyAction,
                title: config.replyButtonTitle,
                options: [],
                textInputButtonTitle: "Enviar",
                textInputPlaceholder: "escribe una respuesta…"
            )
            center.setNotificationCategories([
                UNNotificationCategory(identifier: Self.agentCategory, actions: [reply],
                                       intentIdentifiers: [], options: [])
            ])
        }
    }

    func requestAuthorization() {
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound]) { granted, error in
            if let error { Log.error("permiso de notificaciones: \(error.localizedDescription)") }
            else if !granted { Log.error("permiso de notificaciones denegado; no habra avisos") }
            else { Log.info("permiso de notificaciones concedido") }
        }
    }

    /// `threadIdentifier` agrupa por panel: N avisos del mismo sitio no llenan el
    /// centro de notificaciones con filas sueltas.
    func post(title: String, subtitle: String, body: String, sound: String?, thread: String, action: ClickAction) {
        let content = UNMutableNotificationContent()
        content.title = title
        if !subtitle.isEmpty { content.subtitle = subtitle }
        content.body = body
        content.threadIdentifier = thread
        content.userInfo = action.userInfo
        if case .focus = action, config.replyEnabled { content.categoryIdentifier = Self.agentCategory }
        if let sound, !sound.isEmpty {
            content.sound = UNNotificationSound(named: UNNotificationSoundName(rawValue: "\(sound).aiff"))
        }
        let request = UNNotificationRequest(identifier: UUID().uuidString, content: content, trigger: nil)
        UNUserNotificationCenter.current().add(request) { error in
            if let error { Log.error("no se pudo publicar el aviso: \(error.localizedDescription)") }
        }
    }

    // Sin esto, un aviso llegado mientras la app esta activa no se muestra.
    func userNotificationCenter(_ center: UNUserNotificationCenter,
                               willPresent notification: UNNotification,
                               withCompletionHandler handler: @escaping (UNNotificationPresentationOptions) -> Void) {
        handler([.banner, .sound])
    }

    func userNotificationCenter(_ center: UNUserNotificationCenter,
                               didReceive response: UNNotificationResponse,
                               withCompletionHandler handler: @escaping () -> Void) {
        defer { handler() }
        guard let action = ClickAction(userInfo: response.notification.request.content.userInfo) else { return }

        if response.actionIdentifier == Self.replyAction,
           let text = (response as? UNTextInputNotificationResponse)?.userText,
           case .focus(let session, let pane) = action {
            reply(session: session, pane: pane, text: text)
            return
        }
        guard response.actionIdentifier == UNNotificationDefaultActionIdentifier else { return }
        switch action {
        case .focus(let session, let pane): focus(session: session, pane: pane)
        case .open(let target):             open(target: target)
        }
    }

    private func reply(session: String, pane: String, text: String) {
        let clean = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !clean.isEmpty else { return }
        guard let socket = herdr.socketPath(session: session) else {
            Log.error("la sesion '\(session)' ya no esta viva; el prompt no se envia")
            return
        }
        if herdr.prompt(pane: pane, socket: socket, text: clean) {
            Log.info("prompt enviado a \(session) \(pane)")
        } else {
            Log.error("herdr agent prompt fallo en \(session) \(pane)")
        }
    }

    private func focus(session: String, pane: String) {
        guard let script = config.resolvedFocusScript() else {
            Log.error("no encuentro ouija-focus; el clic no puede llevar a ningun sitio")
            return
        }
        let p = Process()
        p.executableURL = URL(fileURLWithPath: "/bin/sh")
        p.arguments = [script, "--session", session, "--pane", pane]
        // launchd arranca con un PATH minimo y el script llama a herdr.
        var env = ProcessInfo.processInfo.environment
        if let herdrBinary = config.resolvedHerdr() {
            let dir = (herdrBinary as NSString).deletingLastPathComponent
            env["PATH"] = "\(dir):\(env["PATH"] ?? "/usr/bin:/bin")"
        }
        p.environment = env
        do { try p.run() } catch { Log.error("ouija-focus no arranco: \(error.localizedDescription)") }
    }

    private func open(target: String) {
        guard !target.isEmpty else { return }
        if let url = URL(string: target), let scheme = url.scheme, scheme != "file" {
            NSWorkspace.shared.open(url)
        } else {
            NSWorkspace.shared.open(URL(fileURLWithPath: (target as NSString).expandingTildeInPath))
        }
    }
}
