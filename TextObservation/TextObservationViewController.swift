import UIKit
import AVFoundation
import Vision

class TextObservationViewController: UIViewController {
    // 読み取り範囲の定義
    static let imageSizeWidth: CGFloat = 1080
    static let readAreaWidth: CGFloat = 1080
    static let readAreaHeight: CGFloat = 120
    static let readAreaX: CGFloat = imageSizeWidth / 2 - readAreaWidth / 2
    static let readAreaY: CGFloat = 540
    static let readArea = CGRect(
        x: TextObservationViewController.readAreaX,
        y: TextObservationViewController.readAreaY,
        width: TextObservationViewController.readAreaWidth,
        height: TextObservationViewController.readAreaHeight
    )
    
    @IBOutlet weak var previewImageView: UIImageView!

    private let textLabel = UILabel()
    
    private let avCaptureSession = AVCaptureSession()
    
    override func viewDidLoad() {
        super.viewDidLoad()
        setupCamera()
    }

    override func viewDidDisappear(_ animated: Bool) {
        super.viewDidDisappear(animated)
        avCaptureSession.stopRunning()
    }

    /// カメラのセットアップ
    private func setupCamera() {
        avCaptureSession.sessionPreset = .hd1920x1080

        let device = AVCaptureDevice.default(for: .video)
        let input = try! AVCaptureDeviceInput(device: device!)
        avCaptureSession.addInput(input)

        let videoDataOutput = AVCaptureVideoDataOutput()
        videoDataOutput.videoSettings = [kCVPixelBufferPixelFormatTypeKey as String : Int(kCVPixelFormatType_32BGRA)]
        videoDataOutput.alwaysDiscardsLateVideoFrames = true
        videoDataOutput.setSampleBufferDelegate(self, queue: .global())

        avCaptureSession.addOutput(videoDataOutput)
        avCaptureSession.startRunning()
    }
    
    /// テキストビューの定義
    private func showText(_ mes: String?) {
        // テキストメッセージを配置
        textLabel.numberOfLines = 4
        textLabel.font = UIFont.systemFont(ofSize: 17, weight: .bold)
        textLabel.frame = CGRect(x: 0, y: 395, width: 320, height: 100)
        textLabel.textColor = UIColor.white
        textLabel.text = mes
        // 上辺揃えになるよう調整
        var rect = textLabel.frame
        textLabel.sizeToFit()
        rect.size.height = textLabel.frame.height
        textLabel.frame = rect
        view.addSubview(textLabel)
    }

    /// 文字認識情報の配列取得 (非同期)
    private func read(_ cgImage: CGImage, completion: @escaping (([VNRecognizedTextObservation])->())) {
        let request = VNRecognizeTextRequest { (request, error) in
            guard let results = request.results as? [VNRecognizedTextObservation] else {
                completion([])
                return
            }
            completion(results)
        }

        request.recognitionLevel = .fast
        request.recognitionLanguages = ["en_US"]
        request.usesLanguageCorrection = false

        let handler = VNImageRequestHandler(cgImage: cgImage, options: [:])
        try? handler.perform([request])
    }

    /// 文字検出位置に矩形を描画した image を取得
    private func addMarker(to cgImage: CGImage, textObservations: [VNRecognizedTextObservation]) -> CGImage? {
        let imageSize = CGSize(width: cgImage.width, height: cgImage.height)
        
        UIGraphicsBeginImageContext(imageSize)
        defer {
            UIGraphicsEndImageContext()
        }
        guard let context = UIGraphicsGetCurrentContext() else { return nil }
        context.draw(cgImage, in: CGRect(origin: .zero, size: imageSize))
        if 0 < textObservations.count {
            let t = textObservations[0]
            // 正規化された矩形位置を指定領域に展開
            let rect = CGRect(
                x: t.boundingBox.minX * imageSize.width,
                y: t.boundingBox.minY * imageSize.height,
                width: t.boundingBox.width * imageSize.width,
                height: t.boundingBox.height * imageSize.height
            )
            context.setStrokeColor(UIColor.red.cgColor)
            context.setLineWidth(4.0)
            context.stroke(rect)
        }
        
        return context.makeImage()
    }
}

extension TextObservationViewController : AVCaptureVideoDataOutputSampleBufferDelegate {

    /// カメラからの映像取得デリゲート
    func captureOutput(_ output: AVCaptureOutput, didOutput sampleBuffer: CMSampleBuffer, from connection: AVCaptureConnection) {
        connection.videoOrientation = .portrait
        
        guard let pixelBuffer = CMSampleBufferGetImageBuffer(sampleBuffer) else { return }
        let backImage = CIImage(cvPixelBuffer: pixelBuffer)
        let readArea = type(of: self).readArea
        let ciContext = CIContext()
        guard
            let cgBackImage = ciContext.createCGImage(backImage, from: backImage.extent),
            let readAreaImage = cgBackImage.cropping(to: readArea)
            else { return }
        
        read(readAreaImage) { [weak self] textObservations in
            guard
                let markerImage = self?.addMarker(to: readAreaImage, textObservations: textObservations),
                let paddedImage = markerImage.padding(origin: readArea.origin, size: backImage.extent.size, alpha: 0.92)
                else { return }
            let foreImage = CIImage(cgImage: paddedImage)
            let compositedImage = foreImage.composited(over: backImage)
            
            DispatchQueue.main.async { [weak self] in
                self?.previewImageView.image = UIImage(ciImage: compositedImage)
                self?.showText(textObservations.first?.topCandidates(1).first?.string)
            }
        }
    }
}


