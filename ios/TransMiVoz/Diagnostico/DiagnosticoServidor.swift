import Foundation

/// «Servidor»: pide los anuncios por el mismo cliente de la pestaña Avisos (`GET /api/anuncios`, mismo origen, misma clave,
/// sin redirecciones). Que responda y decodifique prueba que el origen de Ajustes es alcanzable y que la clave sirve. No toca
/// el estado de la pestaña Avisos: usa su propio cliente.
struct SondaServidor: SondaDiagnostico {
    let cliente: ClienteAnuncios

    func ejecutar() async -> ResultadoPrueba {
        do {
            return DiagnosticoTexto.servidor(try await cliente.consultar())
        } catch {
            return DiagnosticoTexto.falloDeServidor(error)
        }
    }
}

/// «Asistente»: hace una pregunta de viaje por el mismo cliente de Consulta (`POST /api/agent`). Prueba que el servidor
/// responde con el formato del contrato; el texto de la respuesta no se muestra ni se habla.
struct SondaAsistente: SondaDiagnostico {
    let cliente: ClienteAgente

    func ejecutar() async -> ResultadoPrueba {
        do {
            return DiagnosticoTexto.asistente(try await cliente.consultar(texto: DiagnosticoTexto.preguntaDelAsistente))
        } catch {
            return DiagnosticoTexto.falloDeServidor(error)
        }
    }
}

/// «Rutas y viaje»: pide la lista de lugares por el mismo cliente de las pantallas de rutas (`POST /api/planificador`,
/// operación `listar-lugares`: solo lee, no planea nada). Prueba que el servidor tiene el planificador y que su catálogo
/// decodifica y valida con las reglas de la app.
struct SondaPlanificador: SondaDiagnostico {
    let cliente: ClientePlanificador

    func ejecutar() async -> ResultadoPrueba {
        do {
            return DiagnosticoTexto.planificador(try await cliente.listarLugares())
        } catch {
            return DiagnosticoTexto.falloDelPlanificador(error)
        }
    }
}

/// «Voz de la app»: dice de verdad la frase de prueba por la `ControlVoz` compartida de la app (la de los avisos, la consulta y
/// Emergencia), sin abrir otra sesión de audio ni otra cola de voz. Por eso sigue sus reglas: solo suena con la voz permitida
/// y por auriculares, y no corta ni tapa una locución ajena; solo cuenta como correcta si su frase sonó entera, y cada otro caso se dice con su texto.
/// `vocesEnEspanol` lo da el sistema (`AVSpeechSynthesisVoice`).
struct SondaVoz: SondaDiagnostico {
    let voz: ControlVoz
    let vocesEnEspanol: @MainActor @Sendable () -> Int
    /// Cuánto se espera a que termine la frase antes de cortarla (si sigue siendo la propia).
    var tope: TimeInterval = 8

    @MainActor func ejecutar() async -> ResultadoPrueba {
        let voces = vocesEnEspanol()
        guard !voz.hablando else { return DiagnosticoTexto.voz(vocesEnEspanol: voces, habla: .otraVozSonando) }
        switch voz.anunciar(DiagnosticoTexto.fraseDeVoz) {
        case .silenciado(.rutaNoPrivada):
            return DiagnosticoTexto.voz(vocesEnEspanol: voces, habla: .rutaNoPrivada)
        case .silenciado(.vozApagada):
            return DiagnosticoTexto.voz(vocesEnEspanol: voces, habla: .vozApagada)
        case .silenciado(.cedeAUnAviso):
            return DiagnosticoTexto.voz(vocesEnEspanol: voces, habla: .otraVozSonando)
        case .silenciado(.interrumpido):
            return DiagnosticoTexto.voz(vocesEnEspanol: voces, habla: .interrumpida)
        case .silenciado:
            // Sesión de audio rechazada: el iPhone no dejó hablar.
            return DiagnosticoTexto.voz(vocesEnEspanol: voces, habla: .sesionNoDisponible)
        case .hablado:
            // Espera a que termine la frase: es éxito solo si SU locución sonó entera. Si habló otro después (un aviso del
            // accesorio), la cola de uno ya la cortó y lo que suena no es nuestro: no se toca.
            let propia = voz.locuciones
            var esperado: TimeInterval = 0
            while voz.hablando && voz.locuciones == propia && esperado < tope && !Task.isCancelled {
                try? await Task.sleep(nanoseconds: 50_000_000)
                esperado += 0.05
            }
            let habla: HablaDiagnostico
            if voz.hablando && voz.locuciones == propia {
                voz.descartarTodo()
                habla = Task.isCancelled ? .interrumpida : .noTerminoATiempo
            } else {
                habla = voz.locuciones == propia && voz.ultimaSeOyoEntera && !Task.isCancelled ? .dichaEntera : .interrumpida
            }
            return DiagnosticoTexto.voz(vocesEnEspanol: voces, habla: habla)
        }
    }
}
