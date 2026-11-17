import Observation
import XCTest
@testable import TransMiVoz

/// Cuenta los avisos de `withObservationTracking`: el cierre `onChange` es `@Sendable` y no puede mutar una variable local.
private final class ContadorDeAvisos: @unchecked Sendable {
    private let candado = NSLock()
    private var cuenta = 0
    var valor: Int { candado.lock(); defer { candado.unlock() }; return cuenta }
    func sumar() { candado.lock(); cuenta += 1; candado.unlock() }
}

/// Almacén en memoria que cuenta las escrituras, para comprobar qué se guarda y cuándo.
/// `@unchecked Sendable`: las pruebas lo usan solo desde el actor principal.
private final class AlmacenFavoritasFalso: AlmacenFavoritas, @unchecked Sendable {
    var guardado: [String]?
    private(set) var escrituras = 0

    init(guardado: [String]? = nil) { self.guardado = guardado }

    func leer() -> [String]? { guardado }
    func guardar(_ codigos: [String]) {
        guardado = codigos
        escrituras += 1
    }
}

@MainActor
final class FavoritasModeloTests: XCTestCase {
    func testSinNadaGuardadoEmpiezaVacia() {
        let modelo = FavoritasModelo(almacen: AlmacenFavoritasFalso())
        XCTAssertEqual(modelo.codigos, [])
    }

    func testAgregarNormalizaGuardaYNoDuplica() {
        let almacen = AlmacenFavoritasFalso()
        let modelo = FavoritasModelo(almacen: almacen)
        XCTAssertTrue(modelo.agregar(" b23 "))
        XCTAssertFalse(modelo.agregar("B23"))
        XCTAssertEqual(modelo.codigos, ["B23"])
        XCTAssertEqual(almacen.guardado, ["B23"])
        XCTAssertEqual(almacen.escrituras, 1)
    }

    func testAgregarConservaElOrden() {
        let modelo = FavoritasModelo(almacen: AlmacenFavoritasFalso())
        modelo.agregar("M83")
        modelo.agregar("B23")
        XCTAssertEqual(modelo.codigos, ["M83", "B23"])
    }

    func testAgregarCodigoVacioNoHaceNada() {
        let almacen = AlmacenFavoritasFalso()
        let modelo = FavoritasModelo(almacen: almacen)
        XCTAssertFalse(modelo.agregar("   "))
        XCTAssertEqual(modelo.codigos, [])
        XCTAssertEqual(almacen.escrituras, 0)
    }

    func testQuitarSacaLaRutaYLoGuarda() {
        let almacen = AlmacenFavoritasFalso(guardado: ["B23", "H54"])
        let modelo = FavoritasModelo(almacen: almacen)
        XCTAssertTrue(modelo.quitar("b23"))
        XCTAssertEqual(modelo.codigos, ["H54"])
        XCTAssertEqual(almacen.guardado, ["H54"])
        XCTAssertFalse(modelo.contiene("B23"))
    }

    func testQuitarUnaRutaQueNoEstaNoEscribe() {
        let almacen = AlmacenFavoritasFalso(guardado: ["B23"])
        let modelo = FavoritasModelo(almacen: almacen)
        XCTAssertFalse(modelo.quitar("H54"))
        XCTAssertEqual(modelo.codigos, ["B23"])
        XCTAssertEqual(almacen.escrituras, 0)
    }

    func testContieneIgnoraMayusculasYEspacios() {
        let modelo = FavoritasModelo(almacen: AlmacenFavoritasFalso(guardado: ["B23"]))
        XCTAssertTrue(modelo.contiene(" b23"))
        XCTAssertFalse(modelo.contiene("H54"))
        XCTAssertFalse(modelo.contiene(""))
    }

    func testAlCargarNormalizaYQuitaVaciosYRepetidos() {
        let modelo = FavoritasModelo(almacen: AlmacenFavoritasFalso(guardado: ["b23", " H54 ", "B23", "", "H54"]))
        XCTAssertEqual(modelo.codigos, ["B23", "H54"])
    }

