//
//  CameraView.swift
//  aspa-camera
//
//  Created by Takashi Otsuka on 2026/02/10.
//

import SwiftUI
import UIKit
import Combine

struct CameraView: View {
    @StateObject private var cameraManager = CameraManager()
    @StateObject private var yoloModel = YOLOSegmentationModel()
    @State private var showingSettings = false
    @State private var showPerformanceDetails = false
    
    var body: some View {
        ZStack {
            if cameraManager.isAuthorized {
                // カメラプレビュー
                GeometryReader { geometry in
                    let viewSize = geometry.size
                    let videoSize = cameraManager.videoResolution
                    // AspectFillと同じスケール計算
                    let scaleX = viewSize.width / videoSize.width
                    let scaleY = viewSize.height / videoSize.height
                    let fillScale = max(scaleX, scaleY)
                    let scaledW = videoSize.width * fillScale
                    let scaledH = videoSize.height * fillScale

                    ZStack {
                        CameraPreviewView(previewLayer: cameraManager.previewLayer)

                        // オーバーレイをAspectFillに合わせたサイズで中央配置
                        ZStack {
                            // セグメンテーションオーバーレイ
                            SegmentationOverlayView(
                                result: yoloModel.currentResult,
                                frameSize: CGSize(width: scaledW, height: scaledH)
                            )

                            // マスクオーバーレイ
                            if let maskImage = yoloModel.currentResult?.maskImage {
                                MaskOverlayView(maskImage: maskImage)
                            }
                        }
                        .frame(width: scaledW, height: scaledH)
                    }
                    .clipped()
                }
                .edgesIgnoringSafeArea(.all)
                
                // モデル読み込み中の表示
                if !yoloModel.isModelLoaded {
                    VStack(spacing: 12) {
                        ProgressView()
                            .scaleEffect(1.5)
                            .tint(.white)
                        Text("モデルを読み込み中...")
                            .font(.callout)
                            .foregroundColor(.white)
                    }
                    .padding(24)
                    .background(Color.black.opacity(0.7))
                    .cornerRadius(16)
                }

                // UI オーバーレイ
                VStack(spacing: 0) {
                    // トップバー
                    HStack {
                        // 録画インジケーター
                        if cameraManager.isRecording {
                            RecordingIndicatorView(isRecording: cameraManager.isRecording)
                        }

                        Spacer()

                        // パフォーマンス表示
                        if let result = yoloModel.currentResult {
                            PerformanceMetricsView(
                                inferenceTime: result.inferenceTime,
                                fps: result.fps
                            )
                        }
                        
                        Spacer()
                        
                        Button(action: { showingSettings.toggle() }) {
                            Image(systemName: "gear")
                                .font(.title2)
                                .foregroundColor(.white)
                                .padding(12)
                                .background(Color.black.opacity(0.6))
                                .clipShape(Circle())
                        }
                    }
                    .padding()
                    
                    Spacer()
                    
                    // 凡例とパフォーマンス詳細
                    VStack(alignment: .leading, spacing: 12) {
                        HStack(alignment: .top) {
                            ClassLegendView()
                            Spacer()
                            DetailedPerformanceView(
                                result: yoloModel.currentResult,
                                averageFPS: yoloModel.averageFPS,
                                averageInferenceTime: yoloModel.averageInferenceTime
                            )
                            .frame(maxWidth: 200)
                        }
                        
                        // 統計情報
                        DetectionStatsView(result: yoloModel.currentResult)
                            .padding(.horizontal)
                    }
                    .padding(.horizontal)
                    
                    // 撮影コントロール
                    CaptureControlsView(cameraManager: cameraManager)
                        .padding(.bottom, 20)
                }
            } else {
                // カメラ権限がない場合
                VStack(spacing: 20) {
                    Image(systemName: "camera.fill")
                        .font(.system(size: 60))
                        .foregroundColor(.gray)
                    
                    Text("カメラへのアクセスが必要です")
                        .font(.title2)
                        .fontWeight(.semibold)
                    
                    Text("設定からカメラへのアクセスを許可してください")
                        .font(.body)
                        .foregroundColor(.secondary)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal)
                    
                    Button("設定を開く") {
                        if let url = URL(string: UIApplication.openSettingsURLString) {
                            UIApplication.shared.open(url)
                        }
                    }
                    .buttonStyle(.borderedProminent)
                }
                .padding()
            }
        }
        .task {
            await cameraManager.requestAuthorizationAndSetup()
            if cameraManager.isAuthorized {
                cameraManager.startSession()
            }
        }
        .task {
            await yoloModel.loadModel()
        }
        .onDisappear {
            cameraManager.stopSession()
        }
        .onChange(of: cameraManager.currentFrame) { _, newFrame in
            if let frame = newFrame {
                yoloModel.processFrame(frame)
                // 録画用にマスク画像をCameraManagerに渡す
                cameraManager._currentMaskSnapshot = yoloModel.currentResult?.maskImage
            }
        }
        .sheet(isPresented: $showingSettings) {
            SettingsView()
                .environmentObject(yoloModel)
        }
    }
}

