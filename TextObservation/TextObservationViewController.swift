import UIKit
import AVFoundation
import Vision

class TextObservationViewController: UIViewController {

    @IBOutlet weak var previewImageView: UIImageView!

    private let avCaptureSession = AVCaptureSession()
    
    /// 認識制度を設定。 リアルタイム処理なので fastで
    private let recognitionLevel : VNRequestTextRecognitionLevel = .accurate
    
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
        avCaptureSession.sessionPreset = .photo

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

    /// コンテキストに矩形を描画
    private func drawRect(_ rect: CGRect, text: String, context: CGContext) {

        context.setLineWidth(4.0)
        context.setStrokeColor(UIColor.green.cgColor)
        context.stroke(rect)
        context.setFillColor(UIColor.black.withAlphaComponent(0.6).cgColor)
        context.fill(rect)
        
        drawText(text, rect: rect, context: context)
 
    }

    /// コンテキストにテキストを描画　 (そのまま描画すると文字が反転するので、反転させる必要あり）
    private func drawText(_ text: String, rect: CGRect, context: CGContext) {
        
        context.saveGState()
        defer {
            context.restoreGState()
        }

        let transform = CGAffineTransform(scaleX: 1, y: 1)
        context.concatenate(transform)
        
        guard let textStyle = NSMutableParagraphStyle.default.mutableCopy() as? NSMutableParagraphStyle else {
            return
        }
        let font = UIFont.boldSystemFont(ofSize: 20)
        let textFontAttributes = [
            NSAttributedString.Key.font: font,
            NSAttributedString.Key.foregroundColor: UIColor.white,
            NSAttributedString.Key.paragraphStyle: textStyle
        ]
        
        let astr = NSAttributedString(string: text, attributes: textFontAttributes)
        let setter = CTFramesetterCreateWithAttributedString(astr)
        let path = CGPath(rect: rect, transform: nil)
        let frame = CTFramesetterCreateFrame(setter, CFRange(), path, nil)

        context.textMatrix = CGAffineTransform.identity
        CTFrameDraw(frame, context)

    }
    
    /// 文字認識情報の配列取得 (非同期)
    private func getTextObservations(pixelBuffer: CVPixelBuffer, completion: @escaping (([VNRecognizedTextObservation])->())) {
        let request = VNRecognizeTextRequest { (request, error) in
            guard let results = request.results as? [VNRecognizedTextObservation] else {
                completion([])
                return
            }
            completion(results)
        }

        request.recognitionLevel = recognitionLevel
        request.recognitionLanguages = supportedRecognitionLanguages
        request.usesLanguageCorrection = true

        let handler = VNImageRequestHandler(cvPixelBuffer: pixelBuffer, options: [:])
        try? handler.perform([request])
    }

    /// 正規化された矩形位置を指定領域に展開
    private func getUnfoldRect(normalizedRect: CGRect, targetSize: CGSize) -> CGRect {
        return CGRect(
            x: normalizedRect.minX * targetSize.width,
            y: normalizedRect.minY * targetSize.height,
            width: normalizedRect.width * targetSize.width,
            height: normalizedRect.height * targetSize.height
        )
    }

    /// 文字検出位置に矩形を描画した image を取得
    private func getTextRectsImage(sampleBuffer :CMSampleBuffer, textObservations: [VNRecognizedTextObservation]) -> UIImage? {

        guard let imageBuffer = CMSampleBufferGetImageBuffer(sampleBuffer) else {
            return nil
        }

        CVPixelBufferLockBaseAddress(imageBuffer, CVPixelBufferLockFlags(rawValue: 0))

        guard let pixelBufferBaseAddres = CVPixelBufferGetBaseAddressOfPlane(imageBuffer, 0) else {
            CVPixelBufferUnlockBaseAddress(imageBuffer, CVPixelBufferLockFlags(rawValue: 0))
            return nil
        }

        let width = CVPixelBufferGetWidth(imageBuffer)
        let height = CVPixelBufferGetHeight(imageBuffer)
        let bitmapInfo = CGBitmapInfo(rawValue:
            (CGBitmapInfo.byteOrder32Little.rawValue | CGImageAlphaInfo.premultipliedFirst.rawValue)
        )

        guard let newContext = CGContext(
            data: pixelBufferBaseAddres,
            width: width,
            height: height,
            bitsPerComponent: 8,
            bytesPerRow: CVPixelBufferGetBytesPerRow(imageBuffer),
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: bitmapInfo.rawValue
            ) else
        {
            CVPixelBufferUnlockBaseAddress(imageBuffer, CVPixelBufferLockFlags(rawValue: 0))
            return nil
        }

        let imageSize = CGSize(width: width, height: height)

        textObservations.forEach{
            let rect = getUnfoldRect(normalizedRect: $0.boundingBox, targetSize: imageSize)
            let text = $0.topCandidates(1).first?.string ?? "" // topCandidates に文字列候補配列が含まれている
            self.drawRect(rect, text: text, context: newContext)
        }

        CVPixelBufferUnlockBaseAddress(imageBuffer, CVPixelBufferLockFlags(rawValue: 0))

        guard let imageRef = newContext.makeImage() else {
            return nil
        }
        let image = UIImage(cgImage: imageRef, scale: 1.0, orientation: UIImage.Orientation.right)

        return image
    }
}


extension TextObservationViewController : AVCaptureVideoDataOutputSampleBufferDelegate{

    /// カメラからの映像取得デリゲート
    func captureOutput(_ output: AVCaptureOutput, didOutput sampleBuffer: CMSampleBuffer, from connection: AVCaptureConnection) {
        guard let pixelBuffer = CMSampleBufferGetImageBuffer(sampleBuffer) else {
            return
        }
        getTextObservations(pixelBuffer: pixelBuffer) { [weak self] textObservations in
            guard let self = self else { return }
            let image = self.getTextRectsImage(sampleBuffer: sampleBuffer, textObservations: textObservations)
            DispatchQueue.main.async { [weak self] in
                self?.previewImageView.image = image
            }
        }
    }
}
