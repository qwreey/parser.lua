  --[[lit-meta
    name = "qwreey/parser"
    version = "2.1.3"
    dependencies = {}
    description = "Parsing support lib"
    tags = { "lua", "parsing" }
    license = "MIT"
    author = { name = "qwreey", email = "me@qwreey.moe" }
    homepage = "https://github.com/qwreey/parser.lua"
  ]]
  
--[[
# parser.lua - qwreey/parser

todo
{"'", "[["}, func
style handler

should impl
 - mustReachEnd
 - cache

## Parser options

## Basic uses

### noEOF - Simple ${value} parser
All parser should have 'init', 'stop', 'orphans' and regex/handlers (Not always)
```lua
-- Execute all regular expressions, and execute the function of the closest match.
-- If they exist in exactly the same place, execute the function of the one further up in the code (preceded by the index).
local simpleParser = createParser {
	-- Regex, and handle function
	"%${([%w_]+)}", function(self,str,pos,startAt,endAt,match1) -- self(context), original string, and string.find results
		table.insert(self.inst,{t="val", v=match1})
		-- Handler function can return next search start position and whether parsing has ended
		-- If function returns nothing, use endAt+1 as next search position
	end;

	-- Handle characters not found by matching
	orphans = function (self,orphan)
		-- Raise an error if a character not found by matching shouldn't exist
		-- Or handle orphan string
		table.insert(self.inst,{t="str", v=orphan})
	end;

	-- Execute when parsing started
	init = function (self,str,pos)
		-- print(pos) -- 1, starting position
		self.inst = {}
		-- init can return starting position. If return nothing, use pos as staring position
	end;

	-- Execute when parsing ended. it should return result (If not, use self as result)
	stop = function (self)
		return self.inst
	end;

	-- This means that there may be no terminator (EOF), and parsing may proceed to the end of the string.
	-- If this value is not present, an error will be thrown if no terminator is found before the end of the string is reached
	noEOF = true;

	-- Whether use result caching. Only use if result won't change every time you parse same value
	-- This can be useful if you'll be using the same value over and over again
	cache = true;
}
-- simpleParser will return result and ending position
local result = simpleParser("test${value1}test")
print(result)
-- { {t="str", v="test"}, {t="val", v="value1"}, {t="str", v="test"} }
-- 17
print(simpleParser("test${value1}test") == result) -- true (cached)
```

#### Extend - Formatter
You can create simple formatter like below
```lua
local function f(format)
	local parsed = simpleParser(format)
	return function (tbl)
		local buffer = {}
		for _,item in ipairs(parsed) do
			if item.t == "str" then
				table.insert(buffer,item.v)
			elif item.t == "val" then
				table.insert(buffer,tostring(tbl[item.v]))
			end
		end
		return table.concat(buffer)
	end
end
print(
	f "Hello ${name}" {
		name = "qwreey";
	}
) -- Hello qwreey
```

### EOF - Simple string parsing
```lua
local simpleStringParser = createParser {
	-- Ending
	"['\"]" = function (self,str,pos,startAt,endAt)
		-- If return true like below, parsing will end up
		return endAt+1,true
	end;

	-- Escape
	"\\(['\"])" = function (self,str,pos,startAt,endAt,match1)
		table.insert(self.buffer,match1)
	end;

	orphans = function (self,orphan)
		table.insert(self.buffer,orphan)
	end;
	init = function (self,str,pos)
		self.start == str:sub(pos,pos) -- save starting char
		self.buffer = {}
		if self.start ~= "'" and self.start ~= "\"" then -- check starting
			error("Not allowed starting " .. tostring(self.start))
		end
		return pos+1 -- 2, means first char should be ignored (Processed)
	end;
	stop = function (self)
		return table.concat(self.buffer)
	end;

	-- Whether there should be no more trailing characters after the end of parsing.
	mustReachEnd = true;
}
print(simpleStringParser('"Hello world"')) -- 'Hello world'  13
-- print(simpleStringParser('"Hello world" tailing characters')) -- error
simpleStringParser.mustReachEnd = false
print(simpleStringParser(' "Hello world" tailing characters'), 2) -- 'Hello world'  14
```

## subParser

## basic escapes

]]

