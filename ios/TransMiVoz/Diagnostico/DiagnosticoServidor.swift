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
