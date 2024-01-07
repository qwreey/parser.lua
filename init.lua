  --[[lit-meta
    name = "qwreey/parser"
    version = "2.1.4"
    dependencies = {}
    description = "Parsing support lib"
    tags = { "lua", "parsing" }
    license = "MIT"
    author = { name = "qwreey", email = "me@qwreey.moe" }
    homepage = "https://github.com/qwreey/parser.lua"
  ]]

--[[
todo
{"'", "[["}, func
style handler

should impl
 - cache
]]

local utf8 = utf8 or require "utf8"
local concat = table.concat
local insert = table.insert
local remove = table.remove

-- flatten templates
local function flatten(comps)
	local cur,tmp = 1,comps[1]
	while tmp do
		if type(tmp) == "table" and rawget(tmp,"__template") then
			flatten(tmp)
			remove(comps,cur)
			for i,v in ipairs(tmp) do
				insert(comps,cur+i-1,v)
			end
		end

		-- next
		cur = cur + 1
		tmp = comps[cur]
	end
end

local function isCacheable(regex)
	if regex:sub(1,1) == "^" then return false end
	return true
end

local function createParser(comps)
	comps.__index = comps
	comps.__parser = true

	-- flatten templates
	flatten(comps)

	-- Update super for children
	for key,v in pairs(comps) do
		if key ~= "__index" and key ~= "super" and type(v) == "table" and rawget(v,"__parser") then
			if v.super then error("this parser already has super") end
			if v.super ~= true then
				v.super = comps
			end
		end
	end

	-- unpacking
	local regexs = {}
	local funcs = {}
	local cacheable = {}
	local len do
		local index = 1
		local cur = 1
		while comps[cur*2-1] do
			local regex = comps[cur*2-1]
			local func = comps[cur*2]
			if func == nil then
				error("Regular expressions and handler functions are not paired. (length: "..tostring(#comps)..")")
			end
			if type(regex) == "table" then -- unpack table
				for _,childRegex in ipairs(regex) do
					cacheable[index] = isCacheable(childRegex)
					regexs[index] = childRegex
					funcs[index] = func
					index = index + 1
				end
			else
				cacheable[index] = isCacheable(regex)
				regexs[index] = regex
				funcs[index] = func
				index = index + 1
			end
			cur = cur + 1
		end
		len = index-1
	end

	-- main parser function
	local function parse(self,str,start,verbose)
		local state = setmetatable({parent = self, __state = true},comps)
		local findCache = {}
		local strlen = #str
		local pos = start or 1
		local lastpos
		local init = comps.init
		local stop = comps.stop
		local orphans = comps.orphans
		local tailing = comps.tailing
		local noEOF = comps.noEOF

		-- Run init function
		if init then
			local initPos,initEndup = init(state,str,pos)
			if initPos then pos = initPos end -- move position if updated
			if initEndup then -- check endup
				local result = state
				if stop then
					result = stop(state)
				end
				return result,pos
			end
		end

		-- Loop find
		while true do
			if verbose then print("LOOP: pos "..pos) end

			-- Check infinity loop
			if pos == lastpos then
				error("Infinite loop detected")
			end
			lastpos = pos

			-- Check buffer exhaust
			if pos > strlen then
				if noEOF then -- EOF is not required
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
				local find

				-- Check old cache by position (use memoization for performance)
				local oldFind = findCache[index]
				if cacheable[index] and oldFind and oldFind[1] and oldFind[1] >= pos then
					find = oldFind
				elseif (not cacheable[index]) or (not oldFind) or (oldFind[1] and oldFind[1] < pos) then
					local regex = regexs[index]
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

			if minFind then
				-- If token found
				if verbose then
					print("From "..pos..": "..regexs[minIndex].." ("..minStartAt.."~"..minFind[2]..")")
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
				local func = funcs[minIndex]
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
				
				-- if EOF is required
				if not noEOF then
					error("No token found")
				end

				-- Process tailing
				if tailing and strlen >= pos then
					local tailingString = string.sub(str,pos,strlen)
					if tailingString ~= "" then
						if verbose then print(" | Push tailing : "..tailingString) end
						tailing(state,tailingString)
					end
					pos = strlen + 1
				end

				-- Make result
				local result = state
				if stop then
					result = stop(state)
				end
				return result,pos-1
			end
		end
	end

	setmetatable(comps,{
		__call = function (_,self,...)
			if type(self) == "table" and rawget(self,"__state") then
				return parse(self,...)
			end
			return parse(nil,self,...)
		end
	})
	return comps
end

local whitespaces = "%s+"
local function ignore(_,_,_,_,endAt)
	return endAt+1
end
local function eof(_,_,_,_,endAt)
	return endAt+1,true
end

local stringEscapes = setmetatable({
	["n"] = "\n";
	["r"] = "\r";
	["f"] = "\f";
	["v"] = "\v";
	["b"] = "\b";
	["\\"] = "\\";
	["t"] = "\t";
	["\""] = "\"";
	["\'"] = "\'";
	["a"] = "\a";
	["z"] = "\z";
},{ __index = function(self,key) return key end })

local function luaStringEscapes(func)
	return {
		__template = true,
		"\\u{(%x+)}",   function (self,str,pos,startAt,endAt,hex) return func(self,str,pos,startAt,endAt,utf8.char(tonumber(hex,16))) end,
		"\\(%d%d?%d?)", function (self,str,pos,startAt,endAt,num) return func(self,str,pos,startAt,endAt,string.char(num)) end,
		"\\x(%x%x?)",   function (self,str,pos,startAt,endAt,hex) return func(self,str,pos,startAt,endAt,string.char(tonumber(hex,16))) end,
		"\\(.)",        function (self,str,pos,startAt,endAt,char) return func(self,str,pos,startAt,endAt,stringEscapes[char]) end,
	}
end

local function luaNumbers(func)
	return {
		__template = true,
		"(%d*%.?%d+[eE][%+%-]?%d+)", function (self,str,pos,startAt,endAt,expo)
			return func(self,str,pos,startAt,endAt,tonumber(expo))
		end,
		"(0x%x*%.?%x+)", function (self,str,pos,startAt,endAt,hex)
			return func(self,str,pos,startAt,endAt,tonumber(hex))
		end,
		"(0b[10]*%.?[10]+)", function (self,str,pos,startAt,endAt,bin)
			return func(self,str,pos,startAt,endAt,tonumber(bin))
		end,
		"(%d*%.?%d+)", function (self,str,pos,startAt,endAt,num)
			return func(self,str,pos,startAt,endAt,tonumber(num))
		end,
	}
end

local luaStringParser = createParser {
	-- Block
	blockParser = createParser {
		"%]%]", eof;
		orphans = function (self,str) insert(self.parent.buffer,str) end;
		tailing = function (self,str) insert(self.parent.buffer,str) end;
	};
	"^%[%[", function (self,str,pos,startAt,endAt)
		local _,parseEndAt = self:blockParser(str,endAt+1)
		return parseEndAt+1,true
	end;

	-- Double Quote
	doubleQuoteParser = createParser {
		"\"", eof;
		orphans = function (self,str) insert(self.parent.buffer,str) end;
		tailing = function (self,str) insert(self.parent.buffer,str) end;
		luaStringEscapes(function (self,str,pos,startAt,endAt,char)
			insert(self.parent.buffer,char)
		end);
	};
	"^\"", function (self,str,pos,startAt,endAt)
		local _,parseEndAt = self:doubleQuoteParser(str,endAt+1)
		return parseEndAt+1,true
	end;

	-- Single Quote
	singleQuoteParser = createParser {
		"\'", eof;
		orphans = function (self,str) insert(self.parent.buffer,str) end;
		tailing = function (self,str) insert(self.parent.buffer,str) end;
		luaStringEscapes(function (self,str,pos,startAt,endAt,char)
			insert(self.parent.buffer,char)
		end);
	};
	"^'", function (self,str,pos,startAt,endAt)
		local _,parseEndAt = self:singleQuoteParser(str,endAt+1)
		return parseEndAt+1,true
	end;

	init = function (self,str,pos) self.buffer = {} end;
	stop = function (self) return concat(self.buffer) end;
}
local function luaStrings(func)
	return {
		__template = true,
		{"\'","\"","%[%["}, function (self,str,pos,startAt,endAt)
			local result, parseEndAt = luaStringParser(str,startAt)
			local funcPos,funcStop = func(self,str,pos,startAt,parseEndAt,result)
			return funcPos or (parseEndAt + 1), funcStop
		end,
	}
end

local function luaValues(func)
	return {
		__template = true,

		-- Boolean parsing
		"true", function (self, str, pos, startAt, endAt)
			local funcPos,funcStop = func(self,str,pos,startAt,endAt,true)
			return funcPos or (endAt + 1), funcStop
		end;
		"false", function (self, str, pos, startAt, endAt)
			local funcPos,funcStop = func(self,str,pos,startAt,endAt,false)
			return funcPos or (endAt + 1), funcStop
		end;

		-- Nil parsing
		"nil", function (self, str, pos, startAt, endAt)
			local funcPos,funcStop = func(self,str,pos,startAt,endAt,nil)
			return funcPos or (endAt + 1), funcStop
		end;

		-- Number parsing
		luaNumbers(function(self, str, pos, startAt, endAt, num)
			local funcPos,funcStop = func(self,str,pos,startAt,endAt,num)
			return funcPos or (endAt + 1), funcStop
		end);

		-- String parsing
		luaStrings(function(self, str, pos, startAt, endAt, string)
			local funcPos,funcStop = func(self,str,pos,startAt,endAt,string)
			return funcPos or (endAt + 1), funcStop
		end);
	}
end

local luaValueParser = createParser {
	stop = function (self)
		return self.value
	end;

	-- common lua values
	luaValues(function(self, str, pos, startAt, endAt, value)
		self.value = value
		return endAt+1,true
	end);

	-- table parsing
	objectParser = createParser {
		init = function (self,str,pos)
			self.terminatorRequired = false
			self.orphanIndex = 1
		end;

		-- index by string
		"^%s*([_%w][%w_]*)%s*=%s*", function (self, str, pos, startAt, endAt, key)
			if self.terminatorRequired then
				error("token [;,] is require on position "..tostring(startAt))
			end
			self.terminatorRequired = true
			local value, valueEndAt = self.super(str,endAt+1)
			self.parent.value[key] = value
			self.terminatorRequired = true
			return valueEndAt+1
		end;

		-- index by lua value
		indexParser = createParser {
			"^%s*]%s*=%s*", function (self, str, pos, startAt, endAt)
				return endAt+1,true
			end;
		};
		"^%s*%[", function (self, str, pos, startAt, endAt)
			if self.terminatorRequired then
				error("token [;,] is require on position "..tostring(startAt))
			end
			self.terminatorRequired = true
			local key,keyEndAt = self.super(str,endAt+1)
			local _,indexEndAt = self.indexParser(str,keyEndAt+1)
			local value, valueEndAt = self.super(str,indexEndAt+1)
			self.parent.value[key] = value
			return valueEndAt+1
		end;

		-- next key
		"^%s*[;,]", function (self, str, pos, startAt, endAt, key)
			if not self.terminatorRequired then
				error("Unexpected token "..str:sub(endAt,endAt).." at position "..tostring(endAt))
			end
			self.terminatorRequired = false
			return endAt+1
		end;

		-- EOF
		"^%s*}", function (self, str, pos, startAt, endAt)
			return endAt+1,true
		end;

		-- any (array style items)
		"^%s*().+", function (self, str, pos, startAt, endAt, valueStartAt)
			if self.terminatorRequired then
				error("token [;,] is require on position "..tostring(startAt))
			end
			self.terminatorRequired = true
			local index = self.orphanIndex
			local value, valueEndAt = self.super(str,valueStartAt)
			self.parent.value[index] = value
			self.orphanIndex = index+1
			return valueEndAt+1
		end;
		whitespaces, ignore;
	};
	"{", function (self, str, pos, startAt, endAt)
		-- pass self to object parser
		self.value = {}
		local _,parseEndAt = self:objectParser(str,endAt+1)
		return parseEndAt+1,true
	end;
	whitespaces, ignore;
}

-- Allow : instead of =
-- Allow no ; or , (eg: { true true true { true } true } )
local luaNonstrictValueParser = createParser {
	stop = function (self)
		return self.value
	end;

	-- common lua values
	luaValues(function(self, str, pos, startAt, endAt, value)
		self.value = value
		return endAt+1,true
	end);

	-- table parsing
	objectParser = createParser {
		init = function (self,str,pos)
			self.orphanIndex = 1
		end;

		-- index by string
		"^%s*([_%w][%w_]*)%s*[=:]%s*", function (self, str, pos, startAt, endAt, key)
			local value, valueEndAt = self.super(str,endAt+1)
			self.parent.value[key] = value
			return valueEndAt+1
		end;

		-- index by lua value
		indexParser = createParser {
			"^%s*]%s*[=:]%s*", function (self, str, pos, startAt, endAt)
				return endAt+1,true
			end;
		};
		"^%s*%[", function (self, str, pos, startAt, endAt, key)
			local key,keyEndAt = self.super(str,endAt+1)
			local _,indexEndAt = self.indexParser(str,keyEndAt+1)
			local value, valueEndAt = self.super(str,indexEndAt+1)
			self.parent.value[key] = value
			return valueEndAt+1
		end;

		-- next key
		"^%s*[;,]", function (self, str, pos, startAt, endAt, key)
			return endAt+1
		end;

		-- EOF
		"^%s*}", function (self, str, pos, startAt, endAt)
			return endAt+1,true
		end;

		-- any (array style items)
		"^%s*().+", function (self, str, pos, startAt, endAt, valueStartAt)
			local index = self.orphanIndex
			local value, valueEndAt = self.super(str,valueStartAt)
			self.parent.value[index] = value
			self.orphanIndex = index+1
			return valueEndAt+1
		end;
		whitespaces, ignore;
	};
	"{", function (self, str, pos, startAt, endAt)
		-- pass self to object parser
		self.value = {}
		local _,parseEndAt = self:objectParser(str,endAt+1)
		return parseEndAt+1,true
	end;
	whitespaces, ignore;
}

return {
	version = "2.1.4";
	createParser = createParser;

	-- parsers
	luaNonstrictValueParser = luaNonstrictValueParser;
	luaValueParser = luaValueParser;
	luaStringEscapes = luaStringEscapes;
	luaStringParser = luaStringParser;

	-- utility
	ignore = ignore;
	whitespaces = whitespaces;
	eof = eof;

	-- templates
	luaNumbers = luaNumbers;
	luaStrings = luaStrings;
}
