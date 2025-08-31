import Foundation
@preconcurrency import Dispatch
@preconcurrency import AVFoundation
@preconcurrency import Vision

// MARK: - Core actor (serializes all mutable state)
    actor CameraCore {
        enum State { case stopped, running }

    // Config (owned by the actor)
    var minConsecutiveDetections: Int
    var targetFPS: Double

    // Callbacks (Sendable so we can hop threads safely)
    private var onRiskDetected: (@Sendable () -> Void)?
    private var onPermissionProblem: (@Sendable (String) -> Void)?

    // Internals
    private let session = AVCaptureSession()
    private var lastProcessTime: TimeInterval = 0
    private var detectionStreak = 0
    private(set) var state: State = .stopped

    // A lightweight Objective‑C delegate bridge owned by the core
    private let sampleBufferBridge: SampleBufferBridge

    init(minConsecutiveDetections: Int,
         targetFPS: Double,
         onRiskDetected: (@Sendable () -> Void)?,
         onPermissionProblem: (@Sendable (String) -> Void)?) {
        self.minConsecutiveDetections = minConsecutiveDetections
        self.targetFPS = targetFPS
        self.onRiskDetected = onRiskDetected
        self.onPermissionProblem = onPermissionProblem
        self.sampleBufferBridge = SampleBufferBridge()
        self.sampleBufferBridge.install(core: self)
    }

    func updateCallbacks(onRiskDetected: (@Sendable () -> Void)?,
                         onPermissionProblem: (@Sendable (String) -> Void)?) {
        self.onRiskDetected = onRiskDetected
        self.onPermissionProblem = onPermissionProblem
    }

    // Isolated setters to mutate actor state from outside safely
    func setMinConsecutiveDetections(_ value: Int) { self.minConsecutiveDetections = value }
    func setTargetFPS(_ value: Double) { self.targetFPS = value }

    // Start/Stop are fully serialized inside the actor
    func start() async {
        // Check Info.plist key presence (to avoid crash on access)
        if Bundle.main.object(forInfoDictionaryKey: "NSCameraUsageDescription") == nil {
            onPermissionProblem?("缺少隐私权限描述：请在 Target > Info 添加 Privacy - Camera Usage Description (NSCameraUsageDescription)")
            return
        }

        switch AVCaptureDevice.authorizationStatus(for: .video) {
        case .notDetermined:
            // Avoid capturing `self` in a @Sendable closure: capture only the Sendable callbacks
            let permissionHandler = self.onPermissionProblem
            await withCheckedContinuation { (cont: CheckedContinuation<Void, Never>) in
                AVCaptureDevice.requestAccess(for: .video) { granted in
                    if granted {
                        cont.resume()
                    } else {
                        permissionHandler?("相机访问被拒绝")
                        cont.resume()
                    }
                }
            }
            // After returning, either we have permission or we already reported the error
            if AVCaptureDevice.authorizationStatus(for: .video) == .authorized {
                configureAndStart()
            }
        case .authorized:
            configureAndStart()
        case .denied, .restricted:
            onPermissionProblem?("相机访问受限或被拒绝")
        @unknown default:
            onPermissionProblem?("相机权限未知状态")
        }
    }

    func stop() {
        guard state == .running else { return }
        session.stopRunning()
        state = .stopped
    }

    private func configureAndStart() {
        // Ensure serialized access
        session.beginConfiguration()
        session.sessionPreset = .vga640x480
        session.inputs.forEach { session.removeInput($0) }
        session.outputs.forEach { session.removeOutput($0) }

        guard let device = AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: .unspecified) ?? AVCaptureDevice.default(for: .video) else {
            onPermissionProblem?("未找到可用摄像头设备")
            session.commitConfiguration()
            return
        }
        do {
            let input = try AVCaptureDeviceInput(device: device)
            if session.canAddInput(input) { session.addInput(input) }
        } catch {
            onPermissionProblem?("无法创建摄像头输入：\(error.localizedDescription)")
            session.commitConfiguration()
            return
        }

        let output = AVCaptureVideoDataOutput()
        output.alwaysDiscardsLateVideoFrames = true
        output.videoSettings = [kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA]
        output.setSampleBufferDelegate(sampleBufferBridge, queue: sampleBufferBridge.queue)
        if session.canAddOutput(output) { session.addOutput(output) }

        session.commitConfiguration()
        session.startRunning()
        state = .running
        detectionStreak = 0
        lastProcessTime = 0
    }

    // Called from the delegate bridge
    func process(_ sampleBuffer: CMSampleBuffer) {
        guard state == .running else { return }
        // Throttle to target FPS
        let now = CFAbsoluteTimeGetCurrent()
        let minInterval = 1.0 / max(1.0, targetFPS)
        if now - lastProcessTime < minInterval { return }
        lastProcessTime = now

        guard let pixelBuffer = CMSampleBufferGetImageBuffer(sampleBuffer) else { return }
        let request = VNDetectFaceRectanglesRequest()
        let handler = VNImageRequestHandler(cvPixelBuffer: pixelBuffer, options: [:])
        do {
            try handler.perform([request])
            let faces = request.results ?? []
            if faces.count > 0 {
                detectionStreak += 1
                if detectionStreak >= minConsecutiveDetections {
                    detectionStreak = 0
                    onRiskDetected?()
                }
            } else {
                detectionStreak = 0
            }
        } catch {
            // ignore vision errors to keep pipeline flowing
        }
    }
}

