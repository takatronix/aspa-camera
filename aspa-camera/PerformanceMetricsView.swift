//
//  PerformanceMetricsView.swift
//  aspa-camera
//
//  Created by Takashi Otsuka on 2026/02/10.
//

import SwiftUI

struct PerformanceMetricsView: View {
    let inferenceTime: TimeInterval
    let fps: Double
    
    var body: some View {
        HStack(spacing: 16) {
            // 推論時間
            MetricBadge(
                icon: "clock.fill",
                label: "推論",
                value: String(format: "%.1f ms", inferenceTime * 1000),
                color: inferenceTimeColor
            )
            
            // FPS
            MetricBadge(
                icon: "speedometer",
                label: "FPS",
                value: String(format: "%.1f", fps),
                color: fpsColor
            )
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(.ultraThinMaterial)
        .cornerRadius(12)
        .shadow(radius: 4)
    }
    
    private var inferenceTimeColor: Color {
        if inferenceTime < 0.033 { // < 33ms (30fps相当)
            return .green
        } else if inferenceTime < 0.066 { // < 66ms (15fps相当)
            return .yellow
        } else {
            return .red
        }
    }
    
    private var fpsColor: Color {
        if fps >= 24 {
            return .green
        } else if fps >= 15 {
            return .yellow
        } else {
            return .red
        }
    }
}

struct MetricBadge: View {
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
                    .font(.system(.caption, design: .monospaced))
                    .fontWeight(.bold)
                    .foregroundColor(.primary)
                Text(label)
                    .font(.caption2)
                    .foregroundColor(.secondary)
            }
        }
    }
}

// 詳細なパフォーマンス情報ビュー
struct DetailedPerformanceView: View {
    let result: SegmentationResult?
    let averageFPS: Double
    let averageInferenceTime: TimeInterval
    @State private var isExpanded = false
    
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Button(action: { isExpanded.toggle() }) {
                HStack {
                    Image(systemName: "chart.xyaxis.line")
                        .foregroundColor(.white)
                    Text("パフォーマンス")
                        .font(.caption)
                        .fontWeight(.semibold)
                        .foregroundColor(.white)
                    Spacer()
                    Image(systemName: isExpanded ? "chevron.up" : "chevron.down")
                        .foregroundColor(.white)
                        .font(.caption2)
                }
                .padding(8)
                .background(Color.black.opacity(0.6))
                .cornerRadius(8)
            }
            
            if isExpanded, let result = result {
                VStack(alignment: .leading, spacing: 6) {
                    // 現在のフレーム
                    HStack {
                        Text("現在:")
                            .font(.caption2)
                            .foregroundColor(.white.opacity(0.7))
                        Spacer()
                        Text(String(format: "%.1f ms | %.1f FPS", result.inferenceTime * 1000, result.fps))
                            .font(.system(.caption2, design: .monospaced))
                            .foregroundColor(.white)
                    }
                    
                    Divider()
                        .background(Color.white.opacity(0.3))
                    
                    // 平均値
                    HStack {
                        Text("平均:")
                            .font(.caption2)
                            .foregroundColor(.white.opacity(0.7))
                        Spacer()
                        Text(String(format: "%.1f ms | %.1f FPS", averageInferenceTime * 1000, averageFPS))
                            .font(.system(.caption2, design: .monospaced))
                            .foregroundColor(.white)
                    }
                    
                    // パフォーマンス評価
                    HStack {
                        Text("評価:")
                            .font(.caption2)
                            .foregroundColor(.white.opacity(0.7))
                        Spacer()
                        PerformanceRating(fps: averageFPS)
                    }
                }
                .padding(8)
                .background(Color.black.opacity(0.6))
                .cornerRadius(8)
            }
        }
    }
}

struct PerformanceRating: View {
    let fps: Double
    
    var body: some View {
        HStack(spacing: 4) {
            if fps >= 30 {
                Image(systemName: "star.fill")
                    .foregroundColor(.green)
                Text("優秀")
                    .foregroundColor(.green)
            } else if fps >= 24 {
                Image(systemName: "star.leadinghalf.filled")
                    .foregroundColor(.yellow)
                Text("良好")
                    .foregroundColor(.yellow)
            } else if fps >= 15 {
                Image(systemName: "star")
                    .foregroundColor(.orange)
                Text("普通")
                    .foregroundColor(.orange)
            } else {
                Image(systemName: "exclamationmark.triangle")
                    .foregroundColor(.red)
                Text("低速")
                    .foregroundColor(.red)
            }
        }
        .font(.caption2)
    }
}

#Preview {
    ZStack {
        Color.black
        
        VStack(spacing: 20) {
            PerformanceMetricsView(inferenceTime: 0.025, fps: 35.5)
            
            DetailedPerformanceView(
                result: SegmentationResult(
                    maskImage: nil,
                    detections: [],
                    inferenceTime: 0.025,
                    fps: 35.5
                ),
                averageFPS: 32.1,
                averageInferenceTime: 0.028
            )
            .frame(maxWidth: 300)
        }
        .padding()
    }
}
