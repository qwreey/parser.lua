# parser.lua - qwreey/parser

Simple parser utility

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
local result,endPos = simpleParser("test${value1}test")
print(result,endPos)
-- { {t="str", v="test"}, {t="val", v="value1"}, {t="str", v="test"} }
-- 17
print(simpleParser("test${value1}test") == result)
-- true (cached)
```

#### Extend - Formatter
You can create simple formatter like below (append to above code)
```lua
local function f(format)
	local parsed = simpleParser(format)
	return function (tbl)
		local buffer = {}
		for _,item in ipairs(parsed) do
			if item.t == "str" then
				table.insert(buffer,item.v)
			elseif item.t == "val" then
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

## template

## subParser

## basic escapes


