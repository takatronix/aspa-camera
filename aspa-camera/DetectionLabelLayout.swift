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

    /// 病気クラスのインデックス（これらの領域はラベルで隠さない）
    private static let diseaseClassIndices: Set<Int> = [3, 4, 5] // 褐斑病, 茎枯病, 斑点病

    /// 全検出のラベル位置を計算し、重なりを解消して返す
    /// ルール:
    /// - 基本はボックス中心に配置
    /// - 病気領域と重なる場合のみ移動（植物体は重なってOK）
    /// - 他のラベルと重なる場合も移動
    nonisolated static func resolvePositions(
        detections: [SegmentationResult.Detection],
        viewSize: CGSize,
        estimatedLabelSize: CGSize = CGSize(width: 100, height: 44)
    ) -> [LabelPosition] {
        guard !detections.isEmpty else { return [] }

        let estW = estimatedLabelSize.width
        let estH = estimatedLabelSize.height
        let margin: CGFloat = 4

        // 全検出のバウンディングボックスをピクセル座標で取得
        let allBoxRects: [CGRect] = detections.map { convertBox($0.boundingBox, to: viewSize) }

        // 病気の検出領域のみ回避対象にする（ボックスを60%に縮小して近似）
        var diseaseAreas: [CGRect] = []
        for (i, det) in detections.enumerated() {
            if diseaseClassIndices.contains(det.classIndex) {
                let box = allBoxRects[i]
                let area = box.insetBy(dx: box.width * 0.2, dy: box.height * 0.2)
                diseaseAreas.append(area)
            }
        }

        // (元のindex, ラベルrect, boxRect) を作成
        var items: [(Int, CGRect, CGRect)] = detections.enumerated().map { i, det in
            let boxRect = allBoxRects[i]
            let cx = boxRect.midX
            let cy = boxRect.midY
            let labelRect = CGRect(x: cx - estW / 2, y: cy - estH / 2, width: estW, height: estH)
            return (i, labelRect, boxRect)
        }

        // Y座標でソート（上から配置）
        items.sort { $0.2.midY < $1.2.midY }

        // 配置済みラベルのリスト
        var placedLabels: [CGRect] = []

        for idx in 0..<items.count {
            let boxRect = items[idx].2
            let boxCX = boxRect.midX
            let boxCY = boxRect.midY

            // まず中心で配置を試みる
            let centerRect = CGRect(x: boxCX - estW / 2, y: boxCY - estH / 2, width: estW, height: estH)
            let centerOverlapsDisease = diseaseAreas.contains { $0.intersects(centerRect) }
            let centerExpanded = centerRect.insetBy(dx: -margin, dy: -margin)
            let centerOverlapsLabel = placedLabels.contains { $0.intersects(centerExpanded) }

            if !centerOverlapsDisease && !centerOverlapsLabel {
                // 中心に配置OK → そのまま
                items[idx].1 = centerRect
                placedLabels.append(centerRect)
                continue
            }

            // 中心がダメな場合、近い候補位置を探す
            // 小さいオフセットから試す（ボックス内にとどまるように）
            let halfH = estH * 0.6
            let halfW = estW * 0.6
            let fullH = estH + margin
            let fullW = estW + margin

            let candidates: [(CGFloat, CGFloat)] = [
                // ボックス内の微調整（中心から少しずらす）
                (boxCX + halfW, boxCY),
                (boxCX - halfW, boxCY),
                (boxCX, boxCY - halfH),
                (boxCX, boxCY + halfH),
                (boxCX + halfW, boxCY - halfH),
                (boxCX - halfW, boxCY - halfH),
                (boxCX + halfW, boxCY + halfH),
                (boxCX - halfW, boxCY + halfH),
                // もう少し離す
                (boxCX + fullW, boxCY),
                (boxCX - fullW, boxCY),
                (boxCX, boxCY - fullH),
                (boxCX, boxCY + fullH),
                (boxCX + fullW, boxCY - fullH),
                (boxCX - fullW, boxCY - fullH),
                (boxCX + fullW, boxCY + fullH),
                (boxCX - fullW, boxCY + fullH),
            ]

            var bestRect: CGRect?
            var bestDist: CGFloat = .infinity

            for (cx, cy) in candidates {
                let candidate = CGRect(
                    x: cx - estW / 2,
                    y: cy - estH / 2,
                    width: estW,
                    height: estH
                )

                // 画面内チェック
                guard candidate.minX >= 0,
                      candidate.minY >= 0,
                      candidate.maxX <= viewSize.width,
                      candidate.maxY <= viewSize.height else {
                    continue
                }

                // 病気領域との重なりチェック
                let overlapsDiseaseArea = diseaseAreas.contains { $0.intersects(candidate) }
                if overlapsDiseaseArea { continue }

                // 配置済みラベルとの重なりチェック
                let expanded = candidate.insetBy(dx: -margin, dy: -margin)
                let overlapsLabel = placedLabels.contains { $0.intersects(expanded) }
                if overlapsLabel { continue }

                let dist = hypot(cx - boxCX, cy - boxCY)
                if dist < bestDist {
                    bestDist = dist
                    bestRect = candidate
                }
            }

            // どの候補もダメな場合、中心に配置（最悪重なってもOK）
            if bestRect == nil {
                bestRect = centerRect
            }

            items[idx].1 = bestRect!
            placedLabels.append(bestRect!)
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