local function createParser(comps)
	local len = #comps/2
	comps.__index = comps
	comps.__parser = true

	for _,v in pairs(comps) do
		if type(v) == "table" and rawget(v,"__parser") and (not v.parent) then
			v.super = comps
		end
	end

	local function parse(str,start,verbose)
		local state = setmetatable({},comps)
		local strlen = #str
		local pos = start or 1
		local lastpos
		local init = comps.init
		local stop = comps.stop
		local orphans = comps.orphans
		local noEOF = comps.noEOF
		if init then
			local initPos,initEndup = init(state,str,pos)
			if initPos then pos = initPos end
			if initEndup then
				local result = state
				if stop then
					result = stop(state)
				end
				return result,pos
			end
		end
		local findCache = {}

		while true do
			if verbose then print("LOOP: pos "..pos) end

			-- Check infinity loop
			if pos == lastpos then
				error("Infinite loop detected")
			end
			lastpos = pos

			-- Check buffer exhaust
			if pos >= strlen then
				if noEOF then -- EOF is not required
					-- Process orphans
					if orphans and strlen >= pos then
						local orphanString = string.sub(str,pos,strlen)
						if orphanString ~= "" then
							if verbose then print(" | Push orphans : "..orphanString) end
							orphans(state,orphanString,true) -- is Tailing
						end
					end

					-- Make result
					local result = state
					if stop then
						result = stop(state)
					end
					return result,strlen
				end
				error("Buffer exhausted") -- EOF is required
			end

			-- Loop matchers
			local minStartAt = math.huge
			local minFind
			local minIndex
			for index=1,len do
				-- Check old cache by position
				local find
				local oldFind = findCache[index] -- use memoization for performance
				if oldFind and oldFind[1] and oldFind[1] >= pos then
					find = oldFind
				elseif (not oldFind) or (oldFind and oldFind[1]) then
					local regex = comps[index*2-1]
					find = table.pack(string.find(str,regex,pos))
					findCache[index] = find
				end

				-- Check min startat
				local startAt = find and find[1]
				if startAt and minStartAt > startAt then
					minStartAt = startAt
					minFind = find
					minIndex = index
				end
			end

			if minFind then -- If matchd
				local func = comps[minIndex*2]
				if verbose then
					print("From "..pos..": "..comps[minIndex*2-1].." ("..minStartAt.."~"..minFind[2]..")")
				end

				-- Push orphans
				if orphans and minStartAt-1 >= pos then
					local orphanString = string.sub(str,pos,minStartAt-1)
					if orphanString ~= "" then
						if verbose then print(" | Push orphans : "..orphanString) end
						orphans(state,orphanString,false)
					end
				end

				-- Call function and update position
				local nextPos, endup = func(state,str,pos,table.unpack(minFind,1,minFind.n))
				pos = nextPos or (minFind[2] + 1)
				if verbose then
					print(" | Next : "..pos..", EndUp : "..tostring(endup))
				end

				-- If parse ended
				if endup then
					local result = state
					if stop then
						result = stop(state)
					end
					return result,pos - 1
				end
			else
				-- no token found
				if verbose then print("No more token") end
				if noEOF then -- if EOF is not required
					-- Process orphans
					if orphans and strlen >= pos then
						local orphanString = string.sub(str,pos,strlen)
						if orphanString ~= "" then
							if verbose then print(" | Push orphans : "..orphanString) end
							orphans(state,orphanString,true) -- is Tailing
						end
					end

					-- Make result
					local result = state
					if stop then
						result = stop(state)
					end
					return result,strlen
				end
				error("No token found")
			end
		end
	end
	comps.parse = parse

	setmetatable(comps,{
		__call = function (self,...)
			return parse(...)
		end
	})
	return comps
end

