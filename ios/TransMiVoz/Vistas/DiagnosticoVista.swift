import SwiftUI

/// «Diagnóstico» (web: `/diagnostico`, `components/diagnostics.tsx`): comprueba en vivo, en este iPhone, que cada función
/// responde. Se abre desde el menú «Más ajustes» de la pestaña Ajustes. Cada fila dice con palabras cómo terminó su prueba
/// («Correcto», «Atención», «Falló»): ni el ícono ni el color son la única señal. Ninguna prueba pide permisos ni muestra la
/// clave del servidor; el servidor, el asistente y el planificador de rutas se prueban con los clientes de siempre y la configuración de Ajustes.
struct DiagnosticoVista: View {
    @State private var modelo: DiagnosticoModelo

    init(ajustes: AjustesServidorModelo, voz: ControlVoz, modoPruebas: Bool) {
        _modelo = State(initialValue: DiagnosticoModelo.crear(ajustes: ajustes, voz: voz, simulado: modoPruebas))
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                EncabezadoPantalla(titulo: DiagnosticoTexto.titulo, subtitulo: DiagnosticoTexto.subtitulo, simbolo: "stethoscope")
                    .accessibilityIdentifier("diagnostico-encabezado")
                parrafos(DiagnosticoTexto.explicacion + DiagnosticoTexto.notas, id: "diagnostico-nota")
                Button(DiagnosticoTexto.probarTodo) { modelo.iniciarTodo() }
                    .buttonStyle(EstiloBotonPrimario())
                    .disabled(modelo.ocupado)
                    .accessibilityIdentifier("diagnostico-probar-todo")
                Text(DiagnosticoTexto.resumen(correctas: modelo.correctas, total: modelo.total))
                    .font(.jakarta(.bold, .xl))
                    .foregroundStyle(Paleta.foreground)
                    .fixedSize(horizontal: false, vertical: true)
                    .accessibilityAddTraits(.updatesFrequently)
                    .accessibilityIdentifier("diagnostico-resumen")
                ForEach(PruebaDiagnostico.allCases) { prueba in
                    FilaPrueba(prueba: prueba, fila: modelo.fila(prueba), ocupado: modelo.ocupado) { modelo.iniciar(prueba) }
                }
            }
            .padding(16)
        }
        .navigationTitle(DiagnosticoTexto.titulo)
        .navigationBarTitleDisplayMode(.inline)
        .bordeInferiorLegible()
        .bordeSuperiorNitido()
        // Cada resultado se anuncia al terminar la prueba, para quien no mira la pantalla.
        .onChange(of: modelo.filas) { anteriores, nuevas in
            for prueba in PruebaDiagnostico.allCases {
                guard anteriores[prueba] != nuevas[prueba], case .terminada = nuevas[prueba] ?? .sinProbar else { continue }
                AccessibilityNotification.Announcement(
                    "\(DiagnosticoTexto.titulo(prueba)). \(DiagnosticoTexto.linea(nuevas[prueba] ?? .sinProbar))"
                ).post()
            }
        }
        // Salir corta lo que esté corriendo: nadie espera ese resultado.
        .onDisappear { modelo.cancelar() }
    }
}

/// Un `Text` por frase: con el texto más grande cada una cabe entera en el área visible. La primera conserva `id`; las demás
/// le añaden su posición.
private func parrafos(_ frases: [String], id: String) -> some View {
    ForEach(Array(frases.enumerated()), id: \.offset) { posicion, frase in
        Text(frase)
            .font(.jakarta(.regular, .base))
            .foregroundStyle(Paleta.foreground)
            .fixedSize(horizontal: false, vertical: true)
            .accessibilityIdentifier(posicion == 0 ? id : "\(id)-\(posicion)")
    }
}

/// Una prueba: ficha de estado, título, qué demuestra, su resultado en texto y «Probar».
private struct FilaPrueba: View {
    let prueba: PruebaDiagnostico
    let fila: FilaDiagnostico
    let ocupado: Bool
    let probar: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            // El ícono repite lo que dice el texto del resultado; el estado nunca depende solo de él.
            Text("\(Image(systemName: simbolo)) \(DiagnosticoTexto.titulo(prueba))")
                .font(.jakarta(.bold, .xl))
                .fixedSize(horizontal: false, vertical: true)
                .accessibilityLabel(DiagnosticoTexto.titulo(prueba))
                .accessibilityAddTraits(.isHeader)
                .accessibilityIdentifier("diagnostico-titulo-\(prueba.id)")
            Text(DiagnosticoTexto.demuestra(prueba))
                .font(.jakarta(.regular, .base))
                .fixedSize(horizontal: false, vertical: true)
                .accessibilityIdentifier("diagnostico-demuestra-\(prueba.id)")
            ForEach(Array(DiagnosticoTexto.lineas(fila).enumerated()), id: \.offset) { posicion, frase in
                Text(frase)
                    .font(.jakarta(.semibold, .lg))
                    .fixedSize(horizontal: false, vertical: true)
                    .accessibilityIdentifier(posicion == 0 ? "diagnostico-resultado-\(prueba.id)" : "diagnostico-resultado-\(prueba.id)-\(posicion)")
            }
            Button(DiagnosticoTexto.probar, action: probar)
                .buttonStyle(EstiloBotonSecundario())
                .disabled(ocupado)
                .accessibilityLabel("Probar: \(DiagnosticoTexto.titulo(prueba))")
                .accessibilityIdentifier("diagnostico-probar-\(prueba.id)")
        }
        .tarjetaWeb()
        .accessibilityElement(children: .contain)
    }

    private var simbolo: String {
        switch fila {
        case .sinProbar: return "circle.dashed"
        case .probando: return "hourglass"
        case .terminada(let resultado):
            switch resultado.estado {
            case .correcto: return "checkmark.circle"
            case .atencion: return "exclamationmark.triangle"
            case .fallo: return "xmark.circle"
            }
        }
    }
}
