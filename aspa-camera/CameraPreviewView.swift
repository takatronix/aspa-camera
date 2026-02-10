//
//  CameraPreviewView.swift
//  aspa-camera
//
//  Created by Takashi Otsuka on 2026/02/10.
//

import SwiftUI
import AVFoundation

struct CameraPreviewView: UIViewRepresentable {
    let previewLayer: AVCaptureVideoPreviewLayer

    func makeUIView(context: Context) -> PreviewLayerView {
        let view = PreviewLayerView()
        view.backgroundColor = .black
        view.previewLayer = previewLayer

        return view
    }

    func updateUIView(_ uiView: PreviewLayerView, context: Context) {
        // フレーム更新はPreviewLayerViewが自動的に処理
    }
}

// カスタムビューでレイヤーのサイズを自動調整
class PreviewLayerView: UIView {
    var previewLayer: AVCaptureVideoPreviewLayer? {
        didSet {
            if let oldLayer = oldValue {
                oldLayer.removeFromSuperlayer()
            }
            if let newLayer = previewLayer {
                layer.addSublayer(newLayer)
                newLayer.frame = bounds
            }
        }
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        previewLayer?.frame = bounds
    }
}
