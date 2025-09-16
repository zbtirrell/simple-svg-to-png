import SwiftUI
import AppKit

/// Main view for the Simple SVG to PNG converter app
/// This app allows users to load SVG files, preview them with a checkerboard background,
/// adjust the scale, and export them as PNG images using the resvg command-line tool.
struct ContentView: View {
    // MARK: - State Properties
    
    /// URL of the currently selected SVG file
    @State private var svgURL: URL?
    
    /// Raw slider value (0.0 to 1.0) that maps to actual scale
    @State private var sliderValue: Double = 0.0
    
    /// Status message displayed to the user
    @State private var status: String = "Pick an SVG, choose a scale, export PNG."
    
    /// Preview image generated from the SVG for display in the UI
    @State private var previewImage: NSImage?
    
    /// Flag indicating whether a preview is currently being generated
    @State private var isGeneratingPreview = false
    
    /// Whether to show checkerboard background in the preview
    @State private var showCheckerboard = false
    
    /// Original SVG size in pixels, extracted from the SVG file
    @State private var baseSize: CGSize?
    
    // MARK: - Computed Properties
    
    /// Converts slider value (0.0-1.0) to actual scale (0.1-100.0)
    /// First 2/3 (0.0-0.67) maps to 0.1-10.0 in 0.1 increments
    /// Last 1/3 (0.67-1.0) maps to 10.0-100.0 in 5.0 increments
    private var actualScale: Double {
        if sliderValue <= 2.0/3.0 {
            // 0.0 to 0.67 maps to 0.1 to 10.0 (fine increments)
            let progress = sliderValue / (2.0/3.0)
            let rawValue = 0.1 + progress * 9.9
            // Round to nearest 0.1
            return round(rawValue * 10) / 10
        } else {
            // 0.67 to 1.0 maps to 10.0 to 100.0 (5x increments)
            let progress = (sliderValue - 2.0/3.0) / (1.0/3.0)
            // Map to discrete 5x increments: 10, 15, 20, 25, 30, 35, 40, 45, 50, 55, 60, 65, 70, 75, 80, 85, 90, 95, 100
            let incrementIndex = round(progress * 18) // 0 to 18 for 19 values
            let clampedIndex = max(0, min(18, incrementIndex))
            return 10.0 + clampedIndex * 5.0
        }
    }
    
    /// Converts actual scale back to slider value for display
    private func scaleToSliderValue(_ scale: Double) -> Double {
        if scale <= 10.0 {
            // 0.1 to 10.0 maps to 0.0 to 0.67
            let progress = (scale - 0.1) / 9.9
            return progress * (2.0/3.0)
        } else {
            // 10.0 to 100.0 maps to 0.67 to 1.0 (discrete 5x increments)
            let incrementIndex = (scale - 10.0) / 5.0
            let progress = incrementIndex / 18.0 // 0 to 18 for 19 values
            return (2.0/3.0) + progress * (1.0/3.0)
        }
    }
    
    /// Icon for the status message based on current state
    private var statusIcon: String {
        if status.contains("Saved") {
            return "checkmark.circle.fill"
        } else if status.contains("failed") || status.contains("error") {
            return "exclamationmark.triangle.fill"
        } else if status.contains("Loading") || status.contains("Loaded") {
            return "doc.fill"
        } else {
            return "info.circle"
        }
    }
    
    /// Color for the status icon based on current state
    private var statusColor: Color {
        if status.contains("Saved") {
            return .green
        } else if status.contains("failed") || status.contains("error") {
            return .red
        } else if status.contains("Loading") || status.contains("Loaded") {
            return .blue
        } else {
            return .secondary
        }
    }

    // MARK: - Main View Body
    
