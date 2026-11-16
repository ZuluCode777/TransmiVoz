import Foundation
import Observation

/// Estado de una petición al planificador.
enum EstadoCarga<Valor: Equatable & Sendable>: Equatable, Sendable {
    case inactivo
    case cargando
    case listo(Valor)
    case fallo(ErrorConsulta)
}

/// Una sola petición vigente a la vez: solo el resultado de la ÚLTIMA llamada llega a `alTerminar`. Una respuesta
/// de una petición reemplazada o invalidada se descarta aunque el cliente ignore la cancelación (misma garantía
/// que `ConsultaModelo`).
@MainActor
final class EjecutorUnico {
    private var tarea: Task<Void, Never>?
    private var generacion = 0

    func ejecutar<Valor: Sendable>(
        _ operacion: @escaping @Sendable () async throws -> Valor,
        alTerminar: @escaping (Result<Valor, ErrorConsulta>) -> Void
    ) {
        generacion += 1
        let miGeneracion = generacion
        tarea?.cancel()
        tarea = Task {
            let resultado: Result<Valor, ErrorConsulta>
            do {
                resultado = .success(try await operacion())
            } catch let error as ErrorConsulta {
                resultado = .failure(error)
            } catch is CancellationError {
                resultado = .failure(.cancelada)
            } catch {
                resultado = .failure(.sinConexion)
            }
            guard miGeneracion == self.generacion, !Task.isCancelled else { return }
            self.tarea = nil
            alTerminar(resultado)
        }
    }

    /// Descarta la petición en curso: su resultado, si llega, no se aplica.
    func invalidar() {
        generacion += 1
        tarea?.cancel()
        tarea = nil
    }
}

private extension EstadoCarga {
    init(_ resultado: Result<Valor, ErrorConsulta>) {
        switch resultado {
        case .success(let valor): self = .listo(valor)
        case .failure(let error): self = .fallo(error)
        }
    }
}

/// Lo que el iPhone necesita para las pantallas de rutas, de Metro y de «Mapa y GPS»: el cliente del planificador, las favoritas
/// y si corre en las pruebas de interfaz (donde el mapa no se dibuja).
struct ServiciosRutas {
    let cliente: ClientePlanificador
    let favoritas: FavoritasModelo
    let modoPruebas: Bool
    /// El dictado de la consulta (`ConsultaModelo.dictado`, el mismo, no otro reconocedor) para «Buscar hablando». Es `nil` solo
    /// cuando la consulta no tiene dictado (las pruebas de interfaz sin `-PRUEBAS_UI_DICTADO_SINTETICO`): la superposición lo dice
    /// y se sigue escribiendo a mano. Sin valor por omisión: `EntornoApp` lo entrega siempre, y un olvido no compila.
    let dictado: DictadoModelo?
    /// La `ControlVoz` de la app (la misma de la consulta, los avisos y el accesorio: un solo dueño del audio) para «Escuchar».
    let voz: ControlVoz
    /// «Mapa y GPS»: un solo modelo para toda la app, así la raíz suelta la ubicación al cambiar de pestaña o pasar a segundo plano
    /// sea cual sea la pantalla que la abrió (Inicio, el asistente de voz o una respuesta de Consulta).
    let gps: GpsAuditivoModelo
}

/// Búsqueda de rutas por código o estación.
@MainActor
@Observable
final class BusquedaRutasModelo {
    var texto: String
    private(set) var estado: EstadoCarga<ResultadoBusquedaRutas> = .inactivo
    /// Por qué no se envió el texto (vacío o demasiado largo); `nil` si se envió.
    private(set) var avisoEntrada: String?
    /// Texto de la última búsqueda enviada, para decir «no encontré rutas para…» y para «Reintentar».
    private(set) var ultimaConsulta: String?

    @ObservationIgnored private let cliente: ClientePlanificador
    @ObservationIgnored private let ejecutor = EjecutorUnico()

