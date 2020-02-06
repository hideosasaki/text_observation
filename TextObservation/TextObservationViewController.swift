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
    
    @IBOutlet weak var previewImageView: UIImageView!

    private let textLabel = UILabel()
    
    private let avCaptureSession = AVCaptureSession()
    
    /// 認識精度を設定。 リアルタイム処理なので fastで
    private let recognitionLevel : VNRequestTextRecognitionLevel = .fast
    
    /// サポートしている言語リストを取得 （現在は英語のみ）
    private lazy var supportedRecognitionLanguages : [String] = {
        return (try? VNRecognizeTextRequest.supportedRecognitionLanguages(
        for: recognitionLevel,
        revision: VNRecognizeTextRequestRevision1)) ?? []
    }()
    
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
    private func getTextObservations(cgImage: CGImage, completion: @escaping (([VNRecognizedTextObservation])->())) {
        let request = VNRecognizeTextRequest { (request, error) in
            guard let results = request.results as? [VNRecognizedTextObservation] else {
                completion([])
                return
            }
            completion(results)
        }

        request.recognitionLevel = recognitionLevel
        request.recognitionLanguages = supportedRecognitionLanguages
        request.usesLanguageCorrection = false

        let handler = VNImageRequestHandler(cgImage: cgImage, options: [:])
        try? handler.perform([request])
    }

    /// 文字検出位置に矩形を描画した image を取得
    private func createTextRects(cgImage: CGImage, textObservations: [VNRecognizedTextObservation]) -> CIImage? {
        let imageSize = CGSize(width: cgImage.width, height: cgImage.height)
        
        UIGraphicsBeginImageContext(imageSize)
        defer {
            UIGraphicsEndImageContext()
        }
        guard let context = UIGraphicsGetCurrentContext() else { return nil }
        
        var affine = CGAffineTransform(scaleX: 1, y: -1)
        affine.ty = CGFloat(cgImage.height)
        context.concatenate(affine)
        context.draw(cgImage, in: CGRect(x: 0, y: 0, width: cgImage.width, height: cgImage.height))

        for (index, el) in textObservations.enumerated() where index == 0 {
            // 正規化された矩形位置を指定領域に展開
            let rect = CGRect(
                x: el.boundingBox.minX * imageSize.width,
                y: el.boundingBox.minY * imageSize.height,
                width: el.boundingBox.width * imageSize.width,
                height: el.boundingBox.height * imageSize.height
            )
            context.setStrokeColor(UIColor.red.cgColor)
            context.setLineWidth(4.0)
            context.stroke(rect)
        }
        
        guard let imageRef = context.makeImage() else { return nil }
        return CIImage(cgImage: imageRef)
    }
}

extension TextObservationViewController : AVCaptureVideoDataOutputSampleBufferDelegate{

    /// カメラからの映像取得デリゲート
    func captureOutput(_ output: AVCaptureOutput, didOutput sampleBuffer: CMSampleBuffer, from connection: AVCaptureConnection) {
        guard let pixelBuffer = CMSampleBufferGetImageBuffer(sampleBuffer) else { return }
        connection.videoOrientation = .portrait
        let backImage = CIImage(cvPixelBuffer: pixelBuffer)
        let x = TextObservationViewController.readAreaX
        let y = TextObservationViewController.readAreaY
        let w = TextObservationViewController.readAreaWidth
        let h = TextObservationViewController.readAreaHeight
        
        let ciContext = CIContext()
        guard
            let cgImage = ciContext.createCGImage(backImage, from: backImage.extent),
            let dugImage = cgImage.digging(to: CGRect(x: x, y: y, width: w, height: h), red: 0, green: 0, blue: 0, alpha: 0.92)
            else { return }
        
        getTextObservations(cgImage: dugImage) { [weak self] textObservations in
            guard
                let self = self,
                let foreImage = self.createTextRects(cgImage: dugImage, textObservations: textObservations)
                else { return }
            
            let compositedImage = foreImage.composited(over: backImage)
            
            DispatchQueue.main.async { [weak self] in
                self?.previewImageView.image = UIImage(ciImage: compositedImage)
                self?.showText(textObservations.first?.topCandidates(1).first?.string)
            }
        }
    }
}


