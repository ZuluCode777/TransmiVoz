import SwiftUI

/// Preferencias con efecto en la app hoy: la voz propia de los avisos del accesorio. Es el MISMO estado que el
/// interruptor de la pestaña Sesión (`SesionAccesorioModelo.fijarVozPropia`), no una copia; y «Alto contraste», el
/// interruptor de colores fluorescentes de la web (`AltoContrasteModelo`). El resto (texto, VoiceOver) lo decide iOS.
struct PreferenciasVista: View {
    /// `nil` solo en las pruebas de interfaz de la sesión simulada.
    let accesorio: SesionAccesorioModelo?
    let altoContraste: AltoContrasteModelo

    /// Lo que se ve ahora mismo: mientras la persona no elija, el interruptor muestra la apariencia del sistema.
    @Environment(\.colorScheme) private var esquema

    /// Solo para que la pantalla se redibuje si la persona enciende o apaga VoiceOver con la app abierta;
    /// la política sigue en el modelo (`vozPropiaActiva`).
    @Environment(\.accessibilityVoiceOverEnabled) private var voiceOverActivo

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                voz
                sistema
            }
            .padding(16)
        }
        .pantallaWeb()
        .navigationTitle("Preferencias")
        .navigationBarTitleDisplayMode(.inline)
        .bordeInferiorLegible()
    }

    private func vozPropiaActiva(_ accesorio: SesionAccesorioModelo) -> Bool {
        _ = voiceOverActivo
        return accesorio.vozPropiaActiva
    }

    private var voz: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(TextoPreferencias.tituloVoz)
                .font(.headline)
                .accessibilityAddTraits(.isHeader)
            if let accesorio {
                Toggle(isOn: Binding(
                    get: { vozPropiaActiva(accesorio) },
                    set: { accesorio.fijarVozPropia($0) })) {
                        Text(TextoPreferencias.etiquetaVoz)
                            .accessibilityIdentifier("etiqueta-interruptor-voz-preferencias")
                    }
                    .tint(Paleta.ok)
                    .frame(minHeight: 44)
                    .accessibilityIdentifier("interruptor-voz-preferencias")
                Text(TextoPreferencias.notaVoz)
                    .font(.footnote)
                    .foregroundStyle(.textoSecundario)
                    .fixedSize(horizontal: false, vertical: true)
                    .accessibilityIdentifier("nota-voz-preferencias")
            } else {
                Text(TextoPreferencias.sinAccesorio)
                    .fixedSize(horizontal: false, vertical: true)
                    .accessibilityIdentifier("sin-voz-preferencias")
            }
        }
    }

    private var sistema: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(TextoPreferencias.tituloSistema)
                .font(.headline)
                .accessibilityAddTraits(.isHeader)
            Toggle(isOn: Binding(
                get: { altoContraste.elegido ?? (esquema == .dark) },
                set: { activo in
                    altoContraste.elegir(activo)
                    AccessibilityNotification.Announcement(AltoContrasteModelo.anuncio(activo)).post()
                })) {
                    Text(TextoPreferencias.etiquetaAltoContraste)
                        .accessibilityIdentifier("etiqueta-interruptor-alto-contraste")
                }
                .tint(Paleta.ok)
                .frame(minHeight: 44)
                .accessibilityIdentifier("interruptor-alto-contraste")
            Text(TextoPreferencias.notaAltoContraste)
                .font(.footnote)
                .foregroundStyle(.textoSecundario)
                .fixedSize(horizontal: false, vertical: true)
                .accessibilityIdentifier("nota-alto-contraste")
            Text(TextoPreferencias.notaSistema)
                .fixedSize(horizontal: false, vertical: true)
                .accessibilityIdentifier("nota-sistema-preferencias")
        }
    }
}
