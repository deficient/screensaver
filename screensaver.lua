-- Widget for controlling black screen timeout using `xset`

-- Capture environment
local awful = require("awful")
local wibox = require("wibox")
local gears = require("gears")

local math = math
local string = string
local table = table
local io = io
local tostring = tostring
local tonumber = tonumber
local setmetatable = setmetatable


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

local screensaverctrl = {}

function screensaverctrl:new(args)
  return setmetatable({}, {__index = self}):init(args)
end

function screensaverctrl:init(args)

  self.step = args.step or 10
  self.smallstep = args.smallstep or 1

  self.widget = wibox.widget.textbox()
  self.widget.set_align("right")

  self.widget:buttons(awful.util.table.join(
    awful.button({ }, 1, function() self:up(self.step) end),
    awful.button({ }, 3, function() self:down(self.step) end),
    awful.button({ }, 2, function() self:toggle() end),
    awful.button({ }, 4, function() self:up(self.smallstep) end),
    awful.button({ }, 5, function() self:down(self.smallstep) end)
  ))

  self.timer = gears.timer({ timeout = args.timeout or 3 })
  self.timer:connect_signal("timeout", function() self:get() end)
  self.timer:start()
  self:get()

  return self
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

return setmetatable(screensaverctrl, {
  __call = screensaverctrl.new,
})
