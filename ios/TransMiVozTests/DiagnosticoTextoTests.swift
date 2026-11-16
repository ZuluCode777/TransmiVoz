import XCTest
@testable import TransMiVoz

final class DiagnosticoTextoTests: XCTestCase {
    func testCadaPruebaTieneTituloYQueDemuestraYLosIdentificadoresSonUnicos() {
        let ids = PruebaDiagnostico.allCases.map(\.id)
        XCTAssertEqual(Set(ids).count, ids.count)
        for prueba in PruebaDiagnostico.allCases {
            XCTAssertFalse(DiagnosticoTexto.titulo(prueba).isEmpty)
            XCTAssertFalse(DiagnosticoTexto.demuestra(prueba).isEmpty)
        }
    }

    func testCadaFilaDiceSuEstadoConPalabras() {
        XCTAssertEqual(DiagnosticoTexto.linea(.sinProbar), "Sin probar")
        XCTAssertEqual(DiagnosticoTexto.linea(.probando), "Probando…")
        XCTAssertEqual(DiagnosticoTexto.linea(.terminada(ResultadoPrueba(estado: .correcto, detalle: "a"))), "Correcto: a")
        XCTAssertEqual(DiagnosticoTexto.linea(.terminada(ResultadoPrueba(estado: .atencion, detalle: "b"))), "Atención: b")
        XCTAssertEqual(DiagnosticoTexto.linea(.terminada(ResultadoPrueba(estado: .fallo, detalle: "c"))), "Falló: c")
        XCTAssertEqual(DiagnosticoTexto.resumen(correctas: 3, total: 7), "3 de 7 correctas")
    }

    func testCadaPermisoTieneUnEstadoDistintoYUnTextoPropio() {
        let estados: [PermisoDiagnostico: EstadoPrueba] = [.concedido: .correcto, .porPreguntar: .atencion, .denegado: .fallo, .restringido: .fallo]
        var detalles = Set<String>()
        for (permiso, estado) in estados {
            let microfono = DiagnosticoTexto.microfono(permiso)
            XCTAssertEqual(microfono.estado, estado)
            detalles.insert(microfono.detalle)
            XCTAssertEqual(DiagnosticoTexto.camara(permiso, hayCamara: true).estado, estado)
        }
        XCTAssertEqual(detalles.count, 4, "denegado y restringido no se confunden con concedido ni entre sí")
    }

    func testLaCamaraSinDispositivoFallaAunqueElPermisoEsteConcedido() {
        let resultado = DiagnosticoTexto.camara(.concedido, hayCamara: false)
        XCTAssertEqual(resultado.estado, .fallo)
        XCTAssertTrue(resultado.detalle.contains("no tiene una cámara trasera"))
    }

    func testElReconocimientoDiceDondeSeReconoceYQueFaltaElPermiso() {
        let local = DiagnosticoTexto.reconocimiento(permiso: .concedido, capacidad: .local(idioma: "es-CO"))
        XCTAssertEqual(local.estado, .correcto)
        XCTAssertTrue(local.detalle.contains("en el iPhone (es-CO)"))
        let remoto = DiagnosticoTexto.reconocimiento(permiso: .concedido, capacidad: .remoto(idioma: "es-ES"))
        XCTAssertTrue(remoto.detalle.contains("se envía a Apple"))
        let sinPermiso = DiagnosticoTexto.reconocimiento(permiso: .porPreguntar, capacidad: .local(idioma: "es-CO"))
        XCTAssertEqual(sinPermiso.estado, .atencion, "sin permiso pedido no hay éxito que informar")
        XCTAssertEqual(DiagnosticoTexto.reconocimiento(permiso: .denegado, capacidad: .local(idioma: "es-CO")).estado, .fallo)
        XCTAssertEqual(DiagnosticoTexto.reconocimiento(permiso: .concedido, capacidad: .noDisponible).estado, .fallo)
    }

    func testLaVozQueNoSuenaPorElAltavozEsAtencionConLaSalida() {
        let sinAuriculares = DiagnosticoTexto.voz(vocesEnEspanol: 3, habla: .rutaNoPrivada)
        XCTAssertEqual(sinAuriculares.estado, .atencion)
        XCTAssertTrue(sinAuriculares.detalle.contains("3 voces en español"))
        XCTAssertTrue(sinAuriculares.detalle.contains("auriculares"))
        XCTAssertEqual(DiagnosticoTexto.voz(vocesEnEspanol: 1, habla: .iniciada).estado, .correcto)
        XCTAssertTrue(DiagnosticoTexto.voz(vocesEnEspanol: 1, habla: .iniciada).detalle.contains("1 voz en español."))
        XCTAssertEqual(DiagnosticoTexto.voz(vocesEnEspanol: 0, habla: .iniciada).estado, .atencion)
        XCTAssertEqual(DiagnosticoTexto.voz(vocesEnEspanol: 2, habla: .sesionNoDisponible).estado, .fallo)
    }