    func testUserDefaultsConservaLasFavoritasEntreModelos() {
        let nombre = "pruebas.transmivoz.\(UUID().uuidString)"
        let preferencias = UserDefaults(suiteName: nombre)!
        defer { preferencias.removePersistentDomain(forName: nombre) }

        let primero = FavoritasModelo(almacen: AlmacenFavoritasUserDefaults(preferencias: preferencias))
        primero.agregar("B23")
        primero.agregar("H54")
        primero.quitar("B23")

        let segundo = FavoritasModelo(almacen: AlmacenFavoritasUserDefaults(preferencias: preferencias))
        XCTAssertEqual(segundo.codigos, ["H54"])
    }

    func testUnValorGuardadoQueNoEsUnaListaDeTextosSeIgnora() {
        let nombre = "pruebas.transmivoz.\(UUID().uuidString)"
        let preferencias = UserDefaults(suiteName: nombre)!
        defer { preferencias.removePersistentDomain(forName: nombre) }

        preferencias.set("no es una lista", forKey: AlmacenFavoritasUserDefaults.claveGuardado)
        XCTAssertEqual(FavoritasModelo(almacen: AlmacenFavoritasUserDefaults(preferencias: preferencias)).codigos, [])
        preferencias.set([1, 2], forKey: AlmacenFavoritasUserDefaults.claveGuardado)
        XCTAssertEqual(FavoritasModelo(almacen: AlmacenFavoritasUserDefaults(preferencias: preferencias)).codigos, [])
    }

    /// El recorrido de la prueba de interfaz «quitar favoritas» (`testQuitarFavoritasLasSacaDeLaListaHastaVaciarla`), sin pantalla:
    /// las dos de ejemplo se siembran en una suite como `favoritasDePruebas`, quitar la primera avisa a quien observa `codigos` (es
    /// lo que repinta la lista), deja la otra y lo guardado, y quitar la segunda vacía la lista y también avisa. Si la lista de la
    /// pantalla no se repintara, la causa no estaría aquí: esto fija que el modelo SÍ avisa y guarda en cada quita.
    func testQuitarAvisaALaVistaYDejaLaOtraGuardadaHastaVaciar() {
        let nombre = "pruebas.transmivoz.\(UUID().uuidString)"
        let preferencias = UserDefaults(suiteName: nombre)!
        defer { preferencias.removePersistentDomain(forName: nombre) }
        let modelo = FavoritasModelo(almacen: AlmacenFavoritasUserDefaults(preferencias: preferencias))
        modelo.agregar("Z99")
        modelo.agregar("Z98")

        let avisos = ContadorDeAvisos()
        func observar() { withObservationTracking({ _ = modelo.codigos }, onChange: { avisos.sumar() }) }
        observar()
        XCTAssertTrue(modelo.quitar("Z99"))
        XCTAssertEqual(avisos.valor, 1, "quitar avisa a quien observa la lista")
        XCTAssertEqual(modelo.codigos, ["Z98"])
        XCTAssertFalse(modelo.contiene("Z99"))
        XCTAssertEqual(preferencias.stringArray(forKey: AlmacenFavoritasUserDefaults.claveGuardado), ["Z98"], "lo guardado ya no tiene Z99")
        XCTAssertEqual(FavoritasModelo(almacen: AlmacenFavoritasUserDefaults(preferencias: preferencias)).codigos, ["Z98"])

        observar() // la observación es de un solo uso: la vista vuelve a registrarla al repintar
        XCTAssertTrue(modelo.quitar("Z98"))
        XCTAssertEqual(avisos.valor, 2)
        XCTAssertEqual(modelo.codigos, [])
        XCTAssertEqual(preferencias.stringArray(forKey: AlmacenFavoritasUserDefaults.claveGuardado), [])
    }

    /// Quitar la que no está no avisa ni escribe: la lista no se repinta por un toque que no cambió nada.
    func testQuitarUnaQueNoEstaNoAvisaALaVista() {
        let modelo = FavoritasModelo(almacen: AlmacenFavoritasFalso(guardado: ["Z98"]))
        let avisos = ContadorDeAvisos()
        withObservationTracking({ _ = modelo.codigos }, onChange: { avisos.sumar() })
        XCTAssertFalse(modelo.quitar("Z99"))
        XCTAssertEqual(avisos.valor, 0)
        XCTAssertEqual(modelo.codigos, ["Z98"])
    }
}

