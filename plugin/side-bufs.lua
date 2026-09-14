if vim.g.loaded_side_bufs then
	return
end
vim.g.loaded_side_bufs = true

vim.api.nvim_create_user_command("SideBufsOpen", function()
	require("side-bufs").open()
end, {})

vim.api.nvim_create_user_command("SideBufsClose", function()
	require("side-bufs").close()
end, {})

vim.api.nvim_create_user_command("SideBufsToggle", function()
	require("side-bufs").toggle()
end, {})

vim.api.nvim_create_user_command("SideBufsPick", function()
	require("side-bufs").pick()
end, {})

vim.api.nvim_create_user_command("SideBufsPickClose", function()
	require("side-bufs").pick_close()
end, {})
