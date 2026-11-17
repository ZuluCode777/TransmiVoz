import XCTest
@testable import TransMiVoz

/// Almacén en memoria que cuenta las escrituras. `@unchecked Sendable`: las pruebas lo usan solo desde el actor principal.
private final class AlmacenModoFalso: AlmacenModo, @unchecked Sendable {
    var guardado: String?
    private(set) var escrituras = 0

    init(guardado: String? = nil) { self.guardado = guardado }

    func leer() -> String? { guardado }
    func guardar(_ valor: String) {
        guardado = valor
        escrituras += 1
    }
}

@MainActor
final class ModoAppModeloTests: XCTestCase {
    func testSinNadaGuardadoEmpiezaEnBajaVision() {
        XCTAssertEqual(ModoAppModelo(almacen: AlmacenModoFalso()).modo, .parcial)
    }

    func testLeeElModoGuardado() {
        XCTAssertEqual(ModoAppModelo(almacen: AlmacenModoFalso(guardado: "total")).modo, .total)
        XCTAssertEqual(ModoAppModelo(almacen: AlmacenModoFalso(guardado: "parcial")).modo, .parcial)
    }

    /// Como la web: un valor guardado que no es `parcial` ni `total` se ignora.
    func testUnValorDesconocidoSeIgnora() {
        XCTAssertEqual(ModoAppModelo(almacen: AlmacenModoFalso(guardado: "otro")).modo, .parcial)
        XCTAssertEqual(ModoAppModelo(almacen: AlmacenModoFalso(guardado: "")).modo, .parcial)
    }

    func testElegirCambiaElModoYGuardaElValorDeLaWeb() {
        let almacen = AlmacenModoFalso()
        let modelo = ModoAppModelo(almacen: almacen)
        XCTAssertTrue(modelo.elegir(.total))
        XCTAssertEqual(modelo.modo, .total)
        XCTAssertEqual(almacen.guardado, "total")
        XCTAssertEqual(almacen.escrituras, 1)
    }

    func testElegirElModoActualNoEscribe() {
        let almacen = AlmacenModoFalso()
        let modelo = ModoAppModelo(almacen: almacen)
        XCTAssertFalse(modelo.elegir(.parcial))
        XCTAssertEqual(almacen.escrituras, 0)
        XCTAssertNil(almacen.guardado)
    }

    func testLoElegidoSobreviveAUnaNuevaInstancia() {
        let almacen = AlmacenModoFalso()
        ModoAppModelo(almacen: almacen).elegir(.total)
        XCTAssertEqual(ModoAppModelo(almacen: almacen).modo, .total)
    }

    /// La clave y los valores son los de la web (`localStorage`: `transmivoz-mode` = `parcial` | `total`).
    func testLaClaveYLosValoresSonLosDeLaWeb() {
        XCTAssertEqual(AlmacenModoUserDefaults.clave, "transmivoz-mode")
        XCTAssertEqual(ModoApp.allCases.map(\.rawValue), ["parcial", "total"])
    }

    func testAlmacenUserDefaultsGuardaYLee() throws {
        let nombre = "pruebas.modo.\(UUID().uuidString)"
        let preferencias = try XCTUnwrap(UserDefaults(suiteName: nombre))
        defer { preferencias.removePersistentDomain(forName: nombre) }
        let almacen = AlmacenModoUserDefaults(preferencias: preferencias)
        XCTAssertNil(almacen.leer())
        almacen.guardar("total")
        XCTAssertEqual(almacen.leer(), "total")
        XCTAssertEqual(preferencias.string(forKey: "transmivoz-mode"), "total")
    }

    /// Los textos son los de `components/mode-menu.tsx` y de `changeMode`.
    func testLosTextosDeLosModosSonLosDeLaWeb() {
        XCTAssertEqual(ModoApp.parcial.titulo, "Baja visión")
        XCTAssertEqual(ModoApp.total.titulo, "Ceguera total")
        XCTAssertEqual(ModoApp.parcial.anuncio, "Modo baja visión activado.")
        XCTAssertEqual(ModoApp.total.anuncio, "Modo ceguera total activado.")
        XCTAssertEqual(ModoApp.parcial.descripcion, "Para personas con visión parcial. Texto e íconos grandes: buscar rutas, frecuentes y asistencia.")
        XCTAssertEqual(ModoApp.total.descripcion, "Para personas totalmente ciegas. Sin mirar la pantalla: solo voz y escaneo guiados por audio.")
    }
}

/// «Alto contraste» (el interruptor de colores fluorescentes de la web): sin elección manda el sistema; la elección se guarda
/// con la clave y los valores de la web y sobrevive a otra instancia.
@MainActor
final class AltoContrasteModeloTests: XCTestCase {
    func testSinNadaGuardadoNoHayEleccionYMandaElSistema() {
        let almacen = AlmacenModoFalso()
        XCTAssertNil(AltoContrasteModelo(almacen: almacen).elegido)
        XCTAssertEqual(almacen.escrituras, 0, "leer la preferencia no escribe nada")
    }

