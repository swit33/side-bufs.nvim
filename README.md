# side-bufs.nvim

A small native Neovim buffer sidebar with one-key picking.

- Native left or right split; no window-management dependency
- One-key buffer switching and deletion
- Duplicate filename disambiguation
- Current and modified buffer indicators
- Mouse support
- Optional `nvim-web-devicons` integration

## Requirements

- Neovim 0.12+
- `nvim-web-devicons` is optional

## Installation

With lazy.nvim:

```lua
{
	"your-name/side-bufs.nvim",
    dependencies = {
        "nvim-tree/nvim-web-devicons", -- optional for icons
    },
	opts = {},
	keys = {
		{ "<leader>1", "<cmd>SideBufsToggle<cr>", desc = "Toggle buffer sidebar" },
		{ "'", "<cmd>SideBufsPick<cr>", desc = "Pick buffer" },
		{ "<leader>'", "<cmd>SideBufsPickClose<cr>", desc = "Pick and delete buffer" },
	},
}
```

## Configuration

Defaults:

```lua
require("side-bufs").setup({
	side = "left",
	width = 25,
})
```

## Edgy integration

The sidebar buffer uses the `side-bufs` filetype, so Edgy can capture it without any plugin-side integration:

```lua
left = {
	{ 
		title = "Buffers",
		ft = "side-bufs",
		pinned = true,
		open = function()
			require("side-bufs").open()
		end,
	},
}
```

## Commands

- `:SideBufsOpen`
- `:SideBufsClose`
- `:SideBufsToggle`
- `:SideBufsPick`
- `:SideBufsPickClose`

## Sidebar mappings

- `<CR>` or left click: open the selected buffer in the editor
- `p`: pick a buffer by letter
- `d`: delete the selected buffer
- `q` or `<Esc>`: close the sidebar

## Lua API

```lua
local side_bufs = require("side-bufs")

side_bufs.open()
side_bufs.close()
side_bufs.toggle()
side_bufs.pick()
side_bufs.pick_close()
```

## Credits

[bufferline.nvim](https://github.com/akinsho/bufferline.nvim) - inspiration for picker UX.
