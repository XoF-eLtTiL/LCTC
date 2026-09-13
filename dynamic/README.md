# LCTC GitHub 動態翻譯資料

這個資料夾必須放在 `XoF-eLtTiL/LCTC` 的 `main` 分支根目錄下。

- `files/terminal/`：終端機模組翻譯。
- `files/game/Text/`：遊戲本體 XUnity 文字翻譯。
- `files/game/Texture/`：遊戲本體翻譯貼圖。
- `manifest.txt`：SHA-256 與檔案大小清單。

更新方式：

```powershell
.\scripts\update-translations.ps1
```

腳本會從原版 Steam 遊戲的 `BepInEx\config` 收集翻譯，驗證白名單後重新產生 SHA-256 清單。確認內容後可執行：

```powershell
.\scripts\update-translations.ps1 -Publish
```

DLL 只接受以上三個固定路徑中的 `.txt` 與 `.png`，不會下載或執行程式碼。倉庫的 `.gitignore` 也會排除 C#、專案檔、DLL 與建置輸出。
