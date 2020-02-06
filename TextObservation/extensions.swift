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
    func padding(to rect: CGRect, red: CGFloat = 0, green: CGFloat = 0, blue: CGFloat = 0, alpha: CGFloat = 0) -> CGImage? {
        UIGraphicsBeginImageContext(CGSize(width: rect.width, height: rect.height))
        defer {
            UIGraphicsEndImageContext()
        }
        guard let context = UIGraphicsGetCurrentContext() else { return nil }
        
        if 0 < alpha {
            context.setFillColor(red: red, green: green, blue: blue, alpha: alpha)
            context.fill(CGRect(x: 0, y: 0, width: rect.width, height: rect.height))
        }
        
        let origin: CGRect = CGRect(x: rect.minX, y: rect.minY, width: CGFloat(width), height: CGFloat(height))
        context.drawBitmap(self, in: origin)
        return context.makeImage()
    }
    
    func digging(to rect: CGRect, red: CGFloat = 0, green: CGFloat = 0, blue: CGFloat = 0, alpha: CGFloat = 0) -> CGImage? {
        guard
            let cropped = cropping(to: rect),
            let padded = cropped.padding(to: CGRect(x: rect.minX, y: rect.minY, width: CGFloat(width), height: CGFloat(height)), red: red, green: green, blue: blue, alpha: alpha)
            else { return nil }
        return padded
    }

}

extension CGContext {
    func drawBitmap(_ image: CGImage, in rect: CGRect, byTiling: Bool = false) {
        var affine = CGAffineTransform(scaleX: 1, y: -1)
        affine.ty = CGFloat(image.height) + rect.minY * 2.0
        concatenate(affine)
        draw(image, in: rect, byTiling: byTiling)
    }
}
