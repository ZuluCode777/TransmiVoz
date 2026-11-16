import SwiftUI

/// Inicio del modo «Ceguera total» (web: `components/total-agent.tsx`): el asistente de voz a pantalla completa, sin las
/// baldosas. `InicioVista` lo pone en lugar de las baldosas cuando el modo es `.total`.
///
/// Se construye sobre la `ConsultaModelo` de la app (`entorno.consulta`): la misma consulta, dictado y voz que la pestaña
/// Consulta. **Dependencia de integración**: `InicioVista` debe pasarla, `AgenteTotalVista(consulta: entorno.consulta)`. Mientras
/// no lo haga (`AgenteTotalVista()`) se queda el marcador provisional de la base, que compila y no hace nada.
struct AgenteTotalVista: View {
    /// Única línea provisional de esta pantalla, solo mientras `InicioVista` no pasa la consulta.
    static let textoProvisional = "Ceguera total: el Inicio de voz está en construcción."

    private let consulta: ConsultaModelo?

    init(consulta: ConsultaModelo? = nil) {
        self.consulta = consulta
    }

    var body: some View {
        if let consulta {
            AgenteTotalContenido(consulta: consulta)
        } else {
            ScrollView {
                Text(Self.textoProvisional)
                    .font(.jakarta(.bold, .lg))
                    .tarjetaWeb()
                    .accessibilityIdentifier("provisional-agente-total")
                    .padding(16)
            }
            .bordeInferiorLegible()
        }
    }
}