// MARK: - ObjC delegate bridge (no shared mutable state)
final class SampleBufferBridge: NSObject, AVCaptureVideoDataOutputSampleBufferDelegate {
    // A dedicated serial queue for the AVCapture output
    let queue = DispatchQueue(label: "ai.camera.monitor.bridge")

    // Weak-like install to avoid retain cycles (the actor will outlive the bridge once installed)
    private var _core: CameraCore?

    func install(core: CameraCore) { _core = core }

    func captureOutput(_ output: AVCaptureOutput,
                       didOutput sampleBuffer: CMSampleBuffer,
                       from connection: AVCaptureConnection) {
        // Make an independent copy to avoid task-isolated capture diagnostics
        var copy: CMSampleBuffer? = nil
        let status = CMSampleBufferCreateCopy(allocator: kCFAllocatorDefault, sampleBuffer: sampleBuffer, sampleBufferOut: &copy)
        guard status == noErr, let safeCopy = copy else { return }

        struct SampleBufferBox: @unchecked Sendable { let buffer: CMSampleBuffer }
        let box = SampleBufferBox(buffer: safeCopy)

        if let core = _core {
            Task { await core.process(box.buffer) }
        }
    }
}

// MARK: - Public facade (non-Sendable, no @unchecked needed)
final class CameraMonitor: NSObject {
    // Exposed callbacks (Sendable so they can cross threads safely)
    var onRiskDetected: (@Sendable () -> Void)? {
        didSet {
            let c = core
            let risk = onRiskDetected
            let perm = onPermissionProblem
            Task { await c.updateCallbacks(onRiskDetected: risk, onPermissionProblem: perm) }
        }
    }
    var onPermissionProblem: (@Sendable (String) -> Void)? {
        didSet {
            let c = core
            let risk = onRiskDetected
            let perm = onPermissionProblem
            Task { await c.updateCallbacks(onRiskDetected: risk, onPermissionProblem: perm) }
        }
    }

    // Config proxies
    var minConsecutiveDetections: Int {
        get { storedMin }
        set {
            storedMin = newValue
            let c = core
            Task { await c.setMinConsecutiveDetections(newValue) }
        }
    }
    var targetFPS: Double {
        get { storedFPS }
        set {
            storedFPS = newValue
            let c = core
            Task { await c.setTargetFPS(newValue) }
        }
    }

    // Local mirrors for quick reads (not used from multiple threads concurrently)
    private var storedMin: Int
    private var storedFPS: Double

    // The actor that owns the mutable state and the AVCaptureSession
    private let core: CameraCore

    override init() {
        self.storedMin = 1
        self.storedFPS = 4.0
        self.core = CameraCore(minConsecutiveDetections: 1,
                               targetFPS: 4.0,
                               onRiskDetected: nil,
                               onPermissionProblem: nil)
        super.init()
    }

    func start() {
        let c = core
        let risk = onRiskDetected
        let perm = onPermissionProblem
        Task {
            await c.updateCallbacks(onRiskDetected: risk, onPermissionProblem: perm)
            await c.start()
        }
    }

    func stop() {
        let c = core
        Task { await c.stop() }
    }
}

// Concurrency notes:
// - All mutable state (session, throttling, detection counters) lives in the CameraCore actor.
// - We never capture `self` from CameraMonitor inside a `@Sendable` closure.
// - The AVCapture delegate is a separate NSObject (SampleBufferBridge) that forwards frames to the actor via Task, which is safe because actors are Sendable by construction.
// - Public callbacks are typed as `@Sendable` so clients can safely assign closures that might be invoked from non-main threads (callers can still dispatch to main if they touch UI).
