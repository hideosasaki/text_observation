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
        x: readAreaX,
        y: readAreaY,
        width: readAreaWidth,
        height: readAreaHeight
    )
    
    @IBOutlet weak var previewImageView: UIImageView!
    
    @IBOutlet weak var accurateTextLabel: UILabel!
    
    @IBOutlet weak var detectedImageView: UIImageView!
    
    private let fastTextLabel = UILabel()
    
    private let avCaptureSession = AVCaptureSession()
    
    private var detectedImage: CGImage?
    
    private var fastText: String?
    
    private var isCaptureing: Bool = false
    
    @IBAction func captureButtonTouchDown(_ sender: UIButton) {
        guard let image = detectedImage else { return }
        isCaptureing = true
        accurateTextLabel.text = "...Captureing..."
        DispatchQueue.global(qos: .userInitiated).async {
            self.read(image, recognitionLevel: .accurate) { [weak self] textObservations in
                DispatchQueue.main.sync {
                    self?.accurateTextLabel.text = textObservations.first?.topCandidates(1).first?.string
                }
                self?.isCaptureing = false
            }
        }
    }
    
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

        guard let device = AVCaptureDevice.default(for: .video) else {
            // unable to use the default camera
            return
        }
        if let input = try? AVCaptureDeviceInput(device: device) {
            avCaptureSession.addInput(input)

            let videoDataOutput = AVCaptureVideoDataOutput()
            videoDataOutput.videoSettings = [kCVPixelBufferPixelFormatTypeKey as String : Int(kCVPixelFormatType_32BGRA)]
            videoDataOutput.alwaysDiscardsLateVideoFrames = true
            videoDataOutput.setSampleBufferDelegate(self, queue: .global(qos: .userInteractive))

            avCaptureSession.addOutput(videoDataOutput)
            avCaptureSession.startRunning()
        } else {
            // DeviceInput is unavailable
        }
    }
    
    /// テキストビューの定義
    private func showFastText() {
        // テキストメッセージを配置
        fastTextLabel.numberOfLines = 4
        fastTextLabel.font = UIFont.systemFont(ofSize: 17, weight: .bold)
        fastTextLabel.frame = CGRect(x: 0, y: 395, width: 320, height: 100)
        fastTextLabel.textColor = UIColor.white
        fastTextLabel.lineBreakMode = .byCharWrapping
        fastTextLabel.text = fastText
        // 上辺揃えになるよう調整
        var rect = fastTextLabel.frame
        fastTextLabel.sizeToFit()
        rect.size.height = fastTextLabel.frame.height
        fastTextLabel.frame = rect
        view.addSubview(fastTextLabel)
    }

    /// 文字認識情報の配列取得 (非同期)
    private func read(_ image: CGImage, recognitionLevel: VNRequestTextRecognitionLevel = .fast, completion: @escaping ([VNRecognizedTextObservation]) -> ()) {
        let request = VNRecognizeTextRequest { (request, error) in
            guard let results = request.results as? [VNRecognizedTextObservation] else {
                completion([])
                return
            }
            completion(results)
        }

        request.recognitionLevel = recognitionLevel
        request.recognitionLanguages = ["en_US"]
        request.usesLanguageCorrection = false

        let handler = VNImageRequestHandler(cgImage: image, options: [:])
        try? handler.perform([request])
    }

    /// 文字検出位置に矩形を描画した image を取得
    private func detect(_ image: CGImage, textObservations: [VNRecognizedTextObservation]) -> CGImage? {
        let imageSize = CGSize(width: image.width, height: image.height)
        
        UIGraphicsBeginImageContext(imageSize)
        defer {
            UIGraphicsEndImageContext()
        }
        guard let context = UIGraphicsGetCurrentContext() else { return nil }
        context.draw(image, in: CGRect(origin: .zero, size: imageSize))
        
        let drawMarker = {(_ t: VNRecognizedTextObservation) in
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
            
            let rectReversed = CGRect(
                x: rect.minX,
                y: imageSize.height - rect.minY - rect.height,
                width: rect.width,
                height: rect.height
            )
            
            if let cropped = image.cropping(to: rectReversed) {
                self.detectedImage = cropped
                DispatchQueue.main.sync {
                    self.detectedImageView.image = UIImage(cgImage: cropped)
                }
            }
        }
        
        let t = textObservations.filter { fastText == $0.topCandidates(1).first?.string }.first
        if let t = t {
            drawMarker(t)
        } else if let t = textObservations.first {
            fastText = t.topCandidates(1).first?.string
            drawMarker(t)
        } else {
            fastText = ""
        }
        return context.makeImage()
    }
}

extension TextObservationViewController : AVCaptureVideoDataOutputSampleBufferDelegate {
    /// カメラからの映像取得デリゲート
    func captureOutput(_ output: AVCaptureOutput, didOutput sampleBuffer: CMSampleBuffer, from connection: AVCaptureConnection) {
        if isCaptureing { return }
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
                let markerImage = self?.detect(readAreaImage, textObservations: textObservations),
                let paddedImage = markerImage.padding(origin: readArea.origin, size: backImage.extent.size, alpha: 0.92)
                else { return }
            let foreImage = CIImage(cgImage: paddedImage)
            let compositedImage = foreImage.composited(over: backImage)
            DispatchQueue.main.sync {
                self?.previewImageView.image = UIImage(ciImage: compositedImage)
                self?.showFastText()
            }
        }
    }
}
