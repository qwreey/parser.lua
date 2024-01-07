local parser = require "../init.lua"
local print = p

local simpleParser = parser.createParser {
	"%${([%w_]+)}", function(self,str,pos,startAt,endAt,match1) -- self(context), original string, and string.find results
		table.insert(self.inst,{t="val", v=match1})
	end;
	orphans = function (self,orphan)
		table.insert(self.inst,{t="str", v=orphan})
	end;
	tailing = function (self,orphan)
		table.insert(self.inst,{t="str", v=orphan})
	end;
	init = function (self,str,pos)
		self.inst = {}
	end;
	stop = function (self)
		return self.inst
	end;
	noEOF = true;
	cache = true;
}

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