local function commonEscapes(char)
	if     char == "n"  then return "\n"
	elseif char == "r"  then return "\r"
	elseif char == "f"  then return "\f"
	elseif char == "v"  then return "\v"
	elseif char == "b"  then return "\b"
	elseif char == "\\" then return "\\"
	elseif char == "t"  then return "\t"
	elseif char == "\"" then return "\""
	elseif char == "\'" then return "\'"
	elseif char == "a"  then return "\a"
	elseif char == "z"  then return "\z"
	end
end

local utf8 = utf8 or require "utf8"
local function luaEscapes(func)
	return "\\u{(%x+)}",   function (self,str,pos,startAt,endAt,hex) return func(self,str,pos,startAt,endAt,utf8.char(tonumber(hex,16))) end,
	       "\\(%d%d?%d?)", function (self,str,pos,startAt,endAt,num) return func(self,str,pos,startAt,endAt,string.char(num)) end,
	       "\\x(%x%x?)",   function (self,str,pos,startAt,endAt,hex) return func(self,str,pos,startAt,endAt,string.char(tonumber(hex,16))) end,
	       "\\(.)",        function (self,str,pos,startAt,endAt,char) return func(self,str,pos,startAt,endAt,commonEscapes(char)) end
end

function ignore(_,_,_,_,endAt)
	return endAt
end
function eof(_,_,_,_,endAt)
	return endAt,true
end

local concat = table.concat
local insert = table.insert
local luaStringParser = createParser {
	super = true;
	
	blockQuoteParser = createParser {
		"%]%]", eof;
		init = function (self) self.buffer = {} end;
		stop = function (self) return concat(self.buffer) end;
		orphans = function (self,str) insert(self.buffer,str) end;
	};
	"\"", function (self,str,pos,startAt,endAt)
		if self.open == self.OpenTypes.DoubleQuote then
			return endAt,true
		end
		if self.open then
			insert(self.buffer,"\"")
		else
			self.open = self.OpenTypes.DoubleQuote
		end

		return endAt
	end;
	"'", function (self,str,pos,startAt,endAt)
		if self.open == self.OpenTypes.SingleQuote then
			return endAt,true
		end
		if self.open then
			insert(self.buffer,"'")
		else
			self.open = self.OpenTypes.SingleQuote
		end

		return endAt
	end;
	"%[%[", function (self,str,pos,startAt,endAt)
		if not self.open then
			local blockQuoteString,blockQuoteEndAt = self.blockQuoteParser(str,endAt+1)
			insert(self.buffer,blockQuoteString)
			return blockQuoteEndAt,true
		end

		insert(self.buffer,"[[")
		return endAt
	end;
	luaEscapes(function (self,str,pos,startAt,endAt,char)
		insert(self.buffer,char)
		return endAt
	end);

	orphans = function (self,str)
		insert(self.buffer,str)
	end;
	OpenTypes = {
		DoubleQuote = 1,
		SingleQuote = 2,
		Block = 3,
	};
	openParser = createParser {
		"^\"", function (self,str,pos,startAt,endAt)
			self.value = self.super.OpenTypes.DoubleQuote
			return endAt,true
		end;
		"^'", function (self,str,pos,startAt,endAt)
			self.value = self.super.OpenTypes.SingleQuote
			return endAt,true
		end;
		"^%[%[", function (self,str,pos,startAt,endAt)
			self.value = self.super.OpenTypes.SingleQuote
			return endAt,true
		end;
		stop = function (self) return self.value end;
	};
	init = function (self,str,pos)
		self.open,pos = self.openParser(str,pos)
		self.buffer = {}
	end;
	stop = function (self)
		return concat(self.buffer)
	end;
}
return {
	version = "2.1.3";
	createParser = createParser;
	whitespaces = "%s+";
	eof = eof;
	ignore = ignore;
	commonEscapes = function (func)
		return "\\(.)", function(self,str,pos,startAt,endAt,char)
			return func(self,str,pos,startAt,endAt,commonEscapes(char))
		end
	end;
	luaEscapes = luaEscapes;
	luaStringParser = luaStringParser;
}

