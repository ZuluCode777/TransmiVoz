import SwiftUI

/// «Emergencia» (web: `components/assistance.tsx`). Se abre desde la baldosa «Emergencia» de Inicio. El botón rojo grande llama
/// al 123 y debajo están las otras líneas de la web. Cada botón es un enlace `tel:`: iOS abre su propia confirmación y la
/// persona decide si llama; la app nunca marca sola. Al abrirse dice la introducción de la web por la `ControlVoz` compartida
/// de la app (`EmergenciaVozModelo`: sin otra sesión de audio ni otra cola de voz; habla solo con la voz permitida y por
/// auriculares, y nunca tapa un aviso del accesorio; con VoiceOver se lee la pantalla). Conserva el título de navegación
/// «Emergencia»: las pruebas de Inicio abren la pantalla por él.
struct EmergenciaVista: View {
    @State private var voz: EmergenciaVozModelo
    /// Lleva el foco de VoiceOver al resultado de «Repetir»: es el único canal, no se anuncia además.
    @AccessibilityFocusState private var enResultado: Bool

    init(voz: ControlVoz) {
        _voz = State(initialValue: EmergenciaVozModelo(voz: voz))
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                EncabezadoPantalla(titulo: TextoEmergencia.titulo, subtitulo: TextoEmergencia.subtitulo, simbolo: "exclamationmark.shield")
                    .accessibilityIdentifier("emergencia-encabezado")
                BotonLlamada123()
                Text(TextoEmergencia.encabezadoOtras)
                    .font(.jakarta(.bold, .xl))
                    .foregroundStyle(Paleta.foreground)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.top, 8)
                    .accessibilityAddTraits(.isHeader)
                    .accessibilityIdentifier("emergencia-otras-lineas")
                ForEach(TextoEmergencia.otras, id: \.numero) { llamada in
                    FilaLlamada(llamada: llamada)
                }
                ForEach(Array(TextoEmergencia.aclaracion.enumerated()), id: \.offset) { posicion, frase in
                    Text(frase)
                        .font(.jakarta(.regular, .base))
                        .foregroundStyle(Paleta.foreground)
                        .fixedSize(horizontal: false, vertical: true)
                        .accessibilityIdentifier(posicion == 0 ? "emergencia-aclaracion" : "emergencia-aclaracion-\(posicion)")
                }
                appDijo
            }
            .padding(16)
        }
        .pantallaWeb()
        .navigationTitle(TextoEmergencia.titulo)
        .navigationBarTitleDisplayMode(.inline)
        .bordeInferiorLegible()
        .bordeSuperiorNitido()
        .onAppear { voz.decirIntroduccion() }
        .onChange(of: voz.repeticiones) { _, _ in enResultado = true }
        // Al salir se corta solo esta locución: la voz no sigue hablando de una pantalla que ya no se ve.
        .onDisappear { voz.salir() }
    }
}

extension EmergenciaVista {
    /// «La app dijo» con «Repetir»: lo mismo que dice la voz, en texto (no solo por audio), y cómo salió. Va al final para que el
    /// botón rojo siga siendo lo primero.
    fileprivate var appDijo: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(TextoEmergencia.appDijo)
                .font(.jakarta(.bold, .xl))
                .fixedSize(horizontal: false, vertical: true)
                .accessibilityAddTraits(.isHeader)
                .accessibilityIdentifier("emergencia-app-dijo")
            Text(TextoEmergencia.introHablada)
                .font(.jakarta(.regular, .lg))
                .fixedSize(horizontal: false, vertical: true)
                .accessibilityIdentifier("emergencia-app-dijo-texto")
            if let resultado = voz.resultado {
                Text(resultado)
                    .font(.jakarta(.semibold, .base))
                    .fixedSize(horizontal: false, vertical: true)
                    .accessibilityFocused($enResultado)
                    .accessibilityIdentifier("emergencia-app-dijo-resultado")
            }
            Button(TextoEmergencia.repetir) { voz.repetir() }
                .buttonStyle(EstiloBotonSecundario())
                .accessibilityLabel(TextoEmergencia.repetirEtiqueta)
                .accessibilityIdentifier("emergencia-repetir")
        }
        .tarjetaWeb()
        .padding(.top, 8)
    }
}

