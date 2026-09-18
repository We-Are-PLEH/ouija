import AppKit
import Foundation

/// Vigila el estado de los agentes de herdr y avisa en cada transicion que
/// importa.
///
/// Se muestrea `herdr api snapshot` porque la API de herdr 0.9.0 no ofrece
/// suscripcion a eventos. El duplicado se evita con `state_change_seq`, que es
/// monotono: sin el, un mismo `blocked` avisaria en cada vuelta.
final class Watcher {
    /// Ultimo estado visto de un panel. `since` marca cuando entro en el, y
    /// `pending` si todavia debe un aviso.
    private struct Seen {
        let status: String
        let seq: Int
        let since: Date
        var pending: Bool
    }

    private let config: Config
    private let herdr: Herdr
    private let notifier: Notifier
    private var seen: [String: Seen] = [:]
    private let startedAt = Date()
    private var timer: Timer?

    init(config: Config, herdr: Herdr, notifier: Notifier) {
        self.config = config
        self.herdr = herdr
        self.notifier = notifier
    }

    func start() {
        Log.info("vigilando cada \(config.pollSeconds) s; estados que avisan: \(config.notifyStates.joined(separator: ", "))")
        let t = Timer(timeInterval: config.pollSeconds, repeats: true) { [weak self] _ in self?.tick() }
        RunLoop.main.add(t, forMode: .common)
        timer = t
        tick()
    }

    private var warmedUp: Bool { Date().timeIntervalSince(startedAt) >= config.startupGraceSeconds }

    private func tick() {
        let now = Date()
        var alive: Set<String> = []

        for session in herdr.runningSessions() {
            for agent in herdr.agents(of: session) {
                let key = agent.key(session: session.name)
                alive.insert(key)
                let previous = seen[key]
                let changed = previous == nil
                    || previous!.status != agent.status
                    || agent.seq > previous!.seq

                if changed {
                    // El aviso anterior de este panel ya no describe la realidad:
                    // fuera del centro de notificaciones antes de publicar nada.
                    if previous != nil { notifier.withdraw(thread: key) }
                    // Transicion: empieza a contar el tiempo en el estado nuevo.
                    // Un aviso pendiente del estado anterior se descarta aqui, que
                    // es justo lo que queremos: si lo resolviste, no suena.
                    let deserves = warmedUp && previous != nil && config.notifyStates.contains(agent.status)
                    seen[key] = Seen(status: agent.status, seq: agent.seq, since: now, pending: deserves)
                } else if previous != nil {
                    seen[key] = previous
                }

                guard var state = seen[key], state.pending else { continue }
                guard now.timeIntervalSince(state.since) >= config.minSeconds(for: agent.status) else { continue }
                guard !isBeingWatched(agent) else {
                    // Estas delante: no hay nada que avisar, y no se vuelve a intentar.
                    state.pending = false
                    seen[key] = state
                    continue
                }
                state.pending = false
                seen[key] = state
                announce(agent, session: session)
            }
        }
        // Paneles cerrados: fuera del mapa, que si no crece sin fin, y sin dejar
        // atras un aviso que apunta a un panel que ya no existe.
        for key in seen.keys where !alive.contains(key) { notifier.withdraw(thread: key) }
        seen = seen.filter { alive.contains($0.key) }
    }

    /// Callar el aviso cuando ya estas delante: el panel tiene el foco dentro de
    /// herdr y el terminal es la aplicacion en primer plano.
    private func isBeingWatched(_ agent: HerdrAgent) -> Bool {
        guard agent.focused else { return false }
        return NSWorkspace.shared.frontmostApplication?.bundleIdentifier == config.terminalBundleID
    }

    private func announce(_ agent: HerdrAgent, session: HerdrSession) {
        let project = agent.cwd.isEmpty ? "" : (agent.cwd as NSString).lastPathComponent
        let values: [String: String] = [
            "title": agent.title.isEmpty ? "\(session.name) · \(agent.paneID)" : agent.title,
            "agent": agent.agent,
            "session": session.name,
            "pane": agent.paneID,
            "tab": agent.tabID,
            "workspace": agent.workspaceID,
            "project": project,
            "cwd": agent.cwd,
            "status": agent.status,
        ]
        let text = config.template(for: agent.status).render(values)
        Log.info("aviso: \(session.name) \(agent.paneID) \(agent.status) — \(text.title)")
        notifier.post(
            title: text.title,
            subtitle: text.subtitle,
            body: text.body,
            sound: config.sounds[agent.status],
            thread: agent.key(session: session.name),
            action: .focus(session: session.name, pane: agent.paneID),
            iconPath: config.icon(for: agent.agent)
        )
    }
}
