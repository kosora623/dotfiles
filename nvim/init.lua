-- 基本設定
vim.opt.number = true
vim.opt.cursorline = true
vim.opt.termguicolors = true
vim.opt.tabstop = 4
vim.opt.shiftwidth = 4
vim.opt.expandtab = true
vim.opt.clipboard = "unnamedplus"
vim.opt.ignorecase = true
vim.opt.smartcase = true
vim.opt.mouse = "a" 

-- ネイティブシェルをPowerShellに設定
if vim.fn.has("win32") == 1 then
    vim.opt.shell = "pwsh"
    vim.opt.shellcmdflag = "-NoProfile -ExecutionPolicy Bypass -Command [Console]::OutputEncoding = [System.Text.Encoding]::UTF8;"
    vim.opt.shellquote = ""
    vim.opt.shellxquote = ""
end

-- リーダーキーをスペース
vim.g.mapleader = " "

local lazypath = vim.fn.stdpath("data") .. "/lazy/lazy.nvim"
if not vim.loop.fs_stat(lazypath) then
  vim.fn.system({
    "git", "clone", "--filter=blob:none",
    "https://github.com/folke/lazy.nvim.git", "--branch=stable", lazypath,
  })
end
vim.opt.rtp:prepend(lazypath)

-- プラグインの登録と個別設定
require("lazy").setup({
  {
    "Mofiqul/vscode.nvim",
    config = function()
      vim.cmd("colorscheme vscode")
    end
  },

  { "nvim-tree/nvim-web-devicons" },

  {
    "nvim-neo-tree/neo-tree.nvim",
    branch = "v3.x",
    dependencies = {
      "nvim-lua/plenary.nvim",
      "nvim-tree/nvim-web-devicons",
      "MunifTanjim/nui.nvim",
    },
    config = function()
      require("neo-tree").setup({
        window = { width = 30 }
      })
      vim.keymap.set('n', '<leader>e', '<cmd>Neotree toggle<CR>', { silent = true })
    end
  },

  {
    "nvim-telescope/telescope.nvim",
    dependencies = { "nvim-lua/plenary.nvim" },
    config = function()
      -- ショートカット： スペース + f でファイル検索のポップアップを開く
      local builtin = require('telescope.builtin')
      vim.keymap.set('n', '<leader>f', builtin.find_files, {})
    end
  }
})


-- Ctrl + t で画面下部にターミナルをトグル（開閉）する設定
local term_buf = nil  -- 元のコードの「term_buff」のタイポを修正しました
local term_win = nil

function ToggleTerminal()
  if term_win and vim.api.nvim_win_is_valid(term_win) then
    -- ターミナルが開いているなら閉じる
    vim.api.nvim_win_close(term_win, true)
    term_win = nil
  else
    -- 画面を下分割して高さ10行でターミナルを開く
    vim.cmd("botright split")
    vim.cmd("resize 10")
    if term_buf and vim.api.nvim_buf_is_valid(term_buf) then
      vim.api.nvim_win_set_buf(0, term_buf)
    else
      vim.cmd("terminal")
      term_buf = vim.api.nvim_get_current_buf()
    end
    term_win = vim.api.nvim_get_current_win()
    -- 開いた瞬間に入力モード（Insert）にする
    vim.cmd("startinsert")
  end
end

-- ターミナルの開閉ショートカット (Ctrl + t)
vim.keymap.set('n', '<C-t>', ToggleTerminal, { silent = true })
vim.keymap.set('t', '<C-t>', ToggleTerminal, { silent = true })

-- ターミナル画面内での文字入力モードから一瞬で抜ける設定 (Escでノーマルに戻る)
vim.keymap.set('t', '<Esc>', [[<C-\><C-n>]], { silent = true })

vim.opt.splitbelow = true    -- 横分割(split)したとき、新しい画面を下にする
vim.opt.splitright = true    -- 縦分割(vsplit)したとき、新しい画面を右にする

-- コードの実行 --
vim.keymap.set('n', '<F5>', function()
  -- 編集中のファイルを自動で一旦上書き保存
  vim.cmd('write')
  
  -- 今開いているファイルの拡張子（py や c など）を取得
  local file_ext = vim.fn.expand('%:e')
  
  -- 拡張子に応じて実行コマンドを切り替える
  if file_ext == 'py' then
    -- [[ ]] で囲むことで、バックスラッシュやクォーテーションがそのまま安全にWindowsに渡ります
    vim.cmd([[!cmd.exe /c start cmd /k python -X utf8 "%"]])

  elseif file_ext == 'c' then
    -- 🌟 実行後に一時停止する処理を追加
    vim.cmd('!gcc "%" -o app ; if ($?) { .\\app } ; Write-Host "`nPress Enter to continue..." ; Read-Host')

  elseif file_ext == 'cpp' then
    -- 🌟 C++ も同様に、実行後に一時停止する処理を追加
    vim.cmd('!g++ "%" -o app ; if ($?) { .\\app } ; Write-Host "`nPress Enter to continue..." ; Read-Host')

  elseif file_ext == 'js' then
    vim.cmd('!node "%" ; Write-Host "`nPress Enter to continue..." ; Read-Host')

  elseif file_ext == 'ts' then
    vim.cmd('!ts-node "%" ; Write-Host "`nPress Enter to continue..." ; Read-Host')

  elseif file_ext == 'go' then
    vim.cmd('!go run "%" ; Write-Host "`nPress Enter to continue..." ; Read-Host')

  elseif file_ext == 'java' then
    vim.cmd('!java "%" ; Write-Host "`nPress Enter to continue..." ; Read-Host')

  else
    print("このファイルの実行コマンドが登録されていません")
  end

end, { silent = true })