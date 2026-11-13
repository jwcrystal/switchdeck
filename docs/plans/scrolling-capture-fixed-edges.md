# 計畫：滾動截圖的固定邊緣判定

狀態：草稿，待確認
範圍：`Sources/SwitchDeckApp/Screenshot/ScrollingCapture.swift` 的 `detectFixedEdges`、`append`、`composeFixedEdges`，以及 `Tests/ScreenshotTests/`
不在範圍：抓幀 I/O（另一個分支已修）、色彩空間、`ScreenshotAvailability` 開關

## 為什麼要改

目前在第一次成功配對時，只拿 `firstFrame` 和當前這一幀比較「同一個 y 的列是否相同」，判定一次就永久鎖定。這會造成三種失敗：

| 情境 | 現在的行為 | 後果 |
|---|---|---|
| A. 左右是空白留白，之後捲到較寬的內容（大圖、表格） | 留白在前兩幀相同，被當成側邊欄 | 輸出時那一欄被換成單色填色加上第一幀的內容，寬內容被截掉 |
| B. 固定 header 在捲動開始時才出現陰影或分隔線，或 header 裡有閃爍游標、動畫 | 那幾列兩幀不同，不算固定 | header 被留在配對區域裡，它不會移動，配對失敗或 `worstTile` 超標，一直顯示「Waiting for overlap」 |
| C. sticky header 捲到一半才出現或縮小 | 邊緣已鎖定，不會重算 | 之後每一幀都配對失敗，捲動截圖卡住 |

（上下的空白列被誤判成固定其實不會出事：內容從下方進來，最後的 footer 用的是最後一幀，和內容是連續的。真正會壞的是左右誤判、漏判，以及晚出現的變化。）

## 做法

### 1. 先找位移，再依位移判定每一列

不再用「同一個 y 是否相同」來猜邊緣。改成：

1. 先用畫面中間的帶狀區（例如垂直 25%–75%）找出候選位移 `s`。中間區域最不可能是 header 或 footer。現有的 `pixelShift` 可以直接用在裁切後的影像上。
2. 有了 `s` 之後，每一列 y 分成三類：
   - **跟著動**：`current[y] ≈ previous[y + s]`，而且 `≉ previous[y]`
   - **固定**：`current[y] ≈ previous[y]`，而且 `≉ previous[y + s]`
   - **不確定**：兩邊都相同（空白），或兩邊都不同（動畫、雜訊）
3. 每一欄 x 也用同樣方式分類。

### 2. 把「排除在配對之外」和「當成固定區合成」分開

- **配對時排除**：固定加上不確定的邊緣列和欄都排除。排除空白不會讓配對變差，還能避開動畫。
- **合成時當成固定區**：只有連續多次被判成「固定」、而且有紋理（不是空白）的邊緣，才會被當成 header、footer 或側邊欄。
- 被判成不確定的空白留白，合成時照樣當成內容的一部分。這樣就修好了情境 A：之後出現在留白的寬內容會被保留下來。

### 3. 用多幀累積證據，不是一組就定案

- 每一列和每一欄都記錄「判成固定的次數」和「判成跟著動的次數」。
- 至少累積 N 次成功配對（先定 3 次），或累積位移總和超過內容高度的 1/4，才把合成用的固定區定下來。在那之前，slice 先保留完整寬度，最後合成時再裁掉。
- 有一列只要出現過一次「跟著動」，就不再被當成固定。

### 4. 上下的固定區之後可以變大，左右不行

- 上下的固定區可以在鎖定後變大（處理情境 C 的 sticky header）：之後的幀把新增的列排除在配對之外。已經加入的 slice 不受影響，因為 slice 一律是全寬，只有高度不同。
- 左右的固定區鎖定後就不再改變，因為改了會讓 slice 寬度不一致。如果之後出現衝突，就退回「沒有側邊欄」，改用完整寬度。這需要第 3 步先保留完整寬度的 slice 才做得到。
- 最後合成時，header 用第一幀的、footer 用最後一幀的，這部分和現在一樣。

## 測試（先寫測試，紅了再改）

在 `FixedEdgeCaptureTests.swift` 新增合成幀測試：

1. `testBlankSideMarginsKeepLaterWideContent`：左右留白一開始是空白，第 3 幀開始出現橫跨全寬的區塊。輸出必須保留這個區塊。
2. `testHeaderShadowAppearingOnFirstScrollIsStillFixed`：第一幀的 header 沒有陰影，之後都有。輸出的 header 只出現一次，內容要連續。
3. `testStickyHeaderAppearingMidCaptureDoesNotStall`：第 4 幀起頂部出現固定列。捲動截圖要繼續長高，不能卡在 overlap。
4. `testBlinkingCaretInHeaderDoesNotBreakMatching`：header 裡有幾個像素每幀切換。
5. 現有的 `testFixedHeaderFooterAndSidebarsAreNotRepeated`、`testBlankMarginsAndRepeatedRowsDoNotOvercountMovement` 和 `ScrollingCaptureTests` 必須維持通過。

## 待決定

1. **要不要錄真實幀當 fixture**：合成幀只能覆蓋我們想得到的情境，這個功能被暫停也是因為實機上的問題。建議加一個只在 DEBUG 建置有效的開關，把每一幀存成 PNG，從 Safari、Notes、Xcode 各錄一組放進 `Tests/ScreenshotTests/Fixtures/`。缺點是 repo 會變大，每組大約幾 MB。
2. **側邊欄的合成方式**：目前是「用單色延伸背景，控制項只畫一次」。如果固定區判定變準了，可以保留這個做法；也可以改成側邊欄直接用最後一幀。這會影響輸出的樣子，需要你決定。
3. **N 的值**：3 次成功配對是先抓的數字，建議等有真實 fixture 之後再調。

## 驗收

- 上面的新測試和舊測試全部通過，`swift test` 整套綠燈。
- 如果有錄真實 fixture：每組的輸出都不能有重複或缺漏的內容（用人工檢查加上像素比對）。
- `ScreenshotAvailability.scrollingCapture` 仍然是 `false`。要不要打開是另一個決定。
