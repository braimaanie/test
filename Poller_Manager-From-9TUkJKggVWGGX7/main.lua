---------------------------------------
-- Iguana Tools Poller Manager 0.9
-- Copyright © 2016 iNTERFACEWARE, Inc.
-- All Rights Reserved
---------------------------------------

-- The Poller Manager provides HA for Iguana Channels which poll/fetch their own data,
-- as opposed to feed/listening channels I.e. everything but From LLP and From HTTP.
-- 
-- To be managed by the Poller Manager an Iguana must appear in the Remote Iguana
-- list and also have be explicitly configured. The URL of the remote Iguana must
-- match the key of the conf.servers object.
--
conf = require "ha.conf"
PollerManagerConf = require "conf"
require "net.http.cache"
-- This is a Lua "class"
poller_manager = require "poller_manager"

local function serverFilter(Url, ServerConfig)
   if PollerManagerConf.weights[Url] then
      return false
   else
      return true
   end   
end

ThePollerManager = poller_manager:new(PollerManagerConf, serverFilter)

function main()
   ThePollerManager:fillServersList()

   local IsActive, KeepWaiting = ThePollerManager:run()

   trace(IsActive, KeepWaiting)

   if not IsActive then
      ThePollerManager:stopChannels()
   elseif IsActive and KeepWaiting then
      ThePollerManager:wait()
   elseif IsActive and not KeepWaiting then
      ThePollerManager:startChannels()
   end
end

