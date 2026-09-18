import Foundation

/// Una sesion de herdr con su socket. El socket es lo que permite hablar con una
/// sesion que no es la nuestra: `herdr --session X` arrancaria o se adjuntaria a
/// ella en vez de consultar su API.
struct HerdrSession {
    let name: String
    let socketPath: String
}

/// Un pane con agente, tal y como lo describe `herdr api snapshot`.
struct HerdrAgent {
    let agent: String          // claude, codex, droid...
    let status: String         // idle | working | blocked | done | unknown
    let paneID: String         // w3:p12
    let tabID: String
    let workspaceID: String
    let title: String          // terminal_title_stripped
    let cwd: String
    let focused: Bool
    let seq: Int               // state_change_seq, monotono

    /// Identidad estable de un pane entre muestreos.
    func key(session: String) -> String { "\(session)|\(paneID)" }
}

/// Lector del estado de herdr. Solo lee: no enfoca, no escribe, no arranca nada.
struct Herdr {
    let binary: String

    private func run(_ args: [String], socket: String? = nil) -> Data? {
        let p = Process()
        p.executableURL = URL(fileURLWithPath: binary)
        p.arguments = args
        var env = ProcessInfo.processInfo.environment
        if let socket { env["HERDR_SOCKET_PATH"] = socket }
        p.environment = env
        let out = Pipe()
        p.standardOutput = out
        p.standardError = FileHandle.nullDevice
        do { try p.run() } catch {
            Log.error("no se pudo ejecutar \(binary): \(error.localizedDescription)")
            return nil
        }
        let data = out.fileHandleForReading.readDataToEndOfFile()
        p.waitUntilExit()
        guard p.terminationStatus == 0 else { return nil }
        return data
    }

    /// Sesiones vivas. Una sesion parada no tiene socket que responda.
    func runningSessions() -> [HerdrSession] {
        guard let data = run(["session", "list", "--json"]),
              let root = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any],
              let list = root["sessions"] as? [[String: Any]] else { return [] }
        return list.compactMap { s in
            guard s["running"] as? Bool == true,
                  let name = s["name"] as? String,
                  let socket = s["socket_path"] as? String else { return nil }
            return HerdrSession(name: name, socketPath: socket)
        }
    }

    /// Agentes de una sesion. Se validan los campos que se usan: si herdr cambia
    /// el esquema en una actualizacion, el fallo se ve en el log en vez de
    /// quedarse callado con cero agentes.
    func agents(of session: HerdrSession) -> [HerdrAgent] {
        guard let data = run(["api", "snapshot"], socket: session.socketPath) else { return [] }
        guard let root = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any],
              let result = root["result"] as? [String: Any],
              let snapshot = result["snapshot"] as? [String: Any],
              let list = snapshot["agents"] as? [[String: Any]] else {
            Log.error("snapshot de '\(session.name)' sin la forma esperada result.snapshot.agents")
            return []
        }
        return list.compactMap { a in
            guard let status = a["agent_status"] as? String,
                  let paneID = a["pane_id"] as? String else {
                Log.error("agente sin agent_status o pane_id en '\(session.name)'")
                return nil
            }
            return HerdrAgent(
                agent: a["agent"] as? String ?? "agente",
                status: status,
                paneID: paneID,
                tabID: a["tab_id"] as? String ?? "",
                workspaceID: a["workspace_id"] as? String ?? "",
                title: (a["terminal_title_stripped"] as? String) ?? (a["terminal_title"] as? String) ?? "",
                cwd: a["cwd"] as? String ?? "",
                focused: a["focused"] as? Bool ?? false,
                seq: a["state_change_seq"] as? Int ?? 0
            )
        }
    }
}

extension Herdr {
    /// Socket de una sesion viva, por nombre. Hace falta en el clic: la
    /// notificacion solo lleva el nombre, y hablar con otra sesion exige su socket.
    func socketPath(session: String) -> String? {
        runningSessions().first { $0.name == session }?.socketPath
    }

    /// Manda un prompt al agente de un panel. Es lo que respalda el campo de
    /// texto de la notificacion: contestar sin ir a la pestana.
    ///
    /// No aprueba dialogos de permiso —eso son pulsaciones de tecla, y aprobar a
    /// ciegas lo que no has leido es mala idea—, solo escribe un prompt.
    @discardableResult
    func prompt(pane: String, socket: String, text: String) -> Bool {
        run(["agent", "prompt", pane, text], socket: socket) != nil
    }
}
