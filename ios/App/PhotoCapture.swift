import AVFoundation
import SwiftUI
import UIKit
import VisionKit

/// Ce que la page web demande de photographier (boutons « Photographier… » du site et d’Orbiscan).
enum PhotoKind: String {
    case piece       // pièce de monnaie : appareil photo avec un cercle de cadrage
    case identite    // pièce d’identité, RIB, facture : scanner de documents d’Apple
    case rib
    case facture

    var usesDocumentScanner: Bool { self != .piece }
}

/// Prise de vue native pour les pages web de l’application. La photo repart dans la page, qui la
/// traite comme avant (Orbiscan la chiffre sur le téléphone avec la clé du PC).
@MainActor
final class PhotoCapture: NSObject {
    static let shared = PhotoCapture()
    private var done: ((Data?) -> Void)?

    func take(_ kind: PhotoKind, from host: UIViewController, done: @escaping (Data?) -> Void) {
        self.done?(nil)
        self.done = done
        let hasCamera = UIImagePickerController.isSourceTypeAvailable(.camera)
        guard hasCamera else { return presentLibrary(from: host) }   // simulateur
        Task {
            guard await Self.cameraAllowed() else { return self.refused(from: host) }
            if kind.usesDocumentScanner, VNDocumentCameraViewController.isSupported {
                let scanner = VNDocumentCameraViewController()
                scanner.delegate = self
                host.present(scanner, animated: true)
            } else if kind == .piece {
                let camera = CoinCameraController()
                camera.onDone = { [weak self, weak camera] image in
                    camera?.dismiss(animated: true)
                    self?.finish(image)
                }
                camera.modalPresentationStyle = .fullScreen
                host.present(camera, animated: true)
            } else {
                let picker = UIImagePickerController()
                picker.sourceType = .camera
                picker.delegate = self
                host.present(picker, animated: true)
            }
        }
    }

    static func cameraAllowed() async -> Bool {
        switch AVCaptureDevice.authorizationStatus(for: .video) {
        case .authorized: return true
        case .notDetermined: return await AVCaptureDevice.requestAccess(for: .video)
        default: return false
        }
    }

    private func refused(from host: UIViewController) {
        let a = UIAlertController(title: "Appareil photo refusé",
                                  message: "Autorise l’appareil photo pour Orbismini dans les réglages de l’iPhone.",
                                  preferredStyle: .alert)
        a.addAction(UIAlertAction(title: "Réglages", style: .default) { _ in
            if let url = URL(string: UIApplication.openSettingsURLString) { UIApplication.shared.open(url) }
        })
        a.addAction(UIAlertAction(title: "Annuler", style: .cancel))
        host.present(a, animated: true)
        finish(nil)
    }

    private func presentLibrary(from host: UIViewController) {
        let picker = UIImagePickerController()
        picker.sourceType = .photoLibrary
        picker.delegate = self
        host.present(picker, animated: true)
    }

    fileprivate func finish(_ image: UIImage?) {
        let data = image.flatMap { Self.jpeg($0) }
        done?(data)
        done = nil
    }

    /// JPEG d’au plus 2400 px de côté (le site réduit ensuite à sa façon).
    static func jpeg(_ image: UIImage, maxSide: CGFloat = 2400) -> Data? {
        let size = image.size
        let scale = min(1, maxSide / max(size.width, size.height))
        let target = CGSize(width: (size.width * scale).rounded(), height: (size.height * scale).rounded())
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        let resized = UIGraphicsImageRenderer(size: target, format: format).image { _ in
            image.draw(in: CGRect(origin: .zero, size: target))
        }
        return resized.jpegData(compressionQuality: 0.85)
    }
}

extension PhotoCapture: VNDocumentCameraViewControllerDelegate {
    nonisolated func documentCameraViewController(_ controller: VNDocumentCameraViewController,
                                                  didFinishWith scan: VNDocumentCameraScan) {
        let image = scan.pageCount > 0 ? scan.imageOfPage(at: 0) : nil
        Task { @MainActor in
            controller.dismiss(animated: true)
            self.finish(image)
        }
    }

    nonisolated func documentCameraViewControllerDidCancel(_ controller: VNDocumentCameraViewController) {
        Task { @MainActor in
            controller.dismiss(animated: true)
            self.finish(nil)
        }
    }

    nonisolated func documentCameraViewController(_ controller: VNDocumentCameraViewController,
                                                  didFailWithError error: Error) {
        Task { @MainActor in
            controller.dismiss(animated: true)
            self.finish(nil)
        }
    }
}

extension PhotoCapture: UIImagePickerControllerDelegate, UINavigationControllerDelegate {
    nonisolated func imagePickerController(_ picker: UIImagePickerController,
                                           didFinishPickingMediaWithInfo info: [UIImagePickerController.InfoKey: Any]) {
        let image = info[.originalImage] as? UIImage
        Task { @MainActor in
            picker.dismiss(animated: true)
            self.finish(image)
        }
    }

    nonisolated func imagePickerControllerDidCancel(_ picker: UIImagePickerController) {
        Task { @MainActor in
            picker.dismiss(animated: true)
            self.finish(nil)
        }
    }
}

