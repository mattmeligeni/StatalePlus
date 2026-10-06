import SwiftUI
import UIKit

/// Chiusura della tastiera uguale in tutta l'app:
/// - tocco in un punto qualsiasi fuori dai campi di testo;
/// - trascinamento verso il basso del contenuto (la tastiera segue il dito) o swipe verso il basso;
/// - pulsante "Chiudi" a destra sopra la tastiera (`tastieraConChiudi()`), utile soprattutto nei campi su più righe
///   dove Invio va a capo.
/// I tasti della tastiera stanno in un processo di sistema: lì le app non possono ricevere gesti.
enum Tastiera {
    static func chiudi() {
        UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil)
    }
}

extension View {
    /// Da applicare una volta alla radice: installa i gesti sulla finestra (valgono anche per fogli e schermate a
    /// tutto schermo, che stanno nella stessa finestra) e il trascinamento interattivo nelle liste.
    func gestiTastiera() -> some View {
        scrollDismissesKeyboard(.interactively)
            .background(InstallatoreGestiTastiera().frame(width: 0, height: 0))
    }

    /// Pulsante "Chiudi" a destra sopra la tastiera. Va messo sul contenitore (Form, List, schermata),
    /// non sui singoli campi: ogni dichiarazione aggiunge un pulsante.
    func tastieraConChiudi() -> some View {
        modifier(BarraTastiera())
    }
}

/// La barra della tastiera di SwiftUI (`placement: .keyboard`) su iOS 26 centra i pulsanti anche con lo spazio
/// flessibile, oppure allarga il vetro oltre il pulsante. Qui il pulsante è dell'app: una capsula di vetro chiaro
/// grande quanto la scritta "Chiudi", allineata a destra nello spazio sopra la tastiera (`safeAreaInset`: con la tastiera
/// aperta il fondo dell'area sicura coincide con il bordo della tastiera, e il contenuto non finisce sotto il pulsante).
private struct BarraTastiera: ViewModifier {
    @State private var aperta = false

    func body(content: Content) -> some View {
        content
            .safeAreaInset(edge: .bottom, alignment: .trailing, spacing: 0) {
                if aperta {
                    PulsanteChiudi()
                        .padding(.trailing, 16)
                        .padding(.vertical, 8)
                        .transition(.scale(scale: 0.6).combined(with: .opacity))
                }
            }
            .onReceive(NotificationCenter.default.publisher(for: UIResponder.keyboardWillShowNotification)) { _ in
                withAnimation(.snappy(duration: 0.25)) { aperta = true }
            }
            .onReceive(NotificationCenter.default.publisher(for: UIResponder.keyboardWillHideNotification)) { _ in
                withAnimation(.snappy(duration: 0.2)) { aperta = false }
            }
    }
}

private struct PulsanteChiudi: View {
    var body: some View {
        let pulsante = Button(action: Tastiera.chiudi) {
            Text("Chiudi")
                .font(.body.weight(.semibold))
                .padding(.horizontal, 4)
                .frame(minHeight: 30)
        }
        .buttonBorderShape(.capsule)
        .accessibilityHint("Chiude la tastiera")
        pulsante.buttonStyle(.glass)
    }
}

/// Vista vuota che, entrata nella finestra, aggiunge i riconoscitori di gesti (una sola volta per finestra).
private struct InstallatoreGestiTastiera: UIViewRepresentable {
    func makeUIView(context: Context) -> VistaInstallatore { VistaInstallatore() }
    func updateUIView(_ uiView: VistaInstallatore, context: Context) {}

    final class VistaInstallatore: UIView {
        override func didMoveToWindow() {
            super.didMoveToWindow()
            guard let window, !(window.gestureRecognizers ?? []).contains(where: { $0.delegate === GestiTastiera.shared })
            else { return }
            GestiTastiera.shared.installa(in: window)
        }
    }
}

/// Tocco e swipe verso il basso sulla finestra: non interferiscono con pulsanti, liste e gesti delle viste
/// (`cancelsTouchesInView = false` e riconoscimento simultaneo) e ignorano i tocchi dentro i campi di testo, così
/// il cursore si sposta normalmente.
private final class GestiTastiera: NSObject, UIGestureRecognizerDelegate {
    static let shared = GestiTastiera()

    func installa(in window: UIWindow) {
        let tocco = UITapGestureRecognizer(target: self, action: #selector(chiudi))
        tocco.cancelsTouchesInView = false
        tocco.delegate = self
        window.addGestureRecognizer(tocco)

        let swipe = UISwipeGestureRecognizer(target: self, action: #selector(chiudi))
        swipe.direction = .down
        swipe.cancelsTouchesInView = false
        swipe.delegate = self
        window.addGestureRecognizer(swipe)
    }

    @objc private func chiudi(_ g: UIGestureRecognizer) {
        g.view?.endEditing(true)
    }

    func gestureRecognizer(_ g: UIGestureRecognizer, shouldReceive touch: UITouch) -> Bool {
        // Nei campi di testo il tocco sposta il cursore; nell'editor di testo lo swipe scorre il testo
        // (lì la tastiera si chiude trascinando il testo verso la tastiera o con "Chiudi").
        var v = touch.view
        while let corrente = v {
            if corrente is UITextField || corrente is UITextView || corrente is UISearchBar { return false }
            v = corrente.superview
        }
        return true
    }

    func gestureRecognizer(_ g: UIGestureRecognizer,
                           shouldRecognizeSimultaneouslyWith other: UIGestureRecognizer) -> Bool { true }
}

/// Campo per codici (es. il codice lezione): niente correttore, controllo ortografico, suggerimenti nella barra
/// della tastiera, previsioni in linea né virgolette "intelligenti". Con SwiftUI `autocorrectionDisabled()` toglie solo
/// la correzione: da iOS 26 la barra dei suggerimenti resta e propone parole al posto del codice.
struct CampoCodice: UIViewRepresentable {
    let segnaposto: String
    @Binding var testo: String
    var invio: UIReturnKeyType = .done
    var onInvio: () -> Void = {}

    func makeUIView(context: Context) -> UITextField {
        let campo = UITextField()
        campo.placeholder = segnaposto
        campo.font = .preferredFont(forTextStyle: .body)
        campo.adjustsFontForContentSizeCategory = true
        campo.autocapitalizationType = .allCharacters
        campo.autocorrectionType = .no
        campo.spellCheckingType = .no
        campo.smartQuotesType = .no
        campo.smartDashesType = .no
        campo.smartInsertDeleteType = .no
        campo.inlinePredictionType = .no
        campo.keyboardType = .asciiCapable
        campo.textContentType = .oneTimeCode
        campo.returnKeyType = invio
        campo.clearButtonMode = .whileEditing
        campo.delegate = context.coordinator
        campo.addTarget(context.coordinator, action: #selector(Coordinatore.cambiato(_:)), for: .editingChanged)
        campo.setContentHuggingPriority(.defaultLow, for: .horizontal)
        campo.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        return campo
    }

    func updateUIView(_ campo: UITextField, context: Context) {
        context.coordinator.genitore = self
        if campo.text != testo { campo.text = testo }
    }

    func makeCoordinator() -> Coordinatore { Coordinatore(self) }

    final class Coordinatore: NSObject, UITextFieldDelegate {
        var genitore: CampoCodice
        init(_ genitore: CampoCodice) { self.genitore = genitore }

        @objc func cambiato(_ campo: UITextField) { genitore.testo = campo.text ?? "" }

        func textFieldShouldReturn(_ campo: UITextField) -> Bool {
            campo.resignFirstResponder()
            genitore.onInvio()
            return false
        }
    }
}
