import SwiftUI

/// «Mapa y GPS» (web: `components/auditory-gps.tsx`). Se abre desde la baldosa «Mapa y GPS» de Inicio.
///
/// Dice por voz hacia qué estación de TransMilenio orientarse. La ubicación y la brújula las da CoreLocation SOLO «al usar la
/// app»: la persona la activa y la detiene (nada se pide al abrir la pantalla), se suelta sola al salir de la pantalla o al
/// bloquear el iPhone, no hay ubicación en segundo plano y no se guarda ni se registra. El servidor ordena las estaciones, mide
/// la distancia y orienta: aquí no hay ninguna regla de transporte. Cada estación se lee en el listado (el mapa es una ayuda
/// visual) y la voz es la de `ControlVoz`, la misma de los avisos del accesorio.
///
/// El modelo es el de `ServiciosRutas.gps`, uno para toda la app: su voz es la `ControlVoz` compartida y la raíz suelta la ubicación
/// al cambiar de pestaña o pasar a segundo plano, sea cual sea la pantalla que la abrió.
struct GpsAuditivoVista: View {
    let servicios: ServiciosRutas

    @Environment(\.scenePhase) private var faseEscena
    @Environment(\.openURL) private var abrirURL
    @AccessibilityFocusState private var foco: ZonaFocoGps?

