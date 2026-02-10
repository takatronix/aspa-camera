//
//  DetectionLabelLayout.swift
//  aspa-camera
//
//  Created by Takashi Otsuka on 2026/02/10.
//

import CoreGraphics

/// 検出ラベルの位置情報
struct LabelPosition {
    /// ラベル表示位置（中心座標）
    let center: CGPoint
    /// バウンディングボックスのピクセル座標
    let boxRect: CGRect
}

/// 検出ラベルの位置計算（ライブプレビュー・保存画像で共通使用）
enum DetectionLabelLayout {

    /// 正規化座標をピクセル座標に変換
    nonisolated static func convertBox(_ box: CGRect, to size: CGSize) -> CGRect {
        let x = clamp01(box.minX) * size.width
        let y = clamp01(box.minY) * size.height
        let w = clamp01(box.width) * size.width
        let h = clamp01(box.height) * size.height
        return CGRect(x: x, y: y, width: w, height: h)
    }

    /// 全検出のラベル位置を計算し、重なりを解消して返す
    /// - Parameters:
    ///   - detections: 検出結果の配列
    ///   - viewSize: 描画先のサイズ（ピクセル）
    ///   - estimatedLabelSize: ラベルの推定サイズ
    /// - Returns: 各検出に対応する `LabelPosition` の配列（入力と同じ順序）
    nonisolated static func resolvePositions(
        detections: [SegmentationResult.Detection],
        viewSize: CGSize,
        estimatedLabelSize: CGSize = CGSize(width: 90, height: 36)
    ) -> [LabelPosition] {
        guard !detections.isEmpty else { return [] }

        let estW = estimatedLabelSize.width
        let estH = estimatedLabelSize.height

        // (元のindex, ラベルrect, boxRect) を作成
        var items: [(Int, CGRect, CGRect)] = detections.enumerated().map { i, det in
            let boxRect = convertBox(det.boundingBox, to: viewSize)
            let cx = boxRect.midX
            let cy = boxRect.midY
            let labelRect = CGRect(x: cx - estW / 2, y: cy - estH / 2, width: estW, height: estH)
            return (i, labelRect, boxRect)
        }

        // Y座標でソート
        items.sort { $0.1.midY < $1.1.midY }

        // 重なりを解消（上から順に配置）
        var placed: [CGRect] = []
        for idx in 0..<items.count {
            var rect = items[idx].1
            for p in placed {
                if rect.intersects(p) {
                    rect.origin.y = p.maxY + 4
                }
            }
            items[idx].1 = rect
            placed.append(rect)
        }

        // 元の順序で結果を返す
        var result = [LabelPosition](repeating: LabelPosition(center: .zero, boxRect: .zero), count: detections.count)
        for (origIdx, labelRect, boxRect) in items {
            result[origIdx] = LabelPosition(
                center: CGPoint(x: labelRect.midX, y: labelRect.midY),
                boxRect: boxRect
            )
        }
        return result
    }

    nonisolated private static func clamp01(_ v: CGFloat) -> CGFloat {
        max(0, min(1, v))
    }
}
