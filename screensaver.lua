-- Widget for controlling black screen timeout using `xset`

-- Capture environment
local awful = require("awful")
local wibox = require("wibox")
local gears = require("gears")

local timer = gears.timer

local math = math
local string = string
local tostring = tostring
local tonumber = tonumber
local setmetatable = setmetatable

local exec = awful.spawn.easy_async


------------------------------------------
-- Compatibility with Lua <= 5.1
------------------------------------------

local _unpack = table.unpack or unpack

-- same as table.pack in lua 5.2:
local function pack(...)
    return {n = select('#', ...), ...}
end

-- different from table.unpack in lua.5.2:
local function unpack(t)
    return _unpack(t, 1, t.n)
end


------------------------------------------
-- Private utility functions
------------------------------------------

local function parse_sections(text)
  local result = {}
  local prefix = ""
  for key, val, suffix in (text .. "\nX"):gmatch("([^\n]*):\n(.-)\n(%S)") do
    result[(prefix .. key):lower()] = val
    prefix = suffix
  end
  return result
end

local function spawn_sequential(...)
  if select('#', ...) > 0 then
    local command = select(1, ...)
    local args = pack(select(2, ...))
    local exec_tail = function()
      spawn_sequential(unpack(args))
    end
    if type(command) == "function" then
      command()
      exec_tail()
    elseif command == nil then
      exec_tail()
    else
      exec(command, exec_tail)
    end
  end
end


------------------------------------------
-- Volume control interface
------------------------------------------

local screensaverctrl = {}

function screensaverctrl:new(args)
  return setmetatable({}, {__index = self}):init(args)
end

function screensaverctrl:init(args)

  self.unit = args.unit or 60
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

  self.timer = timer({ timeout = args.timeout or 3 })
  self.timer:connect_signal("timeout", function() self:update() end)
  self.timer:start()
  self:update()

  return self
end

function screensaverctrl:update()
  self:get(function(value)
    self:set_text(value)
  end)
end

function screensaverctrl:set_text(value)
  self.widget:set_text(string.format("(%d)", value))
end

function screensaverctrl:get(callback)
  self:get_seconds(function(seconds)
    callback(math.floor(seconds / self.unit + 0.5))
  end)
end

function screensaverctrl:get_seconds(callback)
  exec({'xset', 'q'}, function(output)
    callback(self:parse_status(output))
  end)
end

function screensaverctrl:parse_status(output)
  local parsed = parse_sections(output)
  local scrs = parsed['screen saver']
  local dpms = parsed['dpms (energy star)']
  local timeout = tonumber(scrs:match('timeout:%s+(%d+)'))
  local standby = tonumber(dpms:match('Standby:%s+(%d+)'))
  local suspend = tonumber(dpms:match('Suspend:%s+(%d+)'))
  local off     = tonumber(dpms:match(    'Off:%s+(%d+)'))
  local seconds = math.min(timeout, standby, suspend, off)
  return seconds
end

function screensaverctrl:set(value)
  self:set_seconds(value * self.unit)
end

function screensaverctrl:set_seconds(sec)
  local val = tostring(sec)
  spawn_sequential(
    {'xset', 's', val, val},
    {'xset', 'dpms', val, val, val},
    function() self:update() end)
end

function screensaverctrl:enable(finally)
  finally = finally or function() self:ensure_on() end
  spawn_sequential(
    {'xset', '+dpms'},
    {'xset', 's', 'on'},
    finally)
end

function screensaverctrl:disable(finally)
  finally = finally or function() self:update() end
  spawn_sequential(
    {'xset', '-dpms'},
    {'xset', 's', 'off'},
    finally)
end

function screensaverctrl:ensure_on()
  self:get(function(value)
    if value == 0 then
      self:set(self.step)
    else
      self:set_text(value)
    end
  end)
end

function screensaverctrl:up(step)
  self:get(function(value)
    if value == 0 then
      self:enable(function()
        self:set(step)
      end)
    else
      self:set(value + step)
    end
  end)
end

function screensaverctrl:down(step)
  self:get(function(value)
    if value <= step then
      self:disable(function()
        self:set(0)
      end)
    else
      self:set(value - step)
    end
  end)
end

function screensaverctrl:toggle()
  self:get(function(value)
    if value > 0 then
      self:disable()
    else
      self:enable()
    end
  end)
end

return setmetatable(screensaverctrl, {
  __call = screensaverctrl.new,
})
