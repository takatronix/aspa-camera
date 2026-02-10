//
//
//  YOLOSegmentationModel.swift
//  aspa-camera
//
//  Created by Takashi Otsuka on 2026/02/10.
//

import Foundation
import CoreML
@preconcurrency import Vision
import CoreImage
import Combine

#if canImport(UIKit)
import UIKit
#elseif canImport(AppKit)
import AppKit
#endif

// セグメンテーションクラス
enum AsparagusClass: Int, CaseIterable {
    case mainStem = 0      // 親茎
    case asparagus = 1     // アスパラガス
    case branch = 2        // 枝
    case brownSpot = 3     // 褐斑病
    case stemBlight = 4    // 茎枯病
    case leafSpot = 5      // 斑点病
    
    var name: String {
        switch self {
        case .mainStem: return "親茎"
        case .asparagus: return "アスパラガス"
        case .branch: return "枝"
        case .brownSpot: return "褐斑病"
        case .stemBlight: return "茎枯病"
        case .leafSpot: return "斑点病"
        }
    }
    
    var color: UIColor {
        switch self {
        case .mainStem: return .systemGreen
        case .asparagus: return .systemBlue
        case .branch: return .systemBrown
        case .brownSpot: return .systemOrange
        case .stemBlight: return .systemRed
        case .leafSpot: return .systemYellow
        }
    }
    
    var iconName: String {
        switch self {
        case .mainStem: return "leaf.fill"
        case .asparagus: return "camera.macro"
        case .branch: return "arrow.branch"
        case .brownSpot: return "exclamationmark.triangle.fill"
        case .stemBlight: return "exclamationmark.circle.fill"
        case .leafSpot: return "exclamationmark.bubble.fill"
        }
    }
    
    var detailedDescription: String? {
        switch self {
        case .mainStem:
            return "健康な主要茎"
        case .asparagus:
            return "成長中のアスパラガス"
        case .branch:
            return "側枝・分岐部"
        case .brownSpot:
            return "⚠️ 褐色の斑点が特徴。早期対処が必要"
        case .stemBlight:
            return "⚠️ 茎の枯死。感染拡大に注意"
        case .leafSpot:
            return "⚠️ 葉の斑点病変。治療を推奨"
        }
    }
    
    var isDiseased: Bool {
        switch self {
        case .brownSpot, .stemBlight, .leafSpot:
            return true
        default:
            return false
        }
    }
}

// セグメンテーション結果
struct SegmentationResult {
    let maskImage: CGImage?
    let detections: [Detection]
    let inferenceTime: TimeInterval // 推論時間（秒）
    let fps: Double // フレームレート
    
    struct Detection {
        let classIndex: Int
        let confidence: Float
        let boundingBox: CGRect
        let maskCoefficients: [Float]?
    }
}

@MainActor
class YOLOSegmentationModel: ObservableObject {
    @Published var currentResult: SegmentationResult?
    @Published var isProcessing = false
    @Published var averageFPS: Double = 0.0
    @Published var averageInferenceTime: TimeInterval = 0.0
    @Published var isModelLoaded = false
    @Published var confidenceThreshold: Float = 0.25
    /// 病害虫をアスパラ/親茎と重なるもののみ表示
    @Published var diseaseOverlapOnly: Bool = true

    private var model: VNCoreMLModel?
    private var frameCount = 0
    private var lastFrameTime = Date()
    private var fpsHistory: [Double] = []
    private var inferenceTimeHistory: [TimeInterval] = []
    private let maxHistorySize = 30
    private let processingQueue = DispatchQueue(label: "yolo.processing.queue", qos: .userInitiated)

    /// CameraViewの.taskから呼ぶ
    func loadModel() async {
        let modelNames = [
            "aspara-v3-b1",
            "best",
            "yolo11seg",
            "yolo11seg_small",
            "yolo11seg-small",
            "asparagus_model",
            "model"
        ]

        let extensions = ["mlpackage", "mlmodelc", "mlmodel"]

        // バックグラウンドスレッドでモデルを読み込み
        let result: VNCoreMLModel? = await Task.detached {
            for modelName in modelNames {
                for ext in extensions {
                    if let modelURL = Bundle.main.url(forResource: modelName, withExtension: ext) {
                        do {
                            let config = MLModelConfiguration()
                            config.computeUnits = .all

                            let mlModel = try MLModel(contentsOf: modelURL, configuration: config)
                            let visionModel = try VNCoreMLModel(for: mlModel)
                            visionModel.inputImageFeatureName = "image"
                            visionModel.featureProvider = nil

                            print("✅ モデル読み込み成功: \(modelName).\(ext)")
                            return visionModel
                        } catch {
                            print("❌ モデル読み込み失敗 (\(modelName).\(ext)): \(error.localizedDescription)")
                        }
                    }
                }
            }
            print("⚠️ モデルが見つかりません。ダミーデータモードで動作します")
            return nil
        }.value

        if let visionModel = result {
            self.model = visionModel
            self.isModelLoaded = true
            print("✅ モデル準備完了")
        } else {
            print("⚠️ モデル読み込み結果: nil")
        }
    }
    
