import AVFoundation
import SwiftUI
import UIKit

/// Ce que la page web demande de photographier avec l’appareil photo de l’application.
enum PhotoKind: String {
    case piece       // pièce de monnaie : cercle de cadrage
    case identite    // pièce d’identité : cadre de carte, recto puis verso
}

/// Photos prises, dans l’ordre. `end` : « passeport » (une seule page, pas de verso),
/// « annule » (arrêt avant le verso) ou rien.
struct PhotoResult {
    var photos: [Data] = []
    var end = ""
}

/// Prise de vue native pour les pages web de l’application (Orbiscan, pièce inconnue). Les photos
/// repartent dans la page, qui les traite comme avant : le détourage reste fait par l’extension,
/// sur le PC. RIB et facture gardent l’appareil photo normal de l’iPhone.
@MainActor
final class PhotoCapture: NSObject {
    static let shared = PhotoCapture()
    /// Mesures de la dernière pièce d’identité photographiée (affichées dans Réglages, pour régler les seuils).
    static let lastQualityKey = "photoDerniereQualite"
    private var done: ((PhotoResult) -> Void)?

    func take(_ kind: PhotoKind, bothSides: Bool, from host: UIViewController, done: @escaping (PhotoResult) -> Void) {
        self.done?(PhotoResult())
        self.done = done
        guard UIImagePickerController.isSourceTypeAvailable(.camera) else { return presentLibrary(from: host) }   // simulateur
        Task {
            guard await Self.cameraAllowed() else { return self.refused(from: host) }
            let camera = FramedCameraController(mode: kind == .piece ? .coin : .card(bothSides: bothSides))
            camera.onDone = { [weak self, weak camera] images, end in
                camera?.dismiss(animated: true)
                self?.finish(images, end: end)
            }
            camera.modalPresentationStyle = .fullScreen
            host.present(camera, animated: true)
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
        finish([], end: "")
    }

    private func presentLibrary(from host: UIViewController) {
        let picker = UIImagePickerController()
        picker.sourceType = .photoLibrary
        picker.delegate = self
        host.present(picker, animated: true)
    }

    fileprivate func finish(_ images: [UIImage], end: String) {
        done?(PhotoResult(photos: images.compactMap { Self.jpeg($0) }, end: end))
        done = nil
    }

    /// JPEG d’au plus 3000 px de côté (la limite de la page du relais, qui réduit ensuite à sa façon).
    static func jpeg(_ image: UIImage, maxSide: CGFloat = 3000) -> Data? {
        let size = image.size
        let scale = min(1, maxSide / max(size.width, size.height))
        let target = CGSize(width: (size.width * scale).rounded(), height: (size.height * scale).rounded())
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        let resized = UIGraphicsImageRenderer(size: target, format: format).image { _ in
            image.draw(in: CGRect(origin: .zero, size: target))
        }
        return resized.jpegData(compressionQuality: 0.9)
    }
}

extension PhotoCapture: UIImagePickerControllerDelegate, UINavigationControllerDelegate {
    nonisolated func imagePickerController(_ picker: UIImagePickerController,
                                           didFinishPickingMediaWithInfo info: [UIImagePickerController.InfoKey: Any]) {
        let image = info[.originalImage] as? UIImage
        Task { @MainActor in
            picker.dismiss(animated: true)
            self.finish(image.map { [$0] } ?? [], end: "")
        }
    }

    nonisolated func imagePickerControllerDidCancel(_ picker: UIImagePickerController) {
        Task { @MainActor in
            picker.dismiss(animated: true)
            self.finish([], end: "")
        }
    }
}

/// Netteté et reflets d’une photo de carte, mesurés sur l’intérieur du cadre.
struct PhotoQuality {
    /// Variance du laplacien sur l’image ramenée à 1200 px : petite = floue.
    let sharpness: Double
    /// Part des points « brûlés » (blancs saturés), en pour cent : grande = reflet.
    let glare: Double

    static let minSharpness = 50.0
    static let maxGlare = 4.0

    var blurry: Bool { sharpness < Self.minSharpness }
    var shiny: Bool { glare > Self.maxGlare }
    var summary: String {
        "netteté " + String(Int(sharpness.rounded())) + ", reflet " + String(format: "%.1f", glare).replacingOccurrences(of: ".", with: ",") + " %"
    }

