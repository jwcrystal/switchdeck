# 計畫：滾動截圖的固定邊緣判定

狀態：方向已確認，待實作
範圍：`Sources/SwitchDeckApp/Screenshot/ScrollingCapture.swift` 的 `detectFixedEdges`、`append`、`composeFixedEdges`，以及 `Tests/ScreenshotTests/`
不在範圍：抓幀 I/O（已在 PR #1 修好）、色彩空間、`ScreenshotAvailability` 開關。一般截圖只拍一張，不需要拼接，完全不受影響。

## 已確認的決定

| 項目 | 決定 |
|---|---|
| 測試資料 | 錄真實幀當 fixture，合成幀用來固定已知情境 |
| 鎖定前要累積幾次配對（N） | 錄好 fixture 後由資料決定，不先猜數字 |
| 側邊欄合成 | 維持「取第一幀」，下方改成重複側邊欄最底部那一列往下延伸，不再用單色 |
| 方向 | 固定區邏輯兩個軸共用；往回捲（反方向延伸）拆成第二階段，見最後一節 |

## 為什麼要改

目前在第一次成功配對時，只拿 `firstFrame` 和當前這一幀比較「同一個 y 的列是否相同」，判定一次就永久鎖定。這會造成三種失敗：

| 情境 | 現在的行為 | 後果 |
|---|---|---|
| A. 左右是空白留白，之後捲到較寬的內容（大圖、表格） | 留白在前兩幀相同，被當成側邊欄 | 輸出時那一欄被換成單色填色加上第一幀的內容，寬內容被截掉 |
| B. 固定 header 在捲動開始時才出現陰影或分隔線，或 header 裡有閃爍游標、動畫 | 那幾列兩幀不同，不算固定 | header 被留在配對區域裡，它不會移動，配對失敗或 `worstTile` 超標，一直顯示「Waiting for overlap」 |
| C. sticky header 捲到一半才出現或縮小 | 邊緣已鎖定，不會重算 | 之後每一幀都配對失敗，捲動截圖卡住 |

（上下的空白列被誤判成固定其實不會出事：內容從下方進來，最後的 footer 用的是最後一幀，和內容是連續的。真正會壞的是左右誤判、漏判，以及晚出現的變化。）

## 第零步：錄真實幀

1. 加一個只在 DEBUG 建置有效的開關（環境變數或 launch argument），把 `ScrollingCapture` 收到的每一幀原樣存成 PNG，連同區域大小和 scale 一起存成 manifest。正式建置完全不會編進去。
2. 每組 fixture 都由你在實機上錄，至少涵蓋：
   - Safari 長文章（有固定 header，捲動後出現陰影）
   - Safari 有 sticky 目錄側邊欄的文件頁
   - Notes 或郵件（左側清單 + 右側內容，框選範圍跨兩欄）
   - Xcode 或終端機（等寬字、大量重複列）
   - 一組水平捲動（例如試算表或時間軸）
3. 放在 `Tests/ScreenshotTests/Fixtures/<名稱>/`，每組控制在幾 MB 以內。必要時降低幀數，或裁成較小的區域。
4. 先用現在的演算法跑過全部 fixture，記錄失敗的樣子（重複、缺漏、卡住），作為改動前的基準。

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
- 累積 N 次成功配對後，才把合成用的固定區定下來。N 由 fixture 決定：取「所有 fixture 的判定都不再變動」所需的最小次數，再加一點餘裕。在那之前，slice 先保留完整寬度，最後合成時再裁掉。
- 有一列只要出現過一次「跟著動」，就不再被當成固定。

### 4. 上下的固定區之後可以變大，左右不行

- 上下的固定區可以在鎖定後變大（處理情境 C 的 sticky header）：之後的幀把新增的列排除在配對之外。已經加入的 slice 不受影響，因為 slice 一律是全寬，只有高度不同。
- 左右的固定區鎖定後就不再改變，因為改了會讓 slice 寬度不一致。如果之後出現衝突，就退回「沒有側邊欄」，改用完整寬度。這需要第 3 步先保留完整寬度的 slice 才做得到。
- 最後合成時，header 用第一幀的、footer 用最後一幀的，這部分和現在一樣。

### 5. 側邊欄的延伸方式

長圖裡，側邊欄只在頂部畫一次（取第一幀），原本那段高度以下要補滿：

