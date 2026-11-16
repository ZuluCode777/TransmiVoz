import SwiftUI

/// «Metro de Bogotá» (web: `components/metro-list.tsx`). Se abre desde la baldosa «Metro de Bogotá» de Inicio.
///
/// Es una pantalla de CONSULTA del catálogo educativo de un proyecto futuro: la Línea 1 está en construcción y SIN servicio
/// comercial, y la pantalla lo dice primero y siempre, también mientras carga o si falla. No usa rutas, GPS ni el
/// planificador de TransMilenio. El catálogo lo pide al servidor (`metro-linea-1`) y se muestra tal cual, con el rótulo y la
/// atribución (licencia, fecha, cambios) junto al mapa. El listado de las 16 estaciones es completo y no depende del mapa.
struct MetroVista: View {
    @Environment(\.serviciosRutas) private var servicios

    var body: some View {
        if let servicios {
            MetroPantalla(servicios: servicios)
        } else {
            // Sin servicios no hay cliente: solo pasa fuera de la app (vistas previas).
            Text(TextoMetro.servidorNoConfigurado).padding(16)
        }
    }
}

private struct MetroPantalla: View {
    let servicios: ServiciosRutas
    @State private var modelo: MetroModelo
    @State private var abiertas: Set<String> = []
    @AccessibilityFocusState private var foco: ZonaFocoMetro?

