//
//  Image+Extensions.swift
//  zsignapp
//
//  Created by Sato on 26/10/25.
//
import SwiftUI

extension Image {
    /// Style cho app icon
    func appIconStyle(
        size: CGFloat = 56,
        lineWidth: CGFloat = 1,
        cornerRadius: CGFloat? = nil
    ) -> some View {
        let radius = cornerRadius ?? (size * 0.2237) // iOS app icon radius
        
        return self
            .resizable()
            .scaledToFit()
            .frame(width: size, height: size)
            .background(Theme.cardAlt)
            .clipShape(RoundedRectangle(cornerRadius: radius, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: radius, style: .continuous)
                    .strokeBorder(Theme.hairline, lineWidth: lineWidth)
            )
    }
}