    static func measure(_ image: CGImage) -> PhotoQuality? {
        let w = min(1200, image.width)
        let h = Int((Double(image.height) / Double(image.width) * Double(w)).rounded())
        guard w > 8, h > 8 else { return nil }
        var px = [UInt8](repeating: 0, count: w * h)
        let drawn = px.withUnsafeMutableBytes { buffer -> Bool in
            guard let ctx = CGContext(data: buffer.baseAddress, width: w, height: h, bitsPerComponent: 8, bytesPerRow: w,
                                      space: CGColorSpaceCreateDeviceGray(), bitmapInfo: CGImageAlphaInfo.none.rawValue)
            else { return false }
            ctx.interpolationQuality = .medium
            ctx.draw(image, in: CGRect(x: 0, y: 0, width: w, height: h))
            return true
        }
        guard drawn else { return nil }
        var sum = 0.0, squares = 0.0, burnt = 0
        var n = 0
        for y in 1..<(h - 1) {
            let row = y * w
            for x in 1..<(w - 1) {
                let i = row + x
                let c = Int(px[i])
                let lap = Double(Int(px[i - 1]) + Int(px[i + 1]) + Int(px[i - w]) + Int(px[i + w]) - 4 * c)
                sum += lap
                squares += lap * lap
                if c >= 250 { burnt += 1 }
                n += 1
            }
        }
        guard n > 0 else { return nil }
        let mean = sum / Double(n)
        return PhotoQuality(sharpness: squares / Double(n) - mean * mean, glare: Double(burnt) / Double(n) * 100)
    }
}

/// Appareil photo à cadre : un cercle pour une pièce de monnaie, un cadre de carte « debout » pour
/// une pièce d’identité (recto puis verso sans quitter l’écran). La photo est recadrée sur le cadre
/// avec une marge : le sujet arrive centré, et l’extension garde de quoi détourer.
final class FramedCameraController: UIViewController, AVCapturePhotoCaptureDelegate {
    enum Mode: Equatable {
        case coin
        case card(bothSides: Bool)
    }

    /// Photos prises et fin (« passeport », « annule » ou rien).
    var onDone: (([UIImage], String) -> Void)?

    private let mode: Mode
    private let session = AVCaptureSession()
    private let output = AVCapturePhotoOutput()
    private var preview: AVCaptureVideoPreviewLayer?
    private var device: AVCaptureDevice?
    private let shade = CAShapeLayer()
    private let ring = CAShapeLayer()
    private let titleLabel = UILabel()
    private let hint = UILabel()
    private let shutter = UIButton(type: .custom)
    private let cancel = UIButton(type: .system)
    private let single = UIButton(type: .system)
    private var frame = CGRect.zero
    private var busy = false
    private var aimed = false
    private var areaChanged: NSObjectProtocol?
    private var taken: [UIImage] = []
    private var notes: [String] = []

    private static let gold = UIColor(red: 0.91, green: 0.75, blue: 0.46, alpha: 1)

    init(mode: Mode) {
        self.mode = mode
        super.init(nibName: nil, bundle: nil)
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) non utilisé") }

    deinit {
        if let areaChanged { NotificationCenter.default.removeObserver(areaChanged) }
    }

    override var prefersStatusBarHidden: Bool { true }
    override var supportedInterfaceOrientations: UIInterfaceOrientationMask { .portrait }

    private var isCard: Bool { mode != .coin }
    private var wantsVerso: Bool { mode == .card(bothSides: true) }
    private var atVerso: Bool { wantsVerso && taken.count == 1 }

