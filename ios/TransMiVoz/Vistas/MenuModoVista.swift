import SwiftUI

/// Menú «Modo de visualización» (components/mode-menu.tsx): una hoja con los dos modos, Baja visión y Ceguera total. El
/// modo activo va marcado con el rasgo «seleccionado», una marca y su texto, no solo con el color. Elegir uno no cambia
/// nada aquí: lo hace `alElegir` (vuelve a Inicio y lo anuncia), igual que `changeMode` de la web.
struct MenuModoVista: View {
    let modo: ModoApp
    let alElegir: (ModoApp) -> Void
    let alCerrar: () -> Void

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                // «Cerrar menú» va en una fila fija del contenido y no en la barra: allí iOS 26 lo deja en 36 pt de alto y
                // su texto no escala con Dynamic Type (auditoría nativa).
                Button(action: alCerrar) {
                    Label(TextoInicio.cerrarMenuModo, systemImage: "xmark")
                }
                .buttonStyle(EstiloBotonPildora())
                .accessibilityIdentifier("boton-cerrar-menu-modo")
                .frame(maxWidth: .infinity, alignment: .trailing)
                .padding(.horizontal, 16)
                .padding(.vertical, 8)

                ScrollView {
                    VStack(spacing: 12) {
                        ForEach(ModoApp.allCases) { opcion in
                            OpcionModo(modo: opcion, activo: opcion == modo) { alElegir(opcion) }
                        }
                    }
                    .padding(16)
                }
            }
            .pantallaWeb()
            .navigationTitle(TextoInicio.tituloMenuModo)
            .navigationBarTitleDisplayMode(.inline)
        }
    }
}

/// Una tarjeta del menú: ficha con el ícono, título con marca si está activo y descripción.
private struct OpcionModo: View {
    let modo: ModoApp
    let activo: Bool
    let accion: () -> Void

    @Environment(\.dynamicTypeSize) private var tamanoTexto

    var body: some View {
        Button(action: accion) {
            HStack(alignment: .top, spacing: 16) {
                if !tamanoTexto.isAccessibilitySize {
                    Image(systemName: modo == .parcial ? "eye" : "eye.slash")
                        .font(.title3)
                        .frame(width: 48, height: 48)
                        .background(activo ? Color.clear : Paleta.brandSoft, in: RoundedRectangle(cornerRadius: Tema.radio2XL))
                        .overlay {
                            if activo {
                                RoundedRectangle(cornerRadius: Tema.radio2XL).strokeBorder(Paleta.brandForeground, lineWidth: Tema.borde)
                            }
                        }
                        .accessibilityHidden(true)
                }
                VStack(alignment: .leading, spacing: 4) {
                    HStack(spacing: 8) {
                        Text(modo.titulo).font(.jakarta(.bold, .xl2))
                        if activo {
                            Image(systemName: "checkmark").font(.headline).accessibilityHidden(true)
                        }
                    }
                    Text(modo.descripcion).font(.jakarta(.regular, .lg))
                }
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .foregroundStyle(activo ? Paleta.brandForeground : Paleta.cardForeground)
            .padding(16)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(activo ? Paleta.brand : Paleta.card, in: RoundedRectangle(cornerRadius: Tema.radio2XL))
            .overlay(RoundedRectangle(cornerRadius: Tema.radio2XL).strokeBorder(Paleta.border, lineWidth: Tema.borde))
            .contentShape(RoundedRectangle(cornerRadius: Tema.radio2XL))
        }
        .buttonStyle(EstiloApreton())
        .accessibilityAddTraits(activo ? .isSelected : [])
        .accessibilityValue(activo ? TextoInicio.modoActivo : "")
        .accessibilityIdentifier("modo-\(modo.rawValue)")
    }
}