    func testLeeLaEleccionGuardadaConLosValoresDeLaWeb() {
        XCTAssertEqual(AltoContrasteModelo(almacen: AlmacenModoFalso(guardado: "on")).elegido, true)
        XCTAssertEqual(AltoContrasteModelo(almacen: AlmacenModoFalso(guardado: "off")).elegido, false)
    }

    /// Un valor guardado que no es `on` ni `off` se ignora: sigue mandando el sistema.
    func testUnValorDesconocidoSeIgnora() {
        for valor in ["", "true", "ON", "oscuro"] {
            XCTAssertNil(AltoContrasteModelo(almacen: AlmacenModoFalso(guardado: valor)).elegido, "«\(valor)»")
        }
    }

    func testElegirGuardaYApagarloTambienEsUnaEleccion() {
        let almacen = AlmacenModoFalso()
        let modelo = AltoContrasteModelo(almacen: almacen)
        XCTAssertTrue(modelo.elegir(true))
        XCTAssertEqual(modelo.elegido, true)
        XCTAssertEqual(almacen.guardado, "on")
        XCTAssertTrue(modelo.elegir(false))
        XCTAssertEqual(modelo.elegido, false, "apagado a mano no vuelve a seguir al sistema")
        XCTAssertEqual(almacen.guardado, "off")
        XCTAssertEqual(almacen.escrituras, 2)
    }

    func testElegirLoYaElegidoNoEscribe() {
        let almacen = AlmacenModoFalso(guardado: "on")
        let modelo = AltoContrasteModelo(almacen: almacen)
        XCTAssertFalse(modelo.elegir(true))
        XCTAssertEqual(almacen.escrituras, 0)
    }

    func testLaEleccionSobreviveAUnaNuevaInstancia() {
        let almacen = AlmacenModoFalso()
        AltoContrasteModelo(almacen: almacen).elegir(false)
        XCTAssertEqual(AltoContrasteModelo(almacen: almacen).elegido, false)
    }

    /// Clave propia, la de la web (`transmivoz-fluor`), sin pisar la del modo aunque compartan preferencias.
    func testLaClaveEsLaDeLaWebYNoPisaLaDelModo() throws {
        XCTAssertEqual(AlmacenModoUserDefaults.claveAltoContraste, "transmivoz-fluor")
        let nombre = "pruebas.contraste.\(UUID().uuidString)"
        let preferencias = try XCTUnwrap(UserDefaults(suiteName: nombre))
        defer { preferencias.removePersistentDomain(forName: nombre) }
        let modo = ModoAppModelo(almacen: AlmacenModoUserDefaults(preferencias: preferencias))
        let contraste = AltoContrasteModelo(almacen: AlmacenModoUserDefaults(
            preferencias: preferencias, clave: AlmacenModoUserDefaults.claveAltoContraste))
        modo.elegir(.total)
        contraste.elegir(true)
        XCTAssertEqual(preferencias.string(forKey: "transmivoz-mode"), "total")
        XCTAssertEqual(preferencias.string(forKey: "transmivoz-fluor"), "on")
    }

    func testElAnuncioEsElDeLaWeb() {
        XCTAssertEqual(AltoContrasteModelo.anuncio(true), "Colores fluorescentes activados.")
        XCTAssertEqual(AltoContrasteModelo.anuncio(false), "Colores fluorescentes desactivados.")
    }
}

final class TextoInicioTests: XCTestCase {
    /// Las seis baldosas de `components/partial-home.tsx`, en su orden: Emergencia siempre al final.
    func testLasSeisOpcionesTienenElOrdenYLosTextosDeLaWeb() {
        let esperado: [(String, String)] = [
            ("Asistente", "Pregunta cómo llegar"), ("Rutas", "Buscar y frecuentes"), ("Mapa y GPS", "Estaciones cercanas"),
            ("Metro de Bogotá", "En construcción, sin servicio"), ("Lupa", "Ampliar letreros"), ("Emergencia", "Llamar al 123"),
        ]
        XCTAssertEqual(OpcionInicio.allCases.map(\.titulo), esperado.map(\.0))
        XCTAssertEqual(OpcionInicio.allCases.map(\.pista), esperado.map(\.1))
        XCTAssertEqual(OpcionInicio.allCases.last, .emergencia)
    }

    func testLosIdentificadoresSonUnicosYEstables() {
        let ids = OpcionInicio.allCases.map(\.identificador)
        XCTAssertEqual(Set(ids).count, ids.count)
        XCTAssertEqual(ids, ["inicio-asistente", "inicio-rutas", "inicio-gps", "inicio-metro", "inicio-lupa", "inicio-emergencia"])
    }

    func testLosTextosDeLaCabeceraSonLosDeLaWeb() {
        XCTAssertEqual(TextoInicio.abrirMenu, "Abrir menú de accesibilidad")
        XCTAssertEqual(TextoInicio.abrirAvisos, "Avisos y anuncios")
        XCTAssertEqual(TextoInicio.pregunta, "¿Qué necesitas?")
        XCTAssertEqual(TextoInicio.nombreApp, "TransMiVoz")
    }
}
