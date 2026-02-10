//
//  CameraManager.swift
//  aspa-camera
//
//  Created by Takashi Otsuka on 2026/02/10.
//

import Foundation
@preconcurrency import AVFoundation
import SwiftUI
import UIKit
import Combine

@MainActor
final class CameraManager: NSObject, ObservableObject {
    @Published var currentFrame: CVPixelBuffer?
    @Published var isAuthorized = false
    @Published var error: Error?
    @Published var isRecording = false
    @Published var capturedImage: UIImage?
    @Published var videoResolution: CGSize = CGSize(width: 1080, height: 1920)
    @Published var currentZoomFactor: CGFloat = 1.0
    @Published var maxZoomFactor: CGFloat = 10.0

    nonisolated private let captureSession = AVCaptureSession()
    nonisolated private let videoOutput = AVCaptureVideoDataOutput()
    nonisolated private let photoOutput = AVCapturePhotoOutput()
    nonisolated private let sessionQueue = DispatchQueue(label: "camera.session.queue")
    nonisolated(unsafe) private var videoDevice: AVCaptureDevice?

    // AVAssetWriter ベースの録画
    nonisolated(unsafe) private var assetWriter: AVAssetWriter?
    nonisolated(unsafe) private var assetWriterVideoInput: AVAssetWriterInput?
    nonisolated(unsafe) private var pixelBufferAdaptor: AVAssetWriterInputPixelBufferAdaptor?
    nonisolated(unsafe) private var recordingStartTime: CMTime?
    nonisolated(unsafe) private var _isRecordingFlag = false
    /// 録画時にsessionQueueから読まれるマスクのスナップショット
    nonisolated(unsafe) var _currentMaskSnapshot: CGImage?

    // プレビューレイヤーを保持
    nonisolated(unsafe) private(set) lazy var previewLayer: AVCaptureVideoPreviewLayer = {
        let layer = AVCaptureVideoPreviewLayer(session: captureSession)
        layer.videoGravity = .resizeAspectFill
        return layer
    }()

    private var currentVideoURL: URL?

    override init() {
        // 同期的に権限チェック（UIブロックなし）
        let status = AVCaptureDevice.authorizationStatus(for: .video)
        let alreadyAuthorized = (status == .authorized)

        super.init()

        if alreadyAuthorized {
            isAuthorized = true
        }

        NotificationCenter.default.addObserver(
            forName: UIDevice.orientationDidChangeNotification,
            object: nil,
            queue: nil
        ) { [weak self] _ in
            Task { @MainActor in
                self?.updateVideoOrientation()
            }
        }
        UIDevice.current.beginGeneratingDeviceOrientationNotifications()
    }

    deinit {
        UIDevice.current.endGeneratingDeviceOrientationNotifications()
    }

    /// 権限がまだ未確定の場合にダイアログ表示し、カメラセットアップを行う
    func requestAuthorizationAndSetup() async {
        if !isAuthorized {
            switch AVCaptureDevice.authorizationStatus(for: .video) {
            case .authorized:
                isAuthorized = true
            case .notDetermined:
                isAuthorized = await AVCaptureDevice.requestAccess(for: .video)
            default:
                isAuthorized = false
            }
        }

        if isAuthorized {
            await setupCamera()
        }
    }

