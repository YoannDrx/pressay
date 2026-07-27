import AppKit
import SwiftUI

@main
struct PressayAXFixtureApp: App {
    var body: some Scene {
        WindowGroup("Pressay AX Fixture", id: "fixture") {
            FixtureView()
                .frame(minWidth: 760, minHeight: 620)
        }
        .defaultSize(width: 820, height: 680)
    }
}

private struct FixtureView: View {
    @State private var swiftUIText = "Texte SwiftUI — sélection initiale"
    @State private var swiftUIArea =
        "Première ligne SwiftUI.\nDeuxième ligne à transformer."
    @State private var swiftUISecureText = "secret-swiftui"
    @State private var showsSwiftUITextField = true
    @State private var appKitGeneration = 0

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 22) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Pressay — fixture d’accessibilité")
                        .font(.title2.bold())
                    Text(
                        "Contrôles reproductibles pour lecture, remplacement, "
                        + "changement de sélection, destruction de cible et champs protégés."
                    )
                    .foregroundStyle(.secondary)
                }

                GroupBox("AppKit") {
                    AppKitFixture(generation: appKitGeneration)
                        .id(appKitGeneration)
                        .frame(minHeight: 250)
                }

                GroupBox("SwiftUI") {
                    VStack(alignment: .leading, spacing: 12) {
                        if showsSwiftUITextField {
                            TextField("SwiftUI.TextField", text: $swiftUIText)
                                .accessibilityIdentifier(
                                    "fixture.swiftui.textfield"
                                )
                        } else {
                            Text("Le TextField SwiftUI a été détruit.")
                                .foregroundStyle(.secondary)
                        }

                        TextEditor(text: $swiftUIArea)
                            .font(.body)
                            .frame(minHeight: 90)
                            .border(.separator)
                            .accessibilityIdentifier(
                                "fixture.swiftui.texteditor"
                            )

                        SecureField(
                            "SwiftUI.SecureField",
                            text: $swiftUISecureText
                        )
                        .accessibilityIdentifier("fixture.swiftui.securefield")

                        HStack {
                            Button("Modifier le texte SwiftUI") {
                                swiftUIText =
                                    "La sélection SwiftUI a changé."
                            }
                            .accessibilityIdentifier("fixture.swiftui.change")

                            Button(
                                showsSwiftUITextField
                                    ? "Détruire le TextField SwiftUI"
                                    : "Recréer le TextField SwiftUI"
                            ) {
                                showsSwiftUITextField.toggle()
                            }
                            .accessibilityIdentifier("fixture.swiftui.destroy")

                            Button("Recréer les contrôles AppKit") {
                                appKitGeneration += 1
                            }
                            .accessibilityIdentifier("fixture.appkit.recreate")
                        }
                    }
                    .padding(10)
                }
            }
            .padding(24)
        }
    }
}

private struct AppKitFixture: NSViewRepresentable {
    let generation: Int

    func makeNSView(context: Context) -> NSView {
        context.coordinator.makeView()
    }

    func updateNSView(_ nsView: NSView, context: Context) {}

    func makeCoordinator() -> Coordinator {
        Coordinator()
    }

    final class Coordinator: NSObject {
        private weak var textField: NSTextField?
        private weak var textView: NSTextView?

        func makeView() -> NSView {
            let stack = NSStackView()
            stack.orientation = .vertical
            stack.alignment = .leading
            stack.spacing = 10

            let field = NSTextField(
                string: "Texte AppKit — sélection initiale"
            )
            field.placeholderString = "NSTextField"
            field.setAccessibilityIdentifier("fixture.appkit.textfield")
            field.widthAnchor
                .constraint(greaterThanOrEqualToConstant: 620)
                .isActive = true
            textField = field
            stack.addArrangedSubview(field)

            let scrollView = NSScrollView()
            scrollView.hasVerticalScroller = true
            scrollView.borderType = .bezelBorder
            scrollView.widthAnchor
                .constraint(greaterThanOrEqualToConstant: 620)
                .isActive = true
            scrollView.heightAnchor
                .constraint(equalToConstant: 90)
                .isActive = true
            let area = NSTextView()
            area.string =
                "Première ligne AppKit.\nDeuxième ligne à transformer."
            area.isRichText = false
            area.setAccessibilityIdentifier("fixture.appkit.textview")
            scrollView.documentView = area
            textView = area
            stack.addArrangedSubview(scrollView)

            let secureField = NSSecureTextField(
                string: "secret-appkit"
            )
            secureField.placeholderString = "NSSecureTextField"
            secureField.setAccessibilityIdentifier(
                "fixture.appkit.securefield"
            )
            secureField.widthAnchor
                .constraint(greaterThanOrEqualToConstant: 620)
                .isActive = true
            stack.addArrangedSubview(secureField)

            let buttons = NSStackView()
            buttons.orientation = .horizontal
            buttons.spacing = 8
            buttons.addArrangedSubview(
                makeButton(
                    "Sélectionner « AppKit »",
                    identifier: "fixture.appkit.select",
                    action: #selector(selectKnownRange)
                )
            )
            buttons.addArrangedSubview(
                makeButton(
                    "Modifier la sélection",
                    identifier: "fixture.appkit.change",
                    action: #selector(changeSelection)
                )
            )
            buttons.addArrangedSubview(
                makeButton(
                    "Détruire le NSTextField",
                    identifier: "fixture.appkit.destroy",
                    action: #selector(destroyTextField)
                )
            )
            stack.addArrangedSubview(buttons)
            return stack
        }

        private func makeButton(
            _ title: String,
            identifier: String,
            action: Selector
        ) -> NSButton {
            let button = NSButton(
                title: title,
                target: self,
                action: action
            )
            button.setAccessibilityIdentifier(identifier)
            return button
        }

        @objc private func selectKnownRange() {
            guard let textField, let window = textField.window else {
                return
            }
            window.makeFirstResponder(textField)
            textField.currentEditor()?.selectedRange = NSRange(
                location: 6,
                length: 6
            )
        }

        @objc private func changeSelection() {
            guard let textField, let window = textField.window else {
                return
            }
            textField.stringValue =
                "La cible AppKit a changé pendant le traitement."
            window.makeFirstResponder(textField)
            textField.currentEditor()?.selectedRange = NSRange(
                location: 3,
                length: 5
            )
        }

        @objc private func destroyTextField() {
            guard let textField else { return }
            if textField.window?.firstResponder
                === textField.currentEditor() {
                textField.window?.makeFirstResponder(textView)
            }
            textField.removeFromSuperview()
            self.textField = nil
        }
    }
}
