import AVFoundation
import CoreBluetooth
import Foundation
import Speech

// Las sondas de sistema del diagnóstico: leen el estado real de este iPhone con las mismas piezas que usa la app
// (`ReconocedorSFSpeech`, `CamaraLupaAVFoundation`; la voz, por la `ControlVoz` compartida: `SondaVoz`). Ninguna provoca un aviso de permiso del sistema.
// Nada de esto se ha probado en un iPhone: en las pruebas de interfaz las sustituyen las sintéticas (`SondaSintetica`).

/// «Reconocimiento de voz»: permiso de reconocimiento y lo que el sistema declara poder hacer en español
/// (`ReconocedorSFSpeech.capacidad`).
struct SondaReconocimiento: SondaDiagnostico {
    @MainActor func ejecutar() async -> ResultadoPrueba {
        let permiso: PermisoDiagnostico
        switch SFSpeechRecognizer.authorizationStatus() {
        case .authorized: permiso = .concedido
        case .notDetermined: permiso = .porPreguntar
        case .restricted: permiso = .restringido
        case .denied: permiso = .denegado
        @unknown default: permiso = .denegado
        }
        return DiagnosticoTexto.reconocimiento(permiso: permiso, capacidad: ReconocedorSFSpeech().capacidad)
    }
}

/// «Micrófono»: permiso del micrófono (el mismo `AVAudioApplication` que consulta el dictado).
struct SondaMicrofono: SondaDiagnostico {
    func ejecutar() async -> ResultadoPrueba {
        switch AVAudioApplication.shared.recordPermission {
        case .granted: return DiagnosticoTexto.microfono(.concedido)
        case .undetermined: return DiagnosticoTexto.microfono(.porPreguntar)
        case .denied: return DiagnosticoTexto.microfono(.denegado)
        @unknown default: return DiagnosticoTexto.microfono(.denegado)
        }
    }
}

/// «Cámara»: permiso y si hay cámara trasera, por `CamaraLupaAVFoundation` (la cámara de la lupa). No la abre.
struct SondaCamara: SondaDiagnostico {
    @MainActor func ejecutar() async -> ResultadoPrueba {
        let camara = CamaraLupaAVFoundation()
        let permiso: PermisoDiagnostico
        switch camara.permiso {
        case .concedido: permiso = .concedido
        case .porPreguntar: permiso = .porPreguntar
        case .denegado: permiso = .denegado
        case .restringido: permiso = .restringido
        }
        return DiagnosticoTexto.camara(permiso, hayCamara: camara.hayCamara)
    }
}

/// «Bluetooth»: el permiso (sin pedirlo) y, solo si ya está concedido, el estado que informa el sistema. No busca ni se
/// conecta a nada. Con el permiso por preguntar no crea el gestor de Bluetooth: crearlo provocaría el aviso del sistema.
/// Los textos son los de la pantalla Sesión (`TextoAccesorio.bluetooth`).
@MainActor
final class SondaBluetooth: NSObject, SondaDiagnostico, CBCentralManagerDelegate {
    private static let plazo: UInt64 = 3_000_000_000

    private var gestor: CBCentralManager?
    private var continuacion: CheckedContinuation<CBManagerState, Never>?

    func ejecutar() async -> ResultadoPrueba {
        switch CBCentralManager.authorization {
        case .notDetermined:
            return ResultadoPrueba(
                estado: .atencion, detalle: "Todavía no diste el permiso de Bluetooth; se pide al buscar el accesorio en Sesión.")
        case .denied:
            return ResultadoPrueba(estado: .fallo, detalle: TextoAccesorio.bluetooth(.sinPermiso))
        case .restricted:
            return ResultadoPrueba(estado: .fallo, detalle: TextoAccesorio.bluetooth(.restringido))
        case .allowedAlways:
            break
        @unknown default:
            return ResultadoPrueba(estado: .fallo, detalle: TextoAccesorio.bluetooth(.sinPermiso))
        }
        switch await estadoDelSistema() {
        case .poweredOn: return ResultadoPrueba(estado: .correcto, detalle: TextoAccesorio.bluetooth(.disponible))
        case .poweredOff: return ResultadoPrueba(estado: .atencion, detalle: TextoAccesorio.bluetooth(.apagado))
        case .unauthorized: return ResultadoPrueba(estado: .fallo, detalle: TextoAccesorio.bluetooth(.sinPermiso))
        case .unsupported: return ResultadoPrueba(estado: .fallo, detalle: TextoAccesorio.bluetooth(.noSoportado))
        case .resetting, .unknown: return ResultadoPrueba(estado: .atencion, detalle: "El sistema no informó el estado del Bluetooth a tiempo.")
        @unknown default: return ResultadoPrueba(estado: .atencion, detalle: "El sistema no informó el estado del Bluetooth a tiempo.")
        }
    }

