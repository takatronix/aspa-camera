//
//  CaptureControlsView.swift
//  aspa-camera
//
//  Created by Takashi Otsuka on 2026/02/10.
//

import SwiftUI
import UIKit

struct CaptureControlsView: View {
    @ObservedObject var cameraManager: CameraManager
    @State private var showPhotoPreview = false
    
    var body: some View {
        HStack(spacing: 50) {
            // 写真撮影ボタン
            Button(action: {
                cameraManager.capturePhoto()
            }) {
                ZStack {
                    Circle()
                        .fill(Color.white)
                        .frame(width: 70, height: 70)
                    
                    Circle()
                        .strokeBorder(Color.white, lineWidth: 3)
                        .frame(width: 80, height: 80)
                }
            }
            
            // 動画撮影ボタン
            Button(action: {
                if cameraManager.isRecording {
                    cameraManager.stopRecording()
                } else {
                    cameraManager.startRecording()
                }
            }) {
                ZStack {
                    Circle()
                        .fill(cameraManager.isRecording ? Color.red : Color.white)
                        .frame(width: 70, height: 70)
                    
                    if cameraManager.isRecording {
                        RoundedRectangle(cornerRadius: 4)
                            .fill(Color.white)
                            .frame(width: 30, height: 30)
                    } else {
                        Circle()
                            .fill(Color.red)
                            .frame(width: 60, height: 60)
                    }
                    
                    Circle()
                        .strokeBorder(Color.white, lineWidth: 3)
                        .frame(width: 80, height: 80)
                }
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 20)
        .padding(.horizontal)
        .sheet(isPresented: $showPhotoPreview) {
            if let image = cameraManager.capturedImage {
                PhotoPreviewView(image: image)
            }
        }
        .onChange(of: cameraManager.capturedImage) { _, newImage in
            if newImage != nil {
                showPhotoPreview = true
            }
        }
    }
    
}

// 録画時間表示
struct RecordingIndicatorView: View {
    @State private var isBlinking = false
    @State private var recordingDuration: TimeInterval = 0
    let isRecording: Bool
    
    var body: some View {
        if isRecording {
            HStack(spacing: 8) {
                Circle()
                    .fill(Color.red)
                    .frame(width: 12, height: 12)
                    .opacity(isBlinking ? 1.0 : 0.3)
                    .animation(.easeInOut(duration: 0.8).repeatForever(autoreverses: true), value: isBlinking)
                
                Text(formatDuration(recordingDuration))
                    .font(.system(.body, design: .monospaced))
                    .fontWeight(.bold)
                    .foregroundColor(.white)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 8)
            .background(Color.black.opacity(0.7))
            .cornerRadius(20)
            .onAppear {
                isBlinking = true
                startTimer()
            }
            .onDisappear {
                isBlinking = false
            }
        }
    }
    
    private func startTimer() {
        Timer.scheduledTimer(withTimeInterval: 0.1, repeats: true) { timer in
            if !isRecording {
                timer.invalidate()
                recordingDuration = 0
            } else {
                recordingDuration += 0.1
            }
        }
    }
    
    private func formatDuration(_ duration: TimeInterval) -> String {
        let minutes = Int(duration) / 60
        let seconds = Int(duration) % 60
        let milliseconds = Int((duration.truncatingRemainder(dividingBy: 1)) * 10)
        return String(format: "%02d:%02d.%d", minutes, seconds, milliseconds)
    }
}

struct PhotoPreviewView: View {
    let image: UIImage
    @Environment(\.dismiss) private var dismiss
    
    var body: some View {
        NavigationStack {
            ZStack {
                Color.black
                    .ignoresSafeArea()
                
                Image(uiImage: image)
                    .resizable()
                    .aspectRatio(contentMode: .fit)
            }
            .navigationTitle("撮影した写真")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("閉じる") {
                        dismiss()
                    }
                }
                
                ToolbarItem(placement: .primaryAction) {
                    ShareLink(item: Image(uiImage: image), preview: SharePreview("アスパラガス検出", image: Image(uiImage: image)))
                }
            }
        }
    }
}

#Preview {
    ZStack {
        Color.black
        
        VStack {
            Spacer()
            
            RecordingIndicatorView(isRecording: true)
            
            CaptureControlsView(cameraManager: CameraManager())
        }
    }
}
