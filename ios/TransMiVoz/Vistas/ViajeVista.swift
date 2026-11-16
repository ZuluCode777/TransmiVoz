import SwiftUI

/// Planear un viaje entre dos lugares ELEGIDOS de la lista del servidor. La selección viaja como datos al planificador
/// compartido (nunca como una frase), y el resultado muestra el listado de tramos y, si hay coordenadas, el mapa de los
/// mismos tramos. El servidor decide el estado del viaje; la app no lo recalcula ni da órdenes de abordaje.
///
/// Como `trip-view.tsx`: con un viaje planeado a la vista se vuelve a planear el mismo viaje cada 30 s (`REVALIDA_MS`),
/// porque el plan puede dejar de ser válido con el paso del tiempo; el servidor decide cada vez. También muestra las
/// otras rutas directas que sirven al viaje («También te sirven…»), tal como las manda el servidor: solo códigos.
struct ViajeVista: View {
    let servicios: ServiciosRutas
    @State private var modelo: ViajeModelo
    /// La pantalla está a la vista: con ella en segundo plano, o con otra encima, el reloj de 30 s no corre.
    @State private var aLaVista = false
    @AccessibilityFocusState private var foco: ZonaFocoRutas?
    @Environment(\.scenePhase) private var faseEscena

    init(servicios: ServiciosRutas) {
        self.servicios = servicios
        _modelo = State(initialValue: ViajeModelo(cliente: servicios.cliente))
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                Text(TextoRutas.introduccionViaje).accessibilityIdentifier("introduccion-viaje")
                Text(TextoRutas.sinUbicacion).font(.footnote).foregroundStyle(.textoSecundario)
                selectores
                planearBoton
                resultado
            }
            .padding(16)
        }
        .bordeSuperiorNitido()
        .navigationTitle(TextoRutas.tituloViaje)
        .navigationBarTitleDisplayMode(.inline)
        .bordeInferiorLegible()
        .task { modelo.cargarLugaresSiHaceFalta() }
        .onAppear {
            aLaVista = true
            modelo.pantallaVisible(faseEscena == .active)
        }
        .onDisappear {
            aLaVista = false
            modelo.pantallaVisible(false)
        }
        .onChange(of: faseEscena) { _, nueva in modelo.pantallaVisible(aLaVista && nueva == .active) }
        .onChange(of: modelo.plan) { anterior, nuevo in
            // La consulta periódica cambia un viaje ya mostrado por otro: no se anuncia ni se mueve el foco.
            if case .listo = anterior, case .listo = nuevo { return }
            anunciar(nuevo)
        }
        .onChange(of: modelo.lugares) { _, nuevo in anunciarLugares(nuevo) }
    }

    @ViewBuilder private var selectores: some View {
        switch modelo.lugares {
        case .inactivo:
            EmptyView()
        case .cargando:
            ProgressView(TextoRutas.cargandoLugares).accessibilityIdentifier("progreso-lugares")
        case .fallo(let error):
            ErrorRutasVista(error: error, foco: $foco, alReintentar: { modelo.cargarLugares() })
        case .listo(let lista):
            filaSelector(rol: TextoRutas.origen, elegido: modelo.origen, lista: lista, identificador: "selector-origen") {
                modelo.elegirOrigen($0)
            }
            filaSelector(rol: TextoRutas.destino, elegido: modelo.destino, lista: lista, identificador: "selector-destino") {
                modelo.elegirDestino($0)
            }
        }
    }

    private func filaSelector(
        rol: String, elegido: String?, lista: ListaLugares, identificador: String, alElegir: @escaping (String) -> Void
    ) -> some View {
        NavigationLink {
            SelectorLugarVista(rol: rol, lugares: lista.lugares, elegido: elegido, alElegir: alElegir)
        } label: {
            Text(TextoRutas.filaSelector(rol, elegido))
                .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
        }
        .buttonStyle(EstiloBotonSecundario())
        .accessibilityHint(TextoRutas.pistaSelector)
        .accessibilityIdentifier(identificador)
    }

    @ViewBuilder private var planearBoton: some View {
        if case .listo = modelo.lugares {
            Button(TextoRutas.botonPlanear) { modelo.planear() }
                .accion(prominente: true, disponible: modelo.puedePlanear)
                .controlSize(.large)
                .frame(minHeight: 44)
                .accessibilityIdentifier("boton-planear-viaje")
            if modelo.origen == nil || modelo.destino == nil {
                Text(TextoRutas.faltaElegir).font(.footnote).foregroundStyle(.textoSecundario)
            }
        }
    }

    @ViewBuilder private var resultado: some View {
        switch modelo.plan {
        case .inactivo:
            EmptyView()
        case .cargando:
            ProgressView(TextoRutas.planeando).accessibilityIdentifier("progreso-viaje")
        case .fallo(let error):
            ErrorRutasVista(error: error, foco: $foco, alReintentar: { modelo.planear() })
        case .listo(let plan):
            PlanViajeVista(
                plan: plan, servicios: servicios, foco: $foco, refrescoFallido: modelo.refrescoFallido,
                alVolverAConsultar: { modelo.planear() })
        }
    }

    /// La carga de la lista de lugares y su falla se anuncian como las de la búsqueda; el foco pasa al error.
    private func anunciarLugares(_ lugares: EstadoCarga<ListaLugares>) {
        let texto: String
        switch lugares {
        case .inactivo: return
        case .cargando: texto = TextoRutas.cargandoLugares
        case .listo: texto = TextoRutas.lugaresCargados
        case .fallo(let error): texto = "\(error.mensaje) \(error.recuperacion)"
        }
        AccessibilityNotification.Announcement(texto).post()
        if case .fallo = lugares { foco = .resultado }
    }

    private func anunciar(_ plan: EstadoCarga<PlanViaje>) {
        let texto: String
        switch plan {
        case .inactivo: return
        case .cargando: texto = TextoRutas.planeando
        case .listo(let viaje): texto = TextoRutas.tituloResultado(viaje)
        case .fallo(let error): texto = "\(error.mensaje) \(error.recuperacion)"
        }
        AccessibilityNotification.Announcement(texto).post()
        if plan != .cargando { foco = .resultado }
    }
}

