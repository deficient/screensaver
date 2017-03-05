-- Widget for controlling black screen timeout using `xset`

-- Capture environment
local awful = require("awful")
local wibox = require("wibox")

local timer = timer

local math = math
local string = string
local table = table
local io = io
local tostring = tostring
local tonumber = tonumber
local setmetatable = setmetatable

-- screensaverctrl.mmt: module (class) metatable
-- screensaverctrl.wmt: widget (instance) metatable
local screensaverctrl = { mmt = {}, wmt = {} }
screensaverctrl.wmt.__index = screensaverctrl


------------------------------------------
-- Private utility functions
------------------------------------------

local function readcommand(command)
  local file = io.popen(command)
  local text = file:read('*all')
  file:close()
  return text
end

local function quote_arg(str)
  return "'" .. string.gsub(str, "'", "'\\''") .. "'"
end

local function quote_args(first, ...)
  if #{...} == 0 then
    return quote_arg(first)
  else
    return quote_arg(first), quote_args(...)
  end
end

local function make_argv(...)
  return table.concat({quote_args(...)}, " ")
end

local function exec(...)
  return readcommand(make_argv(...))
end

local function parse_sections(text)
  local result = {}
  local section = nil
  for line in text:gmatch('[^\n]+') do
    local sec_name = line:match('^(%S.*):$')
    if sec_name then
      section = {}
      result[sec_name:lower()] = section
    else
      table.insert(section, line)
    end
  end
  for k, v in pairs(result) do
    result[k] = table.concat(v, '\n')
  end
  return result
end


------------------------------------------
-- Volume control interface
------------------------------------------

function screensaverctrl.new(args)
  local sw = setmetatable({}, screensaverctrl.wmt)

  sw.step = args.step or 10
  sw.smallstep = args.smallstep or 1

  sw.widget = wibox.widget.textbox()
  sw.widget.set_align("right")

  sw.widget:buttons(awful.util.table.join(
    awful.button({ }, 1, function() sw:up(sw.step) end),
    awful.button({ }, 3, function() sw:down(sw.step) end),
    awful.button({ }, 2, function() sw:toggle() end),
    awful.button({ }, 4, function() sw:up(sw.smallstep) end),
    awful.button({ }, 5, function() sw:down(sw.smallstep) end)
  ))

  sw.timer = timer({ timeout = args.timeout or 3 })
  sw.timer:connect_signal("timeout", function() sw:get() end)
  sw.timer:start()
  sw:get()

  return sw
end

function screensaverctrl:get()
  local output = exec('xset', 'q')
  local parsed = parse_sections(output)

  local scrs = parsed['screen saver']
  local dpms = parsed['dpms (energy star)']

  local timeout = tonumber(scrs:match('timeout:%s+(%d+)'))
  local standby = tonumber(dpms:match('Standby:%s+(%d+)'))
  local suspend = tonumber(dpms:match('Suspend:%s+(%d+)'))
  local off     = tonumber(dpms:match(    'Off:%s+(%d+)'))

  local seconds = math.min(timeout, standby, suspend, off)
  local minutes = math.floor(seconds/60+0.5)

  self.widget:set_text(string.format("(%d)", minutes))
  return minutes
end

function screensaverctrl:set(minutes)
  local sec = minutes*60
  local val = tostring(sec)
  exec('xset', 's', val, val)
  exec('xset', 'dpms', val, val, val)
  self:get()
end

function screensaverctrl:enable()
  exec('xset', '+dpms')
  exec('xset', 's', 'on')
  if self:get() == 0 then
    self:set(self.step)
  end
end

function screensaverctrl:disable()
  exec('xset', '-dpms')
  exec('xset', 's', 'off')
  self:get()
end

function screensaverctrl:up(step)
  cur = self:get()
  if cur == 0 then
    self:enable()
  end
  self:set(cur + step)
end

function screensaverctrl:down(step)
  cur = self:get()
  if cur < step then
    cur = step
    self:disable()
  end
  self:set(cur - step)
end

function screensaverctrl:toggle()
  if self:get() > 0 then
    self:disable()
  else
    self:enable()
  end
end

function screensaverctrl.mmt:__call(...)
  return screensaverctrl.new(...)
end

return setmetatable(screensaverctrl, screensaverctrl.mmt)
