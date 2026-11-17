import SwiftUI

extension ShapeStyle where Self == Color {
    /// Texto secundario: `muted-foreground` de la web (negro en claro, neón en oscuro), opaco. Antes era `label` al 70 %:
    /// sobre las tarjetas lima se mezclaba con el relleno y la auditoría de contraste lo medía mal.
    static var textoSecundario: Color { Paleta.mutedForeground }

    /// Rojo para acciones destructivas con contraste ≥ 7:1. El rojo del sistema
    /// (#FF383C) da ~3,6:1 sobre blanco y la auditoría lo marca "casi aprobado".
    static var rojoAccesible: Color {
        Color(uiColor: UIColor { rasgos in
            rasgos.userInterfaceStyle == .dark
                ? UIColor(red: 1, green: 0.42, blue: 0.38, alpha: 1)
                : UIColor(red: 0.70, green: 0, blue: 0.09, alpha: 1)
        })
    }

    /// Texto y borde de una acción no disponible, con contraste ≥ 4,5:1 sobre `fondoAccionInhabilitada`.
    /// El aspecto atenuado del sistema (~1,6:1) hace fallar la auditoría de contraste.
    static var textoAccionInhabilitada: Color {
        Color(uiColor: UIColor { rasgos in
            let alto = rasgos.accessibilityContrast == .high
            return rasgos.userInterfaceStyle == .dark
                ? UIColor(white: alto ? 0.92 : 0.78, alpha: 1)
                : UIColor(white: alto ? 0.12 : 0.28, alpha: 1)
        })
    }

    /// Fondo opaco de una acción no disponible (opaco para poder medir su contraste).
    static var fondoAccionInhabilitada: Color { Color(uiColor: .secondarySystemBackground) }
}

extension View {
    /// El margen exterior evita que ScrollView extienda su marco bajo la barra de pestañas.
    func bordeInferiorLegible() -> some View { padding(.bottom) }

    /// En iOS 26 el área desplazable desvanece y difumina bajo la barra de navegación lo que pasa por debajo (efecto de borde
    /// «suave»). Con el estilo «duro» el corte es nítido y lineal: lo que queda bajo la barra se mide con su aspecto real.
    /// Hipótesis de renderizado que valida la auditoría nativa de contraste. Con iOS 17–25 no existe ese efecto.
    @ViewBuilder func bordeSuperiorNitido() -> some View {
        if #available(iOS 26.0, *) {
            scrollEdgeEffectStyle(.hard, for: .top)
        } else {
            self
        }
    }

    /// Botón principal o secundario de la web, bloqueado si la acción no está disponible. Estilo y bloqueo salen del mismo
    /// valor para que no se desacoplen; el aspecto de «no disponible» (borde discontinuo, contraste ≥ 4,5:1) lo pone el estilo.
    /// Los estilos del sistema (`.borderedProminent`, `.bordered`) dependen del color de acento y no pasan la auditoría.
    /// `compacta`: 48 pt de alto mínimo en vez de 56 (pantallas con muchos controles seguidos).
    @ViewBuilder func accion(prominente: Bool, disponible: Bool, compacta: Bool = false) -> some View {
        if prominente {
            buttonStyle(EstiloBotonPrimario(compacto: compacta)).disabled(!disponible)
        } else {
            buttonStyle(EstiloBotonSecundario(compacto: compacta)).disabled(!disponible)
        }
    }
}
