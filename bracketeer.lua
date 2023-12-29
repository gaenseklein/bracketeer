VERSION = "1.0.0"

local micro = import("micro")
local config = import("micro/config")
local shell = import("micro/shell")
local buffer = import("micro/buffer")

function build_string_arr(line)
	local res = {}
	for i=1,#line do 
		res[i]=string.sub(line,i,i)
	end
	res.length = #line
	return res
end
local quotePairsArr = {{"\"", "\""}, {"'","'"}, {"`","`"}, {"(",")"}, {"{","}"}, {"[","]"}}
local quotePairs = {}
local quoteBool = {}

function build_quote_pairs()
	for i=1,#quotePairsArr do 
		quotePairs[quotePairsArr[i][1]]=quotePairsArr[i][2]
		quoteBool[quotePairsArr[i][1]]=true
		quoteBool[quotePairsArr[i][2]]=true
		
	end
end

function find_end_bracket(string_arr, bracket, pos)
	-- consoleLog({bracket, pos, quotePairs[bracket]})
	for i=pos+1,string_arr.length do 
		if string_arr[i-1]=="\\" then
		elseif string_arr[i]==quotePairs[bracket] then
			return i
		end
	end
	return nil
end

function inside_quote(b, stack, pos)	
	-- consoleLog(stack, "stack",3)
	if pos==nil then 
		consoleLog({"pos is nil!"})
	end
	for key, value in pairs(stack) do 
		if key == "{" or key=="(" or key == "[" or key == nil or value == nil then  
		elseif value.endpos == nil or value.beginpos == nil then 
			consoleLog({key=key, value=value}, 'key,value')		
		elseif value.endpos > pos and value.beginpos < pos then 
			return true
		end
	end
	return false
end

function build_bracket_stack(string_arr)
	local stack = {}
	for i=1,string_arr.length do
		local b = string_arr[i]
		if i>1 and string_arr[i]=="\\" then
		
		elseif b=="{" or b=="(" or b=="(" or b=="\"" or b=="'" or b=="`" then 
			if not inside_quote(b, stack, i) then 			
				local epos = find_end_bracket(string_arr,b,i)	
				-- consoleLog({b,i, epos})
				if epos ~= nil then 
					table.insert(stack,{bracket = b, beginpos = i, endpos = epos})
				end
			end
		end
	end
	return stack
end

function find_outer_bracket(line, pos1, pos2)
	local string_arr = build_string_arr(line)
	local stack = build_bracket_stack(string_arr)	
	local cursor_s = pos1
	local cursor_e = pos2
	if cursor_e == nil then cursor_e = cursor_s end
	local found = false 
	local bpos = 1
	local epos = string_arr.length
	local dist = epos - bpos
	local bracket = ""
	for key, value in pairs(stack) do 
		if value.beginpos < cursor_s and value.endpos > cursor_e and dist > value.endpos - value.beginpos then 
			bpos = value.beginpos
			epos = value.endpos 
			dist = epos - bpos
			bracket = key
			found = true
		end
	end	
	-- consoleLog({beg=bpos, e=epos, br=bracket, stack=stack, string_arr=string_arr},'',3)
	return bpos, epos, found
end

local function get_xy(view)
	local x1 = view.Cursor.Loc.X + 1
	local x2 = x1
	if view.Cursor:HasSelection() then 
		x1 = view.Cursor.CurSelection[1].X + 1
		x2 = view.Cursor.CurSelection[2].X + 1
	end
	local y = view.Cursor.Loc.Y + 1
	return x1,x2,y
end

function mark_outer_bracket(view)
	local x1,x2,y = get_xy(view)
	local line = view.Buf:Line(view.Cursor.Loc.Y)
	local brbegin, brend, found = find_outer_bracket(line, x1, x2)
	if not found then return end
	view.Cursor:SetSelectionStart(buffer.Loc(brbegin,y-1))
	view.Cursor:SetSelectionEnd(buffer.Loc(brend-1,y-1))	
	-- consoleLog({brbegin, brend, br})	
end

function find_next_bracket_pos(line, pos)
	local string_arr = build_string_arr(line)
	for i=pos,string_arr.length do
		if quoteBool[string_arr[i]] then return i end
	end
	return nil
end

function find_previous_bracket_pos(line, pos)
	local string_arr = build_string_arr(line)
	local fpos = nil
	for i=1,pos do
		if quoteBool[string_arr[i]] then fpos = i end
	end
	return fpos
end

function jump_to_next_bracket(view)
	local x1,x2,y = get_xy(view)
	local x = x1
	if x2>x1 then x = x2 end
	local line = view.Buf:Line(view.Cursor.Loc.Y)
	local pos = find_next_bracket_pos(line, x)
	if pos ~= nil then 
		view.Cursor.Loc.X = pos
	end
end

function jump_to_previous_bracket(view)
	local x1,x2,y = get_xy(view)
	local x = x1
	if x2>x1 then x = x2 end
	local line = view.Buf:Line(view.Cursor.Loc.Y)
	local pos = find_previous_bracket_pos(line, x-2)
	if pos ~= nil then 
		view.Cursor.Loc.X = pos
	end
end

function init()
	config.MakeCommand("mb", mark_outer_bracket, config.NoComplete)	
	config.MakeCommand("jumpfw", jump_to_next_bracket, config.NoComplete)	
	config.MakeCommand("jumpbw", jump_to_previous_bracket, config.NoComplete)	
	build_quote_pairs()	
end


--debug function to transform table/object into a string
function dump(o, depth)
	if o == nil then return "nil" end
   if type(o) == 'table' then
      local s = '{ '
      for k,v in pairs(o) do
         if type(k) ~= 'number' then k = '"'..k..'"' end
         if depth > 0 then s = s .. '['..k..'] = ' .. dump(v, depth - 1) .. ',\n'
         else s = s .. '['..k..'] = ' .. '[table]'  .. ',\n'end
      end
      return s .. '} \n'
   elseif type(o) == "boolean" then
   	  return boolstring(o)   
   else
      return tostring(o)
   end
end
-- debug function to get a javascript-like console.log to inspect tables
-- expects: o: object like a table you want to debug
-- pre: text to put in front 
-- depth: depth to print the table/tree, defaults to 1
-- without depth  we are always in risk of a stack-overflow in circle-tables
function consoleLog(o, pre, depth)
	local d = depth
	if depth == nil then d = 1 end
	local text = dump(o, d)
	local begin = pre
	if pre == nil then begin = "" end	
	micro.TermError(begin, d, text)
end

function boolstring(bol)
	if bol then return "true" else return "false" end
end