1. 取第一幀側邊欄區域最底部的一列像素，往下重複到長圖底部。這樣分隔線會一路延伸，左右方向的漸層和背景紋理也會保留。
2. 如果那一列有明顯邊緣（剛好切到按鈕或文字），延伸出來會變成條紋。這時候退回取樣單色填色。判斷方式是看這一列的水平梯度總量，梯度太大就退回。分隔線只是少數幾個像素，不會觸發退回。
3. 現在的單色取樣只取一個像素。退回時改成取該列的中位數顏色，避免剛好取到雜點。

## 方向性

### 現狀

- **兩個軸**：使用者先選垂直或水平。水平模式會先把每一幀順時針轉 90° 變成垂直，處理完再轉回來（`canonicalImage` / `rotate`）。所以固定區判定、側邊欄延伸都只寫一份，兩個軸自動適用：
  - 垂直模式：header/footer 是上下的固定列，側邊欄是左右的固定欄
  - 水平模式：header/footer 對應原畫面左右的固定欄，「側邊欄」對應上方的工具列和下方的狀態列，延伸方向變成往右
- **每個軸只往一個方向長**：位移只搜尋正值。往回捲不會出錯，有 `testUpwardThenDownwardScrollDoesNotDuplicateContent` 和 `testHorizontalPauseAndBacktrackingDoNotDuplicateColumns` 保護，不會重複拼接，但也不會延伸。所以起點之前的內容抓不到：使用者必須先捲到最上面或最左邊再開始。

### 不支援的情況

同時上下又左右捲（像地圖那樣的平面拼接）不在範圍內。那需要二維對位和不規則的畫布，演算法完全不同，也很少用到。

### 第二階段：同一軸的雙向延伸

讓使用者可以從頁面中間開始，先往上捲再往下捲（或先往左再往右），兩頭都能延伸。這會改變合成的基本模型，所以等第一階段穩定之後再做，另開一個分支：

1. **位置游標**：記錄目前畫面在整份長圖裡的偏移量和已知範圍 `[top, bottom]`。每一幀依位移移動游標：
   - 超出 `bottom` → 在尾端追加新的列（現在的行為）
   - 超出 `top` → 在開頭插入新的列
   - 還在已知範圍內 → 只移動游標，不加任何東西（取代現在「忽略往回捲」的做法）
2. **位移搜尋改成正負都找**：`pixelShift` 的搜尋範圍從 `1...maxShift` 改成 `-maxShift...maxShift`，並用同一套信心檢查。
3. **固定區的取法**：header 改用游標到過最上方時的那一幀，footer 改用到過最下方時的那一幀，不再是第一幀和最後一幀。側邊欄仍取第一幀。
4. **測試**：從中間開始先往上再往下的合成幀，驗證輸出和完整文件逐像素一致；水平方向用同一組測試旋轉後再跑一次；fixture 至少錄一組「從中間開始」。

## 測試（先寫測試，紅了再改）

在 `FixedEdgeCaptureTests.swift` 新增合成幀測試：

1. `testBlankSideMarginsKeepLaterWideContent`：左右留白一開始是空白，第 3 幀開始出現橫跨全寬的區塊。輸出必須保留這個區塊。
2. `testHeaderShadowAppearingOnFirstScrollIsStillFixed`：第一幀的 header 沒有陰影，之後都有。輸出的 header 只出現一次，內容要連續。
3. `testStickyHeaderAppearingMidCaptureDoesNotStall`：第 4 幀起頂部出現固定列。捲動截圖要繼續長高，不能卡在 overlap。
4. `testBlinkingCaretInHeaderDoesNotBreakMatching`：header 裡有幾個像素每幀切換。
5. `testSidebarDividerExtendsToTheBottom`：側邊欄右緣有 1px 分隔線，背景是左右漸層。長圖底部的那一列必須和側邊欄最底列相同。
6. `testSidebarWithControlsOnLastRowFallsBackToSolidFill`：側邊欄最底列剛好有文字。下方必須是單色，不能出現條紋。
7. 上面 1–6 在 `HorizontalCaptureTests.swift` 各補一個旋轉後的版本，確認水平模式也成立。
8. Fixture 測試：每組 fixture 合成後，和人工確認過的基準圖比對。
9. 現有的 `testFixedHeaderFooterAndSidebarsAreNotRepeated`、`testBlankMarginsAndRepeatedRowsDoNotOvercountMovement`、`ScrollingCaptureTests` 和 `HorizontalCaptureTests` 必須維持通過。

## 驗收

- 上面的新測試和舊測試全部通過，`swift test` 整套綠燈。
- 每組真實 fixture 的輸出都沒有重複或缺漏的內容：人工檢查一次，之後用基準圖比對。
- `ScreenshotAvailability.scrollingCapture` 仍然是 `false`。要不要打開是另一個決定。
