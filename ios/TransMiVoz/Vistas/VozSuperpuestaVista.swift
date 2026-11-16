import SwiftUI

/// Superposición de la búsqueda por voz: lo que la web llama `VoiceOverlay` (`components/voice-overlay.tsx`). Un micrófono
/// grande, lo que se va oyendo, el botón «Detener» / «Hablar de nuevo» y el aviso de adónde va el audio. Todo el trabajo
/// (abrir el micrófono, entregar el texto final, soltar la captura al cerrar) es de `RutasVozModelo` sobre el dictado de la
/// app; aquí solo se dibuja el estado. Cerrar y escribir la búsqueda a mano siempre es posible.
///
/// Con los colores y estilos de la base (`Paleta`, `EstiloBotonSecundario`); el diseño final de la pantalla queda para la
/// pasada visual.
struct VozSuperpuestaVista: View {
    let modelo: RutasVozModelo

    @Environment(\.openURL) private var abrirURL
    @ScaledMetric(relativeTo: .largeTitle) private var ladoMicrofono: CGFloat = 112

    private var estado: EstadoDictado { modelo.dictado?.estado ?? .inactivo }
    private var capturando: Bool { estado.capturando }

    var body: some View {
        ZStack {
            Paleta.background.ignoresSafeArea()
            ScrollView {
                VStack(spacing: 24) {
                    HStack {
                        Spacer(minLength: 0)
                        Button { modelo.cerrar() } label: {
                            Image(systemName: "xmark")
                                .font(.title2.weight(.bold))
                                .foregroundStyle(Paleta.cardForeground)
                                .frame(width: 48, height: 48)
                                .background(Paleta.card, in: RoundedRectangle(cornerRadius: Tema.radio2XL))
                                .overlay(RoundedRectangle(cornerRadius: Tema.radio2XL).strokeBorder(Paleta.border, lineWidth: Tema.borde))
                                .frame(minWidth: Tema.objetivoMinimo, minHeight: Tema.objetivoMinimo)
                                .contentShape(Rectangle())
                        }
                        .accessibilityLabel(TextoRutas.cerrarMicrofono)
                        .accessibilityIdentifier("boton-cerrar-voz")
                    }

                    Image(systemName: capturando ? "mic.fill" : "mic")
                        .font(.system(size: ladoMicrofono * 0.5, weight: .semibold))
                        .foregroundStyle(capturando ? Paleta.brandForeground : Paleta.brandInk)
                        .frame(width: ladoMicrofono, height: ladoMicrofono)
                        .background(capturando ? Paleta.brand : Paleta.brandSoft, in: Circle())
                        .overlay(Circle().strokeBorder(Paleta.border, lineWidth: Tema.borde))
                        .accessibilityHidden(true)

                    Text(titulo)
                        .font(.jakarta(.semibold, .xl))
                        .multilineTextAlignment(.center)
                        .accessibilityAddTraits(.isHeader)
                        .accessibilityIdentifier("voz-estado")

                    if !modelo.transcripcion.isEmpty {
                        Text(TextoRutas.vozTranscripcion(modelo.transcripcion))
                            .font(.jakarta(.regular, .lg))
                            .multilineTextAlignment(.center)
                            .accessibilityIdentifier("voz-transcripcion")
                    }

                    mensaje

                    Button { modelo.alternar() } label: {
                        Text(estado.enCurso ? TextoRutas.vozDetener : TextoRutas.vozHablarDeNuevo)
                    }
                    .buttonStyle(EstiloBotonSecundario())
                    .disabled(!modelo.disponible)
                    .accessibilityIdentifier("boton-voz-alternar")

                    notas
                }
                .padding(16)
                .frame(maxWidth: .infinity)
            }
        }
        .foregroundStyle(Paleta.foreground)
        .onAppear { modelo.dictado?.actualizarCapacidad() }
        // El texto final cierra la superposición y lo entrega `RutasVozModelo`; un estado que no puede seguir (sin permiso,
        // sin servicio) se queda aquí, dicho, y la persona cierra y escribe.
        .onChange(of: modelo.dictado?.estado) { _, nuevo in
            if let nuevo { modelo.estadoCambio(nuevo) }
        }
        .onDisappear { modelo.cerrar() }
    }

    /// «Escuchando…», «Listo» o «Toca para hablar», como la web.
    private var titulo: String {
        if capturando { return TextoRutas.vozEscuchando }
        return modelo.transcripcion.isEmpty ? TextoRutas.vozTocaParaHablar : TextoRutas.vozListo
    }

    /// Por qué no se oye: sin dictado, o el estado del dictado (permiso, servicio, nada entendido). Con «Abrir Ajustes» si el
    /// permiso está negado. Escuchando y en reposo no dicen nada aquí.
    @ViewBuilder private var mensaje: some View {
        if let dictado = modelo.dictado {
            if estado != .inactivo, estado != .escuchando {
                Text(TextoDictado.descripcion(estado, capacidad: dictado.capacidad))
                    .font(.jakarta(.semibold, .base))
                    .multilineTextAlignment(.center)
                    .accessibilityIdentifier("voz-mensaje")
            }
            if estado == .permisoDenegado || estado == .permisoRestringido {
                Button(TextoDictado.abrirAjustes) {
                    if let url = URL(string: UIApplication.openSettingsURLString) { abrirURL(url) }
                }
                .buttonStyle(EstiloBotonSecundario())
                .accessibilityIdentifier("boton-voz-abrir-ajustes")
            }
        } else {
            Text(TextoRutas.vozSinDictado)
                .font(.jakarta(.semibold, .base))
                .multilineTextAlignment(.center)
                .accessibilityIdentifier("voz-mensaje")
        }
    }

    /// Adónde va el audio según el sistema, qué se envía al servidor y la alternativa por texto.
    @ViewBuilder private var notas: some View {
        VStack(spacing: 8) {
            if let dictado = modelo.dictado {
                Text(TextoDictado.capacidad(dictado.capacidad))
                if let rotulo = dictado.rotuloPruebas {
                    Text(rotulo).accessibilityIdentifier("aviso-dictado-sintetico")
                }
            }
            Text(TextoRutas.vozAvisoServidor)
            Text(TextoRutas.vozAvisoEscribir)
        }
        .font(.jakarta(.regular, .sm))
        .multilineTextAlignment(.center)
    }
}
