import UIKit
import AVFoundation
import Vision

class TextObservationViewController: UIViewController {
    // 読み取り範囲の定義
    private var readAreaX: CGFloat = 0
    private let readAreaY: CGFloat = 540
    private let readAreaWidth: CGFloat = 1080
    private let readAreaHeight: CGFloat = 135
    private let imageSizeWidth: CGFloat = 1080
    private let imageSizeHeight: CGFloat = 1920
    
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
        readAreaX = imageSizeWidth / 2 - readAreaWidth / 2
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

    /// コンテキストに矩形を描画
    private func drawRect(_ rect: CGRect, context: CGContext, index: Int) {
        if index == 0 {
            context.setStrokeColor(UIColor.red.cgColor)
            context.setLineWidth(4.0)
            context.stroke(rect)
        }
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
        request.usesLanguageCorrection = false

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
    private func getTextRectsImage(imageBuffer :CVImageBuffer, textObservations: [VNRecognizedTextObservation]) -> UIImage? {

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

        for (index, el) in textObservations.enumerated() {
            let rect = getUnfoldRect(normalizedRect: el.boundingBox, targetSize: imageSize)
            self.drawRect(rect, context: newContext, index: index)
        }

        CVPixelBufferUnlockBaseAddress(imageBuffer, CVPixelBufferLockFlags(rawValue: 0))

        guard let imageRef = newContext.makeImage() else {
            return nil
        }
        let image = UIImage(cgImage: imageRef)

        return image
    }
}


extension TextObservationViewController : AVCaptureVideoDataOutputSampleBufferDelegate{

    /// カメラからの映像取得デリゲート
    func captureOutput(_ output: AVCaptureOutput, didOutput sampleBuffer: CMSampleBuffer, from connection: AVCaptureConnection) {
        guard let pixelBuffer = CMSampleBufferGetImageBuffer(sampleBuffer) else { return }
        
        connection.videoOrientation = .portrait
        let ciImage: CIImage = CIImage(cvPixelBuffer: pixelBuffer)
        let uiImage = UIImage(ciImage: ciImage)
        
        guard let croppedImage = uiImage.cropped(to: CGRect(x: readAreaX, y: readAreaY, width: readAreaWidth, height: readAreaHeight)) else { return }
        guard let croppedBuffer = croppedImage.safeCiImage?.toCVPixelBuffer() else { return }
        
        let filter = CIFilter(name: "CIColorClamp")
        filter?.setValue(ciImage, forKey: "inputImage")
        filter?.setValue(CIVector(x: 1, y: 1, z: 1, w: 0.2), forKey: "inputMaxComponents")
        filter?.setValue(CIVector(x: 0, y: 0, z: 0, w: 0), forKey: "inputMinComponents")
        
        guard let imageRef = CIContext(options: nil).createCGImage((filter?.outputImage)!, from: (filter?.outputImage!.extent)!) else { return }
        let bgImage = UIImage(cgImage: imageRef)
        
        getTextObservations(pixelBuffer: croppedBuffer) { [weak self] textObservations in
            guard let self = self else { return }
            guard let fgImage = self.getTextRectsImage(imageBuffer: croppedBuffer, textObservations: textObservations) else { return }
            let compImage = bgImage.composite(image: fgImage, x: self.readAreaX, y: self.readAreaY)
            DispatchQueue.main.async { [weak self] in
                self?.previewImageView.image = compImage
                self?.showText(textObservations.first?.topCandidates(1).first?.string)
            }
        }
    }
}


