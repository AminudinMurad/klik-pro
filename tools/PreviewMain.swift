import AppKit
import CoreImage
import Foundation

@main
private struct PreviewMain {
    private static func applyPreviewEnvironmentOverrides() {
        previewRenderingIsActive = true
        let explicitTargets = ProcessInfo.processInfo.environment[
            "KLIK_PRO_PREVIEW_INSTALLED_TARGETS"
        ]
        specialFeatureEnabledPreviewOverride = explicitTargets == nil
        let rawTargets = explicitTargets ?? "both"

        switch rawTargets.lowercased() {
        case "none":
            quickLaunchInstalledTargetsPreviewOverride = []
        case "chatgpt":
            quickLaunchInstalledTargetsPreviewOverride = [.chatGPT]
        case "claude":
            quickLaunchInstalledTargetsPreviewOverride = [.claude]
        case "both":
            quickLaunchInstalledTargetsPreviewOverride = [.chatGPT, .claude]
        default:
            fputs(
                "KLIK_PRO_PREVIEW_INSTALLED_TARGETS must be none, chatgpt, claude, or both\n",
                stderr
            )
            exit(64)
        }

        // Every preview is isolated from the user's real LaunchAgent. Public previews
        // retain the enabled Special Feature presentation; explicit fixtures are OFF.
    }