    // MARK: - Écran

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .black
        if let camera = Self.camera(),
           let input = try? AVCaptureDeviceInput(device: camera),
           session.canAddInput(input), session.canAddOutput(output) {
            session.sessionPreset = .photo
            session.addInput(input)
            session.addOutput(output)
            // Photo prise à l’instant du toucher quand l’iPhone le permet (pas de délai de déclenchement).
            output.maxPhotoQualityPrioritization = .balanced
            if output.isZeroShutterLagSupported { output.isZeroShutterLagEnabled = true }
            if output.isResponsiveCaptureSupported { output.isResponsiveCaptureEnabled = true }
            let layer = AVCaptureVideoPreviewLayer(session: session)
            layer.videoGravity = .resizeAspectFill
            view.layer.addSublayer(layer)
            preview = layer
            device = camera
            prepare(camera)
        }
        shade.fillRule = .evenOdd
        shade.fillColor = UIColor.black.withAlphaComponent(0.55).cgColor
        view.layer.addSublayer(shade)
        ring.fillColor = UIColor.clear.cgColor
        ring.strokeColor = Self.gold.cgColor
        ring.lineWidth = 3
        view.layer.addSublayer(ring)

        titleLabel.textColor = Self.gold
        titleLabel.font = .systemFont(ofSize: 24, weight: .bold)
        titleLabel.textAlignment = .center
        titleLabel.adjustsFontSizeToFitWidth = true
        view.addSubview(titleLabel)

        hint.textColor = .white
        hint.font = .preferredFont(forTextStyle: .subheadline)
        hint.textAlignment = .center
        hint.numberOfLines = 3
        hint.adjustsFontSizeToFitWidth = true
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

        single.setTitle("Passeport :\nune seule page", for: .normal)
        single.setTitleColor(Self.gold, for: .normal)
        single.titleLabel?.font = .preferredFont(forTextStyle: .footnote)
        single.titleLabel?.numberOfLines = 2
        single.titleLabel?.textAlignment = .center
        single.addTarget(self, action: #selector(onePage), for: .touchUpInside)
        single.isHidden = true
        view.addSubview(single)

        view.addGestureRecognizer(UITapGestureRecognizer(target: self, action: #selector(tapped(_:))))
        showTexts()

        let session = self.session
        DispatchQueue.global(qos: .userInitiated).async { session.startRunning() }
    }

    private func showTexts() {
        switch mode {
        case .coin:
            titleLabel.text = ""
            hint.text = "Place la pièce dans le cercle, bien à plat.\nTouche l’écran pour refaire la mise au point."
        case .card:
            titleLabel.text = atVerso ? "↻ Retourne la carte : verso" : (wantsVerso ? "Recto" : "Pièce d’identité")
            hint.text = "Carte debout dans le cadre, à plat, sans reflet.\nTouche l’écran pour refaire la mise au point."
        }
        single.isHidden = !atVerso
    }

    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        let b = view.bounds
        preview?.frame = b
        let path: UIBezierPath
        if isCard {
            // Carte debout (54 × 85,6 mm), comme le guide de la page du relais.
            let h = min(b.height * 0.56, b.width * 0.78 * 1.585)
            let w = h / 1.585
            frame = CGRect(x: (b.width - w) / 2, y: b.height * 0.46 - h / 2, width: w, height: h)
            path = UIBezierPath(roundedRect: frame, cornerRadius: w * 0.06)
        } else {
            let side = min(b.width, b.height) * 0.74
            frame = CGRect(x: (b.width - side) / 2, y: b.height * 0.44 - side / 2, width: side, height: side)
            path = UIBezierPath(ovalIn: frame)
        }
        let hole = UIBezierPath(rect: b)
        hole.append(path)
        shade.path = hole.cgPath
        shade.frame = b
        ring.path = path.cgPath
        ring.frame = b
        let safe = view.safeAreaInsets
        let top = max(safe.top, 20) + 6
        titleLabel.frame = CGRect(x: 16, y: top, width: b.width - 32, height: isCard ? 30 : 0)
        hint.frame = CGRect(x: 16, y: titleLabel.frame.maxY + 2, width: b.width - 32, height: 56)
        shutter.frame = CGRect(x: b.midX - 36, y: b.height - safe.bottom - 100, width: 72, height: 72)
        cancel.frame = CGRect(x: 12, y: shutter.frame.midY - 22, width: 96, height: 44)
        single.frame = CGRect(x: b.width - 138, y: shutter.frame.midY - 26, width: 130, height: 52)
        if !aimed, preview != nil, !frame.isEmpty {
            aimed = true
            focus(at: CGPoint(x: frame.midX, y: frame.midY))
        }
    }

    // MARK: - Mise au point

    /// Appareil « virtuel » (plusieurs objectifs) quand l’iPhone en a un : il choisit tout seul
    /// l’objectif (macro de près pour une pièce de monnaie). Sinon l’objectif principal.
    private static func camera() -> AVCaptureDevice? {
        for type in [AVCaptureDevice.DeviceType.builtInTripleCamera, .builtInDualWideCamera, .builtInDualCamera,
                     .builtInWideAngleCamera] {
            if let d = AVCaptureDevice.default(type, for: .video, position: .back) { return d }
        }
        return nil
    }

    private func prepare(_ d: AVCaptureDevice) {
        guard (try? d.lockForConfiguration()) != nil else { return }
        // « 1× » = l’objectif principal (sur un appareil à plusieurs objectifs, le zoom 1 est l’ultra grand-angle
        // quand il y en a un). Pas de zoom 2× pour les pièces d’identité : plus difficile à cadrer (essai de Sylvian).
        var one: CGFloat = 1
        if d.deviceType == .builtInTripleCamera || d.deviceType == .builtInDualWideCamera,
           let wide = d.virtualDeviceSwitchOverVideoZoomFactors.first?.doubleValue {
            one = CGFloat(wide)
        }
        d.videoZoomFactor = min(max(one, d.minAvailableVideoZoomFactor), d.maxAvailableVideoZoomFactor)
        if !isCard, d.isAutoFocusRangeRestrictionSupported { d.autoFocusRangeRestriction = .near }
        if d.isSmoothAutoFocusSupported { d.isSmoothAutoFocusEnabled = false }
        if d.isFocusModeSupported(.continuousAutoFocus) { d.focusMode = .continuousAutoFocus }
        if d.isExposureModeSupported(.continuousAutoExposure) { d.exposureMode = .continuousAutoExposure }
        d.isSubjectAreaChangeMonitoringEnabled = true
        d.unlockForConfiguration()
        // Le sujet a bougé : nouvelle mise au point sur le cadre.
        areaChanged = NotificationCenter.default.addObserver(forName: AVCaptureDevice.subjectAreaDidChangeNotification,
                                                             object: d, queue: .main) { [weak self] _ in
            Task { @MainActor in
                guard let self else { return }
                self.focus(at: CGPoint(x: self.frame.midX, y: self.frame.midY))
            }
        }
    }

    @objc private func tapped(_ g: UITapGestureRecognizer) {
        let p = g.location(in: view)
        guard !shutter.frame.contains(p), !cancel.frame.contains(p), single.isHidden || !single.frame.contains(p) else { return }
        focus(at: p)
        let mark = CAShapeLayer()
        mark.path = UIBezierPath(ovalIn: CGRect(x: p.x - 30, y: p.y - 30, width: 60, height: 60)).cgPath
        mark.fillColor = UIColor.clear.cgColor
        mark.strokeColor = UIColor.white.cgColor
        mark.lineWidth = 2
        view.layer.addSublayer(mark)
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.7) { mark.removeFromSuperlayer() }
    }