    init(cliente: ClientePlanificador, consultaInicial: String? = nil) {
        self.cliente = cliente
        texto = consultaInicial ?? ""
    }

    func buscar() {
        let limpia = texto.trimmingCharacters(in: .whitespacesAndNewlines)
        if limpia.isEmpty || limpia.utf16.count > EntradaPlanificador.maximoConsulta {
            ejecutor.invalidar()
            avisoEntrada = TextoRutas.entradaInvalida(
                limpia.isEmpty ? .vacia : .demasiadoLarga(maximo: EntradaPlanificador.maximoConsulta))
            estado = .inactivo
            return
        }
        avisoEntrada = nil
        ultimaConsulta = limpia
        estado = .cargando
        ejecutor.ejecutar({ [cliente] in try await cliente.buscarRutas(consulta: limpia) }) { [self] resultado in
            estado = EstadoCarga(resultado)
        }
    }

    func reintentar() {
        guard let anterior = ultimaConsulta else { return }
        texto = anterior
        buscar()
    }
}

/// Detalle de una ruta con su recorrido.
///
/// Mientras la pantalla está a la vista (`pantallaVisible`) se vuelve a pedir el detalle cada 30 s, como el reloj de
/// `route-detail.tsx`: el calendario y las paradas verificadas las decide el servidor con la hora de cada respuesta y
/// pueden vencer aunque el catálogo no cambie. Esa nueva consulta es silenciosa: no vuelve a «cargando» ni mueve el
/// foco; si falla, lo que se ve se conserva y `refrescoFallido` lo dice.
@MainActor
@Observable
final class DetalleRutaModelo {
    let codigo: String
    private(set) var estado: EstadoCarga<DetalleRuta> = .inactivo
    /// La última consulta periódica falló: lo que se ve puede haber vencido.
    private(set) var refrescoFallido = false

    @ObservationIgnored private let cliente: ClientePlanificador
    @ObservationIgnored private let ejecutor = EjecutorUnico()
    @ObservationIgnored private let ejecutorRefresco = EjecutorUnico()
    @ObservationIgnored private let revalidador: RevalidadorPeriodico

    init(codigo: String, cliente: ClientePlanificador, revalidador: RevalidadorPeriodico = RevalidadorPeriodico()) {
        self.codigo = codigo
        self.cliente = cliente
        self.revalidador = revalidador
        revalidador.alVencer = { [weak self] in self?.refrescar() }
    }

    func cargar() {
        ejecutorRefresco.invalidar()
        refrescoFallido = false
        estado = .cargando
        ejecutor.ejecutar({ [cliente, codigo] in try await cliente.detalleRuta(codigo: codigo) }) { [self] resultado in
            estado = EstadoCarga(resultado)
        }
    }

    /// Carga la primera vez que la pantalla aparece; al volver de otra pantalla conserva lo que ya tiene.
    func cargarSiHaceFalta() {
        if case .inactivo = estado { cargar() }
    }

    /// Vuelve a pedir el detalle sin tocar lo que se ve. Solo con un detalle ya mostrado; una carga o un error en curso
    /// mandan sobre ella.
    func refrescar() {
        guard case .listo = estado else { return }
        ejecutorRefresco.ejecutar({ [cliente, codigo] in try await cliente.detalleRuta(codigo: codigo) }) { [self] resultado in
            guard case .listo = estado else { return }
            switch resultado {
            case .success(let detalle):
                estado = .listo(detalle)
                refrescoFallido = false
            case .failure(let error):
                if error != .cancelada { refrescoFallido = true }
            }
        }
    }

    /// La pantalla aparece o desaparece (o la app pasa a segundo plano): el reloj de 30 s corre solo mientras se ve.
    func pantallaVisible(_ visible: Bool) {
        if visible {
            revalidador.iniciar()
        } else {
            revalidador.detener()
            ejecutorRefresco.invalidar()
        }
    }
}