    static func main() {
        guard CommandLine.arguments.count == 3 else {
            fputs("Usage: preview-render <output.png> <onboarding|mappings|settings|profiles|about>\n", stderr)
            exit(64)
        }

        let outputPath = CommandLine.arguments[1]
        let tab = CommandLine.arguments[2]
        guard tab == "onboarding" || tab == "mappings" || tab == "settings"
                || tab == "profiles" || tab == "about" else {
            fputs("Preview must be onboarding, mappings, settings, profiles, or about\n", stderr)
            exit(64)
        }

        applyPreviewEnvironmentOverrides()

        let app = NSApplication.shared
        app.setActivationPolicy(.accessory)
        app.appearance = NSAppearance(named: .aqua)
        var retainedController: ToggleWindowController?
        var retainedAlert: NSAlert?
        let window: NSWindow
        let content: NSView
        if tab == "onboarding" || tab == "about" {
            let alert: NSAlert
            if tab == "onboarding" {
                let accessibilityGranted = ProcessInfo.processInfo.environment[
                    "KLIK_PRO_PREVIEW_ACCESSIBILITY_GRANTED"
                ] == "1"
                alert = makeOnboardingAlert(accessibilityGranted: accessibilityGranted)
            } else {
                let previewIcon = Bundle.main.url(
                    forResource: "OnboardingPreviewIcon",
                    withExtension: "png"
                ).flatMap(NSImage.init(contentsOf:))
                    ?? NSApp.applicationIconImage
                    ?? NSImage(size: NSSize(width: 64, height: 64))
                let info = Bundle.main.infoDictionary
                let version = info?["CFBundleShortVersionString"] as? String ?? "0.0"
                let build = info?["CFBundleVersion"] as? String ?? "0"
                alert = makeKlikProAboutAlert(version: version, build: build, icon: previewIcon)
            }
            alert.layout()
            retainedAlert = alert
            window = alert.window
            guard let alertContent = window.contentView else {
                fputs("Unable to create alert preview\n", stderr)
                exit(1)
            }
            content = alertContent
        } else {
            let controller = ToggleWindowController()
            retainedController = controller
            guard let settingsWindow = controller.window,
                  let settingsContent = settingsWindow.contentView else {
                fputs("Unable to create settings preview window\n", stderr)
                exit(1)
            }
            window = settingsWindow
            content = settingsContent
            if let toggleView = content as? ToggleView {
                if ProcessInfo.processInfo.environment["KLIK_PRO_PREVIEW_UNSAVED"] == "1" {
                    toggleView.showUnsavedChangesPreview()
                }
                if ProcessInfo.processInfo.environment["KLIK_PRO_PREVIEW_SAVE_HOVER"] == "1" {
                    toggleView.showSaveButtonHoverPreview()
                }
                if ProcessInfo.processInfo.environment["KLIK_PRO_PREVIEW_UPDATE_HOVER"] == "1" {
                    toggleView.showUpdateButtonHoverPreview()
                }
                if ProcessInfo.processInfo.environment["KLIK_PRO_PREVIEW_CLOSE_HOVER"] == "1" {
                    toggleView.showCloseButtonHoverPreview()
                }
                if tab == "settings" {
                    toggleView.selectTab(1)
                } else if tab == "profiles" {
                    toggleView.selectTab(2)
                    if ProcessInfo.processInfo.environment[
                        "KLIK_PRO_PREVIEW_APP_PROFILES_EMPTY"
                    ] == "1" {
                        toggleView.showEmptyAppProfilesPreview()
                    } else {
                        toggleView.showSupportedAppProfilesPreview()
                    }
                } else if ProcessInfo.processInfo.environment[
                    "KLIK_PRO_PREVIEW_APP_PROFILES_EMPTY"
                ] != "1" {
                    toggleView.showSupportedAppProfilesPreview()
                }
            }
        }

        _ = retainedController
        _ = retainedAlert

        window.displayIfNeeded()
        content.layoutSubtreeIfNeeded()
        content.display()

        let bounds = content.bounds
        let previewScale: CGFloat = 2
        let pixelWidth = Int((bounds.width * previewScale).rounded())
        let pixelHeight = Int((bounds.height * previewScale).rounded())
        guard let bitmap = NSBitmapImageRep(
            bitmapDataPlanes: nil,
            pixelsWide: pixelWidth,
            pixelsHigh: pixelHeight,
            bitsPerSample: 8,
            samplesPerPixel: 4,
            hasAlpha: true,
            isPlanar: false,
            colorSpaceName: .deviceRGB,
            bitmapFormat: [],
            bytesPerRow: pixelWidth * 4,
            bitsPerPixel: 32
        ) else {
            fputs("Unable to allocate preview bitmap\n", stderr)
            exit(1)
        }
        bitmap.size = bounds.size
        content.cacheDisplay(in: bounds, to: bitmap)
        guard let sourceImage = CIImage(bitmapImageRep: bitmap) else {
            fputs("Unable to create source preview image\n", stderr)
            exit(1)
        }
        let outputRect = sourceImage.extent
        let colorSpace = CGColorSpaceCreateDeviceRGB()
        let whiteBackground = CIImage(color: CIColor.white).cropped(to: outputRect)
        let opaqueImage = sourceImage.composited(over: whiteBackground)
        let renderContext = CIContext(options: [.useSoftwareRenderer: true])
        guard let compositedImage = renderContext.createCGImage(
            opaqueImage,
            from: outputRect,
            format: .RGBA8,
            colorSpace: colorSpace
        ) else {
            fputs("Unable to create flattened preview image\n", stderr)
            exit(1)
        }
        guard let opaqueContext = CGContext(
            data: nil,
            width: bitmap.pixelsWide,
            height: bitmap.pixelsHigh,
            bitsPerComponent: 8,
            bytesPerRow: bitmap.pixelsWide * 4,
            space: colorSpace,
            bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue
        ) else {
            fputs("Unable to allocate opaque preview image\n", stderr)
            exit(1)
        }
        opaqueContext.draw(compositedImage, in: outputRect)
        if tab == "onboarding" {
            // README displays this Retina capture at half size (462 points), matching
            // the Settings previews. A subtle rounded frame keeps it recognizable as
            // the actual onboarding popup against GitHub's white page background.
            let borderRect = CGRect(
                x: 1.5,
                y: 1.5,
                width: CGFloat(bitmap.pixelsWide) - 3,
                height: CGFloat(bitmap.pixelsHigh) - 3
            )
            opaqueContext.setStrokeColor(CGColor(gray: 0.76, alpha: 1))
            opaqueContext.setLineWidth(2)
            opaqueContext.addPath(CGPath(
                roundedRect: borderRect,
                cornerWidth: 30,
                cornerHeight: 30,
                transform: nil
            ))
            opaqueContext.strokePath()
        }
        guard let flattenedImage = opaqueContext.makeImage() else {
            fputs("Unable to finalize opaque preview image\n", stderr)
            exit(1)
        }
        let flattened = NSBitmapImageRep(cgImage: flattenedImage)
        guard let png = flattened.representation(using: .png, properties: [:]) else {
            fputs("Unable to encode preview PNG\n", stderr)
            exit(1)
        }

        do {
            try png.write(to: URL(fileURLWithPath: outputPath), options: .atomic)
            print("Rendered \(tab) preview to \(outputPath)")
        } catch {
            fputs("Unable to write preview: \(error)\n", stderr)
            exit(1)
        }
    }
}
