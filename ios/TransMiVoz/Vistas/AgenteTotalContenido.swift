import SwiftUI

/// El asistente de voz de «Ceguera total» con sus controles (web: `components/total-agent.tsx`). La lógica vive en
/// `AgenteTotalModelo`; aquí solo se arma la pantalla con los componentes de la base (`ComponentesWeb`).
///
/// Va dentro de la `NavigationStack` de Inicio: las pantallas a las que lleva (`DestinoAgenteTotal`) se empujan en esa misma
/// pila con `navigationDestination(item:)`, sin pasar por `InicioVista`.
struct AgenteTotalContenido: View {
    @State private var agente: AgenteTotalModelo
    let servicios: ServiciosRutas
    @Environment(\.scenePhase) private var faseEscena
    @Environment(\.openURL) private var abrirURL
    @FocusState private var campoEnfocado: Bool

    /// La pestaña Inicio es la elegida en la raíz. Al pasar a `false` se corta lo que dejó sonando la respuesta que abrió otra pantalla:
    /// `onDisappear` ya no avisa (esta pantalla estaba cubierta desde antes).
    let inicioVisible: Bool

    init(consulta: ConsultaModelo, servicios: ServiciosRutas, inicioVisible: Bool) {
        self.servicios = servicios
        self.inicioVisible = inicioVisible
        _agente = State(initialValue: AgenteTotalModelo(consulta: consulta, avisos: .sistema))
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                microfono
                lineaDeEstado
                origenPendiente
                accionesDeEstado
                resultado
                campoDeTexto
                lineaDelDictado
                otrasPantallas
                privacidad
            }
            .padding(16)
        }
        .scrollDismissesKeyboard(.interactively)
        .bordeInferiorLegible()
        .bordeSuperiorNitido()
        // El «toque mágico» de VoiceOver (dos dedos, doble toque) es el micrófono desde cualquier punto de la pantalla.
        .accessibilityAction(.magicTap) { agente.tocarMicrofono() }
        .navigationDestination(item: Binding(get: { agente.destino }, set: { if $0 == nil { agente.destinoCerrado() } })) { destino in
            pantalla(destino)
        }
        .onAppear { agente.alAparecer() }
        .onDisappear { agente.alDesaparecer() }
        .onChange(of: inicioVisible) { _, visible in
            if !visible { agente.alSalirDeInicio() }
        }
        .onChange(of: agente.consulta.estado) { _, nuevo in agente.consultaCambio(nuevo) }
        .onChange(of: agente.consulta.dictado?.estado) { _, nuevo in
            if let nuevo { agente.dictadoCambio(nuevo) }
        }
        // Cada texto final del dictado se envía solo; `ultimoDictado` pasa a `nil` al enviarlo y esa vuelta no cuenta.
        .onChange(of: agente.consulta.dictado?.ultimoDictado) { _, nuevo in
            if nuevo != nil { agente.dictadoTerminado() }
        }
        // En segundo plano no hay micrófono ni voz: inactiva no cuenta (los avisos de permiso del sistema la provocan).
        .onChange(of: faseEscena) { _, nueva in
            if nueva == .background { agente.alPasarASegundoPlano() }
        }
    }

    // MARK: Micrófono y estado

    /// Toda la zona es el botón de hablar, como en la web: toca para empezar, otra vez para terminar y enviar.
    private var microfono: some View {
        Button { agente.tocarMicrofono() } label: {
            VStack(spacing: 12) {
                Group {
                    switch agente.fase {
                    case .pensando: ProgressView().controlSize(.large)
                    case .escuchando: Image(systemName: "ear.fill").font(.largeTitle.weight(.bold))
                    case .reposo: Image(systemName: "mic.fill").font(.largeTitle.weight(.bold))
                    }
                }
                .accessibilityHidden(true)
                Text(agente.titulo)
                    .font(.jakarta(.extrabold, .xl3))
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .frame(maxWidth: .infinity, minHeight: 160)
        }
        .buttonStyle(EstiloBotonPrimario())
        // La etiqueta no cambia: el estado va en el valor y lo que hace el toque, en la pista.
        .accessibilityLabel(TextoAgenteTotal.etiquetaMicrofono)
        .accessibilityValue(agente.valorMicrofono)
        .accessibilityHint(agente.pistaMicrofono)
        .accessibilityIdentifier("agente-total-microfono")
    }

    /// La «caption» de la web: qué hace el asistente o qué pasó con la última pregunta. Todo lo que dice también va a la voz.
    private var lineaDeEstado: some View {
        VStack(alignment: .leading, spacing: 8) {
            if let pregunta = agente.consulta.ultimoTextoEnviado, agente.fase != .escuchando {
                Text("Preguntaste: “\(pregunta)”")
                    .font(.jakarta(.semibold, .base))
                    .accessibilityIdentifier("agente-total-pregunta")
            }
            Text(agente.subtitulo)
                .font(.jakarta(.regular, .lg))
                .fixedSize(horizontal: false, vertical: true)
                .accessibilityIdentifier("agente-total-estado")
        }
        .foregroundStyle(Paleta.foreground)
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    /// La aclaración de EA-19: el origen que la persona dijo y al que falta el destino. La siguiente pregunta lo toma como destino.
    @ViewBuilder private var origenPendiente: some View {
        if let origen = agente.consulta.origenPendiente {
            VStack(alignment: .leading, spacing: 8) {
                Text("Origen pendiente: \(origen)")
                    .font(.jakarta(.bold, .lg))
                    .accessibilityHint("Tu próxima pregunta se toma como el destino.")
                    .accessibilityIdentifier("agente-total-origen-pendiente")
                Button("Olvidar origen") { agente.olvidarOrigen() }
                    .buttonStyle(EstiloBotonSecundario())
                    .accessibilityIdentifier("agente-total-olvidar-origen")
            }
            .foregroundStyle(Paleta.foreground)
        }
    }

    /// «Cancelar» mientras escucha o piensa; «Reintentar» tras un fallo o una cancelación.
    @ViewBuilder private var accionesDeEstado: some View {
        if agente.fase != .reposo {
            Button(TextoAgenteTotal.cancelar) { agente.cancelar() }
                .buttonStyle(EstiloBotonSecundario())
                .accessibilityIdentifier("agente-total-cancelar")
        } else if agente.puedeReintentar {
            Button(agente.consulta.etiquetaDeRepetir("Reintentar")) { agente.reintentar() }
                .buttonStyle(EstiloBotonSecundario())
                .accessibilityIdentifier("agente-total-reintentar")
        }
    }

    // MARK: Resultado

    /// «Lo que hice» (web): el motor y los pasos del servidor. Un viaje no muestra pasos: solo se presenta como información.
    @ViewBuilder private var resultado: some View {
        if let respuesta = agente.respuesta {
            let esViaje: Bool = { if case .viaje = respuesta.accion { return true } else { return false } }()
            if !respuesta.pasos.isEmpty && !esViaje {
                VStack(alignment: .leading, spacing: 8) {
                    Text(TextoAgenteTotal.leQueHice)
                        .font(.jakarta(.bold, .lg))
                        .accessibilityAddTraits(.isHeader)
                    Text(TextoAgenteTotal.motor(respuesta.motor))
                        .font(.jakarta(.semibold, .base))
                        .accessibilityIdentifier("agente-total-motor")
                    ForEach(Array(respuesta.pasos.enumerated()), id: \.offset) { _, paso in
                        VStack(alignment: .leading, spacing: 2) {
                            Text(paso.etiqueta).font(.jakarta(.regular, .lg))
                            if let detalle = paso.detalle { Text(detalle).font(.jakarta(.regular, .base)) }
                        }
                        .accessibilityElement(children: .combine)
                    }
                }
                .fixedSize(horizontal: false, vertical: true)
                .tarjetaWeb()
                .accessibilityIdentifier("agente-total-pasos")
            }
            if esViaje {
                Button(TextoAgenteTotal.planearViaje) { agente.abrir(.viaje) }
                    .buttonStyle(EstiloBotonSecundario())
                    .accessibilityIdentifier("agente-total-enlace-viaje")
            }
        }
    }

    // MARK: Escribir

    /// La alternativa al dictado (web: el formulario de abajo). Va por `editarTexto`: una edición deja de contar como «lo dictado».
    private var campoDeTexto: some View {
        VStack(alignment: .leading, spacing: 12) {
            TextField(
                TextoAgenteTotal.marcadorCampo,
                text: Binding(get: { agente.consulta.texto }, set: { agente.consulta.editarTexto($0) }), axis: .vertical
            )
            .lineLimit(1...5)
            .textFieldStyle(.roundedBorder)
            .frame(minHeight: 44)
            .focused($campoEnfocado)
            .submitLabel(.send)
            .onSubmit { enviar() }
            .accessibilityLabel(TextoAgenteTotal.campo)
            .accessibilityHint("Máximo \(EscenarioConsulta.transporte.maximoCaracteres) caracteres.")
            .accessibilityIdentifier("agente-total-campo")

            Button { enviar() } label: {
                Label(TextoAgenteTotal.enviar, systemImage: "paperplane.fill")
            }
            .buttonStyle(EstiloBotonPrimario())
            .disabled(agente.consulta.estaEnviando)
            .accessibilityIdentifier("agente-total-enviar")
        }
    }

    /// Cierra el teclado antes de enviar: si no, tapa el resultado.
    private func enviar() {
        campoEnfocado = false
        agente.preguntar()
    }

    /// Adónde va el audio del dictado y, si no hay permiso, el camino a Ajustes (los mismos textos que la pestaña Consulta).
    @ViewBuilder private var lineaDelDictado: some View {
        if let dictado = agente.consulta.dictado {
            VStack(alignment: .leading, spacing: 8) {
                Text(TextoDictado.descripcion(dictado.estado, capacidad: dictado.capacidad))
                    .font(.jakarta(.regular, .sm))
                    .fixedSize(horizontal: false, vertical: true)
                    .accessibilityIdentifier("agente-total-dictado")
                if let rotulo = dictado.rotuloPruebas {
                    Text(rotulo)
                        .font(.jakarta(.regular, .sm))
                        .accessibilityIdentifier("agente-total-dictado-sintetico")
                }
                if dictado.estado == .permisoDenegado || dictado.estado == .permisoRestringido {
                    Button(TextoDictado.abrirAjustes) {
                        if let url = URL(string: UIApplication.openSettingsURLString) { abrirURL(url) }
                    }
                    .buttonStyle(EstiloBotonSecundario())
                    .accessibilityIdentifier("agente-total-abrir-ajustes")
                }
            }
            .foregroundStyle(Paleta.foreground)
        }
    }

    /// Aviso de privacidad (web: `AVISO_PRIVACIDAD`), visible antes de capturar nada.
    private var privacidad: some View {
        VStack(alignment: .leading, spacing: 8) {
            ForEach(Array(TextoAgenteTotal.privacidad.enumerated()), id: \.offset) { indice, parrafo in
                Text(parrafo)
                    .font(.jakarta(.regular, .sm))
                    .fixedSize(horizontal: false, vertical: true)
                    .accessibilityIdentifier("agente-total-privacidad-\(indice)")
            }
        }
        .tarjetaWeb()
    }

    // MARK: Otras pantallas

    /// Las pantallas a las que la web lleva desde el asistente, también sin hablar: rutas, frecuentes y mapa. Lupa, Metro y
    /// Emergencia no están aquí porque la web tampoco las ofrece en este modo.
    private var otrasPantallas: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(TextoAgenteTotal.otrasPantallas)
                .font(.jakarta(.bold, .lg))
                .foregroundStyle(Paleta.foreground)
                .accessibilityAddTraits(.isHeader)
            enlace(TextoAgenteTotal.buscarRutas, .rutas(estacion: nil), id: "agente-total-enlace-rutas")
            enlace(TextoAgenteTotal.rutasFrecuentes, .favoritas, id: "agente-total-enlace-frecuentes")
            enlace(TextoAgenteTotal.mapaYGps, .gps, id: "agente-total-enlace-gps")
        }
    }

    private func enlace(_ titulo: String, _ destino: DestinoAgenteTotal, id: String) -> some View {
        Button(titulo) { agente.abrir(destino) }
            .buttonStyle(EstiloBotonSecundario())
            .accessibilityIdentifier(id)
    }

    @ViewBuilder private func pantalla(_ destino: DestinoAgenteTotal) -> some View {
        switch destino {
        case .gps: GpsAuditivoVista(servicios: servicios)
        case .favoritas: FavoritasVista(modelo: servicios.favoritas)
        case .rutas(let estacion): RutasVista(servicios: servicios, consultaInicial: estacion)
        case .ruta(let codigo): DetalleRutaVista(servicios: servicios, codigo: codigo)
        case .viaje: ViajeVista(servicios: servicios)
        }
    }
}
