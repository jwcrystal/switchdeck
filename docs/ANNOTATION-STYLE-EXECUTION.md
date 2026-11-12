# 選取標註樣式與 Undo/Redo 執行紀錄

- 日期：2026-11-12
- 需求：依 `docs/ANNOTATION-STYLE-PLAN.md` 實作 Phase 1A 與 Phase 1B，一起交付。
- 不含：滾動截圖計畫、長圖編輯器、無關重構。
- 實作模型：`commandcode/deepseek/deepseek-v4.1-flash`。
- Review 模型：`openai/gpt-6.1-sol#high`，分別檢查規範與需求。
- Review 基準：開始前的 HEAD `1f9e55becec40936ef55afe3dd6c781c670f4ffc`，以最終工作樹差異為範圍，不自動提交。
- 既有工作：三份未追蹤文件 `ANNOTATION-STYLE-PLAN.md`、`HAPIGO-SCREENSHOT.md`、`SCROLLING-CAPTURE.md` 全數保留。

## 執行順序

1. 跑 `swift test` 確認基準，特別檢查 `ToolOptionsTests`。
2. 實作共用樣式、選取樣式橋接與工具列顯示。
3. 實作新增／刪除／移動／縮放／樣式的歷史與互動合併，接上兩個鍵盤入口。
4. 補齊選取、渲染、歷史、工具列測試及 README。
5. 重跑測試，進行雙軸 review；發現問題交回原實作模型修正並複驗。

## 驗證重點

- 改選取物件樣式會同步預設值，不改幾何。
- 單純改預設值不產生內容歷史；無效選取不當機。
- Slider 與拖曳一次互動只有一步 undo；無實際變更不得製造空歷史或清掉 redo。
- Undo/redo 還原內容與預設樣式並清除選取；新內容操作清空 redo。
- 工具切換、選區移動與 popover 不進入歷史。
- 如無法進行 GUI 手動驗收，最終結果明確列出未驗證範圍。

## 結果

### 實作（Phase 1A + 1B）

- `Annotation.swift`
  - 新增 `AnnotationStyle: Equatable`（顏色、線寬、文字大小／氣泡、箭頭、填充、線型、馬賽克區塊、編號形狀、螢光筆透明度）。
  - `Annotation` 與 `Annotation.Shape` 加上 `Equatable`，供歷史判斷是否為 no-op；stored properties 與 memberwise init 未變。
  - 新增 `Annotation.style` 計算屬性（get／set 逐欄位）與 `init(shape:style:)`。
- `CaptureSession.swift`
  - 10 個樣式 `@Published` 收斂為 `@Published var defaultStyle`。
  - 新增 `selectedAnnotation`、`hasSelectedAnnotation`、`displayTool`、`showsOptions`、`activeStyle`、`styleBinding(_:)`、`static tool(for:)`。
  - `activeStyle` 寫入時以「更新副本再賦值」修改選取物件，並同步 `defaultStyle`；只有在選取有效且值真的改變時才記錄歷史。
  - 歷史：`HistoryState`（annotations + defaultStyle）、`canUndo`／`canRedo` 為 `@Published`，上限 50 筆；新增 `recordUndoSnapshot`、`beginInteractiveChange`、`endInteractiveChange`、`undo`、`redo`、`resetHistory`。
  - 互動變更只在「內容真的有差」時才推入歷史並清 redo；單純預設值變更、同值寫入、點擊未移動都不留空歷史、不清 redo。
  - 工具列：`showsOptions` 控制選項列、`displayTool` 決定顯示哪組選項、顏色與所有按鈕／slider 改走 `activeStyle`；箭頭主圖示仍看 `defaultStyle`；undo 按鈕改用 `canUndo`，新增 redo 按鈕（`⇧⌘Z`）；三個 slider 以 `onEditingChanged` 做拖曳合併。
- `SelectionOverlay.swift`
  - 新增／文字提交在 `commit(_:)` 內先記錄快照；刪除前記錄；未按 Enter 的空文字不記錄。
  - 移動／縮放既有標註在 `mouseDown` 開始互動、`mouseUp` 結束並比較是否真的有變更；選區本身移動／縮放不進歷史。
  - `⌘Z`／`⇧⌘Z` 由共用的 `SelectionView.historyCommand(for:)` 判斷，local key monitor 與 `SelectionView.keyDown` 兩個入口都接上 `session.undo()`／`session.redo()`；`onUndo`／`onRedo` 也是同一條路徑。
  - draft 與新標註改用 `Annotation(shape:style:)` + `defaultStyle`。
  - 每次開始新擷取時清空歷史，避免沿用上一個 session 的 undo。
