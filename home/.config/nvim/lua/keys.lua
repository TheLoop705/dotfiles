-- save by pressing Escape
vim.keymap.set('n', '<Esc>', ':w<CR>', { desc = 'Save' })
vim.keymap.set('n', '<leader>w', ':w<CR>', { desc = 'Save' })
vim.keymap.set('n', '<leader>q', ':q<CR>', { desc = 'Quit' })
-- select all
vim.keymap.set('n', '<C-a>', 'ggVG', { desc = 'Select All' })
-- pasting over a selection no longer clobbers your clipboard
vim.cmd([[ xnoremap <expr> p 'pgv"'.v:register.'y' ]])

-- German keyboard friendly navigation: prefer leader letters over bracket keys.
vim.keymap.set('n', '<leader>h', '<C-w>h', { desc = 'Window Left' })
vim.keymap.set('n', '<leader>j', '<C-w>j', { desc = 'Window Down' })
vim.keymap.set('n', '<leader>k', '<C-w>k', { desc = 'Window Up' })
vim.keymap.set('n', '<leader>l', '<C-w>l', { desc = 'Window Right' })
vim.keymap.set('n', '<leader>sv', ':vsplit<CR>', { desc = 'Split Right' })
vim.keymap.set('n', '<leader>ss', ':split<CR>', { desc = 'Split Below' })
vim.keymap.set('n', '<leader>n', ':bnext<CR>', { desc = 'Next Buffer' })
vim.keymap.set('n', '<leader>p', ':bprevious<CR>', { desc = 'Previous Buffer' })
vim.keymap.set('n', '<Tab>', ':bnext<CR>', { desc = 'Next Buffer' })
vim.keymap.set('n', '<S-Tab>', ':bprevious<CR>', { desc = 'Previous Buffer' })
vim.keymap.set('n', '<leader>dn', vim.diagnostic.goto_next, { desc = 'Next Diagnostic' })
vim.keymap.set('n', '<leader>dp', vim.diagnostic.goto_prev, { desc = 'Previous Diagnostic' })
vim.keymap.set('t', '<Esc><Esc>', '<C-\\><C-n>', { desc = 'Terminal Normal Mode' })