/// Appareil photo pour les pièces : un cercle au centre pour bien placer la pièce ; la photo est
/// recadrée sur ce cercle (avec une petite marge), la pièce arrive donc centrée.
final class CoinCameraController: UIViewController, AVCapturePhotoCaptureDelegate {
    var onDone: ((UIImage?) -> Void)?

    private let session = AVCaptureSession()
    private let output = AVCapturePhotoOutput()
    private var preview: AVCaptureVideoPreviewLayer?
    private let shade = CAShapeLayer()
    private let ring = CAShapeLayer()
    private let hint = UILabel()
    private let shutter = UIButton(type: .custom)
    private let cancel = UIButton(type: .system)
    private var circle = CGRect.zero
    private var busy = false

    override var prefersStatusBarHidden: Bool { true }

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .black
        if let camera = AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: .back),
           let input = try? AVCaptureDeviceInput(device: camera),
           session.canAddInput(input), session.canAddOutput(output) {
            session.sessionPreset = .photo
            session.addInput(input)
            session.addOutput(output)
            let layer = AVCaptureVideoPreviewLayer(session: session)
            layer.videoGravity = .resizeAspectFill
            view.layer.addSublayer(layer)
            preview = layer
        }
        shade.fillRule = .evenOdd
        shade.fillColor = UIColor.black.withAlphaComponent(0.55).cgColor
        view.layer.addSublayer(shade)
        ring.fillColor = UIColor.clear.cgColor
        ring.strokeColor = UIColor(red: 0.91, green: 0.75, blue: 0.46, alpha: 1).cgColor
        ring.lineWidth = 3
        view.layer.addSublayer(ring)

        hint.text = "Place la pièce dans le cercle, bien à plat"
        hint.textColor = .white
        hint.font = .preferredFont(forTextStyle: .headline)
        hint.textAlignment = .center
        hint.numberOfLines = 2
        view.addSubview(hint)

        shutter.backgroundColor = .white
        shutter.layer.cornerRadius = 36
        shutter.layer.borderWidth = 5
        shutter.layer.borderColor = UIColor.white.withAlphaComponent(0.5).cgColor
        shutter.accessibilityLabel = "Prendre la photo"
        shutter.addTarget(self, action: #selector(takePhoto), for: .touchUpInside)
        view.addSubview(shutter)

        cancel.setTitle("Annuler", for: .normal)
        cancel.setTitleColor(.white, for: .normal)
        cancel.titleLabel?.font = .preferredFont(forTextStyle: .body)
        cancel.addTarget(self, action: #selector(close), for: .touchUpInside)
        view.addSubview(cancel)

        let session = self.session
        DispatchQueue.global(qos: .userInitiated).async { session.startRunning() }
    }

    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        let b = view.bounds
        preview?.frame = b
        let side = min(b.width, b.height) * 0.74
        circle = CGRect(x: (b.width - side) / 2, y: b.height * 0.44 - side / 2, width: side, height: side)
        let hole = UIBezierPath(rect: b)
        hole.append(UIBezierPath(ovalIn: circle))
        shade.path = hole.cgPath
        shade.frame = b
        ring.path = UIBezierPath(ovalIn: circle).cgPath
        ring.frame = b
        let safe = view.safeAreaInsets
        hint.frame = CGRect(x: 20, y: max(safe.top, 20) + 10, width: b.width - 40, height: 50)
        shutter.frame = CGRect(x: b.midX - 36, y: b.height - safe.bottom - 110, width: 72, height: 72)
        cancel.frame = CGRect(x: 16, y: shutter.frame.midY - 22, width: 100, height: 44)
    }

    @objc private func takePhoto() {
        guard !busy, preview != nil else { return }
        busy = true
        output.capturePhoto(with: AVCapturePhotoSettings(), delegate: self)
    }

    @objc private func close() {
        stop()
        onDone?(nil)
    }

    private func stop() {
        let session = self.session
        DispatchQueue.global(qos: .userInitiated).async { session.stopRunning() }
    }

    func photoOutput(_ output: AVCapturePhotoOutput, didFinishProcessingPhoto photo: AVCapturePhoto, error: Error?) {
        let data = photo.fileDataRepresentation()
        DispatchQueue.main.async {
            self.busy = false
            guard let data, let image = UIImage(data: data) else { return }
            self.stop()
            self.onDone?(self.crop(image))
        }
    }

    /// Recadrage sur le cercle (+ 12 % de marge), en coordonnées du capteur.
    private func crop(_ image: UIImage) -> UIImage {
        guard let preview, let cg = image.cgImage else { return image }
        let area = circle.insetBy(dx: -circle.width * 0.12, dy: -circle.height * 0.12)
        let r = preview.metadataOutputRectConverted(fromLayerRect: area)
        let w = CGFloat(cg.width), h = CGFloat(cg.height)
        let rect = CGRect(x: r.minX * w, y: r.minY * h, width: r.width * w, height: r.height * h)
            .intersection(CGRect(x: 0, y: 0, width: w, height: h))
        guard !rect.isEmpty, let cut = cg.cropping(to: rect) else { return image }
        return UIImage(cgImage: cut, scale: 1, orientation: image.imageOrientation)
    }
}