    func testNingunErrorDeServidorMuestraLaClaveNiLaDireccion() {
        let errores: [ErrorConsulta] = [
            .servidorNoConfigurado, .noAutorizado, .servicioNoDisponible, .demasiadasPeticiones(reintentarEnSegundos: 3), .sinConexion,
            .tiempoAgotado, .conexionNoSegura, .redireccionNoPermitida, .errorDelServidor(estado: 500), .respuestaIncompatible,
        ]
        for error in errores {
            let resultado = DiagnosticoTexto.falloDeServidor(error)
            XCTAssertEqual(resultado.estado, error == .servidorNoConfigurado ? .atencion : .fallo)
            for prohibido in ["Basic ", "Authorization", "transmivoz:", "https://", "clave:"] {
                XCTAssertFalse(resultado.detalle.contains(prohibido), "«\(prohibido)» en: \(resultado.detalle)")
            }
        }
        // Un error que no es de la app se trata como falta de conexión, sin copiar su texto.
        struct Raro: Error, CustomStringConvertible { var description: String { "secreto-123" } }
        XCTAssertFalse(DiagnosticoTexto.falloDeServidor(Raro()).detalle.contains("secreto-123"))
    }

    func testLasLineasPartenElResultadoEnFrasesYJuntasDicenLoMismo() {
        let fila = FilaDiagnostico.terminada(DiagnosticoTexto.voz(vocesEnEspanol: 2, habla: .rutaNoPrivada))
        let lineas = DiagnosticoTexto.lineas(fila)
        XCTAssertGreaterThan(lineas.count, 1)
        XCTAssertTrue(lineas[0].hasPrefix("Atención: "), "la primera frase lleva el estado")
        XCTAssertEqual(lineas.joined(separator: " "), DiagnosticoTexto.linea(fila))
        XCTAssertTrue(lineas.allSatisfy { $0.hasSuffix(".") }, "cada frase conserva su punto")
        XCTAssertEqual(DiagnosticoTexto.lineas(.sinProbar), ["Sin probar"])
        XCTAssertEqual(DiagnosticoTexto.lineas(.probando), ["Probando…"])
    }

    func testElTextoDeLasPruebasNoPideNiPrometeLoQueNoHace() {
        let notas = DiagnosticoTexto.notas.joined(separator: " ")
        XCTAssertTrue(notas.contains("no los pide"))
        XCTAssertTrue(notas.contains("no muestra la clave"))
    }
}

final class EmergenciaContactosTests: XCTestCase {
    func testLosNumerosSonLosDeLaWebEnSuOrden() {
        XCTAssertEqual(TextoEmergencia.principal.numero, "123")
        XCTAssertEqual(TextoEmergencia.otras.map(\.numero), ["156", "195"])
        XCTAssertEqual(TextoEmergencia.otras.map(\.nombre), ["Policía de TransMilenio", "Atención al usuario TransMilenio"])
    }

    func testCadaNumeroEsUnEnlaceTelSinNadaMas() {
        for llamada in [TextoEmergencia.principal] + TextoEmergencia.otras {
            XCTAssertEqual(llamada.url.absoluteString, "tel:\(llamada.numero)")
        }
    }

    func testLosNumerosCoincidenConLosDeLaAyuda() {
        let ayuda = TextoAyuda.secciones.flatMap(\.llamadas).map(\.numero)
        XCTAssertEqual(Set(ayuda), Set(([TextoEmergencia.principal] + TextoEmergencia.otras).map(\.numero)))
    }

    func testLosTextosSonLosDeLaWeb() {
        XCTAssertEqual(TextoEmergencia.titulo, "Emergencia")
        XCTAssertEqual(TextoEmergencia.aclaracion.count, 2, "una frase por párrafo")
        XCTAssertEqual(TextoEmergencia.tituloPrincipal, "Llamar al 123")
        XCTAssertEqual(TextoEmergencia.notaPrincipal, "Emergencias")
        XCTAssertEqual(TextoEmergencia.encabezadoOtras, "Otras líneas")
        XCTAssertEqual(TextoEmergencia.introHablada, "Emergencia. Toca el botón rojo para llamar a la línea 123.")
        XCTAssertEqual(TextoEmergencia.etiqueta(TextoEmergencia.otras[0]), "Policía de TransMilenio. Número 156.")
    }
}
