# MTR Lift Guide · 站內導航

一款為香港地鐵（MTR）設計的 iOS 站內導航應用，協助乘客——尤其是輪椅使用者、視障人士及行動不便者——在站內找到無障礙路線、出口與換乘方式。

> MapTR · finding ways

---

## 功能

- **站內無障礙導航**：電梯 / 扶梯兩條路線，逐步指示，並估算步行距離與時間。
- **真 AR 實景導航**：ARKit 世界追蹤 + RealityKit，把箭頭真正錨定在地面或牆身上（貼合平面、隨手機移動保持在世界座標）；箭頭指向當前指示的羅盤方位，走過之後會自動在前方重新投射。
- **靈動島 / Live Activity**：
  - 小島顯示**出口、羅盤方向、出行方式（電梯 / 樓梯）與進度**；
  - 大島**羅列完整步驟**，當前步驟以品牌紅高亮；
  - 導航完成時自動收起，不常駐。
- **車站互助（尋求 / 提供幫助）**：
  - 在車站內發布求助（找出口、攙扶視障 / 行動不便人士等）；
  - 他人求助以**浮動氣泡**呈現，**雙擊戳破**即接單，附氣泡爆破動畫；
  - 提供**對話框**與**精確位置示意圖**（大堂 / 月台 / 售票大堂 / 出口附近）。
- **官方站內地圖**：內置 MTR 官方站內 PDF 圖則。
- **語音播報 + 多語言**：粵語 / 普通話 / 英語，中英介面切換。
- **深色模式**：自適應淺色 / 深色主題；深色下強調色切換為 MTR 標誌紅。
- **觸覺回饋**：輕點、選擇、成功、爆破等統一的 haptic 回饋。

---

## 技術棧

| 領域 | 技術 |
| --- | --- |
| UI | SwiftUI（iOS 17+） |
| 靈動島 | ActivityKit + WidgetKit |
| 定位 / 羅盤 | CoreLocation |
| AR | ARKit + RealityKit（世界追蹤、平面偵測、場景深度） |
| 相機（模擬器 fallback） | AVFoundation |
| 站內地圖 | PDFKit |
| 語音 | AVSpeechSynthesizer |
| 觸覺 | UIKit Feedback Generators |

---

## 項目結構

```
ios/
├─ MTRLiftGuide/                 # App 主體
│  ├─ App/                       # 入口、環境注入
│  ├─ Design/                    # 玻璃質感、觸覺、設計令牌
│  ├─ Model/                     # 車站資料、路線引擎、互助請求、本地化
│  ├─ Services/                  # AR 場景、相機、羅盤、語音、天氣、Live Activity
│  ├─ Views/                     # 首頁、車站、出口、路線、AR、互助板
│  ├─ Resources/                 # stations.json / official_maps.json
│  └─ Assets.xcassets/           # App 圖標
├─ MTRLiftGuideWidget/           # 靈動島 Widget Extension
├─ Shared/                       # App 與 Widget 共享的 ActivityAttributes
├─ UITests/                      # UI 測試
├─ MTRLiftGuide.xcodeproj
└─ project.yml                   # XcodeGen 配置
figma-design/                    # 設計稿
```

---

## 構建與運行

1. 用 Xcode 打開 `ios/MTRLiftGuide.xcodeproj`。
2. 在 *Signing & Capabilities* 選擇你的開發團隊。
3. 選擇真機運行（**AR 世界追蹤、相機與羅盤均需真機**，模擬器只會退回普通相機預覽）。

```bash
# 命令列構建（真機）
cd ios
xcodebuild -project MTRLiftGuide.xcodeproj \
  -scheme MTRLiftGuide -configuration Debug \
  -destination 'generic/platform=iOS' \
  -allowProvisioningUpdates build
```

> 若項目位於 iCloud「桌面」同步目錄，簽名可能因文件擴展屬性報錯，建議將 DerivedData 指向非同步路徑（如 `/tmp`）。

---

## 資料與免責聲明

- 車站與出口資料為內置整理的網絡結構資料，並非實時官方數據；實際出行請以站內指示牌為準。
- 路線中的車廂號、步行距離等為確定性推算值，僅供參考。
- 本應用與香港鐵路有限公司（MTR Corporation）無隸屬關係，相關商標歸其所有。
