//
//  SegmentationOverlayView.swift
//  aspa-camera
//
//  Created by Takashi Otsuka on 2026/02/10.
//

import SwiftUI

struct SegmentationOverlayView: View {
    let result: SegmentationResult?
    let frameSize: CGSize
    var deviceOrientation: UIDeviceOrientation = .portrait

    var body: some View {
        GeometryReader { geometry in
            ZStack {
                if let result = result {
                    let positions = DetectionLabelLayout.resolvePositions(
                        detections: result.detections,
                        viewSize: geometry.size
                    )
                    ForEach(Array(result.detections.enumerated()), id: \.offset) { index, detection in
                        DetectionBoxView(
                            detection: detection,
                            frameSize: frameSize,
                            deviceOrientation: deviceOrientation,
                            labelCenter: positions[index].center,
                            boxRect: positions[index].boxRect
                        )
                    }
                }
            }
        }
    }
}

struct DetectionBoxView: View {
    let detection: SegmentationResult.Detection
    let frameSize: CGSize
    var deviceOrientation: UIDeviceOrientation = .portrait
    var labelCenter: CGPoint? = nil
    var boxRect: CGRect? = nil
    @State private var showDetailedInfo = false

    private var labelRotation: Angle {
        switch deviceOrientation {
        case .landscapeLeft:
            return .degrees(90)
        case .landscapeRight:
            return .degrees(-90)
        case .portraitUpsideDown:
            return .degrees(180)
        default:
            return .degrees(0)
        }
    }
    
    var body: some View {
        GeometryReader { geometry in
            let rect = boxRect ?? convertBoundingBox(detection.boundingBox, to: geometry.size)
            let classType = AsparagusClass(rawValue: detection.classIndex)
            let center = labelCenter ?? CGPoint(x: rect.midX, y: rect.midY)

            ZStack(alignment: .topLeading) {
                // 引き出し線（ラベルが移動された場合のみ）
                if abs(center.x - rect.midX) > 2 || abs(center.y - rect.midY) > 2 {
                    Path { path in
                        path.move(to: CGPoint(x: rect.midX, y: rect.midY))
                        path.addLine(to: center)
                    }
                    .stroke(Color.white.opacity(0.8), lineWidth: 1.5)
                }

                // タップ領域（透明）
                Color.clear
                    .frame(width: rect.width, height: rect.height)
                    .position(x: rect.midX, y: rect.midY)
                    .contentShape(Rectangle())
                    .onTapGesture {
                        showDetailedInfo.toggle()
                    }

                // ラベル
                if let classType = classType {
                    VStack(spacing: 2) {
                        Text(classType.name)
                            .font(.caption)
                            .fontWeight(.bold)

                        Text("\(Int(detection.confidence * 100))%")
                            .font(.caption2)
                    }
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(Color(classType.color))
                    .foregroundColor(.white)
                    .cornerRadius(6)
                    .shadow(radius: 2)
                    .rotationEffect(labelRotation)
                    .animation(.easeInOut(duration: 0.3), value: deviceOrientation.rawValue)
                    .position(x: center.x, y: center.y)

                    // 詳細情報（検出エリア内）
                    if showDetailedInfo {
                        VStack(alignment: .leading, spacing: 4) {
                            HStack {
                                Image(systemName: classType.iconName)
                                    .font(.title3)
                                Text(classType.name)
                                    .font(.headline)
                            }

                            Divider()
                                .background(Color.white)

                            InfoRow(label: "信頼度", value: String(format: "%.1f%%", detection.confidence * 100))
                            InfoRow(label: "クラス", value: "Class \(detection.classIndex)")

                            if let size = calculateAreaSize(rect) {
                                InfoRow(label: "面積", value: size)
                            }

                            if let description = classType.detailedDescription {
                                Text(description)
                                    .font(.caption2)
                                    .foregroundColor(.white.opacity(0.9))
                                    .padding(.top, 2)
                            }
                        }
                        .padding(8)
                        .background(Color(classType.color).opacity(0.95))
                        .foregroundColor(.white)
                        .cornerRadius(8)
                        .shadow(radius: 4)
                        .frame(maxWidth: max(50, rect.width - 16))
                        .rotationEffect(labelRotation)
                        .animation(.easeInOut(duration: 0.3), value: deviceOrientation.rawValue)
                        .position(x: center.x, y: center.y)
                    }
                }
            }
        }
    }
    
