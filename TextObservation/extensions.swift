//
//  extentions.swift
//  TextObservation
//
//  Created by sasaki on 2020/02/04.
//  Copyright © 2020 test. All rights reserved.
//

import Foundation
import CoreImage
import UIKit

extension UIImage {
    var safeCiImage: CIImage? {
        return self.ciImage ?? CIImage(image: self)
    }

    var safeCgImage: CGImage? {
        if let cgImge = self.cgImage {
            return cgImge
        }
        if let ciImage = safeCiImage {
            let context = CIContext(options: nil)
            return context.createCGImage(ciImage, from: ciImage.extent)
        }
        return nil
    }

    /// Create UIImage by cropping current image with the specified rectangle.
    ///
    /// - parameter rect: The rectangle to crop
    ///
    /// - returns: The cropped image. Nil on error.
    func cropped(to rect: CGRect) -> UIImage? {
        guard let unwrappedCGImage = safeCgImage else {
            return nil
        }
        guard let imgRef = unwrappedCGImage.cropping(to: rect) else {
            return nil
        }
        return UIImage(cgImage: imgRef, scale: scale, orientation: imageOrientation)
    }
    
    func composite(image: UIImage, x: CGFloat, y: CGFloat) -> UIImage? {

        UIGraphicsBeginImageContextWithOptions(self.size, false, 0)
        self.draw(in: CGRect(x: 0, y: 0, width: self.size.width, height: self.size.height))

        let rect = CGRect(x: x,
                          y: y,
                          width: image.size.width,
                          height: image.size.height)
        image.draw(in: rect)

        let image = UIGraphicsGetImageFromCurrentImageContext()
        UIGraphicsEndImageContext()

        return image
    }
}

extension CIImage {
    func toCVPixelBuffer() -> CVPixelBuffer? {
        let size:CGSize = extent.size
        var pixelBuffer:CVPixelBuffer?
        let options = [
            kCVPixelBufferCGImageCompatibilityKey as String: true,
            kCVPixelBufferCGBitmapContextCompatibilityKey as String: true,
            kCVPixelBufferIOSurfacePropertiesKey as String: [:]
        ] as [String : Any]
        let status:CVReturn = CVPixelBufferCreate(kCFAllocatorDefault,
                                                  Int(size.width),
                                                  Int(size.height),
                                                  kCVPixelFormatType_32BGRA,
                                                  options as CFDictionary,
                                                  &pixelBuffer)
        let ciContext = CIContext()
        if (status == kCVReturnSuccess && pixelBuffer != nil) {
            ciContext.render(self, to: pixelBuffer!)
        }
        return pixelBuffer
    }
}
