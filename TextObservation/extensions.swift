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

extension CGImage {
    func toCVPixelBuffer() -> CVPixelBuffer? {
        var pixelBuffer:CVPixelBuffer?
        let options = [
            kCVPixelBufferCGImageCompatibilityKey as String: true,
            kCVPixelBufferCGBitmapContextCompatibilityKey as String: true,
            kCVPixelBufferIOSurfacePropertiesKey as String: [:]
        ] as [String : Any]
        let status:CVReturn = CVPixelBufferCreate(kCFAllocatorDefault,
                                                  Int(width),
                                                  Int(height),
                                                  kCVPixelFormatType_32BGRA,
                                                  options as CFDictionary,
                                                  &pixelBuffer)
        
        let ciContext = CIContext()
        if (status == kCVReturnSuccess && pixelBuffer != nil) {
            ciContext.render(CIImage(cgImage: self), to: pixelBuffer!)
        }
        return pixelBuffer
    }
    
    func padding(to rect: CGRect) -> CGImage? {
        UIGraphicsBeginImageContextWithOptions(CGSize(width: rect.width, height: rect.height), false, 1)
        defer {
            UIGraphicsEndImageContext()
        }
        guard let context = UIGraphicsGetCurrentContext() else { return nil }
        
        context.setFillColor(red: 0, green: 0, blue: 0, alpha: 0.98)
        context.fill(CGRect(x: 0, y: 0, width: rect.width, height: rect.height))
        
        let origin: CGRect = CGRect(x: rect.minX, y: rect.minY, width: CGFloat(width), height: CGFloat(height))

        var affine = CGAffineTransform(scaleX: 1, y: -1)
        affine.ty = CGFloat(height) + origin.minY * 2.0
        context.concatenate(affine)
        context.draw(self, in: origin)

        return context.makeImage()
    }
}