    private func setupCamera() async {
        await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
            sessionQueue.async { [weak self] in
                guard let self = self else {
                    continuation.resume()
                    return
                }

                let session = self.captureSession
                let vOutput = self.videoOutput
                let pOutput = self.photoOutput

                session.beginConfiguration()
                session.sessionPreset = .high

                guard let videoDevice = AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: .back),
                      let videoInput = try? AVCaptureDeviceInput(device: videoDevice) else {
                    session.commitConfiguration()
                    continuation.resume()
                    return
                }

                if session.canAddInput(videoInput) {
                    session.addInput(videoInput)
                }

                self.videoDevice = videoDevice
                let maxZoom = min(videoDevice.activeFormat.videoMaxZoomFactor, 10.0)
                Task { @MainActor in
                    self.maxZoomFactor = maxZoom
                }

                vOutput.videoSettings = [
                    kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA
                ]
                vOutput.setSampleBufferDelegate(self, queue: self.sessionQueue)

                if session.canAddOutput(vOutput) {
                    session.addOutput(vOutput)
                }

                if session.canAddOutput(pOutput) {
                    session.addOutput(pOutput)

                    if let maxDimensions = videoDevice.activeFormat.supportedMaxPhotoDimensions.first {
                        pOutput.maxPhotoDimensions = maxDimensions
                    }
                }

                if let connection = vOutput.connection(with: .video) {
                    connection.videoRotationAngle = 90
                }

                session.commitConfiguration()
                continuation.resume()
            }
        }
    }

    /// デバイスの向きに応じてビデオ出力の回転角度を更新
    private func updateVideoOrientation() {
        let angle: CGFloat
        switch UIDevice.current.orientation {
        case .portrait:            angle = 90
        case .portraitUpsideDown:   angle = 270
        case .landscapeLeft:        angle = 0
        case .landscapeRight:       angle = 180
        default: return
        }

        sessionQueue.async { [weak self] in
            guard let self = self else { return }
            if let connection = self.videoOutput.connection(with: .video),
               connection.isVideoRotationAngleSupported(angle) {
                connection.videoRotationAngle = angle
            }
        }
    }

    // MARK: - Zoom

    func setZoom(_ factor: CGFloat) {
        let clamped = max(1.0, min(factor, maxZoomFactor))
        sessionQueue.async { [weak self] in
            guard let self = self, let device = self.videoDevice else { return }
            do {
                try device.lockForConfiguration()
                device.videoZoomFactor = clamped
                device.unlockForConfiguration()
                Task { @MainActor in
                    self.currentZoomFactor = clamped
                }
            } catch {}
        }
    }

    func startSession() {
        sessionQueue.async { [weak self] in
            self?.captureSession.startRunning()
        }
    }

    func stopSession() {
        sessionQueue.async { [weak self] in
            self?.captureSession.stopRunning()
        }
    }

    // MARK: - Photo Capture

    /// 現在のフレームにマスクを合成してスナップショットとして保存
    func capturePhoto() {
        sessionQueue.async { [weak self] in
            guard let self = self else { return }
            // 最新のフレームを取得してマスクを合成
            Task { @MainActor in
                guard let pixelBuffer = self.currentFrame else { return }
                let image = self.createCompositeImage(from: pixelBuffer, mask: self._currentMaskSnapshot)
                if let image = image {
                    self.capturedImage = image
                    self.saveToPhotoLibrary(image: image)
                }
            }
        }
    }

    /// ピクセルバッファとマスクからUIImageを生成
    private func createCompositeImage(from pixelBuffer: CVPixelBuffer, mask: CGImage?) -> UIImage? {
        let width = CVPixelBufferGetWidth(pixelBuffer)
        let height = CVPixelBufferGetHeight(pixelBuffer)

        CVPixelBufferLockBaseAddress(pixelBuffer, .readOnly)
        defer { CVPixelBufferUnlockBaseAddress(pixelBuffer, .readOnly) }

        guard let baseAddress = CVPixelBufferGetBaseAddress(pixelBuffer) else { return nil }
        let bytesPerRow = CVPixelBufferGetBytesPerRow(pixelBuffer)
        let colorSpace = CGColorSpaceCreateDeviceRGB()

        guard let context = CGContext(
            data: nil,
            width: width,
            height: height,
            bitsPerComponent: 8,
            bytesPerRow: width * 4,
            space: colorSpace,
            bitmapInfo: CGBitmapInfo.byteOrder32Big.rawValue | CGImageAlphaInfo.premultipliedLast.rawValue
        ) else { return nil }

        // BGRAソースからRGBAに変換しながら描画
        guard let srcContext = CGContext(
            data: baseAddress,
            width: width,
            height: height,
            bitsPerComponent: 8,
            bytesPerRow: bytesPerRow,
            space: colorSpace,
            bitmapInfo: CGBitmapInfo.byteOrder32Little.rawValue | CGImageAlphaInfo.premultipliedFirst.rawValue
        ), let srcImage = srcContext.makeImage() else { return nil }

        context.draw(srcImage, in: CGRect(x: 0, y: 0, width: width, height: height))

        // マスクを上に描画
        if let mask = mask {
            context.draw(mask, in: CGRect(x: 0, y: 0, width: width, height: height))
        }

        guard let cgImage = context.makeImage() else { return nil }
        return UIImage(cgImage: cgImage)
    }

    // MARK: - Video Recording (AVAssetWriter)

    func startRecording() {
        guard !_isRecordingFlag else { return }

        let outputURL = createVideoFileURL()
        currentVideoURL = outputURL

        // sessionQueue上でAVAssetWriterをセットアップ
        sessionQueue.async { [weak self] in
            guard let self = self else { return }

            do {
                let writer = try AVAssetWriter(outputURL: outputURL, fileType: .mov)

                // ビデオ入力の設定（実際の解像度はフレーム受信時に確定）
                let videoSettings: [String: Any] = [
                    AVVideoCodecKey: AVVideoCodecType.h264,
                    AVVideoWidthKey: 1080,
                    AVVideoHeightKey: 1920
                ]
                let writerInput = AVAssetWriterInput(mediaType: .video, outputSettings: videoSettings)
                writerInput.expectsMediaDataInRealTime = true

                let adaptor = AVAssetWriterInputPixelBufferAdaptor(
                    assetWriterInput: writerInput,
                    sourcePixelBufferAttributes: [
                        kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA
                    ]
                )

                if writer.canAdd(writerInput) {
                    writer.add(writerInput)
                }

                self.assetWriter = writer
                self.assetWriterVideoInput = writerInput
                self.pixelBufferAdaptor = adaptor
                self.recordingStartTime = nil
                self._isRecordingFlag = true

                Task { @MainActor in
                    self.isRecording = true
                }
            } catch {
                Task { @MainActor in
                    self.error = error
                }
            }
        }
    }

    func stopRecording() {
        guard _isRecordingFlag else { return }

        sessionQueue.async { [weak self] in
            guard let self = self else { return }
            self._isRecordingFlag = false

            self.assetWriterVideoInput?.markAsFinished()
            self.assetWriter?.finishWriting { [weak self] in
                guard let self = self else { return }
                let url = self.currentVideoURL

                Task { @MainActor in
                    self.isRecording = false
                    if let url = url {
                        self.saveVideoToPhotoLibrary(url)
                    }
                }

                self.assetWriter = nil
                self.assetWriterVideoInput = nil
                self.pixelBufferAdaptor = nil
                self.recordingStartTime = nil
            }
        }
    }

    private func createVideoFileURL() -> URL {
        let documentsPath = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        let fileName = "asparagus_\(Date().timeIntervalSince1970).mov"
        return documentsPath.appendingPathComponent(fileName)
    }

    // MARK: - Composite Frame (カメラフレーム + マスクオーバーレイ)

    /// ピクセルバッファにマスク画像を合成（BGRA形式を維持）
    nonisolated private func compositeFrame(_ pixelBuffer: CVPixelBuffer, mask: CGImage?) -> CVPixelBuffer {
        guard let mask = mask else { return pixelBuffer }

        let width = CVPixelBufferGetWidth(pixelBuffer)
        let height = CVPixelBufferGetHeight(pixelBuffer)

        // 一時的なRGBAコンテキストでカメラフレーム+マスクを合成し、
        // 結果をBGRAピクセルバッファに書き戻す
        let colorSpace = CGColorSpaceCreateDeviceRGB()

        // RGBA作業用コンテキスト
        guard let rgbaContext = CGContext(
            data: nil,
            width: width,
            height: height,
            bitsPerComponent: 8,
            bytesPerRow: width * 4,
            space: colorSpace,
            bitmapInfo: CGBitmapInfo.byteOrder32Big.rawValue | CGImageAlphaInfo.premultipliedLast.rawValue
        ) else { return pixelBuffer }

        // カメラフレーム(BGRA)をCGImageとして取得
        CVPixelBufferLockBaseAddress(pixelBuffer, .readOnly)
        let baseAddress = CVPixelBufferGetBaseAddress(pixelBuffer)
        let bytesPerRow = CVPixelBufferGetBytesPerRow(pixelBuffer)

        guard let srcContext = CGContext(
            data: baseAddress,
            width: width,
            height: height,
            bitsPerComponent: 8,
            bytesPerRow: bytesPerRow,
            space: colorSpace,
            bitmapInfo: CGBitmapInfo.byteOrder32Little.rawValue | CGImageAlphaInfo.premultipliedFirst.rawValue
        ), let srcImage = srcContext.makeImage() else {
            CVPixelBufferUnlockBaseAddress(pixelBuffer, .readOnly)
            return pixelBuffer
        }
        CVPixelBufferUnlockBaseAddress(pixelBuffer, .readOnly)

        // RGBAコンテキストにカメラフレームを描画
        let rect = CGRect(x: 0, y: 0, width: width, height: height)
        rgbaContext.draw(srcImage, in: rect)

        // マスクを上に描画
        rgbaContext.draw(mask, in: rect)

        // 結果をBGRAピクセルバッファに書き戻す
        guard let compositeImage = rgbaContext.makeImage() else { return pixelBuffer }

        CVPixelBufferLockBaseAddress(pixelBuffer, [])
        defer { CVPixelBufferUnlockBaseAddress(pixelBuffer, []) }

        guard let dstAddress = CVPixelBufferGetBaseAddress(pixelBuffer) else { return pixelBuffer }
        guard let dstContext = CGContext(
            data: dstAddress,
            width: width,
            height: height,
            bitsPerComponent: 8,
            bytesPerRow: bytesPerRow,
            space: colorSpace,
            bitmapInfo: CGBitmapInfo.byteOrder32Little.rawValue | CGImageAlphaInfo.premultipliedFirst.rawValue
        ) else { return pixelBuffer }

        dstContext.draw(compositeImage, in: rect)

        return pixelBuffer
    }

    // MARK: - Save to Photo Library

    func saveToPhotoLibrary(image: UIImage) {
        UIImageWriteToSavedPhotosAlbum(image, nil, nil, nil)
    }

    func saveVideoToPhotoLibrary(_ videoURL: URL) {
        UISaveVideoAtPathToSavedPhotosAlbum(videoURL.path, nil, nil, nil)
    }
}

