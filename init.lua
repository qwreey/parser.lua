  --[[lit-meta
    name = "qwreey/parser"
    version = "2.1.2"
    dependencies = {}
    description = "Parsing support lib"
    tags = { "lua", "parsing" }
    license = "MIT"
    author = { name = "qwreey", email = "me@qwreey.moe" }
    homepage = "https://github.com/qwreey/parser.lua"
  ]]
  
local function createParser(comps)
	local len = #comps/2
	comps.__index = comps

	local function parse(str,start,verbose)
		local state = setmetatable({},comps)
		local strlen = #str
		local pos = start or 1
		local lastpos
		local init = comps.init
		local stop = comps.stop
		local orphans = comps.orphans
		local noEOF = comps.noEOF
		if init then init(state) end
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
				local oldFind = findCache[index] -- using memoization for performance
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
				local endAt, endup = func(state,str,pos,table.unpack(minFind,1,minFind.n))
				pos = (endAt or minFind[2]) + 1
				if verbose then
					print(" | Next : "..pos..", EndUp : "..tostring(endup))
				end

				-- If parse ended
				if endup then
					local result = state
					if stop then
						result = stop(state)
					end
					return result,endAt
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
	OpenTypes = {
		DoubleQuote = 1,
		SingleQuote = 2,
		Block = 3,
	};
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
	init = function (self)
		self.open = false
		self.buffer = {}
	end;
	stop = function (self)
		return concat(self.buffer)
	end;
}
return {
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