/// Resultado de un viaje: título y notas del estado, tramos (la misma información que el mapa) y el mapa.
private struct PlanViajeVista: View {
    let plan: PlanViaje
    let servicios: ServiciosRutas
    var foco: AccessibilityFocusState<ZonaFocoRutas?>.Binding
    /// La última consulta periódica falló: el viaje que se ve puede haber dejado de ser válido.
    let refrescoFallido: Bool
    let alVolverAConsultar: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(TextoRutas.tituloResultado(plan))
                .font(.title3.bold())
                .accessibilityAddTraits(.isHeader)
                .accessibilityFocused(foco, equals: .resultado)
                .accessibilityIdentifier("resultado-viaje-titulo")
            ForEach(Array(TextoRutas.notasResultado(plan).enumerated()), id: \.offset) { _, nota in
                Text(nota).accessibilityIdentifier("nota-viaje")
            }
            if refrescoFallido {
                Text(TextoRutas.actualizacionFallida)
                    .font(.footnote.bold())
                    .accessibilityIdentifier("aviso-actualizacion-viaje")
            }
        }

        if plan.tramos.count == 2 {
            Text(TextoRutas.notaTransbordo).accessibilityIdentifier("nota-transbordo")
        }
        ForEach(Array(plan.tramos.enumerated()), id: \.offset) { indice, tramo in
            VStack(alignment: .leading, spacing: 4) {
                Text(TextoRutas.tituloTramo(indice + 1, tramo.codigoRuta)).font(.headline)
                ForEach(Array(TextoRutas.filasTramo(tramo).enumerated()), id: \.offset) { _, fila in
                    Text(fila)
                }
            }
            .accessibilityElement(children: .combine)
            .accessibilityIdentifier("tramo-\(indice + 1)")
        }

        // «También te sirven…»: otras rutas directas entre los mismos lugares. Solo el código: el servidor no confirma en qué
        // estación del lugar se aborda cada una, así que no se dice dónde subir; su detalle sí lo cuenta.
        if !plan.alternativas.isEmpty {
            VStack(alignment: .leading, spacing: 8) {
                Text(TextoRutas.tituloAlternativas(plan.alternativas))
                    .font(.headline)
                    .accessibilityAddTraits(.isHeader)
                    .accessibilityIdentifier("titulo-alternativas")
                Text(TextoRutas.notaAlternativas).foregroundStyle(.textoSecundario)
            }
            ForEach(Array(plan.alternativas.enumerated()), id: \.offset) { indice, codigo in
                NavigationLink {
                    DetalleRutaVista(servicios: servicios, codigo: codigo)
                } label: {
                    Text(TextoRutas.tituloDetalle(codigo))
                        .font(.headline)
                        .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
                        .padding(12)
                        .overlay(RoundedRectangle(cornerRadius: 10).strokeBorder(Color.textoSecundario, lineWidth: 1))
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel(TextoRutas.etiquetaAlternativa(codigo))
                .accessibilityHint(TextoRutas.pistaDetalle)
                .accessibilityIdentifier("alternativa-\(indice + 1)")
            }
        }

        // Un candidato solo trae los códigos de sus rutas: ni paradas ni mapa.
        ForEach(Array(plan.codigosCandidatos.enumerated()), id: \.offset) { indice, codigo in
            Text(TextoRutas.rutaCandidata(codigo))
                .font(.headline)
                .accessibilityIdentifier("ruta-candidata-\(indice + 1)")
        }

        if !plan.rutasPorElTrazado.isEmpty {
            Text(TextoRutas.tituloRutasPorElTrazado).font(.headline).accessibilityAddTraits(.isHeader)
            ForEach(Array(plan.rutasPorElTrazado.enumerated()), id: \.offset) { _, ruta in
                NavigationLink {
                    DetalleRutaVista(servicios: servicios, codigo: ruta.codigo)
                } label: {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(TextoRutas.tituloDetalle(ruta.codigo)).font(.headline)
                        Text(TextoRutas.trayecto(ruta.desde, ruta.hacia))
                    }
                    .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
                    .padding(12)
                    .overlay(RoundedRectangle(cornerRadius: 10).strokeBorder(Color.textoSecundario, lineWidth: 1))
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityElement(children: .combine)
                .accessibilityLabel(TextoRutas.etiquetaRuta(ruta))
                .accessibilityHint("Abre el detalle y el mapa de la ruta.")
                .accessibilityIdentifier("ruta-por-el-trazado-\(ruta.codigo)")
            }
        }

        if !plan.tramos.isEmpty {
            MapaRecorridoVista(
                elementos: .de(tramos: plan.tramos),
                etiqueta: TextoRutas.etiquetaMapaViaje(origen: plan.origen, destino: plan.destino),
                modoPruebas: servicios.modoPruebas)
        }

        CatalogoVista(catalogo: plan.catalogo, alVolverAConsultar: alVolverAConsultar)
    }
}