/// El botón rojo de la web: `rounded-3xl border-5 border-sos-border bg-sos p-6 text-center text-sos-foreground`, con el
/// teléfono en un círculo, «Llamar al 123» y «Emergencias».
private struct BotonLlamada123: View {
    @ScaledMetric(relativeTo: .title) private var ladoCirculo: CGFloat = 64
    @Environment(\.dynamicTypeSize) private var tamanoTexto

    var body: some View {
        Link(destination: TextoEmergencia.principal.url) {
            VStack(spacing: 12) {
                // Con el texto más grande se quita el ícono (decorativo) para que el botón entero quepa en la pantalla.
                if !tamanoTexto.isAccessibilitySize {
                    Image(systemName: "phone.fill")
                        .font(.title)
                        .frame(width: ladoCirculo, height: ladoCirculo)
                        .overlay(Circle().strokeBorder(Paleta.sosForeground, lineWidth: Tema.borde))
                        .accessibilityHidden(true)
                }
                Text(TextoEmergencia.tituloPrincipal)
                    .font(.jakarta(.bold, .xl2))
                    .accessibilityIdentifier("emergencia-llamar-123-titulo")
                Text(TextoEmergencia.notaPrincipal)
                    .font(.jakarta(.regular, .xl))
                    .accessibilityIdentifier("emergencia-llamar-123-nota")
            }
            .multilineTextAlignment(.center)
            .fixedSize(horizontal: false, vertical: true)
            .foregroundStyle(Paleta.sosForeground)
            .padding(24)
            .frame(maxWidth: .infinity)
            .background(Paleta.sos, in: RoundedRectangle(cornerRadius: Tema.radio3XL))
            .overlay(RoundedRectangle(cornerRadius: Tema.radio3XL).strokeBorder(Paleta.sosBorder, lineWidth: Tema.bordeEmergencia))
            .contentShape(RoundedRectangle(cornerRadius: Tema.radio3XL))
        }
        .buttonStyle(EstiloApreton())
        .accessibilityLabel("\(TextoEmergencia.tituloPrincipal). \(TextoEmergencia.notaPrincipal).")
        .accessibilityHint(TextoEmergencia.pistaPrincipal)
        .accessibilityIdentifier("emergencia-llamar-123")
    }
}

/// Una línea de «Otras líneas»: ficha con el teléfono, nombre y número, en una tarjeta de la web.
private struct FilaLlamada: View {
    let llamada: LlamadaAyuda

    @Environment(\.dynamicTypeSize) private var tamanoTexto

    var body: some View {
        Link(destination: llamada.url) {
            HStack(spacing: 12) {
                if !tamanoTexto.isAccessibilitySize {
                    Image(systemName: "phone.fill")
                        .font(.body)
                        .foregroundStyle(Paleta.brandInk)
                        .frame(width: 44, height: 44)
                        .background(Paleta.brandSoft, in: RoundedRectangle(cornerRadius: Tema.radioXL))
                        .accessibilityHidden(true)
                }
                Text(llamada.nombre)
                    .font(.jakarta(.semibold, .lg))
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .accessibilityIdentifier("emergencia-llamar-\(llamada.numero)-nombre")
                Text(llamada.numero)
                    .font(.jakarta(.bold, .lg))
                    .accessibilityIdentifier("emergencia-llamar-\(llamada.numero)-numero")
            }
            .fixedSize(horizontal: false, vertical: true)
            .tarjetaWeb()
            .frame(minHeight: Tema.objetivoMinimo)
            .contentShape(RoundedRectangle(cornerRadius: Tema.radio2XL))
        }
        .buttonStyle(EstiloApreton())
        .accessibilityLabel(TextoEmergencia.etiqueta(llamada))
        .accessibilityHint("Abre el marcador del iPhone con el \(llamada.numero). Tú confirmas la llamada.")
        .accessibilityIdentifier("emergencia-llamar-\(llamada.numero)")
    }
}