    /// Espera el primer estado definitivo del sistema, con tope de 3 s.
    private func estadoDelSistema() async -> CBManagerState {
        await withCheckedContinuation { continuacion in
            self.continuacion = continuacion
            gestor = CBCentralManager(delegate: self, queue: .main, options: [CBCentralManagerOptionShowPowerAlertKey: false])
            Task { @MainActor [weak self] in
                try? await Task.sleep(nanoseconds: Self.plazo)
                self?.resolver(.unknown, forzar: true)
            }
        }
    }

    private func resolver(_ estado: CBManagerState, forzar: Bool = false) {
        guard forzar || (estado != .unknown && estado != .resetting), let continuacion else { return }
        self.continuacion = nil
        gestor = nil
        continuacion.resume(returning: estado)
    }

    nonisolated func centralManagerDidUpdateState(_ central: CBCentralManager) {
        let estado = central.state
        Task { @MainActor in self.resolver(estado) }
    }
}

extension DiagnosticoModelo {
    /// El diagnóstico de la app. El servidor, el asistente y el planificador usan los clientes HTTP de siempre con la configuración de Ajustes
    /// (la clave solo viaja en la cabecera que arma el cliente: ningún resultado la muestra). Con `simulado` (pruebas de
    /// interfaz) las cinco pruebas de sistema son sintéticas y rotuladas; el servidor sigue siendo el cliente real, que sin
    /// dirección configurada responde «falta la dirección» sin tocar la red.
    @MainActor static func crear(ajustes: AjustesServidorModelo, voz: ControlVoz, simulado: Bool) -> DiagnosticoModelo {
        var sondas: [PruebaDiagnostico: any SondaDiagnostico] = [
            .servidor: SondaServidor(cliente: ClienteAnunciosHTTP { await ajustes.configuracion }),
            .asistente: SondaAsistente(cliente: ClienteAgenteHTTP { await ajustes.configuracion }),
            .planificador: SondaPlanificador(cliente: ClientePlanificadorHTTP { await ajustes.configuracion }),
        ]
        if simulado {
            sondas[.voz] = SondaSintetica(resultado: DiagnosticoTexto.voz(vocesEnEspanol: 2, habla: .rutaNoPrivada))
            sondas[.reconocimiento] = SondaSintetica(
                resultado: DiagnosticoTexto.reconocimiento(permiso: .porPreguntar, capacidad: .remoto(idioma: "es-CO")))
            sondas[.microfono] = SondaSintetica(resultado: DiagnosticoTexto.microfono(.concedido))
            sondas[.camara] = SondaSintetica(resultado: DiagnosticoTexto.camara(.denegado, hayCamara: true))
            sondas[.bluetooth] = SondaSintetica(resultado: ResultadoPrueba(estado: .correcto, detalle: TextoAccesorio.bluetooth(.disponible)))
        } else {
            sondas[.voz] = SondaVoz(voz: voz) {
                AVSpeechSynthesisVoice.speechVoices().filter { $0.language.lowercased().hasPrefix("es") }.count
            }
            sondas[.reconocimiento] = SondaReconocimiento()
            sondas[.microfono] = SondaMicrofono()
            sondas[.camara] = SondaCamara()
            sondas[.bluetooth] = SondaBluetooth()
        }
        return DiagnosticoModelo(sondas: sondas)
    }
}
