VERSION = "1.0.0"

local micro = import("micro")
local config = import("micro/config")
local shell = import("micro/shell")
local buffer = import("micro/buffer")

-- function test(view, args)
-- 	-- test if go counts in chars or bytes
-- 	view.Buf:Insert(buffer.Loc(0,0),"äöüß²³")
-- 	for i=0,5 do 
-- 		local p = i*2
-- 		view.Buf:Insert(buffer.Loc(p,0),""..i)
-- 	end
-- 	-- go counts in chars :-)
-- unfortunately lua counts in bytes :-(
-- end

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

function is_begin_pair(rune)
	for i=1,#quotePairsArr do 
		if quotePairsArr[i][1] == rune then return true end
	end
	return false
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
	-- for key, value in pairs(stack) do 
	-- 	if key == "{" or key=="(" or key == "[" or key == nil or value == nil then  
	-- 	elseif value.endpos == nil or value.beginpos == nil then 
	-- 		consoleLog({key=key, value=value}, 'key,value')		
	-- 	elseif value.endpos > pos and value.beginpos < pos then 
	-- 		consoleLog({"why are you inside quote?", key, value})
	-- 		return true
	-- 	end
	-- end
	for i=1,#stack do 
		local key = stack[i].bracket
		local epos = stack[i].endpos
		local bpos = stack[i].beginpos		
		local is_quote = (key == "\"" or key == "'" or key == "`")
		local inside = (epos > pos and bpos < pos)
		if is_quote and inside then 
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
			-- consoleLog({"escape char on "..i..":"..string_arr[i]..string_arr[i+1]})
		elseif b=="{" or b=="(" or b=="(" or b=="\"" or b=="'" or b=="`" then 
			-- if b=="\"" then consoleLog({"quote found on "..i})end
			if not inside_quote(b, stack, i) then 			
				local epos = find_end_bracket(string_arr,b,i)	
				-- consoleLog({b,i, epos})
				if epos ~= nil then 
					table.insert(stack,{bracket = b, beginpos = i, endpos = epos})
				else 
					-- consoleLog({"no endpoint found"})
				end
			else 
				-- consoleLog({"inside quote", b, i})
			end
		end
	end
	return stack
end

function find_outer_bracket(line, pos1, pos2)
	local string_arr = build_string_arr(line)
	-- consoleLog(string_arr)
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
		local length_of_value = value.endpos - value.beginpos
		local is_inside = (value.beginpos < cursor_s and value.endpos > cursor_e)
		if cursor_s == cursor_e then is_inside = (value.beginpos < cursor_s and value.endpos >= cursor_e) end
		if is_inside  and dist > length_of_value then 
			bpos = value.beginpos
			epos = value.endpos 
			dist = epos - bpos
			bracket = value.bracket
			found = true
		end
	end	
	-- consoleLog({beg=bpos, e=epos, br=bracket, stack=stack, string_arr=string_arr},'',3)
	return bpos, epos, found, bracket
end

local function get_xy(view)
	local x1 = view.Cursor.Loc.X + 1
	local x2 = x1
	local y1 = view.Cursor.Loc.Y + 1	
	local y2 = y1
	if view.Cursor:HasSelection() then 
		x1 = view.Cursor.CurSelection[1].X + 1
		x2 = view.Cursor.CurSelection[2].X + 1
		y1 = view.Cursor.CurSelection[1].Y + 1
		y2 = view.Cursor.CurSelection[2].Y + 1
	end
	-- consoleLog({x1=x1,x2=x2,y1=y1,y2=y2})
	return x1,x2,y1,y2
end

function mark_outer_bracket(view)
	local x1,x2,y = get_xy(view)
	local line = view.Buf:Line(view.Cursor.Loc.Y)
	local brbegin, brend, found = find_outer_bracket(line, x1, x2)
	if not found then return end
	view.Cursor:SetSelectionStart(buffer.Loc(brbegin,y-1))
	view.Cursor:SetSelectionEnd(buffer.Loc(brend-1,y-1))	
	-- consoleLog({brbegin, brend, br})	
	-- return false
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
	-- consoleLog("jump to next bracket")
	local x1,x2,y = get_xy(view)
	local x = x1
	if x2>x1 then x = x2 end
	local line = view.Buf:Line(view.Cursor.Loc.Y)
	local pos = find_next_bracket_pos(line, x)
	if pos ~= nil then 
		view.Cursor.Loc.X = pos
		return
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
		return
	end
end

function mark_to_next_bracket(view)
	local x1,x2,y1,y2 = get_xy(view)
	local x = x1
	if x2>x1 then x = x2 end
	local line = view.Buf:Line(view.Cursor.Loc.Y)
	local pos = find_next_bracket_pos(line, x)
	if pos ~= nil then 
		-- view.Cursor.Loc.X = pos
		if view.Cursor:HasSelection() then 
			view.Cursor.CurSelection[2].X = pos
		else
			view.Cursor:SetSelectionStart(buffer.Loc(x1-1,y1-1))
			view.Cursor:SetSelectionEnd(buffer.Loc(pos,y1-1))
		end
		return
	end
end

function mark_to_previous_bracket(view)
	local x1,x2,y = get_xy(view)
	local x = x1
	if x2>x1 then x = x2 end
	local line = view.Buf:Line(view.Cursor.Loc.Y)
	local pos = find_previous_bracket_pos(line, x-2)
	if pos ~= nil then 
		if view.Cursor:HasSelection() then 
			view.Cursor.CurSelection[2].X = pos
		else
			view.Cursor:SetSelectionStart(buffer.Loc(x1-1,y1-1))
			view.Cursor:SetSelectionEnd(buffer.Loc(pos,y1-1))
		end
		return
	end
end


function change_bracket(view, bracket)	
	init_quoter()
	local rightleft = ((view.Cursor.CurSelection[1].X + view.Cursor.CurSelection[1].Y*1000) > (view.Cursor.CurSelection[2].X + view.Cursor.CurSelection[2].Y*1000)) 
	local s = 1
	local e = 2
	if rightleft then 
		s = 2
		e = 1
	end
	local sline = view.Buf:Line(view.Cursor.CurSelection[s].Y)
	local eline = view.Buf:Line(view.Cursor.CurSelection[e].Y)
	local sx = view.Cursor.CurSelection[s].X 
	local ex = view.Cursor.CurSelection[e].X + 1		
	local sb = utf8sub(sline, sx,sx)
	local eb = utf8sub(eline, ex,ex)
	local rsx = view.Cursor.CurSelection[s].X
	local rsy = view.Cursor.CurSelection[s].Y		
	local rex = view.Cursor.CurSelection[e].X
	local rey = view.Cursor.CurSelection[e].Y		
	-- consoleLog({sx=sx,ex=ex,sb=sb,eb=eb})
	if sb == bracket and eb == quotePairs[bracket] then 
		view.Buf:Remove(buffer.Loc(rex,rey), buffer.Loc(rex+1,rey))
		view.Buf:Remove(buffer.Loc(rsx-1,rsy), buffer.Loc(rsx,rsy))
	else
		-- consoleLog({sb=sb,br=bracket,eb=eb,ebracket=quotePairs[bracket],el=">>"..eline.."<<",ex=ex})
		view.Buf:Insert(buffer.Loc(rex,rey),quotePairs[bracket])
		view.Buf:Insert(buffer.Loc(rsx,rsy),bracket)
		view.Cursor.CurSelection[e].X = view.Cursor.CurSelection[e].X - 1
	end
	return true
end

function init_quoter()
	local qe = config.GetGlobalOption("quoter.enable")
	-- consoleLog(qe)
	if qe then 
		-- micro.TermPrompt("the plugin quoter is enabled which conflicts with this plugin. please remove or deactivate quoter", {"y"})
		consoleLog("the plugin quoter is enabled which conflicts with this plugin. deactivating quoter")
		config.SetGlobalOption("quoter.enable","false")		
	end
end

function init()
	config.MakeCommand("mb", mark_outer_bracket, config.NoComplete)	
	config.MakeCommand("jumpfw", jump_to_next_bracket, config.NoComplete)	
	config.MakeCommand("jumpbw", jump_to_previous_bracket, config.NoComplete)	
	config.MakeCommand("teststring", test, config.NoComplete)	
	
	config.RegisterCommonOption("bracketeer", "quoter",true)
	
	config.TryBindKey("Alt-Left", "lua:bracketeer.jump_to_previous_bracket", false)
	config.TryBindKey("Alt-Right", "lua:bracketeer.jump_to_next_bracket", false)
	config.TryBindKey("Alt-m", "lua:bracketeer.mark_outer_bracket", true)
	build_quote_pairs()	
	-- init_quoter()
end

-- ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
-- adding/removing quotes/brackets:
-- ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~

function preRune(view, r)
	if not config.GetGlobalOption("bracketeer.quoter") then 
		return true
	end	
	if not view.Cursor:HasSelection() then return true end
	-- if r== "\"" or r == "'" or r == "`" or r =="(" or r == "[" or r =="{" then 
	if is_begin_pair(r) then 
		local changed =  change_bracket(view, r)
		if changed then return false end
	end
	return true
end

-- ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
-- helper functions utf8 vs lua-strings:
-- ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
function extra_char_bytes(begin_byte)
	if begin_byte < 194 then return 0 end
	if begin_byte < 224 then return 1 end
	if begin_byte < 240 then return 2 end
	return 3
end

function utf8sub(str, pos, pos2)
	local epos = pos2
	if pos2 == nil then epos = pos end
	-- local l = extra_char_bytes(string.byte(string.sub(pos,epos)))	
	-- return string.sub(str,pos,epos+l)
	local string_arr = build_string_arr(str)
	local res = ""
	for i=pos,epos do 
		if string_arr[i] ~= nil then
			res = res .. string_arr[i]
		end
	end
	return res
end

function build_string_arr(line)
	local res = {}
	local c = 1
	local length = 0
	for i=1,#line do 
		if i>=c then 
			local l = extra_char_bytes(string.byte(string.sub(line,i,i)))
			res[length+1]=string.sub(line,c,c+l)
			c = c + l + 1
			length = length + 1
		end
			-- c = c + 1
		
		-- local l = char_length(string.byte(line,i))
		-- res[i]=string.sub(line,i,i)
	end
	res.length = length
	-- consoleLog(res)
	return res
end


-- function build_string_arr_ascii(line)
-- 	local res = {}
-- 	for i=1,#line do 
-- 		local l = char_length(string.byte(line,i))
-- 		res[i]=string.sub(line,i,i)
-- 	end
-- 	res.length = #line
-- 	return res
-- end


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
