# アスパラガス セグメンテーション カメラアプリ

YOLO11seg-smallモデルを使用したリアルタイムセグメンテーションアプリです。

## 機能

### 📹 カメラ機能
- **リアルタイムカメラ入力**
- **写真撮影** - 検出結果付きで撮影
- **動画撮影** - 録画中のインジケーター表示
- 自動的にフォトライブラリに保存

### 🎯 検出機能
- **6クラスのセグメンテーション検出**:
  - 0: 親茎 (🌿)
  - 1: アスパラガス (📸)
  - 2: 枝 (🌿)
  - 3: 褐斑病 (⚠️)
  - 4: 茎枯病 (⚠️)
  - 5: 斑点病 (⚠️)

### 📊 表示機能
- **カラーコード化されたオーバーレイ表示**
- **検出信頼度の表示**
- **詳細情報の表示機能**
  - 検出エリアをタップすると詳細情報を表示
  - クラス名、アイコン、信頼度、面積、説明を表示
- **統計情報のリアルタイム表示**
  - 総検出数
  - 病気の検出数
  - 健康な部分の数
- **インタラクティブな凡例**
  - 各クラスの色とアイコンを表示
  - 病気マーカーで注意が必要なクラスを識別

### ⚡️ パフォーマンス表示
- **リアルタイムFPS表示** - フレームレートの即時確認
- **推論時間表示** - モデルの処理速度をミリ秒単位で表示
- **平均値の計算** - 30フレーム分の平均FPSと推論時間
- **パフォーマンス評価** - 優秀/良好/普通/低速の4段階評価
- **色分け表示**:
  - 緑: 優秀なパフォーマンス
  - 黄: 良好なパフォーマンス
  - 赤: 改善が必要

## セットアップ

### 1. 権限の設定

Xcodeプロジェクトの `Info.plist` に以下のキーを追加:

```xml
<key>NSCameraUsageDescription</key>
<string>アスパラガスの病気検出のためにカメラを使用します</string>

<key>NSPhotoLibraryAddUsageDescription</key>
<string>撮影した写真や動画を保存するためにフォトライブラリへのアクセスが必要です</string>

<key>NSPhotoLibraryUsageDescription</key>
<string>撮影した写真や動画を表示するためにフォトライブラリへのアクセスが必要です</string>

<key>NSMicrophoneUsageDescription</key>
<string>動画撮影時に音声を録音します</string>
```

または、Xcodeの Target > Info タブで:
- **Privacy - Camera Usage Description**: "アスパラガスの病気検出のためにカメラを使用します"
- **Privacy - Photo Library Additions Usage Description**: "撮影した写真や動画を保存するためにフォトライブラリへのアクセスが必要です"
- **Privacy - Photo Library Usage Description**: "撮影した写真や動画を表示するためにフォトライブラリへのアクセスが必要です"
- **Privacy - Microphone Usage Description**: "動画撮影時に音声を録音します"

### 2. YOLOモデルの追加

1. YOLO11seg-smallモデルを Core ML形式 (.mlmodel または .mlmodelc) に変換
2. 変換したモデルをXcodeプロジェクトに追加
3. `YOLOSegmentationModel.swift` の `loadModel()` 関数を更新:

```swift
private func loadModel() {
    do {
        // モデルファイル名を実際のファイル名に変更
        let modelURL = Bundle.main.url(forResource: "yolo11seg_small", withExtension: "mlmodelc")!
        let mlModel = try MLModel(contentsOf: modelURL)
        model = try VNCoreMLModel(for: mlModel)
    } catch {
        print("モデルの読み込みに失敗: \(error)")
    }
}
```

### 3. YOLOモデルの出力処理

モデルの出力形式に応じて、`YOLOSegmentationModel.swift` の `processResults()` 関数を実装する必要があります。

典型的なYOLOセグメンテーション出力:
- バウンディングボックス (x, y, width, height)
- クラス信頼度
- セグメンテーションマスク

実装例:

