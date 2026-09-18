import Foundation

/// Plantilla de texto de un aviso. Los tres campos admiten marcadores:
/// `{title} {agent} {session} {pane} {tab} {workspace} {project} {cwd} {status}`.
struct Template {
    var title: String
    var subtitle: String
    var body: String

    func render(_ values: [String: String]) -> (title: String, subtitle: String, body: String) {
        func fill(_ s: String) -> String {
            var out = s
            for (k, v) in values { out = out.replacingOccurrences(of: "{\(k)}", with: v) }
            return out.trimmingCharacters(in: .whitespaces)
        }
        return (fill(title), fill(subtitle), fill(body))
    }
}

/// Ajustes de Ouija.
///
/// Todo lo que puede cambiar de una maquina a otra —cada cuanto se muestrea, que
/// estados avisan, con que texto y con que sonido— vive en el fichero de
/// configuracion. El codigo solo trae los valores por defecto: ni un nombre de
/// sesion, ni un id de pestana, ni una ruta de usuario escritos a mano.
struct Config {
    var pollSeconds: Double = 1.5
    /// Estados de `herdr api snapshot` que merecen aviso. `blocked` = te necesita,
    /// `done` = termino el turno.
    var notifyStates: [String] = ["blocked", "done"]
    var sounds: [String: String] = ["blocked": "Ping", "done": "Glass"]
    /// Cuanto tiene que llevar un panel en ese estado antes de avisar. Un permiso
    /// que resuelves en tres segundos no merece notificacion.
    var minStateSeconds: [String: Double] = ["blocked": 5, "done": 0]
    var templates: [String: Template] = [
        "blocked": Template(title: "{title}", subtitle: "{agent} · {session}", body: "Necesita tu input"),
        "done":    Template(title: "{title}", subtitle: "{agent} · {session}", body: "Turno terminado"),
    ]
    /// Plantilla para un estado sin entrada propia.
    var fallbackTemplate = Template(title: "{title}", subtitle: "{agent} · {session}", body: "{status}")
    /// Margen tras arrancar en el que solo se toma nota del estado, sin avisar:
    /// si no, el primer muestreo dispara un aviso por cada panel ya parado.
    var startupGraceSeconds: Double = 5
    /// Bundle id del terminal que hospeda al multiplexor. Se usa para callar el
    /// aviso cuando ya estas mirando ese panel.
    var terminalBundleID: String = "com.mitchellh.ghostty"
    /// Ofrecer un campo de texto en la notificacion que manda el prompt al agente.
    var replyEnabled: Bool = true
    var replyButtonTitle: String = "Responder"
    /// Ruta del script de foco. Por defecto, el que viaja dentro del .app.
    var focusScript: String?
    /// Ruta del binario de herdr. launchd arranca con un PATH minimo, asi que
    /// conviene poder fijarla.
    var herdrPath: String?

    static var fileURL: URL {
        let env = ProcessInfo.processInfo.environment
        let base = env["XDG_CONFIG_HOME"].map { URL(fileURLWithPath: $0) }
            ?? FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".config")
        return base.appendingPathComponent("ouija/config.json")
    }

    /// Lee el fichero si existe. Un fichero ilegible no tumba el agente: se avisa
    /// por el log y se sigue con los valores por defecto.
    static func load() -> Config {
        var cfg = Config()
        guard let data = try? Data(contentsOf: fileURL) else { return cfg }
        guard let raw = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any] else {
            Log.error("configuracion ilegible en \(fileURL.path); se usan los valores por defecto")
            return cfg
        }
        if let v = raw["pollSeconds"] as? Double, v > 0 { cfg.pollSeconds = v }
        if let v = raw["notifyStates"] as? [String], !v.isEmpty { cfg.notifyStates = v }
        if let v = raw["sounds"] as? [String: String] { cfg.sounds = v }
        if let v = raw["minStateSeconds"] as? [String: Double] { cfg.minStateSeconds.merge(v) { _, new in new } }
        if let v = raw["startupGraceSeconds"] as? Double, v >= 0 { cfg.startupGraceSeconds = v }
        if let v = raw["terminalBundleID"] as? String, !v.isEmpty { cfg.terminalBundleID = v }
        if let v = raw["replyEnabled"] as? Bool { cfg.replyEnabled = v }
        if let v = raw["replyButtonTitle"] as? String, !v.isEmpty { cfg.replyButtonTitle = v }
        if let v = raw["focusScript"] as? String, !v.isEmpty { cfg.focusScript = v }
        if let v = raw["herdrPath"] as? String, !v.isEmpty { cfg.herdrPath = v }
        if let v = raw["templates"] as? [String: [String: String]] {
            for (state, fields) in v {
                let base = cfg.templates[state] ?? cfg.fallbackTemplate
                cfg.templates[state] = Template(
                    title:    fields["title"]    ?? base.title,
                    subtitle: fields["subtitle"] ?? base.subtitle,
                    body:     fields["body"]     ?? base.body
                )
            }
        }
        return cfg
    }

    func template(for state: String) -> Template { templates[state] ?? fallbackTemplate }
    func minSeconds(for state: String) -> Double { minStateSeconds[state] ?? 0 }

    /// Script de foco: el de la configuracion, o el que va dentro del bundle.
    func resolvedFocusScript() -> String? {
        if let s = focusScript, FileManager.default.isExecutableFile(atPath: s) { return s }
        if let s = Bundle.main.url(forResource: "ouija-focus", withExtension: nil)?.path,
           FileManager.default.isExecutableFile(atPath: s) { return s }
        return nil
    }

    /// Binario de herdr: el de la configuracion, el del PATH, o los prefijos
    /// habituales de Homebrew. Sin esto, bajo launchd no se encuentra.
    func resolvedHerdr() -> String? {
        var candidates: [String] = []
        if let h = herdrPath { candidates.append(h) }
        let env = ProcessInfo.processInfo.environment
        for dir in (env["PATH"] ?? "").split(separator: ":") { candidates.append("\(dir)/herdr") }
        candidates.append(contentsOf: ["/opt/homebrew/bin/herdr", "/usr/local/bin/herdr"])
        return candidates.first { FileManager.default.isExecutableFile(atPath: $0) }
    }
}

/// Log a stderr; launchd lo recoge en el fichero que fija el plist.
enum Log {
    private static let stamp: DateFormatter = {
        let f = DateFormatter(); f.dateFormat = "yyyy-MM-dd HH:mm:ss"; return f
    }()
    static func info(_ msg: String)  { write("INFO  \(msg)") }
    static func error(_ msg: String) { write("ERROR \(msg)") }
    private static func write(_ msg: String) {
        FileHandle.standardError.write(Data("\(stamp.string(from: Date()))  \(msg)\n".utf8))
    }
}
