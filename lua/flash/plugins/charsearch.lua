local require = require("flash.require")

local Util = require("flash.util")
local Repeat = require("flash.repeat")

local M = {}

---@alias Flash.CharSearch.Motion "'f'" | "'F'" | "'t'" | "'T'"
M.motion = nil ---@type Flash.CharSearch.Motion?
M.char = nil ---@type string?
M.jumping = false
M.state = nil ---@type Flash.State?

---@type table<Flash.CharSearch.Motion, Flash.State.Config>
M.motions = {
  f = { highlight = { label = { after = { 0, 0 } } } },
  t = {},
  F = { search = { forward = false }, highlight = { label = { after = { 0, 0 } } } },
  T = { search = { forward = false }, highlight = { label = { before = true, after = false } } },
}

function M.new()
  local State = require("flash.state")
  ---@type Flash.State.Config
  local opts = {
    labeler = function(state)
      -- set to empty label, so that the character will just be highlighted
      for _, m in ipairs(state.results) do
        m.label = ""
      end
    end,
    search = {
      wrap = false,
      multi_window = false,
      abort_pattern = false,
      mode = "search",
    },
    highlight = {
      backdrop = true,
    },
    jump = {
      register = false,
    },
  }
  return State.new(vim.tbl_deep_extend("force", opts, M.motions[M.motion] or {}))
end

function M.pattern()
  local c = M.char:gsub("\\", "\\\\")
  local pattern ---@type string
  if M.motion == "t" then
    pattern = "\\m.\\ze\\V" .. c
  elseif M.motion == "T" then
    pattern = "\\V" .. c .. "\\zs\\m."
  else
    pattern = "\\V" .. c
  end
  return pattern
end

function M.visible()
  return M.state and M.state.visible
end

function M.setup()
  for _, key in ipairs({ "f", "F", "t", "T", ";", "," }) do
    vim.keymap.set({ "n", "x", "o" }, key, function()
      if Repeat.is_repeat then
        M.jumping = true
        M.state:jump({ count = vim.v.count1 })
        M.state:show()
        vim.schedule(function()
          M.jumping = false
        end)
      else
        M.jump(key)
      end
    end, {
      silent = true,
    })
  end

  vim.api.nvim_create_autocmd({ "BufLeave", "CursorMoved", "InsertEnter" }, {
    callback = function()
      if not M.jumping and M.state then
        M.state:hide()
      end
    end,
  })

  vim.on_key(function(key)
    if M.state and key == Util.ESC and vim.fn.mode() == "n" then
      M.state:hide()
    end
  end)
end

function M.parse(key)
  -- repeat last search when hitting the same key
  if M.visible() and M.motion == key then
    key = ";"
  end
  -- different motion, clear the state
  if M.motions[key] and M.motion ~= key then
    if M.state then
      M.state:hide()
    end
    M.motion = key
  end
  return key
end

function M.jump(key)
  key = M.parse(key)
  if not M.motion then
    return
  end

  -- always re-calculate when not visible
  M.state = M.visible() and M.state or M.new()
  M.jumping = true

  -- get a new target
  if M.motions[key] or not M.char then
    local char = Util.get_char()
    if char then
      M.char = char
    else
      return M.state:hide()
    end
  end

  -- update the state when needed
  if M.state.pattern:empty() then
    M.state:update({ pattern = M.pattern() })
  end

  local forward = M.state.opts.search.forward
  if key == "," then
    forward = not forward
    -- check if we should enable wrapping.
    if not M.state.opts.search.wrap then
      local before = M.state:find({ count = 1, forward = forward })
      if before and (before.pos < M.state.pos) == M.state.opts.search.forward then
        M.state.opts.search.wrap = true
        M.state:update({ force = true })
      end
    end
  end

  M.state:jump({ count = vim.v.count1, forward = forward })

  vim.schedule(function()
    M.jumping = false
  end)
  return M.state
end

return M