```swift
private func processResults(_ results: [Any]?) {
    guard let observations = results as? [VNCoreMLFeatureValueObservation] else {
        return
    }
    
    var detections: [SegmentationResult.Detection] = []
    
    // モデル出力からバウンディングボックスとマスクを抽出
    for observation in observations {
        // 実際のモデル出力構造に応じて実装
        // 例:
        // - observation.featureValue.multiArrayValue (boxes)
        // - observation.featureValue.multiArrayValue (masks)
        // - observation.featureValue.multiArrayValue (scores)
    }
    
    Task { @MainActor in
        self.currentResult = SegmentationResult(
            maskImage: nil, // マスクから生成
            detections: detections
        )
    }
}
```

## YOLOモデルの変換 (Python)

```python
from ultralytics import YOLO
import coremltools as ct

# YOLOモデルの読み込み
model = YOLO('yolo11seg-small.pt')

# Core ML形式にエクスポート
model.export(format='coreml', nms=True)
```

## 使用方法

### 基本操作

1. アプリを起動
2. カメラ権限とフォトライブラリ権限を許可
3. カメラをアスパラガスに向ける
4. リアルタイムでセグメンテーション結果が表示されます

### 詳細情報の確認

5. **検出エリアをタップして詳細情報を表示**
   - クラス名とアイコン
   - 信頼度の割合
   - 検出エリアの大きさ
   - 病気の場合は対処法の説明

### 撮影機能

6. **写真撮影**
   - 画面下部の白い丸ボタンをタップ
   - 検出結果が表示された状態で撮影
   - 自動的にフォトライブラリに保存

7. **動画撮影**
   - 画面下部の赤い丸ボタンをタップで録画開始
   - 録画中は赤い点滅とタイマーが表示
   - もう一度タップで録画停止
   - 自動的にフォトライブラリに保存

### パフォーマンス確認

8. **パフォーマンスメトリクス**
   - 画面上部に推論時間とFPSを表示
   - 「パフォーマンス」セクションをタップで詳細表示
   - 現在値と平均値を確認
   - パフォーマンス評価を確認

### UI説明

- **上部左**: 録画インジケーター（録画中のみ）
- **上部中央**: パフォーマンスメトリクス（推論時間・FPS）
- **上部右**: 設定ボタン
- **左側**: クラス凡例（折りたたみ可能）
- **右側**: 詳細パフォーマンス情報（折りたたみ可能）
- **中央**: カメラビュー + セグメンテーションオーバーレイ
- **下部中央**: 統計情報（総検出数、病気数、健康数）
- **最下部**: 撮影コントロール（ギャラリー・写真・動画ボタン）

## トラブルシューティング

### カメラが表示されない
- Info.plistにカメラ使用の説明が追加されているか確認
- デバイスの設定でカメラ権限が許可されているか確認

### モデルが読み込めない
- モデルファイルがXcodeプロジェクトに正しく追加されているか確認
- モデルファイル名が `loadModel()` 関数内の名前と一致しているか確認
- Core ML形式(.mlmodel または .mlmodelc)に正しく変換されているか確認

### 検出精度が低い
- モデルの入力サイズを確認
- 照明条件を改善
- カメラとの距離を調整

## アーキテクチャ

- **CameraManager**: カメラセッション、フレームキャプチャ、写真・動画撮影を管理
- **YOLOSegmentationModel**: YOLO推論、結果処理、パフォーマンス計測
- **CameraView**: メインのUIビュー
- **SegmentationOverlayView**: 検出結果のオーバーレイ表示
- **CameraPreviewView**: カメラプレビューのUIKit統合
- **PerformanceMetricsView**: FPSと推論時間の表示
- **CaptureControlsView**: 写真・動画撮影コントロール
- **DetectionStatsView**: 検出統計の表示

## パフォーマンス基準

### FPS評価
- **優秀** (緑): 30 FPS以上 - リアルタイム処理が快適
- **良好** (黄): 24-30 FPS - スムーズな表示
- **普通** (橙): 15-24 FPS - 使用可能だが改善の余地あり
- **低速** (赤): 15 FPS未満 - 最適化が必要

### 推論時間の目安
- **優秀**: 33ms未満 (30 FPS相当)
- **良好**: 33-66ms (15-30 FPS相当)
- **改善必要**: 66ms以上 (15 FPS未満)

## 必要な環境

- iOS 17.0以降
- Xcode 15以降
- カメラ搭載のiOSデバイス(シミュレータでは動作しません)

## ライセンス

このコードはサンプルとして提供されています。
