import Foundation
import AVFoundation
@preconcurrency import Vision

final class CameraMonitor: NSObject, AVCaptureVideoDataOutputSampleBufferDelegate {
    enum State { case stopped, running }
    private(set) var state: State = .stopped // mutated only on `queue`

    // Callbacks
    var onRiskDetected: (() -> Void)?
    var onPermissionProblem: ((String) -> Void)? // message

    // Config
    var minConsecutiveDetections: Int = 1
    var targetFPS: Double = 4.0

    // Internals
    private let session = AVCaptureSession()
    private let queue = DispatchQueue(label: "ai.camera.monitor")
    private var lastProcessTime: TimeInterval = 0
    private var detectionStreak = 0

    func start() {
        // Check Info.plist key presence (to avoid crash on access)
        if Bundle.main.object(forInfoDictionaryKey: "NSCameraUsageDescription") == nil {
            let handler = self.onPermissionProblem
            DispatchQueue.main.async {
                handler?("缺少隐私权限描述：请在 Target > Info 添加 Privacy - Camera Usage Description (NSCameraUsageDescription)")
            }
            return
        }

        switch AVCaptureDevice.authorizationStatus(for: .video) {
        case .notDetermined:
            AVCaptureDevice.requestAccess(for: .video) { [weak self] granted in
                if granted {
                    if let strong = self {
                        strong.queue.async { [weak strong] in strong?.configureAndStartOnQueue() }
                    }
                } else {
                    let handler = self?.onPermissionProblem
                    DispatchQueue.main.async { handler?("相机访问被拒绝") }
                }
            }
        case .authorized:
            queue.async { [weak self] in self?.configureAndStartOnQueue() }
        case .denied, .restricted:
            let handler = self.onPermissionProblem
            DispatchQueue.main.async { handler?("相机访问受限或被拒绝") }
        @unknown default:
            let handler = self.onPermissionProblem
            DispatchQueue.main.async { handler?("相机权限未知状态") }
        }
    }

    func stop() {
        queue.async { [weak self] in
            guard let self = self, self.state == .running else { return }
            self.session.stopRunning()
            self.state = .stopped
        }
    }

    // MARK: - Setup
    private func configureAndStartOnQueue() {
        // Ensure serialized access
        session.beginConfiguration()
        session.sessionPreset = .vga640x480
        session.inputs.forEach { session.removeInput($0) }
        session.outputs.forEach { session.removeOutput($0) }

        guard let device = AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: .unspecified) ?? AVCaptureDevice.default(for: .video) else {
            let handler = self.onPermissionProblem
            DispatchQueue.main.async { handler?("未找到可用摄像头设备") }
            session.commitConfiguration()
            return
        }
        do {
            let input = try AVCaptureDeviceInput(device: device)
            if session.canAddInput(input) { session.addInput(input) }
        } catch {
            let handler = self.onPermissionProblem
            DispatchQueue.main.async { handler?("无法创建摄像头输入：\(error.localizedDescription)") }
            session.commitConfiguration()
            return
        }

        let output = AVCaptureVideoDataOutput()
        output.alwaysDiscardsLateVideoFrames = true
        output.videoSettings = [kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA]
        output.setSampleBufferDelegate(self, queue: queue)
        if session.canAddOutput(output) { session.addOutput(output) }

        session.commitConfiguration()
        session.startRunning()
        state = .running
        detectionStreak = 0
        lastProcessTime = 0
    }

    // MARK: - Delegate
    func captureOutput(_ output: AVCaptureOutput, didOutput sampleBuffer: CMSampleBuffer, from connection: AVCaptureConnection) {
        guard state == .running else { return }
        // Throttle to target FPS
        let now = CFAbsoluteTimeGetCurrent()
        let minInterval = 1.0 / max(1.0, targetFPS)
        if now - lastProcessTime < minInterval { return }
        lastProcessTime = now

        guard let pixelBuffer = CMSampleBufferGetImageBuffer(sampleBuffer) else { return }
        let request = VNDetectFaceRectanglesRequest { [weak self] req, err in
            guard let self = self else { return }
            if err != nil { return }
            // Read Vision results before hopping to another executor to avoid
            // capturing non-Sendable types across concurrency domains.
            let faces = (req.results as? [VNFaceObservation]) ?? []
            // Ensure state mutation on our serial queue
            self.queue.async {
                if faces.count > 0 {
                    self.detectionStreak += 1
                    if self.detectionStreak >= self.minConsecutiveDetections {
                        self.detectionStreak = 0
                        DispatchQueue.main.async { self.onRiskDetected?() }
                    }
                } else {
                    self.detectionStreak = 0
                }
            }
        }
        let handler = VNImageRequestHandler(cvPixelBuffer: pixelBuffer, options: [:])
        do {
            try handler.perform([request])
        } catch {
            // ignore
        }
    }
}

// We guard internal mutable state via a private serial DispatchQueue, and only
// invoke UI callbacks on the main queue. Mark as @unchecked Sendable to silence
// strict concurrency warnings when closures capture `self` across executors.
extension CameraMonitor: @unchecked Sendable {}