/// Selección estructurada de origen y destino: los dos salen de la lista de lugares del servidor y viajan como datos.
///
/// Con un viaje planeado a la vista (`pantallaVisible`) se vuelve a planear el MISMO viaje cada 30 s, como `REVALIDA_MS`
/// de `trip-view.tsx`: el servidor decide cada vez si el plan sigue siendo operativo con la evidencia y la hora de ahora.
/// La nueva consulta es silenciosa y reemplaza el resultado; si falla, se conserva el anterior y `refrescoFallido` lo dice.
@MainActor
@Observable
final class ViajeModelo {
    private(set) var lugares: EstadoCarga<ListaLugares> = .inactivo
    private(set) var plan: EstadoCarga<PlanViaje> = .inactivo
    private(set) var origen: String?
    private(set) var destino: String?
    /// La última consulta periódica falló: el viaje que se ve puede haber dejado de ser válido.
    private(set) var refrescoFallido = false

    @ObservationIgnored private let cliente: ClientePlanificador
    @ObservationIgnored private let ejecutorLugares = EjecutorUnico()
    @ObservationIgnored private let ejecutorPlan = EjecutorUnico()
    @ObservationIgnored private let ejecutorRefresco = EjecutorUnico()
    @ObservationIgnored private let revalidador: RevalidadorPeriodico

    init(cliente: ClientePlanificador, revalidador: RevalidadorPeriodico = RevalidadorPeriodico()) {
        self.cliente = cliente
        self.revalidador = revalidador
        revalidador.alVencer = { [weak self] in self?.refrescarPlan() }
    }

    var puedePlanear: Bool { origen != nil && destino != nil && plan != .cargando }

    func cargarLugares() {
        lugares = .cargando
        ejecutorLugares.ejecutar({ [cliente] in try await cliente.listarLugares() }) { [self] resultado in
            lugares = EstadoCarga(resultado)
        }
    }

    func cargarLugaresSiHaceFalta() {
        if case .inactivo = lugares { cargarLugares() }
    }

    /// Cambiar el origen o el destino descarta el viaje anterior: ya no corresponde a lo elegido.
    func elegirOrigen(_ lugar: String) {
        descartarViajeVigente()
        origen = lugar
    }

    func elegirDestino(_ lugar: String) {
        descartarViajeVigente()
        destino = lugar
    }

    private func descartarViajeVigente() {
        ejecutorPlan.invalidar()
        ejecutorRefresco.invalidar()
        refrescoFallido = false
        plan = .inactivo
    }

    func planear() {
        guard let origen, let destino, plan != .cargando else { return }
        ejecutorRefresco.invalidar()
        refrescoFallido = false
        plan = .cargando
        ejecutorPlan.ejecutar({ [cliente] in try await cliente.planearViaje(origen: origen, destino: destino) }) { [self] resultado in
            plan = EstadoCarga(resultado)
        }
    }

    /// Vuelve a planear el mismo viaje sin tocar lo que se ve. Solo con un viaje ya mostrado.
    func refrescarPlan() {
        guard case .listo = plan, let origen, let destino else { return }
        ejecutorRefresco.ejecutar({ [cliente] in try await cliente.planearViaje(origen: origen, destino: destino) }) { [self] resultado in
            guard case .listo = plan else { return }
            switch resultado {
            case .success(let nuevo):
                plan = .listo(nuevo)
                refrescoFallido = false
            case .failure(let error):
                if error != .cancelada { refrescoFallido = true }
            }
        }
    }

    /// La pantalla aparece o desaparece (o la app pasa a segundo plano): el reloj de 30 s corre solo mientras se ve.
    func pantallaVisible(_ visible: Bool) {
        if visible {
            revalidador.iniciar()
        } else {
            revalidador.detener()
            ejecutorRefresco.invalidar()
        }
    }
}