// MARK: - Photo Capture Delegate (unused, kept for compatibility)

extension CameraManager: AVCapturePhotoCaptureDelegate {
    nonisolated func photoOutput(_ output: AVCapturePhotoOutput, didFinishProcessingPhoto photo: AVCapturePhoto, error: Error?) {
        // Not used - capturePhoto() now creates composite images directly
    }
}

// MARK: - Video Data Output Delegate

extension CameraManager: AVCaptureVideoDataOutputSampleBufferDelegate {
    nonisolated func captureOutput(_ output: AVCaptureOutput, didOutput sampleBuffer: CMSampleBuffer, from connection: AVCaptureConnection) {
        guard let pixelBuffer = CMSampleBufferGetImageBuffer(sampleBuffer) else {
            return
        }

        // 解像度を更新（初回のみ）
        let w = CVPixelBufferGetWidth(pixelBuffer)
        let h = CVPixelBufferGetHeight(pixelBuffer)

        // MainActorにフレームを送信
        Task { @MainActor in
            if Int(self.videoResolution.width) != w || Int(self.videoResolution.height) != h {
                self.videoResolution = CGSize(width: w, height: h)
            }
            self.currentFrame = pixelBuffer
        }

        // 録画中ならフレームを書き込み
        guard _isRecordingFlag,
              let writer = assetWriter,
              let input = assetWriterVideoInput,
              let adaptor = pixelBufferAdaptor else { return }

        let timestamp = CMSampleBufferGetPresentationTimeStamp(sampleBuffer)

        // 初回フレームでwriter開始
        if recordingStartTime == nil {
            recordingStartTime = timestamp
            writer.startWriting()
            writer.startSession(atSourceTime: timestamp)
        }

        guard input.isReadyForMoreMediaData else { return }

        // マスクを合成してフレームを書き込み
        let maskSnapshot = _currentMaskSnapshot
        let composited = compositeFrame(pixelBuffer, mask: maskSnapshot)
        adaptor.append(composited, withPresentationTime: timestamp)
    }
}
