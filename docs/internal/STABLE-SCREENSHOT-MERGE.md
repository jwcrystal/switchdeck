# 穩定截圖功能合併 main

- 日期：2026-11-13
- 目的：讓已驗證的一般截圖、工具選項、選取樣式與 Undo/Redo 進入 main；尚有問題的滾動截圖不提供使用者入口。
- 使用者決策：因滾動程式碼與較早 commits 交錯，採「停用滾動入口後合併」，不在本次完整拆除引擎。
- main 起點：`0f01d4f3d7c32887bbdf11803677ebb3c2df6664`，工作樹原先乾淨。
- 合併來源：`f0aa23b6018568265511893411f0873d3ab9166b`（選取樣式與 Undo/Redo）。
- 排除：不合併 `67c3eb2` 的滾動狀態、側邊即時預覽與直接輸出等後續改動，保留在 `feature/screenshot`。
- 必須保留 main 既有四個 commits，包括 Hide Desktop Icons 與選單副標題修正。
- 實作：CMD DeepSeek V4.1 Flash；Review：GPT-6.1 Sol High。

## 執行

1. 合併前在 main 跑基準測試，確認未提交使用者變更仍為空（除本文件）。
2. 以 `--no-commit --no-ff` 合併指定來源，若有衝突逐一保留兩邊的無關功能，不以整檔覆蓋解決。
3. 隱藏或停用所有正常使用者可到達的滾動入口，並在啟動邊界加防護；不能只隱藏工具列而保留可繞過的快捷鍵／其他入口。
4. 引擎可保留以維持歷史／測試相容；測試或明確的開發診斷入口需標示其範圍，不應讓一般使用者意外啟動。
5. README 明確列出 main 的滾動截圖暫停提供，避免工具列／功能文件宣稱可用。
6. 回歸測試涵蓋入口不可啟動、一般截圖與標註歷史仍可用，以及 main 的既有功能；再跑 Release build／diff-check。
7. Sol High 雙軸 review 檢查合併整合與停用入口，修正後建立 merge commit。原 feature 分支與三份未追蹤使用者文件不動。

## 驗證界線

- 此任務不是修復滾動拼接，也不重新開啟滾動功能。
- 真實 GUI 手動驗收若未執行，明確保留為未驗證，不用單元測試替代實際操作聲明。
- 本次只做本機 main 合併與提交，不推送、不對外發布、不覆蓋已安裝 app。

## 結果

### 停用邊界（gate）

- 新增 `Sources/SwitchDeckApp/Screenshot/ScreenshotAvailability.swift`：`scrollingCapture = false`，單一靜態常數，所有入口共用。
- 工具列：`CaptureSession.showsScrollingCapture` 讀同一個常數，垂直／水平選單整段不建置，使用者看不到 scroll 按鈕。
- 啟動邊界：`SelectionView.startScrolling()` 最前面即擋下；`session.onScroll` closure 也先檢查，避免日後直接接線繞過。
- 診斷入口：`SelectionController.startScrollingForDebug()` 與 `ScreenshotCoordinator.beginScrollingDemo()` 在開 overlay／排 timer 前就 return，`--scroll-demo` 因此無法啟動。
- `--scroll-test` 保留為純引擎診斷：只把兩張合成影像餵給 `ScrollingCapture.detectShift`／`debugStitch`，不開 overlay、不擷取螢幕、不建立 HUD。
- 沒有新增 Settings 開關或 feature-flag framework；engine 程式與其單元測試原樣保留。

### 解衝突保留點

- `README.md`：保留 main 的 Hide Desktop Icons 列與四個 main commits 內容；只採來源的 Screenshot 列，不採 Hide Windows 列（main 已 revert）。Screenshot 段落改寫為「scrolling capture is paused」，不宣稱滾動可用。
- `docs/COMPARISON.md`：保留 main 的 Hide Desktop Icons 與 16 項開關表；加入 Screenshot 列並標註滾動暫停；移除已實作項目的「Candidate additions」Screenshot 條目，測試數更新為 84。
- `scripts/build-app.sh`：保留 main 較新的 `0.7.2` / build `9`，不降回來源的 `0.7.0` / `7`。
- 其餘檔案由 git 自動合併；main 的 Hide Windows revert 仍有效（`SwitchCatalog` 無 hideWindows），Hide Desktop Icons 存在。

### 驗證

- `swift test`：84 tests 全綠（SwitchKitTests 18、ScreenshotTests 66），0 failures。
- 滾動引擎測試保留（ScrollingCaptureTests 12、FixedEdge 2、Horizontal 3 等），未因 known-bad 移除。
- `SelectionScrollingTests` 改為驗證 blocked 入口：工具列入口隱藏、垂直與水平請求都不建立 capture／HUD、不增加 frame 請求、工具列維持可見、debug helper 與 `beginScrollingDemo` 都不開 overlay。
- 一般編輯、Undo/Redo、選取樣式、Copy/Save 相關測試照常通過。
- `./scripts/build-app.sh release`：成功，local signing identity 驗證通過（valid on disk / satisfies designated requirement）。
- conflict markers 已全清；主 agent 的 staged diff-check 發現來源文件 `ANNOTATION-STYLE-EXECUTION.md` 末尾多餘空白，已一併清除後重新檢查。
- 未執行 GUI 手動驗收；不以單元測試代替實際點擊聲明。

### 最終複驗與提交

- 主 agent 獨立重跑 `swift test`：**84 tests、0 失敗**（18 SwitchKit、66 Screenshot），並成功重建 Release，穩定簽章驗證通過。
- GPT-6.1 Sol High 雙軸唯讀 review：**Standards 0 findings、Spec 0 findings**。確認 main 既有功能與版本設定保留、滾動入口及啟動邊界均已停用，沒有帶入 `67c3eb2`。
- 測試與建置完整紀錄位於本機暫存目錄中的 `stable-screenshot-main-tests.log`、`stable-screenshot-main-build.log`；GUI 驗收仍未執行。
- 此紀錄隨本機 merge commit 提交；不 push、不改安裝 app，也不改動 feature 分支及其使用者文件。
- 已知非阻擋事項：Release build 對 `Main.swift` 的 `--dump`／`--menu` 臨時 `ScreenshotCoordinator()` 出現 weak-reference warning；GUI 本體由 AppDelegate 強持有，行為不受影響，未在本次擴大修改。
