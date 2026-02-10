//
//  BuildCheckView.swift
//  aspa-camera
//
//  Created by Takashi Otsuka on 2026/02/10.
//

import SwiftUI

struct BuildCheckView: View {
    @State private var bundleFiles: [String] = []
    @State private var mlFiles: [String] = []
    
    var body: some View {
        List {
            Section("バンドルステータス") {
                if mlFiles.isEmpty {
                    HStack {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundColor(.red)
                        Text("MLモデルファイルが見つかりません")
                            .foregroundColor(.red)
                    }
                } else {
                    HStack {
                        Image(systemName: "checkmark.circle.fill")
                            .foregroundColor(.green)
                        Text("\(mlFiles.count)個のMLモデルファイルが見つかりました")
                            .foregroundColor(.green)
                    }
                }
            }
            
            if !mlFiles.isEmpty {
                Section("見つかったMLモデル") {
                    ForEach(mlFiles, id: \.self) { file in
                        HStack {
                            Image(systemName: "doc.fill")
                                .foregroundColor(.blue)
                            Text(file)
                                .font(.system(.body, design: .monospaced))
                        }
                    }
                }
            }
            
            Section("トラブルシューティング") {
                VStack(alignment: .leading, spacing: 12) {
                    ChecklistItem(
                        number: 1,
                        text: "Xcodeのプロジェクトナビゲータで 'aspara-v3-b1.mlpackage' が見えるか確認"
                    )
                    
                    ChecklistItem(
                        number: 2,
                        text: "ファイルを右クリック → 'Show File Inspector'"
                    )
                    
                    ChecklistItem(
                        number: 3,
                        text: "右サイドバーの 'Target Membership' で 'aspa-camera' にチェックが入っているか確認"
                    )
                    
                    ChecklistItem(
                        number: 4,
                        text: "チェックが入っていない場合、チェックを入れてビルド (Cmd+B)"
                    )
                }
                .padding(.vertical, 4)
            }
            
            Section("バンドル情報") {
                if let bundlePath = Bundle.main.resourcePath {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("バンドルパス:")
                            .font(.caption)
                            .foregroundColor(.secondary)
                        Text(bundlePath)
                            .font(.system(.caption2, design: .monospaced))
                            .foregroundColor(.primary)
                    }
                }
                
                Text("バンドル内のファイル数: \(bundleFiles.count)")
                    .font(.caption)
            }
            
            if !bundleFiles.isEmpty {
                Section("バンドル内のファイル（最初の30個）") {
                    ForEach(Array(bundleFiles.prefix(30).enumerated()), id: \.offset) { index, file in
                        HStack {
                            Text("\(index + 1).")
                                .foregroundColor(.secondary)
                                .frame(width: 30, alignment: .trailing)
                            Text(file)
                                .font(.system(.caption, design: .monospaced))
                        }
                    }
                }
            }
        }
        .navigationTitle("ビルド設定チェック")
        .navigationBarTitleDisplayMode(.inline)
        .onAppear {
            checkBundleContents()
        }
    }
    
    private func checkBundleContents() {
        guard let bundlePath = Bundle.main.resourcePath else { return }
        
        let fileManager = FileManager.default
        if let files = try? fileManager.contentsOfDirectory(atPath: bundlePath) {
            bundleFiles = files.sorted()
            mlFiles = files.filter { 
                $0.hasSuffix(".mlmodel") || 
                $0.hasSuffix(".mlmodelc") || 
                $0.hasSuffix(".mlpackage")
            }.sorted()
        }
    }
}

struct ChecklistItem: View {
    let number: Int
    let text: String
    
    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            ZStack {
                Circle()
                    .fill(Color.blue.opacity(0.2))
                    .frame(width: 28, height: 28)
                Text("\(number)")
                    .font(.caption)
                    .fontWeight(.bold)
                    .foregroundColor(.blue)
            }
            
            Text(text)
                .font(.callout)
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}

#Preview {
    NavigationStack {
        BuildCheckView()
    }
}
