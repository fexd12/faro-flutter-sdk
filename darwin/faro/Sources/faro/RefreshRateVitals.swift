import Foundation
import os

#if os(iOS)
    import UIKit
#elseif os(macOS)
    import AppKit
#endif

// let logging = Logger(subsystem: "com.grafana.rumsdk", category: "refresh_vitals")

@available(macOS 14, *)
public class RefreshRateVitals {
    // private var displayLink: CADisplayLink?

    #if os(iOS)
        var displayLink: CADisplayLink?
    #elseif os(macOS)
        var displayLink: CVDisplayLink?
    #endif

    private var lastFrameTimestamp: CFTimeInterval?
    private var nextFrameDuration: CFTimeInterval?
    private static var backendSupportedFrameRate = 60.0
    public static var lastRefreshRate: Double? = nil

    init() {
        start()
    }

    deinit {
        stop()
    }

    // MARK: - Internal

    func framesPerSecond(provider: FrameInfoProvider) -> Double? {
        var fps: Double? = nil

        if let lastFrameTimestamp = self.lastFrameTimestamp {
            let currentFrameDuration = provider.currentFrameTimestamp - lastFrameTimestamp
            guard currentFrameDuration > 0 else {
                return nil
            }
            let currentFPS = 1.0 / currentFrameDuration

            // ProMotion displays (e.g. iPad Pro and newer iPhone Pro) can have refresh rate higher than 60 FPS.

            if let expectedCurrentFrameDuration = self.nextFrameDuration,
                provider.adaptiveFrameRateSupported
            {
                guard expectedCurrentFrameDuration > 0 else {
                    return nil
                }
                let expectedFPS = 1.0 / expectedCurrentFrameDuration
                fps = currentFPS * (Self.backendSupportedFrameRate / expectedFPS)
            } else {
                fps = currentFPS
            }
        }

        self.lastFrameTimestamp = provider.currentFrameTimestamp
        self.nextFrameDuration = provider.nextFrameTimestamp - provider.currentFrameTimestamp

        return fps
    }

    // MARK: - Private
    #if os(iOS)
        @objc
        private func displayTick(link: CADisplayLink) {
            guard let fps = framesPerSecond(provider: link) else {
                return
            }
            RefreshRateVitals.lastRefreshRate = fps

        }
    #elseif os(macOS)
        @objc
        private func displayTick(link: CVDisplayLink) {
            // guard let fps = framesPerSecond(provider: link) else {
            //     return
            // }
            // RefreshRateVitals.lastRefreshRate = fps
            // NSLog("displayTick in cpuinfo")
        }
    #endif

    func start() {
        guard displayLink == nil else {
            return
        }

        NSLog("start in cpuinfo")

        #if os(iOS)
            displayLink = CADisplayLink(target: self, selector: #selector(displayTick(link:)))
            displayLink?.add(to: .main, forMode: .common)
        #elseif os(macOS)
            CVDisplayLinkCreateWithActiveCGDisplays(&self.displayLink)

            let displayLinkOutputCallback: CVDisplayLinkOutputCallback = {
                (
                    _: CVDisplayLink,
                    _: UnsafePointer<CVTimeStamp>,
                    _: UnsafePointer<CVTimeStamp>,
                    _: CVOptionFlags,
                    _: UnsafeMutablePointer<CVOptionFlags>,
                    displayLinkContext: UnsafeMutableRawPointer?
                ) -> CVReturn in
                if let context = displayLinkContext {
                    let `self` = Unmanaged<RefreshRateVitals>.fromOpaque(context)
                        .takeUnretainedValue()
                    // CVDisplayLink callback is on a background thread, so we dispatch to main.
                    DispatchQueue.main.async {
                        self.displayTick(link: self.displayLink!)
                    }
                }
                return kCVReturnSuccess
            }

            CVDisplayLinkSetOutputCallback(
                displayLink!,
                displayLinkOutputCallback,
                UnsafeMutableRawPointer(Unmanaged.passUnretained(self).toOpaque())
            )
            CVDisplayLinkStart(displayLink!)
        #endif
    }

    private func stop() {
        #if os(macOS)
            CVDisplayLinkStop(displayLink!)
        #elseif os(iOS)
            displayLink?.invalidate()
        #endif
        displayLink = nil
        lastFrameTimestamp = nil
    }

    @objc
    private func appWillResignActive() {
        stop()
    }

    @objc
    private func appDidBecomeActive() {
        start()
    }
}

internal protocol FrameInfoProvider {
    var currentFrameTimestamp: CFTimeInterval { get }

    var nextFrameTimestamp: CFTimeInterval { get }

    var maximumDeviceFramesPerSecond: Int { get }
}

private let adaptiveFrameRateThreshold = 60
extension FrameInfoProvider {
    var adaptiveFrameRateSupported: Bool {
        maximumDeviceFramesPerSecond > adaptiveFrameRateThreshold
    }
}

@available(macOS 14, *)
extension CADisplayLink: FrameInfoProvider {

    var maximumDeviceFramesPerSecond: Int {
        #if os(iOS)
            UIScreen.main.maximumFramesPerSecond
        #elseif os(macOS)
            NSScreen.main?.maximumFramesPerSecond ?? 60
        #endif
    }

    var currentFrameTimestamp: CFTimeInterval {
        timestamp
    }

    var nextFrameTimestamp: CFTimeInterval {
        targetTimestamp
    }
}