    /// El modelo compartido de la app. La raíz lo suspende al cambiar de pestaña o ir a segundo plano; esta pantalla también.
    private var modelo: GpsAuditivoModelo { servicios.gps }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                EncabezadoPantalla(titulo: TextoGps.titulo, subtitulo: TextoGps.subtitulo, simbolo: "map")
                contenido(modelo)
            }
            .padding(16)
        }
        .navigationTitle(TextoGps.titulo)
        .navigationBarTitleDisplayMode(.inline)
        .bordeInferiorLegible()
        // La ubicación solo está abierta con la pantalla a la vista y la app en primer plano; no se reanuda sola. `.inactive`
        // no la suelta: el aviso de permiso del sistema deja la app inactiva un momento, y bloquear el iPhone pasa a
        // `.background` enseguida.
        .onDisappear { modelo.suspender() }
        .onChange(of: faseEscena) { _, nueva in if nueva == .background { modelo.suspender() } }
        .onChange(of: modelo.fallo) { _, nuevo in
            guard let nuevo else { return }
            AccessibilityNotification.Announcement("\(nuevo.mensaje) \(nuevo.recuperacion)").post()
            foco = .error
        }
    }

    // MARK: Contenido

    @ViewBuilder private func contenido(_ modelo: GpsAuditivoModelo) -> some View {
        Text(TextoGps.privacidad)
            .tarjetaWeb()
            .accessibilityIdentifier("gps-privacidad")
        controlDeUbicacion(modelo)
        estadoDeUbicacion(modelo)
        if modelo.estado == .activo || modelo.estado == .vencida {
            if modelo.estado == .activo { acciones(modelo) }
            resultado(modelo)
        }
    }

    @ViewBuilder private func controlDeUbicacion(_ modelo: GpsAuditivoModelo) -> some View {
        if modelo.escuchando {
            Button(TextoGps.detener) { modelo.detener() }
                .buttonStyle(EstiloBotonSecundario())
                .accessibilityIdentifier("gps-detener")
        } else {
            Button(TextoGps.activar) { modelo.iniciar() }
                .buttonStyle(EstiloBotonPrimario())
                .accessibilityIdentifier("gps-activar")
        }
        if modelo.estado == .permisoDenegado {
            Button(TextoGps.abrirAjustes) {
                if let url = URL(string: UIApplication.openSettingsURLString) { abrirURL(url) }
            }
            .buttonStyle(EstiloBotonSecundario())
            .accessibilityIdentifier("gps-abrir-ajustes")
        }
    }

    /// Lo que se sabe de la ubicación y la brújula, en texto: el estado nunca va solo en un color o un icono.
    @ViewBuilder private func estadoDeUbicacion(_ modelo: GpsAuditivoModelo) -> some View {
        if let aviso = modelo.aviso {
            Text(aviso)
                .font(.headline)
                .fixedSize(horizontal: false, vertical: true)
                .accessibilityAddTraits(.updatesFrequently)
                .accessibilityIdentifier("gps-estado")
        }
        if modelo.estado == .activo {
            if let precision = modelo.precisionMetros {
                Text(TextoGps.precision(metros: precision)).accessibilityIdentifier("gps-precision")
            } else {
                Text(TextoGps.precisionDesconocida).accessibilityIdentifier("gps-precision")
            }
        }
        if modelo.escuchando {
            switch modelo.rumbo {
            case .noDisponible: Text(TextoGps.rumboNoDisponible).accessibilityIdentifier("gps-rumbo")
            case .sinLectura: Text(TextoGps.rumboSinLectura).accessibilityIdentifier("gps-rumbo")
            case .conLectura: EmptyView()
            }
        }
    }

    private func acciones(_ modelo: GpsAuditivoModelo) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Button { modelo.repetirIndicacion() } label: {
                Label(TextoGps.repetir, systemImage: "speaker.wave.2")
            }
            .buttonStyle(EstiloBotonSecundario())
            .disabled(modelo.consultando)
            .accessibilityIdentifier("gps-repetir")
            Button { modelo.actualizar() } label: {
                Label(TextoGps.actualizar, systemImage: "arrow.clockwise")
            }
            .buttonStyle(EstiloBotonSecundario())
            .disabled(modelo.consultando)
            .accessibilityIdentifier("gps-actualizar")
        }
    }

    @ViewBuilder private func resultado(_ modelo: GpsAuditivoModelo) -> some View {
        if modelo.consultando {
            ProgressView(TextoGps.consultando).accessibilityIdentifier("gps-consultando")
        }
        if let error = modelo.fallo {
            VStack(alignment: .leading, spacing: 8) {
                Label("No se pudieron traer las estaciones", systemImage: "exclamationmark.triangle")
                    .font(.headline)
                    .accessibilityAddTraits(.isHeader)
                    .accessibilityFocused($foco, equals: .error)
                Text(error.mensaje).accessibilityIdentifier("gps-error")
                Text(error.recuperacion).foregroundStyle(.textoSecundario)
                Button("Reintentar") { modelo.actualizar() }
                    .buttonStyle(.bordered)
                    .controlSize(.large)
                    .frame(minHeight: 44)
                    .accessibilityIdentifier("gps-reintentar")
            }
        }
        if let respuesta = modelo.respuesta {
            MapaGpsVista(
                usuario: modelo.posicionEnMapa,
                estaciones: respuesta.estaciones.enumerated().map { indice, estacion in
                    MapaGpsVista.Marca(
                        id: indice, titulo: estacion.nombre, coordenada: estacion.coordenada,
                        elegida: estacion.nombre == modelo.objetivo)
                },
                modoPruebas: servicios.modoPruebas)
            Text(TextoGps.encabezadoEstaciones)
                .font(.title3.bold())
                .accessibilityAddTraits(.isHeader)
            if respuesta.estaciones.isEmpty {
                Text(TextoGps.sinEstaciones).accessibilityIdentifier("gps-sin-estaciones")
            } else {
                ForEach(Array(respuesta.estaciones.enumerated()), id: \.offset) { indice, estacion in
                    fila(modelo, indice: indice, estacion: estacion)
                }
            }
            if let mapas = modelo.mensajeMapas {
                Text(mapas).accessibilityIdentifier("gps-mapas-aviso")
            }
            CatalogoVista(catalogo: respuesta.catalogo, alVolverAConsultar: { modelo.actualizar() })
        }
    }

    private func fila(_ modelo: GpsAuditivoModelo, indice: Int, estacion: EstacionCercana) -> some View {
        let elegida = estacion.nombre == modelo.objetivo
        return VStack(alignment: .leading, spacing: 8) {
            VStack(alignment: .leading, spacing: 2) {
                Text(estacion.nombre).font(.headline)
                Text(elegida ? "\(TextoGps.filaDistancia(estacion)) · \(TextoGps.orientando)" : TextoGps.filaDistancia(estacion))
                Text(estacion.orientacion.indicacion).font(.subheadline).foregroundStyle(.textoSecundario)
            }
            .accessibilityElement(children: .combine)
            .accessibilityIdentifier("gps-estacion-\(indice)")
            // El aviso de cercanía de la web, también en texto: lo decide el servidor (`muyCerca`) y solo para la estación elegida.
            if elegida && estacion.muyCerca {
                Text(TextoGps.muyCerca(estacion)).font(.subheadline.bold()).accessibilityIdentifier("gps-muy-cerca-\(indice)")
            }
            Button(TextoGps.orientarme) { modelo.orientarHacia(estacion.nombre) }
                .buttonStyle(EstiloBotonSecundario())
                .accessibilityIdentifier("gps-orientar-\(indice)")
            // La ruta a pie en la app Mapas (equivalente a «Abrir en Google Maps»): solo recibe el destino, la estación.
            Button(TextoGps.abrirEnMapas) { modelo.abrirEnMapas(estacion.nombre) }
                .buttonStyle(EstiloBotonSecundario())
                .accessibilityIdentifier("gps-mapas-\(indice)")
            Text(TextoGps.notaMapas)
                .font(.footnote)
                .foregroundStyle(.textoSecundario)
                .accessibilityIdentifier("gps-nota-mapas-\(indice)")
        }
        .tarjetaWeb()
    }
}

/// Zona de foco de VoiceOver: al fallar una consulta, el foco pasa al error.
private enum ZonaFocoGps: Hashable { case error }