    func processFrame(_ pixelBuffer: CVPixelBuffer) {
        guard !isProcessing else { return }
        guard let model = model else {
            // モデルがない場合はダミーデータを生成
            generateDummyResult()
            return
        }
        
        isProcessing = true
        let startTime = Date()
        
        let request = VNCoreMLRequest(model: model) { [weak self] request, error in
            guard let self = self else { return }
            
            let inferenceTime = Date().timeIntervalSince(startTime)
            
            if let error = error {
                print("推論エラー: \(error)")
                Task { @MainActor in
                    self.isProcessing = false
                }
                return
            }
            
            Task { @MainActor in
                await self.processResults(request.results, inferenceTime: inferenceTime)
            }
        }
        
        request.imageCropAndScaleOption = .scaleFill
        
        Task.detached { [weak self] in
            let handler = VNImageRequestHandler(cvPixelBuffer: pixelBuffer, options: [:])
            try? handler.perform([request])
            
            await MainActor.run {
                self?.isProcessing = false
            }
        }
    }
    
    private func processResults(_ results: [Any]?, inferenceTime: TimeInterval) async {
        guard let results = results else {
            let fps = calculateFPS()
            updateMetrics(inferenceTime: inferenceTime, fps: fps)
            
            self.currentResult = SegmentationResult(
                maskImage: nil,
                detections: [],
                inferenceTime: inferenceTime,
                fps: fps
            )
            return
        }
        
        var detections: [SegmentationResult.Detection] = []
        var maskArray: MLMultiArray?
        
        for result in results {
            if let observation = result as? VNCoreMLFeatureValueObservation {
                if let multiArray = observation.featureValue.multiArrayValue {
                    let shape = multiArray.shape.map { $0.intValue }

                    if shape.count == 3 && shape[2] == 8400 {
                        detections.append(contentsOf: parseYOLOOutput(multiArray))
                    } else if shape.count == 4 {
                        maskArray = multiArray
                    }
                }
            }
        }
        
        // セグメンテーションマスクを画像に変換
        let maskImage = maskArray != nil ? createMaskImage(from: maskArray!, detections: detections) : nil
        
        let fps = calculateFPS()
        updateMetrics(inferenceTime: inferenceTime, fps: fps)
        
        self.currentResult = SegmentationResult(
            maskImage: maskImage,
            detections: detections,
            inferenceTime: inferenceTime,
            fps: fps
        )
    }
    
    private func parseYOLOOutput(_ multiArray: MLMultiArray) -> [SegmentationResult.Detection] {
        var detections: [SegmentationResult.Detection] = []
        
        let shape = multiArray.shape.map { $0.intValue }

        if shape.count == 3 {
            let numFeatures = shape[1]
            let numAnchors = shape[2]
            let numClasses = numFeatures - 4 - 32
            let actualClasses = max(numClasses, 6)
            
            // トランスポーズして処理: [1, 42, 8400] -> 各アンカーを走査
            for i in 0..<numAnchors {
                // バウンディングボックス (中心x, 中心y, 幅, 高さ)
                let cx = multiArray[[0, 0, i] as [NSNumber]].floatValue
                let cy = multiArray[[0, 1, i] as [NSNumber]].floatValue
                let w = multiArray[[0, 2, i] as [NSNumber]].floatValue
                let h = multiArray[[0, 3, i] as [NSNumber]].floatValue
                
                // クラススコア（4番目から）
                var maxScore: Float = 0
                var maxClass = 0
                
                // クラススコアをチェック
                for c in 0..<min(actualClasses, numFeatures - 4) {
                    let score = multiArray[[0, 4 + c, i] as [NSNumber]].floatValue
                    if score > maxScore {
                        maxScore = score
                        maxClass = c
                    }
                }
                
                // 信頼度フィルター
                guard maxScore > confidenceThreshold else { continue }
                
                // 座標を正規化 (0-640 -> 0-1)
                let x = (cx - w / 2) / 640.0
                let y = (cy - h / 2) / 640.0
                let normW = w / 640.0
                let normH = h / 640.0
                
                // マスク係数を抽出 (4+numClasses以降の32個)
                let maskStart = 4 + actualClasses
                var coefficients: [Float]? = nil
                if maskStart + 32 <= numFeatures {
                    coefficients = (0..<32).map { j in
                        multiArray[[0, maskStart + j, i] as [NSNumber]].floatValue
                    }
                }

                let detection = SegmentationResult.Detection(
                    classIndex: maxClass,
                    confidence: maxScore,
                    boundingBox: CGRect(
                        x: CGFloat(max(0, min(1, x))),
                        y: CGFloat(max(0, min(1, y))),
                        width: CGFloat(max(0, min(1, normW))),
                        height: CGFloat(max(0, min(1, normH)))
                    ),
                    maskCoefficients: coefficients
                )
                
                detections.append(detection)
                
                // 最大100個まで
                if detections.count >= 100 { break }
            }
        }
        
        var result = applyNMS(detections, iouThreshold: 0.5)
        if diseaseOverlapOnly {
            result = filterDiseaseByOverlap(result)
        }
        return result
    }