    init(servicios: ServiciosRutas) {
        self.servicios = servicios
        _modelo = State(initialValue: MetroModelo(cliente: servicios.cliente))
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                EncabezadoPantalla(
                    titulo: TextoMetro.titulo, subtitulo: "Línea 1 · en construcción · sin servicio", simbolo: "tram")
                switch modelo.estado {
                case .inactivo, .cargando:
                    ProgressView(TextoMetro.cargando)
                        .accessibilityIdentifier("metro-cargando")
                case .fallo(let error):
                    errorView(error)
                case .listo(let respuesta):
                    contenido(respuesta)
                }
            }
            .padding(16)
        }
        .navigationTitle(TextoMetro.titulo)
        .navigationBarTitleDisplayMode(.inline)
        .bordeInferiorLegible()
        .onAppear { modelo.alAparecer() }
        .onDisappear { modelo.alDesaparecer() }
        .onChange(of: modelo.estado) { _, nuevo in
            switch nuevo {
            case .fallo(let error):
                AccessibilityNotification.Announcement(TextoMetro.mensaje(de: error)).post()
                foco = .resultado
            case .listo:
                AccessibilityNotification.Announcement("Metro de Bogotá cargado.").post()
            case .inactivo, .cargando:
                break
            }
        }
    }

    // MARK: Error

    private func errorView(_ error: ErrorConsulta) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Label("No se pudo cargar el Metro", systemImage: "exclamationmark.triangle")
                .font(.headline)
                .accessibilityAddTraits(.isHeader)
                .accessibilityFocused($foco, equals: .resultado)
            Text(TextoMetro.mensaje(de: error)).accessibilityIdentifier("metro-error")
            Button(TextoMetro.reintentar) { modelo.cargar() }
                .buttonStyle(.bordered)
                .controlSize(.large)
                .frame(minHeight: 44)
                .accessibilityIdentifier("metro-reintentar")
        }
    }

    // MARK: Contenido

    @ViewBuilder private func contenido(_ r: RespuestaMetro) -> some View {
        Label {
            Text(r.textoEstado)
        } icon: {
            Image(systemName: "info.circle").accessibilityHidden(true)
        }
        .tarjetaWeb()
        .accessibilityIdentifier("metro-estado")

        mapaYAtribucion(r)
        estaciones(r)
        lineaDos(r)
        fuentes(r)
    }

    private func mapaYAtribucion(_ r: RespuestaMetro) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(TextoMetro.encabezadoMapa).font(.title3.bold()).accessibilityAddTraits(.isHeader)
            // El rótulo y la atribución completa van junto al mapa y no se ocultan.
            Text(r.mapa.rotulo).font(.subheadline.bold()).accessibilityIdentifier("metro-rotulo")
            MapaMetroVista(capa: CapaMetro(r), resaltada: modelo.resaltada, modoPruebas: servicios.modoPruebas)
            if let resaltada = modelo.resaltada, let estacion = r.estaciones.first(where: { $0.id == resaltada }) {
                Text(TextoMetro.huellaResaltada(estacion.etiquetaHuella)).accessibilityIdentifier("metro-huella-resaltada")
            }
            Text(r.mapa.aviso).accessibilityIdentifier("metro-aviso-mapa")
            Text(r.mapa.atribucion)
                .font(.footnote)
                .foregroundStyle(.textoSecundario)
                .accessibilityIdentifier("metro-atribucion")
            if let licencia = URL(string: r.mapa.licenciaUrl), licencia.scheme?.lowercased() == "https" {
                Link("Licencia: \(r.mapa.licencia)", destination: licencia)
                    .frame(minHeight: 44, alignment: .leading)
                    .accessibilityIdentifier("metro-licencia")
            }
        }
    }

    private func estaciones(_ r: RespuestaMetro) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(TextoMetro.encabezadoEstaciones).font(.title3.bold()).accessibilityAddTraits(.isHeader)
            VStack(alignment: .leading, spacing: 12) {
                ForEach(r.estaciones) { estacion in
                    DisclosureGroup(isExpanded: binding(estacion.id)) {
                        ficha(estacion)
                    } label: {
                        VStack(alignment: .leading, spacing: 2) {
                            Text("\(estacion.id) · \(estacion.nombreMostrado)").font(.headline)
                            Text(estacion.corredor).font(.subheadline).foregroundStyle(.textoSecundario)
                        }
                        .frame(minHeight: 44, alignment: .leading)
                        .accessibilityElement(children: .combine)
                        .accessibilityIdentifier("metro-estacion-\(estacion.id)")
                    }
                    .tarjetaWeb()
                }
            }
            .accessibilityElement(children: .contain)
            .accessibilityLabel(TextoMetro.etiquetaListaEstaciones)
        }
    }

    private func ficha(_ estacion: EstacionMetro) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(estacion.descripcionNombre)
            Text(estacion.nombreTecnico)
            Text(estacion.conexion)
            Text(estacion.avisoUbicacion)
            Text(estacion.enElMapa)
            Text("Fuentes: \(estacion.fuentes.joined(separator: ", "))").foregroundStyle(.textoSecundario)
            let resaltada = modelo.resaltada == estacion.id
            Button(resaltada ? TextoMetro.quitarResalte : TextoMetro.verEnElMapa) {
                modelo.resaltar(resaltada ? nil : estacion.id)
            }
            .buttonStyle(.bordered)
            .controlSize(.large)
            .frame(minHeight: 44)
            .accessibilityIdentifier("metro-resaltar-\(estacion.id)")
        }
        .padding(.top, 8)
    }

    private func lineaDos(_ r: RespuestaMetro) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(TextoMetro.encabezadoLinea2).font(.title3.bold()).accessibilityAddTraits(.isHeader)
            DisclosureGroup(isExpanded: binding("linea-2")) {
                Text(r.linea2.texto).padding(.top, 8)
            } label: {
                Text(r.linea2.titulo)
                    .font(.headline)
                    .frame(minHeight: 44, alignment: .leading)
                    .accessibilityIdentifier("metro-linea-2")
            }
            .tarjetaWeb()
        }
    }

    private func fuentes(_ r: RespuestaMetro) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(TextoMetro.encabezadoFuentes).font(.title3.bold()).accessibilityAddTraits(.isHeader)
            Text(r.atribucion).font(.footnote).foregroundStyle(.textoSecundario).accessibilityIdentifier("metro-atribucion-ids")
            ForEach(r.fuentes) { fuente in
                if let enlace = fuente.enlace {
                    Link(destination: enlace) {
                        Text(fuente.texto).frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
                    }
                    .accessibilityIdentifier("metro-fuente-\(fuente.id)")
                } else {
                    Text(fuente.texto)
                        .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
                        .accessibilityIdentifier("metro-fuente-\(fuente.id)")
                }
            }
        }
    }

    private func binding(_ id: String) -> Binding<Bool> {
        Binding(get: { abiertas.contains(id) }, set: { abierta in
            if abierta { abiertas.insert(id) } else { abiertas.remove(id) }
        })
    }
}

/// Zona de foco de VoiceOver de la pantalla: al fallar la carga, el foco pasa al error.
private enum ZonaFocoMetro: Hashable { case resultado }