// 設定画面
struct SettingsView: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject var yoloModel: YOLOSegmentationModel
    
    var body: some View {
        NavigationStack {
            Form {
                Section("モデル情報") {
                    HStack {
                        Text("モデルステータス")
                        Spacer()
                        if yoloModel.isModelLoaded {
                            Label("読み込み済み", systemImage: "checkmark.circle.fill")
                                .foregroundColor(.green)
                        } else {
                            Label("未読み込み", systemImage: "xmark.circle.fill")
                                .foregroundColor(.red)
                        }
                    }
                    
                    // ビルド設定チェックへのリンク
                    NavigationLink(destination: BuildCheckView()) {
                        HStack {
                            Image(systemName: "wrench.and.screwdriver.fill")
                                .foregroundColor(.orange)
                            Text("ビルド設定を確認")
                        }
                    }
                    
                    LabeledContent("モデル", value: "aspara-v3-b1")
                    LabeledContent("クラス数", value: "6")
                    LabeledContent("入力サイズ", value: "640x640")
                    
                    if yoloModel.isModelLoaded {
                        Divider()
                        LabeledContent("平均FPS", value: String(format: "%.1f", yoloModel.averageFPS))
                        LabeledContent("平均推論時間", value: String(format: "%.1f ms", yoloModel.averageInferenceTime * 1000))
                    }
                }
                
                Section("検出設定") {
                    VStack(alignment: .leading) {
                        HStack {
                            Text("信頼度しきい値")
                            Spacer()
                            Text("\(Int(yoloModel.confidenceThreshold * 100))%")
                                .foregroundColor(.secondary)
                        }
                        Slider(value: $yoloModel.confidenceThreshold, in: 0.1...0.9, step: 0.05)
                    }

                    Toggle("病害虫はアスパラ上のみ検出", isOn: $yoloModel.diseaseOverlapOnly)
                }

                Section("検出クラス") {
                    ForEach(AsparagusClass.allCases, id: \.rawValue) { classType in
                        HStack {
                            Image(systemName: classType.iconName)
                                .foregroundColor(Color(classType.color))
                                .frame(width: 24)
                            
                            VStack(alignment: .leading, spacing: 2) {
                                Text(classType.name)
                                    .font(.body)
                                
                                if classType.isDiseased {
                                    Text("病気")
                                        .font(.caption2)
                                        .foregroundColor(.secondary)
                                }
                            }
                            
                            Spacer()
                            
                            Circle()
                                .fill(Color(classType.color))
                                .frame(width: 12, height: 12)
                        }
                    }
                }
                
                Section("機能") {
                    HStack {
                        Image(systemName: "camera.fill")
                            .foregroundColor(.blue)
                            .frame(width: 24)
                        Text("写真撮影")
                    }
                    
                    HStack {
                        Image(systemName: "video.fill")
                            .foregroundColor(.red)
                            .frame(width: 24)
                        Text("動画撮影")
                    }
                    
                    HStack {
                        Image(systemName: "speedometer")
                            .foregroundColor(.green)
                            .frame(width: 24)
                        Text("リアルタイムFPS表示")
                    }
                    
                    HStack {
                        Image(systemName: "clock.fill")
                            .foregroundColor(.orange)
                            .frame(width: 24)
                        Text("推論時間計測")
                    }
                }
                
                Section("使い方") {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("• カメラをアスパラガスに向けて検出")
                        Text("• 検出エリアをタップで詳細情報")
                        Text("• 白ボタンで写真撮影")
                        Text("• 赤ボタンで動画撮影")
                        Text("• パフォーマンス表示で速度確認")
                    }
                    .font(.caption)
                    .foregroundColor(.secondary)
                }
                
                Section("情報") {
                    LabeledContent("バージョン", value: "2.0.0")
                    LabeledContent("ビルド", value: "2026.02.10")
                }
            }
            .navigationTitle("設定")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("完了") {
                        dismiss()
                    }
                }
            }
        }
    }
}

#Preview {
    CameraView()
}
