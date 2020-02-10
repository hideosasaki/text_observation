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
    func padding(origin: CGPoint, size: CGSize, red: CGFloat = 0, green: CGFloat = 0, blue: CGFloat = 0, alpha: CGFloat = 0) -> CGImage? {
        UIGraphicsBeginImageContext(size)
        defer {
            UIGraphicsEndImageContext()
        }
        guard let context = UIGraphicsGetCurrentContext() else { return nil }
        
        if 0 < alpha {
            context.setFillColor(red: red, green: green, blue: blue, alpha: alpha)
            context.fill(CGRect(origin: .zero, size: size))
        }
        
        let place = CGRect(x: origin.x, y: origin.y, width: CGFloat(width), height: CGFloat(height))
        context.draw(self, in: place)
        return context.makeImage()
    }
}
