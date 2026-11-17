import SwiftUI

/// Las cinco pestañas, en el orden de la barra. Inicio es la primera y la de partida.
enum PestanaRaiz: Hashable {
    case inicio, sesion, consulta, avisos, ajustes
}

/// Cinco pestañas: Inicio (las baldosas de la web), sesión local (sin red), consulta de transporte, avisos locales y
/// ajustes. La lupa ya no tiene pestaña: se abre desde la baldosa «Lupa» de Inicio. La sesión es la del accesorio real;
/// solo las pruebas de interfaz muestran la simulada.
///
/// El menú de modo es una hoja de esta raíz: lo abre el botón de la cabecera de Inicio y elegir un modo vuelve a Inicio.
struct RaizVista: View {
    let entorno: EntornoApp

    @Environment(\.scenePhase) private var faseEscena
    @State private var pestana: PestanaRaiz = .inicio
    @State private var menuModoAbierto = false

    var body: some View {
        TabView(selection: $pestana) {
            InicioVista(entorno: entorno, pestana: $pestana, abrirMenuModo: { menuModoAbierto = true })
                .tabItem { Label("Inicio", systemImage: "house") }
                .tag(PestanaRaiz.inicio)
            if let accesorio = entorno.accesorio {
                SesionAccesorioVista(modelo: accesorio, avisoSintetico: entorno.modoPruebas)
                    .tabItem { Label("Sesión", systemImage: "dot.radiowaves.left.and.right") }
                    .tag(PestanaRaiz.sesion)
            } else {
                SesionVista(modelo: entorno.sesion, avisoModoPruebas: entorno.modoPruebas)
                    .tabItem { Label("Sesión", systemImage: "dot.radiowaves.left.and.right") }
                    .tag(PestanaRaiz.sesion)
            }
            ConsultaVista(
                modelo: entorno.consulta,
                resumenServidor: entorno.modoPruebas ? "Modo de pruebas: sin servidor." : entorno.ajustes.resumen,
                avisoModoPruebas: entorno.modoPruebas)
                .tabItem { Label("Consulta", systemImage: "bubble.left.and.text.bubble.right") }
                .tag(PestanaRaiz.consulta)
            AvisosVista(centro: entorno.avisos, anuncios: entorno.anuncios)
                .tabItem { Label("Avisos", systemImage: "bell") }
                .tag(PestanaRaiz.avisos)
            AjustesVista(entorno: entorno)
                .tabItem { Label("Ajustes", systemImage: "gearshape") }
                .tag(PestanaRaiz.ajustes)
        }
        .sheet(isPresented: $menuModoAbierto) {
            MenuModoVista(modo: entorno.modo.modo, alElegir: elegirModo, alCerrar: { menuModoAbierto = false })
        }
        // Íconos, enlaces e interruptores toman la tinta de la paleta y no el color de acento del sistema.
        .tint(Paleta.foreground)
        // «Alto contraste»: sin elección propia (`nil`) manda la apariencia del sistema; con ella, la paleta que eligió la persona.
        .preferredColorScheme(entorno.altoContraste.elegido.map { $0 ? .dark : .light })
        // Solo en primer plano y activa: inactiva (bloqueo, centro de control) o en segundo plano se suspende.
        .onChange(of: faseEscena) { _, nueva in
            entorno.accesorio?.escenaActiva(nueva == .active)
            // La ubicación no corre en segundo plano ni se reanuda sola. `.inactive` no la suelta: el aviso de permiso del
            // sistema deja la app inactiva un momento.
            if nueva == .background { entorno.serviciosRutas.gps.suspender() }
        }
        // «Mapa y GPS» queda empujada en la pila de la pestaña que la abrió: cambiar de pestaña la suelta sin esperar a que
        // el sistema avise a una pantalla ya cubierta. No se reanuda sola al volver.
        .onChange(of: pestana) { _, _ in entorno.serviciosRutas.gps.suspender() }
        // Red caída y datos viejos nacen del resultado de la consulta; la consulta no sabe de avisos.
        .onChange(of: entorno.consulta.estado) { _, nuevo in entorno.avisos.consultaCambio(nuevo) }
    }

    /// Igual que `changeMode` de la web: guarda el modo, cierra el menú, vuelve a Inicio y lo anuncia.
    private func elegirModo(_ nuevo: ModoApp) {
        entorno.modo.elegir(nuevo)
        menuModoAbierto = false
        pestana = .inicio
        AccessibilityNotification.Announcement(nuevo.anuncio).post()
    }
}
