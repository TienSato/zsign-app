//
//  LiquidGlass.swift
//  zsignapp


import SwiftUI

extension View {
    @ViewBuilder
    func adaptiveGlass(
        cornerRadius: CGFloat = 16,
        tint: Color? = nil
    ) -> some View {
        let shape = RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
        #if compiler(>=6.2)
        if #available(iOS 26.0, *) {
            if let tint = tint {
                self.glassEffect(.regular.tint(tint), in: shape)
            } else {
                self.glassEffect(.regular, in: shape)
            }
        } else {
            self.background(shape.fill(.ultraThinMaterial))
        }
        #else
        self.background(shape.fill(.ultraThinMaterial))
        #endif
    }

    var isLiquidGlassOS: Bool {
        if #available(iOS 26.0, *) { return true }
        return false
    }
}
