
local Entities  = {
   ["lt"]   = "<",
   ["gt"]   = ">",
   ["amp"]  = "&",
   ["quot"] = '"',
   ["apos"] = "'"
}

local Escapes  = {
   ["<"]   = "&lt;",
   [">"]   = "&gt;",
   ['"'] = "&quot;",
   ["'"] = "&apos;"
}

local entEsc = function(Item) 
   return Escapes[Item]
end

local entUnEsc = function(Entity)
   return Entities[Entity]
end

local numUnEsc = function(Prefix, Number)
   return Prefix == '#' and string.char(Number) 
     or Prefix == '#x' and string.char(tonumber(Number, 16))
end

function entUnescape(String)
   local UnEsc = String:rxsub('&(#)(\\d{2});', numUnEsc)
   UnEsc = UnEsc:rxsub('&(#x)([\\da-fA-F]{2});', numUnEsc)
   UnEsc = UnEsc:rxsub('&(lt|gt|amp|quot|apos);', entUnEsc)
   return UnEsc
end

function entEscape(String) 
   local Esc = String:gsub('&', '&amp;')
   Esc = Esc:rxsub('(<|>|"|\')', entEsc)
   return Esc
end