    private func focus(at layerPoint: CGPoint) {
        guard let d = device, let preview, (try? d.lockForConfiguration()) != nil else { return }
        let point = preview.captureDevicePointConverted(fromLayerPoint: layerPoint)
        if d.isFocusPointOfInterestSupported { d.focusPointOfInterest = point }
        if d.isFocusModeSupported(.continuousAutoFocus) { d.focusMode = .continuousAutoFocus }
        if d.isExposurePointOfInterestSupported { d.exposurePointOfInterest = point }
        if d.isExposureModeSupported(.continuousAutoExposure) { d.exposureMode = .continuousAutoExposure }
        d.unlockForConfiguration()
    }

    // MARK: - Prise de vue

    @objc private func takePhoto() {
        guard !busy, preview != nil else { return }
        busy = true
        shutter.alpha = 0.5
        capture(waited: 0)
    }

    /// Attend la fin de la mise au point si elle est en cours (0,5 s au plus), puis prend la photo.
    private func capture(waited: Double) {
        if let d = device, d.isAdjustingFocus, waited < 0.5 {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) { self.capture(waited: waited + 0.05) }
            return
        }
        let settings = AVCapturePhotoSettings()
        settings.photoQualityPrioritization = .balanced
        output.capturePhoto(with: settings, delegate: self)
    }

