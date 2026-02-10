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
    
    nonisolated private let captureSession = AVCaptureSession()
    nonisolated private let videoOutput = AVCaptureVideoDataOutput()
    nonisolated private let photoOutput = AVCapturePhotoOutput()
    private var movieOutput: AVCaptureMovieFileOutput?
    nonisolated private let sessionQueue = DispatchQueue(label: "camera.session.queue")
    
    // プレビューレイヤーを保持
    nonisolated(unsafe) private(set) lazy var previewLayer: AVCaptureVideoPreviewLayer = {
        let layer = AVCaptureVideoPreviewLayer(session: captureSession)
        layer.videoGravity = .resizeAspectFill
        return layer
    }()
    
    private var currentVideoURL: URL?
    
    override init() {
        super.init()
        // デバイス回転通知を監視
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
    
    func checkAuthorization() async {
        switch AVCaptureDevice.authorizationStatus(for: .video) {
        case .authorized:
            isAuthorized = true
        case .notDetermined:
            isAuthorized = await AVCaptureDevice.requestAccess(for: .video)
        default:
            isAuthorized = false
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
                
                // nonisolatedクロージャ内なのでunsafeにアクセス
                let session = self.captureSession
                let vOutput = self.videoOutput
                let pOutput = self.photoOutput
                
                session.beginConfiguration()
                session.sessionPreset = .high
                
                // カメラデバイスの設定
                guard let videoDevice = AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: .back),
                      let videoInput = try? AVCaptureDeviceInput(device: videoDevice) else {
                    session.commitConfiguration()
                    continuation.resume()
                    return
                }
                
                if session.canAddInput(videoInput) {
                    session.addInput(videoInput)
                }
                
                // ビデオ出力の設定
                vOutput.videoSettings = [
                    kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA
                ]
                vOutput.setSampleBufferDelegate(self, queue: self.sessionQueue)
                
                if session.canAddOutput(vOutput) {
                    session.addOutput(vOutput)
                }
                
                // 写真出力の設定
                if session.canAddOutput(pOutput) {
                    session.addOutput(pOutput)
                    
                    if let maxDimensions = videoDevice.activeFormat.supportedMaxPhotoDimensions.first {
                        pOutput.maxPhotoDimensions = maxDimensions
                    }
                }
                
                // 動画出力の設定
                let movieOutput = AVCaptureMovieFileOutput()
                if session.canAddOutput(movieOutput) {
                    session.addOutput(movieOutput)
                    Task { @MainActor in
                        self.movieOutput = movieOutput
                    }
                }
                
                // 接続の設定
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
        default: return // .faceUp/.faceDown/.unknown は無視
        }

        sessionQueue.async { [weak self] in
            guard let self = self else { return }
            if let connection = self.videoOutput.connection(with: .video),
               connection.isVideoRotationAngleSupported(angle) {
                connection.videoRotationAngle = angle
            }
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
    
    func capturePhoto() {
        let codec: AVVideoCodecType
        if photoOutput.availablePhotoCodecTypes.contains(.hevc) {
            codec = .hevc
        } else if let first = photoOutput.availablePhotoCodecTypes.first {
            codec = first
        } else {
            // Fallback: use JPEG if no available list reported
            codec = .jpeg
        }
        let settings = AVCapturePhotoSettings(format: [AVVideoCodecKey: codec])
        settings.flashMode = .auto
        photoOutput.capturePhoto(with: settings, delegate: self)
    }
    
    // MARK: - Video Recording
    
    func startRecording() {
        guard let movieOutput = movieOutput, !movieOutput.isRecording else {
            return
        }
        
        let outputURL = createVideoFileURL()
        currentVideoURL = outputURL
        
        sessionQueue.async { [weak self] in
            guard let self = self else { return }
            
            if let connection = movieOutput.connection(with: .video) {
                connection.videoRotationAngle = 90 // Portrait
            }
            
            movieOutput.startRecording(to: outputURL, recordingDelegate: self)
            
            Task { @MainActor in
                self.isRecording = true
            }
        }
    }
    
    func stopRecording() {
        guard let movieOutput = movieOutput, movieOutput.isRecording else {
            return
        }
        
        sessionQueue.async {
            movieOutput.stopRecording()
        }
    }
    
    private func createVideoFileURL() -> URL {
        let documentsPath = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        let fileName = "asparagus_\(Date().timeIntervalSince1970).mov"
        return documentsPath.appendingPathComponent(fileName)
    }
    
    // MARK: - Save to Photo Library
    
    func saveToPhotoLibrary(image: UIImage) {
        UIImageWriteToSavedPhotosAlbum(image, nil, nil, nil)
    }
    
    func saveVideoToPhotoLibrary(_ videoURL: URL) {
        UISaveVideoAtPathToSavedPhotosAlbum(videoURL.path, nil, nil, nil)
    }
}

// MARK: - Photo Capture Delegate

extension CameraManager: AVCapturePhotoCaptureDelegate {
    nonisolated func photoOutput(_ output: AVCapturePhotoOutput, didFinishProcessingPhoto photo: AVCapturePhoto, error: Error?) {
        guard error == nil,
              let imageData = photo.fileDataRepresentation(),
              let image = UIImage(data: imageData) else {
            return
        }
        
        Task { @MainActor in
            self.capturedImage = image
            self.saveToPhotoLibrary(image: image)
        }
    }
}

// MARK: - Video Recording Delegate

extension CameraManager: AVCaptureFileOutputRecordingDelegate {
    nonisolated func fileOutput(_ output: AVCaptureFileOutput, didStartRecordingTo fileURL: URL, from connections: [AVCaptureConnection]) {
    }

    nonisolated func fileOutput(_ output: AVCaptureFileOutput, didFinishRecordingTo outputFileURL: URL, from connections: [AVCaptureConnection], error: Error?) {
        Task { @MainActor in
            self.isRecording = false

            if let error = error {
                self.error = error
            } else {
                self.saveVideoToPhotoLibrary(outputFileURL)
            }
        }
    }
}

extension CameraManager: AVCaptureVideoDataOutputSampleBufferDelegate {
    nonisolated func captureOutput(_ output: AVCaptureOutput, didOutput sampleBuffer: CMSampleBuffer, from connection: AVCaptureConnection) {
        guard let pixelBuffer = CMSampleBufferGetImageBuffer(sampleBuffer) else {
            return
        }
        
        // MainActorに安全に送信
        Task { @MainActor in
            self.currentFrame = pixelBuffer
        }
    }
}