- `README.md`
  - Screenshot 段落補上「Select 選取既有標註後可即時調整該物件樣式，並成為下一筆預設」，快捷鍵說明改為 `⌘Z` / `⇧⌘Z` undo/redo。
- 未變更 `SCROLLING-CAPTURE`、滾動截圖、OCR 或其他非截圖模組；三份使用者文件保持原樣。

### 測試

- 新增 `Tests/ScreenshotTests/SelectedStyleTests.swift`（6 個）：選取樣式寫入目標與預設同步、未選取只改預設、無效選取不當機、shape→tool 映射與 `displayTool`／`showsOptions`、選取時選項列高度與寬度、`styleBinding` 寫入。
- 新增 `Tests/ScreenshotTests/AnnotationHistoryTests.swift`（15 個）：樣式 undo/redo、移動後 undo、刪除後 undo、slider 合併為一步、undo 清選取、`canUndo`／`canRedo` 與堆疊同步、點擊未移動不動歷史且保留 redo、同值寫入不清 redo、預設值變更不進內容歷史、undo 還原 `defaultStyle`、新操作清 redo、歷史上限 50、鍵盤路由（⌘Z／⇧⌘Z／無修飾鍵／⌘其他鍵／⌥Z）。
- `AnnotationStyleTests` 補 2 個：style round-trip、改樣式確實改變 renderer 像素。
- `ToolOptionsTests` 補 1 個：每種既有標註被選取時選項列出現、不撐寬主工具列。
- `swift test`：基準 23 個 ScreenshotTests（全綠）→ 完成後 47 個 ScreenshotTests + 17 個 SwitchKitTests，共 64 個測試、0 失敗。

### 未驗證

- 未進行 GUI 手動驗收：實際點選標註、拖曳 slider、`⌘Z`／`⇧⌘Z` 的即時畫面與按鈕 enabled 狀態只以單元測試與 hosting view 尺寸驗證，尚未在真實螢幕上逐步操作。
- Review 結果待主 agent 的雙軸 review 填寫（規格／規範兩軸）。

### Review 修正（GPT 6.1 Sol High，2 個 P2）

1. **互動中的 undo/redo 先結算 pending gesture**（`CaptureSession`）
   - `undo()`／`redo()` 不再直接丟棄 `pendingSnapshot`，改由 `resolveInteractiveChange()` 先處理：gesture 若真的改過 `annotations`，把拖曳前狀態推入歷史（清 redo）後再導航；沒改過就丢棄 pending、保留 redo。
   - 效果：slider 拖到一半按 `⌘Z`，第一次 undo 只回拉之前，不會跳過樣式編輯去刪掉剛畫的標註；互動中真的改了內容後按 redo，不會跳回已放棄的分支。
   - `endInteractiveChange()` 改用同一條 resolve 路徑。
   - `annotations` 加 `didSet`，`canUndo`／`canRedo` 會把 pending gesture 算進去：手勢一改內容，undo 立刻可用、redo 暫時隱藏；內容拉回原值時 redo 恢復。純 `defaultStyle` 變更仍不建立內容歷史。
2. **history navigation 先中止 canvas 手勢**（`SelectionOverlay`）
   - `performHistory` 會先呼叫 `cancelCanvasInteractionForHistory()`：移動／縮放標註先 `endInteractiveChange()` 結算，並把 `interaction` 重設為 `.none`；繪圖中的 draft／penPoints／startPoint 一併丟棄。
   - 效果：拖曳途中 undo/redo 後，後續 `mouseDragged` 不會再用快取的 `original`／`index` 覆寫已還原的內容；未移動的點擊被 undo 打斷後，放開滑鼠也不會留下未記錄的移動。鍵盤 monitor、`keyDown`、工具列 undo/redo 都經過同一個 `performHistory`。

新增 regression tests：

- Session：slider 改到一半 undo 只回拉前、有舊歷史時不會把標註 undo 掉、互動中真改內容後 redo 不跳分支、未變更手勢保留 redo、`canUndo`／`canRedo` 隨 pending gesture 正確變化。
- 實際 `SelectionView`（真實 `mouseDown`／`mouseDragged`／`mouseUp`／`keyDown`／工具列 closure）：拖曳中 `⌘Z` 只回拖前且後續拖曳不覆寫、點一下未移動時用工具列 undo 刪掉後一筆仍保留 redo 且之後拖曳不生效、繪圖預覽中 undo 會丟棄 draft 不提交。