    @objc private func close() {
        stop()
        onDone?(taken, taken.isEmpty ? "" : "annule")
    }

    @objc private func onePage() {
        stop()
        onDone?(taken, "passeport")
    }

    private func stop() {
        let session = self.session
        DispatchQueue.global(qos: .userInitiated).async { session.stopRunning() }
    }

    /// Éclair blanc à l’instant exact de la prise : on sait quand on peut bouger.
    func photoOutput(_ output: AVCapturePhotoOutput, willCapturePhotoFor resolvedSettings: AVCaptureResolvedPhotoSettings) {
        DispatchQueue.main.async {
            let flash = UIView(frame: self.view.bounds)
            flash.backgroundColor = .white
            flash.alpha = 0.7
            flash.isUserInteractionEnabled = false
            self.view.addSubview(flash)
            UIView.animate(withDuration: 0.25, animations: { flash.alpha = 0 }, completion: { _ in flash.removeFromSuperview() })
        }
    }

    func photoOutput(_ output: AVCapturePhotoOutput, didFinishProcessingPhoto photo: AVCapturePhoto, error: Error?) {
        let data = photo.fileDataRepresentation()
        DispatchQueue.main.async {
            self.busy = false
            self.shutter.alpha = 1
            guard let data, let image = UIImage(data: data) else { return }
            self.review(image)
        }
    }

    /// Pièce d’identité : photo floue ou reflet → on le dit avant d’envoyer (reprendre ou garder).
    private func review(_ image: UIImage) {
        let kept = cropped(image, margin: 0.12) ?? image
        guard isCard, let inside = cut(image, margin: -0.04), let q = PhotoQuality.measure(inside) else { return accept(kept) }
        notes.append((atVerso ? "Verso : " : "Recto : ") + q.summary)
        UserDefaults.standard.set(notes.suffix(2).joined(separator: " · "), forKey: PhotoCapture.lastQualityKey)
        guard q.blurry || q.shiny else { return accept(kept) }
        var why: [String] = []
        if q.blurry { why.append("La photo semble floue.") }
        if q.shiny { why.append("Il y a peut-être un reflet sur la carte.") }
        let a = UIAlertController(title: "Photo à vérifier", message: why.joined(separator: "\n") + "\n(" + q.summary + ")",
                                  preferredStyle: .alert)
        a.addAction(UIAlertAction(title: "Garder quand même", style: .default) { [weak self] _ in self?.accept(kept) })
        let again = UIAlertAction(title: "Reprendre", style: .cancel) { [weak self] _ in
            guard let self else { return }
            self.notes.removeLast()
            self.focus(at: CGPoint(x: self.frame.midX, y: self.frame.midY))
        }
        a.addAction(again)
        a.preferredAction = again
        present(a, animated: true)
    }

    private func accept(_ image: UIImage) {
        taken.append(image)
        UINotificationFeedbackGenerator().notificationOccurred(.success)
        if atVerso {
            // Recto pris : on reste sur l’écran pour le verso.
            showTexts()
            ring.strokeColor = UIColor.systemGreen.cgColor
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) { self.ring.strokeColor = Self.gold.cgColor }
            return
        }
        stop()
        onDone?(taken, "")
    }

    // MARK: - Recadrage

    /// Partie de la photo sous le cadre, élargie (marge positive) ou resserrée (négative), en points du capteur.
    private func cut(_ image: UIImage, margin: CGFloat) -> CGImage? {
        guard let preview, let cg = image.cgImage else { return nil }
        let area = frame.insetBy(dx: -frame.width * margin, dy: -frame.height * margin)
        let r = preview.metadataOutputRectConverted(fromLayerRect: area)
        let w = CGFloat(cg.width), h = CGFloat(cg.height)
        let rect = CGRect(x: r.minX * w, y: r.minY * h, width: r.width * w, height: r.height * h)
            .intersection(CGRect(x: 0, y: 0, width: w, height: h))
        guard !rect.isEmpty else { return nil }
        return cg.cropping(to: rect)
    }

    private func cropped(_ image: UIImage, margin: CGFloat) -> UIImage? {
        cut(image, margin: margin).map { UIImage(cgImage: $0, scale: 1, orientation: image.imageOrientation) }
    }
}
