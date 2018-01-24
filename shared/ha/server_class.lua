require "html_entities"

local function DoubleCheckResult(Url, Result)
   if Url:sub(-9, -1) ~= 'api_query' then 
      return true 
   end
   local Tree = xml.parse{data=Result}
   if Tree.export.success:nodeValue() == 'true' then
      return true
   end
   if Tree.export:childCount('error') > 0 
      and Tree.export:child('error').description:nodeValue() == 'Authentication failed.' then
      return false
   end   
   return true
end

local Server = {}
--
-- This module is a Server class object.
--
-- These server objects make it easy to make API calls. They know their URL,
-- their main configuration, have a list of the channels configurations, as
-- well as their login cookie for making API request with.
--
-- The Server constructor requires a URL. It fetches everything it needs from
-- This URL. The constructor (somewhat unusually) takes a filter function which
-- will cause it to return nil instead of the server object. This is useful for
-- managing a list of servers and came out while working on the Sync Manager
-- and the Poller Manager. If a server is not configured for syncing, it won't
-- bother constructing it.
--
function Server:new(Url, Cookie, filterServerFunc)
   local ServerObject = {url = Url, LoginCookie = Cookie}
   setmetatable(ServerObject, self)
	self.__index = self
   
   local Success, ServerConfigXml, Code, Headers 
      = pcall(ServerObject.apiCall, ServerObject, net.http.get, {
      url   = ServerObject.url .. 'get_server_config',
      live  = true,
      cache_time = conf.cache_time,
   })
   
   if not Success then
      -- In this case, ServerConfigXml is a friendly error message
      return nil, ServerConfigXml
   end

   local ServerConfig = xml.parse{data=ServerConfigXml}
   if filterServerFunc then
      local ShouldFilter = filterServerFunc(Url, ServerConfig)
      if ShouldFilter then
         return nil, "Server was filtered out."
      end
   end

   ServerObject.config = ServerConfig
   local ChannelConfigs = ServerObject:collectChannelConfigsForServer()
   ServerObject.channel_configs = ChannelConfigs

   return ServerObject
end

--
-- Make an API call with this. It will login if it has to and use
-- the login cookie on subsequent API calls.
--
function Server:apiCall(Func, Params)
   trace(self.url)
   trace(self.LoginCookie)

   Params.headers = { Cookie = self.LoginCookie }
   local Result, Code, Headers = Func(Params)
	trace(Code)
   -- The different URLs return "Not logged in" in different
   -- manners, so if it's not a 200, try logging in and if it
   -- still fails it's back to regular behaviour.

   if Code ~= 200 
      or not DoubleCheckResult(Params.url, Result) then
      self:apiLogin()
      trace(self.LoginCookie)
      Params.headers = { Cookie = self.LoginCookie }
      Result, Code, Headers = Func(Params)
   end
   return Result, Code, Headers
end
help.set{input_function=Server.apiCall, help_data={Usage = "local R, C, H = apiCall(Server, net.http.get, SameTableNetHttpGetWouldTake)",}}

function Server:apiLogin()
   local Status, Code, Headers = net.http.get{
      url  = self.url .. '/login.html',
      auth = conf.auth,
      live = true,
   }
   trace(Code)
   trace(Headers)
   -- I'm quite sure there should only be one cookie.
   -- Should probably add logic to ensure it's the session cookie.
   local LoginCookie = Headers["Set-Cookie"]
   self.LoginCookie = LoginCookie
   trace(self.url)
   trace(LoginCookie)
end

--
-- Helper for collectChannelConfigsForServer()
--
function Server:collectChannelConfigs(Group, Collection) 
   for i=1, Group:childCount() do
      local Name = entUnescape(Group[i].channel_name:S())
      local Channel = self:apiCall(net.http.get, {
         url        = self.url .. 'get_channel_config',
         parameters = { name = Name },
         live       = true,
         cache_time = conf.cache_time,
      })

      Collection[Name] = xml.parse{data=Channel}
   end
end
--
-- Fetch the channel configurations for this remote Iguana.
--
function Server:collectChannelConfigsForServer()
   local Channels = {}
   local Grps = self.config.iguana_config.channel_groupings
   local GrpCount = Grps:childCount()

   for i=1, GrpCount do 
      if Grps[i].grouping_name:S() == "All Channels" then
         self:collectChannelConfigs(Grps[i].channels, Channels)
         break
      end
   end

   return Channels
end

--
-- Get XML configuration for remotes configured on this Iguana. This is (partly)
-- how we know which Iguanas to synchronize.
--
function Server:getRemotes()
   local Remotes = {}
   local RemotesConf = self.config.iguana_config.remote_iguana_list
	
   if not RemotesConf then
      error("No remote Iguanas are configured.")
   end

   local Count = RemotesConf:childCount("remote_iguana")
   for i = 1, Count do 
      Remotes[i] = RemotesConf:child('remote_iguana', i)
   end

   return Remotes
end

--
-- Static functions.
--
-- Assemble a URL from a local Iguana's config. 
--
function Server.makeUrl(WebInfo, ForChannel)
   local Loc = ForChannel 
               and 'https_channel_server' 
               or 'web_config'
   local UrlParts = {}
   UrlParts[1] = 'http'
   if WebInfo[Loc].use_https 
      then UrlParts[1] = UrlParts[1] .. 's'
   end
   UrlParts[2] = '://'
   UrlParts[3] = WebInfo.host
   UrlParts[4] = ':'
   UrlParts[5] = WebInfo[Loc].port
   UrlParts[6] = '/'
   return table.concat(UrlParts)
end
--
-- Assemble a URL for a Remote Iguana.
--
function Server.makeRemoteUrl(Remote) 
   local UrlParts = {}
   UrlParts[1] = 'http'
   if Remote.https:nodeValue() == 'true'
      then UrlParts[1] = UrlParts[1] .. 's'
   end
   UrlParts[2] = '://'
   UrlParts[3] = Remote.host:nodeValue()
   UrlParts[4] = ':'
   UrlParts[5] = Remote.port:nodeValue()
   UrlParts[6] = '/'
   trace(UrlParts)
   return table.concat(UrlParts)
end

function Server.fillServerList(Servers, filterServerFunc)
   local ExistingCookie = Servers.this and Servers.this.LoginCookie or nil
   Servers.this = Server:new(Server.makeUrl(iguana.webInfo()), ExistingCookie)

   if not Servers.remotes then 
      Servers.remotes = {}
      Servers.remotesCount = 0
   end

   local GoodUrls = {}
   local Remotes = Servers.this:getRemotes() 
   for i=1, #Remotes do
      local RemoteUrl = Server.makeRemoteUrl(Remotes[i])
      GoodUrls[RemoteUrl] = true
      ExistingCookie = Servers.remotes[RemoteUrl] 
                       and Servers.remotes[RemoteUrl].LoginCookie 
                       or nil

      local TheServer = Server:new(RemoteUrl, ExistingCookie, filterServerFunc)

      if TheServer then
         Servers.remotes[RemoteUrl] = TheServer
         Servers.remotesCount = Servers.remotesCount + 1
         trace(Servers.remotesCount)
      end
   end

   for Url, Server in pairs(Servers.remotes) do 
      if not GoodUrls[Url] then
         Servers.remotes[Url] = nil
         Servers.remotesCount = Servers.remotesCount - 1
      end
   end

   return Servers
end

return Server