`swift test`：55 個 ScreenshotTests + 17 個 SwitchKitTests，共 72 個測試、0 失敗。GUI 手動驗收仍未執行，複驗結果待主 agent 填寫。

### Review 修正（第二輪複查，2 個 P2）

1. **無效的 history 不可結算或破壞互動中的手勢**（`CaptureSession` + `SelectionOverlay`）
   - `undo()`／`redo()` 改為先以 `canUndo`／`canRedo` 做 gate，再 `resolveInteractiveChange()`。`canRedo` 在 pending gesture 真的改過內容時為 false，因此 slider 拖曳中按 `⇧⌘Z` 會直接 no-op：不會結算 pending、不會清 redo、不會把同一次手勢拆成多步；selection 也保留。`undo` 的 gate 同理，無效 undo 不會提前結束 coalescing。
   - `SelectionView.performHistory` 在呼叫 session 之前先檢查同一個 `canUndo`／`canRedo`；無效的 undo/redo 直接返回，不呼叫 `cancelCanvasInteractionForHistory()`，因此不會破壞進行中的標註拖曳或繪圖預覽。
   - 有效 undo 仍會清 selection；之後 slider 繼續送值只會改 `defaultStyle`，不進內容歷史（有測試）。
2. **history navigation 不再中斷選區本身的拖曳**（`SelectionOverlay`）
   - `cancelCanvasInteractionForHistory()` 只處理標註手勢（`.movingAnnotation`／`.resizingAnnotation`）與繪圖預覽（`.drawing`）；`.moving`／`.resizing`／`.creating`／`.none` 保持不動。
   - 選區縮放中的 undo 只還原標註，選區手勢繼續到 `mouseUp`，仍會執行原本的 `loadBase()`，因此凍結底圖與 copy/save 範圍保持正確。
   - interaction 分支與 history gate 的對應：history 只在 editing 時路由，所以 `.creating`／`.moving` 不會與 history 同時發生；`.resizing` 保留給 `mouseUp`；標註手勢與 draft 只在 history 有效時取消。

新增 regression tests（6 個）：

- Session：無效 redo 不破壞 slider coalescing、有舊 redo 但 pending 真變更時不跳舊分支、slider 中 undo 後續 tick 只改預設值。
- 實際 `SelectionView`：拖曳標註中按無效 `⇧⌘Z` 手勢繼續且整段拖曳仍是一步 undo；選區縮放中 undo 後繼續拖曳，`mouseUp` 仍重新載入放大後的底圖；無歷史時 undo 不會丟棄繪圖 draft（有歷史時才會取消並 undo）。

`swift test`：61 個 ScreenshotTests + 17 個 SwitchKitTests，共 78 個測試、0 失敗。GUI 手動驗收仍未執行，複查結果待主 agent 填寫。

### 最終複驗

- 實作與兩輪修正均由 `commandcode/deepseek/deepseek-v4.1-flash` 完成。
- `openai/gpt-6.1-sol#high` 分別完成 Standards 與 Spec 最終唯讀 review。
  - **Standards：通過，剩餘 findings 0。** 無文件規範違反；確認互動中的歷史結算、cached drag 清理及選區底圖更新路徑均已修正。
  - **Spec：通過，剩餘 findings 0。** 前兩輪四個 P2 均已修正；未發現新的需求缺漏或行為錯誤。
- 主 agent 獨立執行 `swift test`：61 個 ScreenshotTests + 17 個 SwitchKitTests，共 **78 個測試、0 失敗**。
- 主 agent 執行 `git diff --check`：通過。
- 測試完整輸出：`/private/var/folders/bm/4cj4n1m901j945_m7jk09w8h0000gn/T/opencode/annotation-style-final-tests.log`（暫存紀錄，非永久成品）。
- 未自動提交；三份既有使用者文件與滾動截圖實作保持不動。
- **剩餘驗收：真實 GUI 手動清單未執行。** 已有實際 `SelectionView` 滑鼠／鍵盤事件的自動化回歸測試，但不等同系統 GUI 中的 slider tracking、快捷鍵與即時畫面驗收，因此不宣稱已滿足原計畫的全部完成定義。

