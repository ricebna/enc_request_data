function FormatValue(val)
    if type(val) == "string" then
        return string.format("%q", val)
    end
    return tostring(val)
end

function FormatTable(t, tabcount)
    tabcount = tabcount or 0
    if tabcount > 5 then
        --防止栈溢出
        return "<table too deep>"..tostring(t)
    end
    local str = ""
    if type(t) == "table" then
        for k, v in pairs(t) do
            local tab = string.rep("\t", tabcount)
            if type(v) == "table" then
                str = str..tab..string.format("[%s] = {", FormatValue(k))..'\n'
                str = str..FormatTable(v, tabcount + 1)..tab..'}\n'
            else
                str = str..tab..string.format("[%s] = %s", FormatValue(k), FormatValue(v))..',\n'
            end
        end
    else
        str = str..tostring(t)..'\n'
    end
    return str
end

function in_array(needle, haystack)
    for k, v in ipairs(haystack) do
        if v == needle then
            return true
        end
    end
    return false
end

function array_key_exists(arr, key)
    for k, v in pairs(arr) do
        if k == key then
            return true
        end
    end
    return false
end

function explode ( _str,seperator )
    local pos, arr = 0, {}
        for st, sp in function() return string.find( _str, seperator, pos, true ) end do
            table.insert( arr, string.sub( _str, pos, st-1 ) )
            pos = sp + 1
        end
    table.insert( arr, string.sub( _str, pos ) )
    return arr
end

function log(data, name)
    if not name then
        name = "debug"
    end
    data = FormatTable(data)
    local log_dir = "/usr/local/nginx/conf/lua/log/"
    local  f = assert(io.open(log_dir..name..".log",'a'))
    f:write(os.date("%Y-%m-%d %H:%M:%S ")..data.."\n")
    f:close()
end

function find_shared_obj(cpath, so_name)
    local string_gmatch = string.gmatch
    local string_match = string.match
    local io_open = io.open

    for k in string_gmatch(cpath, "[^;]+") do
        local so_path = string_match(k, "(.*/)")
        so_path = so_path .. so_name

        -- Don't get me wrong, the only way to know if a file exist is trying
        -- to open it.
        local f = io_open(so_path)
        if f ~= nil then
            io.close(f)
            return so_path
        end
    end
end