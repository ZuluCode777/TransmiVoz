import SwiftUI

/// Inicio del modo «Ceguera total» (web: `components/total-agent.tsx`): el asistente de voz a pantalla completa, sin las
/// baldosas. `InicioVista` lo pone en lugar de las baldosas cuando el modo es `.total`.
///
/// Se construye sobre la `ConsultaModelo` de la app (`entorno.consulta`): la misma consulta, dictado y voz que la pestaña
/// Consulta, sin otro reconocedor ni otro dueño del audio.
struct AgenteTotalVista: View {
    let consulta: ConsultaModelo

    var body: some View {
        AgenteTotalContenido(consulta: consulta)
    }
}