/// Lista de lugares del servidor con un filtro de texto. Elegir uno lo entrega y vuelve a la pantalla del viaje.
private struct SelectorLugarVista: View {
    let rol: String
    let lugares: [String]
    let elegido: String?
    let alElegir: (String) -> Void

    @Environment(\.dismiss) private var cerrar
    @State private var filtro = ""

    /// Mismas reglas de comparación del texto que el resto de la app: sin mayúsculas ni tildes.
    private var visibles: [String] {
        let buscado = filtro.trimmingCharacters(in: .whitespacesAndNewlines)
        return buscado.isEmpty ? lugares : lugares.filter { $0.localizedStandardContains(buscado) }
    }

    var body: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 8) {
                TextField(TextoRutas.etiquetaFiltro, text: $filtro)
                    .textFieldStyle(.roundedBorder)
                    .frame(minHeight: 44)
                    .accessibilityLabel(TextoRutas.etiquetaFiltro)
                    .accessibilityIdentifier("filtro-lugares")

                if visibles.isEmpty {
                    Text(TextoRutas.sinCoincidencias(filtro)).accessibilityIdentifier("sin-coincidencias-lugares")
                }
                ForEach(visibles, id: \.self) { lugar in
                    Button {
                        alElegir(lugar)
                        AccessibilityNotification.Announcement(TextoRutas.lugarElegido(rol, lugar)).post()
                        cerrar()
                    } label: {
                        HStack {
                            Text(lugar)
                            Spacer(minLength: 8)
                            if lugar == elegido { Image(systemName: "checkmark").accessibilityHidden(true) }
                        }
                        .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.bordered)
                    .accessibilityAddTraits(lugar == elegido ? .isSelected : [])
                    .accessibilityIdentifier("lugar-\(lugar)")
                }
            }
            .padding(16)
        }
        .scrollDismissesKeyboard(.interactively)
        .bordeSuperiorNitido()
        .navigationTitle(TextoRutas.tituloSelector(rol))
        .navigationBarTitleDisplayMode(.inline)
        .bordeInferiorLegible()
    }
}
