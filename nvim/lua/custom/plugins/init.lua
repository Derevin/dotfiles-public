-- You can add your own plugins here or in other files in this directory!
--  I promise not to create any merge conflicts in this directory :)
--
-- See the kickstart.nvim README for more information
return {
  {
    'nvim-neo-tree/neo-tree.nvim',
    branch = 'v3.x',
    dependencies = {
      'nvim-lua/plenary.nvim',
      'MunifTanjim/nui.nvim',
    },
    keys = {
      { '<leader>e', '<cmd>Neotree toggle<cr>', desc = 'File explorer' },
    },
    opts = {
      event_handlers = {
        {
          event = 'file_opened',
          handler = function()
            require('neo-tree.command').execute { action = 'close' }
          end,
        },
      },
      filesystem = {
        follow_current_file = { enabled = true },
        filtered_items = {
          visible = true,
        },
      },
    },
  },
  {
    'folke/persistence.nvim',
    event = 'BufReadPre',
    opts = {},
    keys = {
      { '<leader>qs', function() require('persistence').load() end, desc = 'Restore session' },
      { '<leader>qd', function() require('persistence').stop() end, desc = "Don't save session" },
    },
    init = function()
      vim.api.nvim_create_autocmd('VimEnter', {
        nested = true,
        callback = function()
          if vim.fn.argc() == 0 and not vim.g.started_with_stdin then
            require('persistence').load()
          end
        end,
      })
    end,
  },
}