    /// 病害虫検出をアスパラガス/親茎と重なるもののみに絞る
    private func filterDiseaseByOverlap(_ detections: [SegmentationResult.Detection]) -> [SegmentationResult.Detection] {
        // 親茎(0)、アスパラガス(1)、枝(2)のバウンディングボックスを収集
        let plantBoxes = detections.compactMap { d -> CGRect? in
            guard d.classIndex == AsparagusClass.mainStem.rawValue ||
                  d.classIndex == AsparagusClass.asparagus.rawValue ||
                  d.classIndex == AsparagusClass.branch.rawValue else { return nil }
            return d.boundingBox
        }

        return detections.filter { d in
            guard let cls = AsparagusClass(rawValue: d.classIndex), cls.isDiseased else {
                return true // 非病害虫はそのまま通す
            }
            // いずれかの植物体と重なっているか
            return plantBoxes.contains { $0.intersects(d.boundingBox) }
        }
    }

    /// Non-Maximum Suppression: IoUが閾値を超える重複検出を除去
    private func applyNMS(_ detections: [SegmentationResult.Detection], iouThreshold: Float) -> [SegmentationResult.Detection] {
        guard !detections.isEmpty else { return [] }

        // 信頼度の高い順にソート
        let sorted = detections.sorted { $0.confidence > $1.confidence }
        var kept: [SegmentationResult.Detection] = []
        var suppressed = [Bool](repeating: false, count: sorted.count)

        for i in 0..<sorted.count {
            guard !suppressed[i] else { continue }
            kept.append(sorted[i])

            for j in (i + 1)..<sorted.count {
                guard !suppressed[j] else { continue }
                // 同じクラスのみ抑制
                guard sorted[i].classIndex == sorted[j].classIndex else { continue }

                let iou = calculateIoU(sorted[i].boundingBox, sorted[j].boundingBox)
                if iou > CGFloat(iouThreshold) {
                    suppressed[j] = true
                }
            }
        }

        return kept
    }

    private func calculateIoU(_ a: CGRect, _ b: CGRect) -> CGFloat {
        let intersection = a.intersection(b)
        guard !intersection.isNull else { return 0 }
        let intersectionArea = intersection.width * intersection.height
        let unionArea = a.width * a.height + b.width * b.height - intersectionArea
        guard unionArea > 0 else { return 0 }
        return intersectionArea / unionArea
    }

    private func calculateFPS() -> Double {
        let now = Date()
        let timeDiff = now.timeIntervalSince(lastFrameTime)
        lastFrameTime = now
        
        guard timeDiff > 0 else { return 0 }
        return 1.0 / timeDiff
    }
    
    private func updateMetrics(inferenceTime: TimeInterval, fps: Double) {
        // FPS履歴を更新
        fpsHistory.append(fps)
        if fpsHistory.count > maxHistorySize {
            fpsHistory.removeFirst()
        }
        
        // 推論時間履歴を更新
        inferenceTimeHistory.append(inferenceTime)
        if inferenceTimeHistory.count > maxHistorySize {
            inferenceTimeHistory.removeFirst()
        }
        
        // 平均を計算
        let avgFPS = fpsHistory.reduce(0, +) / Double(fpsHistory.count)
        let avgInference = inferenceTimeHistory.reduce(0, +) / Double(inferenceTimeHistory.count)
        
        Task { @MainActor in
            self.averageFPS = avgFPS
            self.averageInferenceTime = avgInference
        }
    }
    
