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

// カスタムビューでレイヤーのサイズと向きを自動調整
class PreviewLayerView: UIView {
    var previewLayer: AVCaptureVideoPreviewLayer? {
        didSet {
            if let oldLayer = oldValue {
                oldLayer.removeFromSuperlayer()
            }
            if let newLayer = previewLayer {
                layer.addSublayer(newLayer)
                newLayer.frame = bounds
                updatePreviewOrientation()
            }
        }
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        previewLayer?.frame = bounds
        updatePreviewOrientation()
    }

    private func updatePreviewOrientation() {
        guard let connection = previewLayer?.connection, connection.isVideoRotationAngleSupported(0) else { return }

        let angle: CGFloat
        switch UIDevice.current.orientation {
        case .portrait:
            angle = 90
        case .portraitUpsideDown:
            angle = 270
        case .landscapeLeft:
            angle = 0
        case .landscapeRight:
            angle = 180
        default:
            // .faceUp, .faceDown, .unknown → use interface orientation
            let scene = UIApplication.shared.connectedScenes.first as? UIWindowScene
            switch scene?.interfaceOrientation {
            case .portrait:
                angle = 90
            case .portraitUpsideDown:
                angle = 270
            case .landscapeLeft:
                angle = 0
            case .landscapeRight:
                angle = 180
            default:
                angle = 90
            }
        }

        if connection.isVideoRotationAngleSupported(angle) {
            connection.videoRotationAngle = angle
        }
    }
}