    private func convertBoundingBox(_ box: CGRect, to size: CGSize) -> CGRect {
        // 無効な値をチェック
        guard box.width > 0, box.height > 0,
              box.minX.isFinite, box.minY.isFinite,
              box.width.isFinite, box.height.isFinite else {
            print("⚠️ 無効なバウンディングボックス: \(box)")
            return CGRect(x: 0, y: 0, width: 1, height: 1)
        }
        
        // 正規化された座標を実際のピクセル座標に変換
        // YOLOの出力は正規化されている（0.0〜1.0）
        let x = max(0, min(1, box.minX)) * size.width
        let y = max(0, min(1, box.minY)) * size.height
        let w = max(0, min(1, box.width)) * size.width
        let h = max(0, min(1, box.height)) * size.height
        
        return CGRect(
            x: x,
            y: y,
            width: w,
            height: h
        )
    }
    
    private func calculateAreaSize(_ rect: CGRect) -> String? {
        let area = Int(rect.width * rect.height)
        if area > 10000 {
            return "大"
        } else if area > 5000 {
            return "中"
        } else {
            return "小"
        }
    }
}

// 情報行のヘルパービュー
struct InfoRow: View {
    let label: String
    let value: String
    
    var body: some View {
        HStack {
            Text(label + ":")
                .font(.caption)
                .fontWeight(.semibold)
            Text(value)
                .font(.caption)
        }
    }
}

// マスク画像のオーバーレイ
struct MaskOverlayView: View {
    let maskImage: CGImage?
    
    var body: some View {
        if let maskImage = maskImage {
            Image(decorative: maskImage, scale: 1.0)
                .resizable()
                .opacity(0.5)
        }
    }
}

// クラスの凡例
struct ClassLegendView: View {
    @State private var isExpanded = true
    
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Button(action: { isExpanded.toggle() }) {
                HStack {
                    Text("クラス")
                        .font(.headline)
                        .foregroundColor(.white)
                    Spacer()
                    Image(systemName: isExpanded ? "chevron.up" : "chevron.down")
                        .foregroundColor(.white)
                }
                .padding(12)
                .background(Color.black.opacity(0.6))
                .cornerRadius(8)
            }
            
            if isExpanded {
                VStack(alignment: .leading, spacing: 6) {
                    ForEach(AsparagusClass.allCases, id: \.rawValue) { classType in
                        HStack(spacing: 8) {
                            Image(systemName: classType.iconName)
                                .foregroundColor(Color(classType.color))
                                .frame(width: 20)
                            
                            Text(classType.name)
                                .font(.caption)
                                .foregroundColor(.white)
                            
                            if classType.isDiseased {
                                Image(systemName: "exclamationmark.circle.fill")
                                    .font(.caption2)
                                    .foregroundColor(.red)
                            }
                        }
                    }
                    
                    Divider()
                        .background(Color.white.opacity(0.3))
                    
                    Text("💡 検出エリアをタップで詳細表示")
                        .font(.caption2)
                        .foregroundColor(.white.opacity(0.7))
                }
                .padding(12)
                .background(Color.black.opacity(0.6))
                .cornerRadius(8)
            }
        }
        .padding()
    }
}

// 検出統計ビュー
struct DetectionStatsView: View {
    let result: SegmentationResult?
    
    var body: some View {
        if let result = result {
            HStack(spacing: 16) {
                // 総検出数
                StatItem(
                    icon: "viewfinder",
                    label: "検出",
                    value: "\(result.detections.count)",
                    color: .blue
                )
                
                // 病気の数
                let diseaseCount = result.detections.filter { detection in
                    if let classType = AsparagusClass(rawValue: detection.classIndex) {
                        return classType.isDiseased
                    }
                    return false
                }.count
                
                if diseaseCount > 0 {
                    StatItem(
                        icon: "exclamationmark.triangle.fill",
                        label: "病気",
                        value: "\(diseaseCount)",
                        color: .red
                    )
                }
                
                // 健康な部分の数
                let healthyCount = result.detections.count - diseaseCount
                if healthyCount > 0 {
                    StatItem(
                        icon: "checkmark.circle.fill",
                        label: "健康",
                        value: "\(healthyCount)",
                        color: .green
                    )
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(Color.black.opacity(0.6))
            .cornerRadius(12)
            .shadow(radius: 4)
        }
    }
}

struct StatItem: View {
    let icon: String
    let label: String
    let value: String
    let color: Color
    
    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: icon)
                .foregroundColor(color)
                .font(.caption)
            
            VStack(alignment: .leading, spacing: 2) {
                Text(value)
                    .font(.headline)
                    .foregroundColor(.white)
                Text(label)
                    .font(.caption2)
                    .foregroundColor(.white.opacity(0.8))
            }
        }
    }
}

#Preview {
    ZStack {
        Color.gray
        
        VStack {
            Spacer()
            HStack {
                ClassLegendView()
                Spacer()
            }
        }
    }
}