    var body: some View {
        ZStack {
            // Background that covers the entire window
            Color(.controlBackgroundColor).opacity(0.3)
                .ignoresSafeArea()
            
            HStack(spacing: 24) {
                // MARK: - Left Panel - Controls
                VStack(spacing: 20) {
                // MARK: - File Selection Card
                VStack(alignment: .leading, spacing: 12) {
                    HStack {
                        Image(systemName: "doc.badge.plus")
                            .foregroundStyle(.blue)
                            .font(.title2)
                        Text("SVG File")
                            .font(.headline)
                            .fontWeight(.semibold)
                    }
                    
                    Button(action: pickSVG) {
                        HStack {
                            Image(systemName: svgURL != nil ? "doc.fill" : "folder")
                                .foregroundStyle(svgURL != nil ? .blue : .secondary)
                            if let url = svgURL {
                                Text(url.lastPathComponent)
                                    .lineLimit(1)
                                    .truncationMode(.middle)
                                    .foregroundStyle(.primary)
                            } else {
                                Text("Choose SVG file...")
                                    .foregroundStyle(.secondary)
                            }
                            Spacer()
                            Image(systemName: "chevron.right")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        .padding(.horizontal, 16)
                        .padding(.vertical, 12)
                        .background(
                            RoundedRectangle(cornerRadius: 8)
                                .fill(Color(.controlBackgroundColor))
                                .overlay(
                                    RoundedRectangle(cornerRadius: 8)
                                        .stroke(svgURL != nil ? Color.blue.opacity(0.3) : Color.clear, lineWidth: 1)
                                )
                        )
                    }
                    .buttonStyle(FilePickerButtonStyle())
                }
                .padding(16)
                .background(Color(.windowBackgroundColor))
                .cornerRadius(12)
                .shadow(color: .black.opacity(0.05), radius: 2, x: 0, y: 1)

                // MARK: - Scale Control Card
                VStack(alignment: .leading, spacing: 12) {
                    HStack {
                        Image(systemName: "arrow.up.left.and.arrow.down.right")
                            .foregroundStyle(.orange)
                            .font(.title2)
                        Text("Scale")
                            .font(.headline)
                            .fontWeight(.semibold)
                    }
                    
                    VStack(spacing: 8) {
                        HStack {
                            Text("0.1x")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .fontWeight(.medium)
                                .frame(width: 30, alignment: .leading)
                            
                            Slider(value: $sliderValue, in: 0.0...1.0, step: 0.01)
                                .accentColor(.orange)
                                .frame(width: 200)
                            
                            Text("100x")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .fontWeight(.medium)
                                .frame(width: 30, alignment: .trailing)
                        }
                        
                        HStack {
                            Spacer()
                            if let size = baseSize {
                                let w = Int(size.width * actualScale)
                                let h = Int(size.height * actualScale)
                                Text("\(String(format: actualScale >= 10.0 ? "%.0fx" : "%.1fx", actualScale)) (\(w) × \(h) px)")
                                    .font(.subheadline)
                                    .fontWeight(.medium)
                                    .monospaced()
                                    .foregroundStyle(.primary)
                            } else {
                                Text(String(format: actualScale >= 10.0 ? "%.0fx" : "%.1fx", actualScale))
                                    .font(.subheadline)
                                    .fontWeight(.medium)
                                    .monospaced()
                                    .foregroundStyle(.primary)
                            }
                        }
                    }
                }
                .padding(16)
                .background(Color(.windowBackgroundColor))
                .cornerRadius(12)
                .shadow(color: .black.opacity(0.05), radius: 2, x: 0, y: 1)
                
                // MARK: - Export Section
                VStack(spacing: 12) {
                    Button(action: exportPNG) {
                        HStack {
                            Image(systemName: "square.and.arrow.down")
                                .font(.system(size: 16, weight: .medium))
                            Text("Export PNG")
                                .fontWeight(.semibold)
                            Spacer()
                        }
                        .padding(.horizontal, 20)
                        .padding(.vertical, 14)
                        .background(
                            RoundedRectangle(cornerRadius: 10)
                                .fill(svgURL != nil ? 
                                    LinearGradient(colors: [.blue, .blue.opacity(0.8)], startPoint: .top, endPoint: .bottom) :
                                    LinearGradient(colors: [.gray.opacity(0.3), .gray.opacity(0.2)], startPoint: .top, endPoint: .bottom)
                                )
                                .shadow(color: svgURL != nil ? .blue.opacity(0.3) : .clear, radius: 4, x: 0, y: 2)
                        )
                        .foregroundStyle(svgURL != nil ? .white : .secondary)
                        .scaleEffect(svgURL != nil ? 1.0 : 0.98)
                    }
                    .buttonStyle(ExportButtonStyle())
                    .disabled(svgURL == nil)
                    
                    HStack {
                        Image(systemName: statusIcon)
                            .foregroundStyle(statusColor)
                            .font(.caption)
                        Text(status)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    .multilineTextAlignment(.center)
                }
                
                Spacer()
            }
            .frame(width: 280)
            
            // MARK: - Right Panel - Preview
            VStack(spacing: 16) {
                HStack {
                    Text("Preview")
                        .font(.headline)
                        .fontWeight(.semibold)
                    
                    Spacer()
                    
                    // MARK: - Background Toggle
                    HStack(spacing: 8) {
                        Image(systemName: "checkerboard.rectangle")
                            .foregroundStyle(.purple)
                            .font(.subheadline)
                        Toggle("Checkerboard", isOn: $showCheckerboard)
                            .toggleStyle(.switch)
                            .tint(.purple)
                            .labelsHidden()
                    }
                }
                
                // MARK: - Preview Area
                ZStack {
                    // Background: either checkerboard pattern or plain gray
                    if showCheckerboard {
                        CheckerboardBackground(square: 12)
                    } else {
                        Color.gray.opacity(0.15)   // plain gray like Preview.app
                    }

                    // Preview content: image, loading indicator, or placeholder
                    if let img = previewImage {
                        Image(nsImage: img)
                            .resizable()
                            .scaledToFit()
                            .padding(12)
                    } else if isGeneratingPreview {
                        VStack(spacing: 12) {
                            ProgressView()
                                .scaleEffect(1.2)
                            Text("Rendering preview…")
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                        }
                    } else {
                        VStack(spacing: 12) {
                            Image(systemName: "photo")
                                .font(.system(size: 48))
                                .foregroundStyle(.secondary.opacity(0.6))
                            Text("No preview")
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                            Text("Select an SVG file to see preview")
                                .font(.caption)
                                .foregroundStyle(.secondary.opacity(0.8))
                        }
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(Color(.controlBackgroundColor))
                .cornerRadius(12)
                .overlay(
                    RoundedRectangle(cornerRadius: 12)
                        .stroke(Color.secondary.opacity(0.2), lineWidth: 1)
                )
                .shadow(color: .black.opacity(0.05), radius: 2, x: 0, y: 1)
            }
            }
            .padding(24)
            .frame(width: 720, height: 500)
            .onAppear {
                sliderValue = scaleToSliderValue(1.0) // Default to 1.0x scale
            }
        }
    }
    
    // MARK: - Checkerboard Background View
    
    /// A custom view that renders a checkerboard pattern background
    /// Used to provide visual contrast for transparent SVG elements
    struct CheckerboardBackground: View {
        /// Size of each checkerboard square in points
        var square: CGFloat = 12
        /// Light color for alternating squares
        var light = Color.white
        /// Dark color for alternating squares
        var dark = Color.gray.opacity(0.25)

        var body: some View {
            GeometryReader { geometry in
                let cols = Int(ceil(geometry.size.width / square))
                let rows = Int(ceil(geometry.size.height / square))
                
                VStack(spacing: 0) {
                    ForEach(0..<rows, id: \.self) { row in
                        HStack(spacing: 0) {
                            ForEach(0..<cols, id: \.self) { col in
                                Rectangle()
                                    .fill((row + col) % 2 == 0 ? light : dark)
                                    .frame(width: square, height: square)
                            }
                        }
                    }
                }
                .frame(width: geometry.size.width, height: geometry.size.height)
                .clipped()
            }
        }
    }


    // MARK: - File Selection
    
    /// Opens a file picker dialog to select an SVG file
    /// Updates the UI state and generates a preview when a file is selected
    private func pickSVG() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.init(filenameExtension: "svg")!]
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        
        if panel.runModal() == .OK {
            svgURL = panel.url
            status = "Loaded \(panel.url?.lastPathComponent ?? "SVG")."
            generatePreview()
            extractBaseSize()
        }
    }
    
    // MARK: - SVG Size Extraction
    
    /// Extracts the base size of the SVG from its XML content
    /// This is used to calculate the output dimensions when scaling
    private func extractBaseSize() {
        guard let url = svgURL,
              let xml = try? String(contentsOf: url, encoding: .utf8) else {
            baseSize = nil
            return
        }
        baseSize = parseSVGBaseSize(xml: xml)
    }

    /// Parses the SVG XML to extract the base dimensions
    /// Supports both explicit width/height attributes and viewBox fallback
    /// - Parameter xml: The SVG XML content as a string
    /// - Returns: The base size in pixels, or nil if unable to determine
    private func parseSVGBaseSize(xml: String) -> CGSize? {
        // Extract the <svg> start tag from the XML
        guard let svgStart = xml.range(of: "<svg", options: [.caseInsensitive]),
              let tagEnd = xml.range(of: ">", range: svgStart.lowerBound..<xml.endIndex)
        else { return nil }
        let tag = String(xml[svgStart.lowerBound..<tagEnd.upperBound])

        // Extract width, height, and viewBox attributes
        let widthStr  = matchAttr(tag, "width")
        let heightStr = matchAttr(tag, "height")
        let viewBox   = matchAttr(tag, "viewBox") ?? matchAttr(tag, "viewbox")

        // Try explicit width/height attributes first
        if let ws = widthStr, let hs = heightStr,
           let w = parseLengthToPixels(ws), let h = parseLengthToPixels(hs),
           w > 0, h > 0 {
            return CGSize(width: w, height: h)
        }

        // Fallback to viewBox dimensions if width/height not available
        if let vb = viewBox {
            // viewBox format: "minX minY width height"
            let parts = vb.split{ $0 == " " || $0 == "," }.compactMap{ Double($0) }
            if parts.count == 4, parts[2] > 0, parts[3] > 0 {
                return CGSize(width: parts[2], height: parts[3])
            }
        }

        return nil
    }

    /// Extracts an attribute value from an XML tag using regex
    /// - Parameters:
    ///   - tag: The XML tag string to search in
    ///   - name: The attribute name to look for
    /// - Returns: The attribute value, or nil if not found
    private func matchAttr(_ tag: String, _ name: String) -> String? {
        // Regex pattern to match name="value" with flexible whitespace
        let pattern = "(?i)\\b" + NSRegularExpression.escapedPattern(for: name) + #"\s*=\s*"([^"]+)""#
        guard let re = try? NSRegularExpression(pattern: pattern),
              let m = re.firstMatch(in: tag, range: NSRange(tag.startIndex..., in: tag)),
              let r = Range(m.range(at: 1), in: tag)
        else { return nil }
        return String(tag[r]).trimmingCharacters(in: .whitespacesAndNewlines)
    }

    // MARK: - SVG Unit Conversion
    
    /// Converts SVG length values to pixels
    /// Supports common SVG units: px, pt, in, cm, mm, pc, q
    /// Percentages and "auto" values return nil
    /// - Parameter s: The length string to convert
    /// - Returns: The value in pixels, or nil if conversion fails
    private func parseLengthToPixels(_ s: String) -> Double? {
        let trimmed = s.trimmingCharacters(in: .whitespacesAndNewlines)
        
        // Reject percentages or "auto" values
        if trimmed.hasSuffix("%") || trimmed.lowercased() == "auto" { return nil }

        // Extract numeric value and unit using regex
        let re = try! NSRegularExpression(pattern: #"^\s*([+-]?\d*\.?\d+)\s*([a-zA-Z]*)\s*$"#)
        guard let m = re.firstMatch(in: trimmed, range: NSRange(trimmed.startIndex..., in: trimmed)),
              let numR = Range(m.range(at: 1), in: trimmed)
        else { return nil }
        let value = Double(trimmed[numR]) ?? 0
        let unit = (Range(m.range(at: 2), in: trimmed).map { String(trimmed[$0]).lowercased() }) ?? "px"

        // Convert to pixels using CSS reference DPI of 96
        let dpi = 96.0
        switch unit {
        case "", "px": return value
        case "pt":     return value * (dpi / 72.0)      // 1pt = 1/72 inch
        case "in":     return value * dpi                // 1 inch = 96px
        case "cm":     return value * (dpi / 2.54)       // 1cm = 1/2.54 inch
        case "mm":     return value * (dpi / 25.4)       // 1mm = 1/25.4 inch
        case "pc":     return value * 16.0               // 1pc = 12pt = 16px
        case "q":      return value * (dpi / 101.6)      // 1Q = 1/4 mm
        default:       return nil
        }
    }



    // MARK: - PNG Export
    
    /// Exports the current SVG as a PNG file using the resvg command-line tool
    /// Opens a save dialog and uses the current scale setting
    private func exportPNG() {
        guard let inURL = svgURL else { return }

        // Configure save dialog
        let save = NSSavePanel()
        save.allowedContentTypes = [.png]
        save.nameFieldStringValue =
            inURL.deletingPathExtension().lastPathComponent +
            "@\(String(format: actualScale >= 10.0 ? "%.0fx" : "%.1fx", actualScale)).png"
        if let downloads = FileManager.default.urls(for: .downloadsDirectory, in: .userDomainMask).first {
            save.directoryURL = downloads
        }
        guard save.runModal() == .OK, let outURL = save.url else { return }

        // Locate the bundled resvg executable
        guard let tool = Bundle.main.url(forResource: "resvg", withExtension: nil) else {
            status = "resvg not found in bundle."
            return
        }

        // Configure resvg command with zoom factor to preserve aspect ratio
        let task = Process()
        task.executableURL = tool
        task.arguments = ["-z", String(actualScale), inURL.path, outURL.path]

        // Capture error output for debugging
        let pipe = Pipe()
        task.standardError = pipe
        
        do {
            try task.run()
            task.waitUntilExit()
        } catch {
            status = "Launch failed: \(error.localizedDescription)"
            return
        }

        // Handle export result
        if task.terminationStatus == 0 {
            status = "Saved \(outURL.lastPathComponent)."
        } else {
            let err = String(data: pipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? "Unknown error"
            status = "resvg failed: \(err.trimmingCharacters(in: .whitespacesAndNewlines))"
        }
    }

    // MARK: - Preview Generation
    
    /// Generates a preview image of the current SVG for display in the UI
    /// Uses resvg to create a 512px wide preview that maintains aspect ratio
    private func generatePreview() {
        guard let inURL = svgURL else { return }
        isGeneratingPreview = true
        previewImage = nil

        // Create a temporary file for the preview PNG
        let tmp = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
            .appendingPathExtension("png")

        // Locate the bundled resvg executable
        guard let tool = Bundle.main.url(forResource: "resvg", withExtension: nil) else {
            status = "resvg not found in bundle."
            isGeneratingPreview = false
            return
        }

        // Configure resvg to render a 512px wide preview
        let task = Process()
        task.executableURL = tool
        task.arguments = ["-w", "512", inURL.path, tmp.path]

        let stderrPipe = Pipe()
        task.standardError = stderrPipe

        // Run preview generation on background queue to avoid blocking UI
        DispatchQueue.global(qos: .userInitiated).async {
            do {
                try task.run()
                task.waitUntilExit()
            } catch {
                DispatchQueue.main.async {
                    self.status = "Preview failed to launch: \(error.localizedDescription)"
                    self.isGeneratingPreview = false
                }
                return
            }

            // Handle successful preview generation
            if task.terminationStatus == 0, let img = NSImage(contentsOf: tmp) {
                DispatchQueue.main.async {
                    self.previewImage = img
                    self.isGeneratingPreview = false
                }
            } else {
                // Handle preview generation error
                let err = String(data: stderrPipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? "Unknown error"
                DispatchQueue.main.async {
                    self.status = "Preview error: \(err.trimmingCharacters(in: .whitespacesAndNewlines))"
                    self.isGeneratingPreview = false
                }
            }

            // Clean up temporary file
            try? FileManager.default.removeItem(at: tmp)
        }
    }

    
}


// MARK: - Custom Button Styles

/// Custom button style for the file picker button
struct FilePickerButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.98 : 1.0)
            .opacity(configuration.isPressed ? 0.8 : 1.0)
            .animation(.easeInOut(duration: 0.1), value: configuration.isPressed)
    }
}

/// Custom button style for the export button
struct ExportButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.95 : 1.0)
            .opacity(configuration.isPressed ? 0.9 : 1.0)
            .animation(.easeInOut(duration: 0.15), value: configuration.isPressed)
    }
}
