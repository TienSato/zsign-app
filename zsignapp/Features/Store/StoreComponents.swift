//
//  StoreComponents.swift
//  zsignapp
//
//  Component dùng chung cho Store (tách ra khi bỏ Zsign Store).
//

import SwiftUI
import UIKit

// MARK: - Color Extractor
class ColorExtractor {
    static func extractColors(from url: URL?) async -> (dominant: Color, secondary: Color) {
        guard let url = url else {
            return (Color(red: 1.0, green: 0.4, blue: 0.7), Color(red: 1.0, green: 0.5, blue: 0.3))
        }
        
        do {
            let (data, _) = try await URLSession.shared.data(from: url)
            guard let uiImage = UIImage(data: data) else {
                return (Color(red: 1.0, green: 0.4, blue: 0.7), Color(red: 1.0, green: 0.5, blue: 0.3))
            }
            
            let colors = await extractDominantColors(from: uiImage)
            return colors
        } catch {
            return (Color(red: 1.0, green: 0.4, blue: 0.7), Color(red: 1.0, green: 0.5, blue: 0.3))
        }
    }
    
    private static func extractDominantColors(from image: UIImage) async -> (dominant: Color, secondary: Color) {
        guard let cgImage = image.cgImage else {
            return (Color(red: 1.0, green: 0.4, blue: 0.7), Color(red: 1.0, green: 0.5, blue: 0.3))
        }
        
        let width = cgImage.width
        let height = cgImage.height
        let bytesPerPixel = 4
        let bytesPerRow = bytesPerPixel * width
        let bitsPerComponent = 8
        
        var pixelData = [UInt8](repeating: 0, count: width * height * bytesPerPixel)
        
        let colorSpace = CGColorSpaceCreateDeviceRGB()
        let context = CGContext(
            data: &pixelData,
            width: width,
            height: height,
            bitsPerComponent: bitsPerComponent,
            bytesPerRow: bytesPerRow,
            space: colorSpace,
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        )
        
        context?.draw(cgImage, in: CGRect(x: 0, y: 0, width: width, height: height))
        
        var colorCounts: [UIColor: Int] = [:]
        
        // Sample pixels
        for y in stride(from: 0, to: height, by: 10) {
            for x in stride(from: 0, to: width, by: 10) {
                let pixelIndex = (y * width + x) * bytesPerPixel
                
                guard pixelIndex + 2 < pixelData.count else { continue }
                
                let r = CGFloat(pixelData[pixelIndex]) / 255.0
                let g = CGFloat(pixelData[pixelIndex + 1]) / 255.0
                let b = CGFloat(pixelData[pixelIndex + 2]) / 255.0
                
                // Skip very bright or very dark colors
                let brightness = (r + g + b) / 3.0
                guard brightness > 0.2 && brightness < 0.9 else { continue }
                
                // Skip very desaturated colors (grayscale)
                let maxComponent = max(r, g, b)
                let minComponent = min(r, g, b)
                let saturation = maxComponent - minComponent
                guard saturation > 0.1 else { continue }
                
                let color = UIColor(red: r, green: g, blue: b, alpha: 1.0)
                colorCounts[color, default: 0] += 1
            }
        }
        
        let sortedColors = colorCounts.sorted { $0.value > $1.value }
        
        if let dominantUIColor = sortedColors.first?.key {
            let dominant = Color(dominantUIColor)
            
            // Create a harmonious secondary color from the dominant color
            // Instead of picking a different color, create a lighter/adjusted variation
            let secondary = createHarmoniousColor(from: dominantUIColor)
            
            return (dominant, secondary)
        }
        
        return (Color(red: 1.0, green: 0.4, blue: 0.7), Color(red: 1.0, green: 0.5, blue: 0.3))
    }
    
    // Create a harmonious secondary color from the dominant color
    private static func createHarmoniousColor(from color: UIColor) -> Color {
        var hue: CGFloat = 0
        var saturation: CGFloat = 0
        var brightness: CGFloat = 0
        var alpha: CGFloat = 0
        
        color.getHue(&hue, saturation: &saturation, brightness: &brightness, alpha: &alpha)
        
        // Create variation by adjusting hue slightly and brightness
        let newHue = hue + 0.05 // Shift hue by 5% for subtle variation
        let newSaturation = saturation * 0.85 // Slightly less saturated
        let newBrightness = min(brightness * 1.15, 1.0) // Slightly brighter
        
        let harmonious = UIColor(hue: newHue, saturation: newSaturation, brightness: newBrightness, alpha: 1.0)
        return Color(harmonious)
    }
}


// MARK: - Rating Bar
struct RatingBar: View {
    let stars: Int
    let percentage: Double
    
    var body: some View {
        HStack(spacing: 8) {
            HStack(spacing: 2) {
                ForEach(0..<stars, id: \.self) { _ in
                    Image(systemName: "star.fill")
                        .font(.system(size: 10))
                        .foregroundColor(.secondary)
                }
            }
            .frame(width: 70, alignment: .leading)
            
            GeometryReader { geometry in
                ZStack(alignment: .leading) {
                    Rectangle()
                        .fill(Color.gray.opacity(0.2))
                        .frame(height: 4)
                    
                    Rectangle()
                        .fill(Color.secondary)
                        .frame(width: geometry.size.width * percentage, height: 4)
                }
            }
            .frame(height: 4)
        }
    }
}


// MARK: - Info Row
struct InfoRow: View {
    let title: String
    let value: String
    
    var body: some View {
        HStack {
            Text(title)
                .foregroundColor(.secondary)
            Spacer()
            Text(value)
                .foregroundColor(.primary)
                .lineLimit(1)
                .truncationMode(.middle)
        }
        .font(.system(size: 15))
    }
}