    // デバッグ用のダミーデータ生成
    private func generateDummyResult() {
        let detections: [SegmentationResult.Detection] = [
            .init(classIndex: 0, confidence: 0.95, boundingBox: CGRect(x: 0.2, y: 0.3, width: 0.3, height: 0.4), maskCoefficients: nil),
            .init(classIndex: 3, confidence: 0.85, boundingBox: CGRect(x: 0.5, y: 0.2, width: 0.2, height: 0.3), maskCoefficients: nil)
        ]
        
        // ダミーの推論時間をシミュレート（20-40ms）
        let inferenceTime = Double.random(in: 0.020...0.040)
        let fps = calculateFPS()
        updateMetrics(inferenceTime: inferenceTime, fps: fps)
              
        
        self.currentResult = SegmentationResult(
            maskImage: nil,
            detections: detections,
            inferenceTime: inferenceTime,
            fps: fps
        )
    }
    
    // セグメンテーションマスクを生成
    // マスクプロトタイプ [1, 32, H, W] と各検出のマスク係数 [32] を線形結合 → sigmoid
    private func createMaskImage(from protoArray: MLMultiArray, detections: [SegmentationResult.Detection]) -> CGImage? {
        let shape = protoArray.shape.map { $0.intValue }
        // マスクプロトタイプは [1, 32, 160, 160]
        guard shape.count == 4 else { return nil }

        let numProtos = shape[1]  // 32
        let maskH = shape[2]      // 160
        let maskW = shape[3]      // 160

        // RGBA画像バッファ (maskW x maskH)
        var pixels = [UInt8](repeating: 0, count: maskW * maskH * 4)

        // MLMultiArrayのストライドを取得（パディング対応）
        let strides = protoArray.strides.map { $0.intValue }
        let protoStride = strides[1]  // プロトタイプ間のストライド
        let rowStride = strides[2]    // 行間のストライド
        let colStride = strides[3]    // 列間のストライド
        let protoPtr = protoArray.dataPointer.bindMemory(
            to: Float.self,
            capacity: strides[0] * shape[0]
        )

        for detection in detections {
            guard let coeffs = detection.maskCoefficients, coeffs.count == numProtos else { continue }
            guard let classType = AsparagusClass(rawValue: detection.classIndex) else { continue }

            let color = classType.color
            var r: CGFloat = 0, g: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
            color.getRed(&r, green: &g, blue: &b, alpha: &a)
            let cr = UInt8(r * 255)
            let cg = UInt8(g * 255)
            let cb = UInt8(b * 255)

            // バウンディングボックスをマスク座標系に変換
            let bx0 = max(0, Int(detection.boundingBox.minX * CGFloat(maskW)))
            let by0 = max(0, Int(detection.boundingBox.minY * CGFloat(maskH)))
            let bx1 = min(maskW, Int(detection.boundingBox.maxX * CGFloat(maskW)))
            let by1 = min(maskH, Int(detection.boundingBox.maxY * CGFloat(maskH)))

            // bounding box 内のみ計算（高速化）
            for py in by0..<by1 {
                for px in bx0..<bx1 {
                    // 線形結合: sum(coeff_j * proto[j][py][px])
                    // ストライドを使って正しいメモリ位置にアクセス
                    var sum: Float = 0
                    let rowOffset = py * rowStride + px * colStride
                    for j in 0..<numProtos {
                        sum += coeffs[j] * protoPtr[j * protoStride + rowOffset]
                    }
                    // sigmoid
                    let prob = 1.0 / (1.0 + exp(-sum))
                    if prob > 0.5 {
                        let idx = (py * maskW + px) * 4
                        pixels[idx]     = cr
                        pixels[idx + 1] = cg
                        pixels[idx + 2] = cb
                        pixels[idx + 3] = 160 // 半透明
                    }
                }
            }
        }

        // CGImage を生成
        let colorSpace = CGColorSpaceCreateDeviceRGB()
        guard let context = CGContext(
            data: &pixels,
            width: maskW,
            height: maskH,
            bitsPerComponent: 8,
            bytesPerRow: maskW * 4,
            space: colorSpace,
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else { return nil }

        return context.makeImage()
    }
}

