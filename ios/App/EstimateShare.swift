import MessageUI
import UIKit
import UniformTypeIdentifiers
import WebKit

/// « Envoyer au client » (Rachat → Imprimer, print.js) : la Proposition de rachat d’Orbis, en PDF
/// fabriqué par le serveur (proposition.py) ; à défaut, la fiche imprimable du site faite en PDF ici.
/// Puis SMS ou e-mail adressé au client (numéro et adresse saisis dans la fenêtre d’impression),
/// ou le partage habituel de l’iPhone.
@MainActor
final class EstimateShare: NSObject {
    static let shared = EstimateShare()

    private static let body = "Bonjour,\n\nVoici votre proposition de rachat. Les cours de l’or évoluant, elle est valable 2 heures.\n\nÀ bientôt."

    func send(from web: WKWebView, client: String, phone: String, email: String, serverPDF: Data? = nil) {
        guard let host = WebPageTop.of(web) else { return }
        let pdf = serverPDF ?? Self.pdf(from: web)
        let name = Self.fileName(client: client)
        var choices: [(String, () -> Void)] = []
        if !phone.isEmpty, MFMessageComposeViewController.canSendText(), MFMessageComposeViewController.canSendAttachments() {
            choices.append(("SMS à " + phone, { self.sms(pdf, name, to: phone, from: host) }))
        }
        if !email.isEmpty, MFMailComposeViewController.canSendMail() {
            choices.append(("E-mail à " + email, { self.mail(pdf, name, to: email, from: host) }))
        }
        choices.append(("Autre (Messages, WhatsApp, AirDrop…)", { self.other(pdf, name, from: host) }))
        if choices.count == 1 { return choices[0].1() }
        let sheet = UIAlertController(title: "Envoyer l’estimation", message: client.isEmpty ? nil : client, preferredStyle: .actionSheet)
        for (title, action) in choices {
            sheet.addAction(UIAlertAction(title: title, style: .default) { _ in action() })
        }
        sheet.addAction(UIAlertAction(title: "Annuler", style: .cancel))
        // Pas d’ancrage : sur iPhone, iOS en ferait une petite bulle en haut de la page (vu par Sylvian).
        host.present(sheet, animated: true)
    }

    // MARK: - PDF

    /// Fiche telle qu’à l’impression (règles @media print de print.css) : A4, marges de 15 mm.
    static func pdf(from web: WKWebView) -> Data {
        let renderer = UIPrintPageRenderer()
        renderer.addPrintFormatter(web.viewPrintFormatter(), startingAtPageAt: 0)
        let paper = CGRect(x: 0, y: 0, width: 595.2, height: 841.8)
        let margin: CGFloat = 42.5
        renderer.setValue(NSValue(cgRect: paper), forKey: "paperRect")
        renderer.setValue(NSValue(cgRect: paper.insetBy(dx: margin, dy: margin)), forKey: "printableRect")
        let data = NSMutableData()
        UIGraphicsBeginPDFContextToData(data, paper, nil)
        renderer.prepare(forDrawingPages: NSRange(location: 0, length: renderer.numberOfPages))
        for page in 0..<renderer.numberOfPages {
            UIGraphicsBeginPDFPage()
            renderer.drawPage(at: page, in: UIGraphicsGetPDFContextBounds())
        }
        UIGraphicsEndPDFContext()
        return data as Data
    }

    static func fileName(client: String, now: Date = Date()) -> String {
        let f = DateFormatter()
        f.locale = Fmt.fr
        f.timeZone = Fmt.paris
        f.dateFormat = "dd-MM-yyyy HH'h'mm"
        let who = client.components(separatedBy: CharacterSet(charactersIn: "/\\:?*\"<>|")).joined()
        return "Proposition de rachat" + (who.isEmpty ? "" : " " + who) + " " + f.string(from: now) + ".pdf"
    }

    // MARK: - Envois

    private func sms(_ pdf: Data, _ name: String, to phone: String, from host: UIViewController) {
        let c = MFMessageComposeViewController()
        c.recipients = [phone]
        c.body = Self.body
        c.addAttachmentData(pdf, typeIdentifier: UTType.pdf.identifier, filename: name)
        c.messageComposeDelegate = self
        host.present(c, animated: true)
    }

    private func mail(_ pdf: Data, _ name: String, to email: String, from host: UIViewController) {
        let c = MFMailComposeViewController()
        c.setToRecipients([email])
        c.setSubject("Votre proposition de rachat")
        c.setMessageBody(Self.body, isHTML: false)
        c.addAttachmentData(pdf, mimeType: "application/pdf", fileName: name)
        c.mailComposeDelegate = self
        host.present(c, animated: true)
    }

    private func other(_ pdf: Data, _ name: String, from host: UIViewController) {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(name)
        try? pdf.write(to: url, options: .atomic)
        let share = UIActivityViewController(activityItems: [url], applicationActivities: nil)
        host.present(share, animated: true)
    }
}

extension EstimateShare: MFMessageComposeViewControllerDelegate, MFMailComposeViewControllerDelegate {
    nonisolated func messageComposeViewController(_ controller: MFMessageComposeViewController,
                                                  didFinishWith result: MessageComposeResult) {
        Task { @MainActor in controller.dismiss(animated: true) }
    }

    nonisolated func mailComposeController(_ controller: MFMailComposeViewController,
                                           didFinishWith result: MFMailComposeResult, error: Error?) {
        Task { @MainActor in controller.dismiss(animated: true) }
    }
}

/// Écran du dessus pour présenter une fenêtre depuis une page web.
enum WebPageTop {
    @MainActor
    static func of(_ web: WKWebView) -> UIViewController? {
        guard var top = web.window?.rootViewController else { return nil }
        while let next = top.presentedViewController { top = next }
        return top
    }
}
