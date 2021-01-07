local os = require "os"
local cjson = require "cjson"
local dist_fields = require "dist_fields"

function in_array(needle, haystack)
    for k, v in ipairs(haystack) do
        if v == needle then
            return true
        end
    end
    return false
end

function enc(data)
    if type(data) == "table" then
        for k,v in pairs(data) do
            if type(v) ~= "table" and (in_array(k, dist_fields) or in_array(string.gsub(k, "%[]", ""), dist_fields)) then
                data[k] = "__mm__"
            else
                data[k] = enc(v)
            end
        end
    end
    return data
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

function log(name, data)
    local log_dir = "log/"..name.."/"
    os.execute('mkdir -p '..log_dir)
    local  f = assert(io.open(log_dir..os.date("%Y%m")..".log",'a'))
    f:write(os.date("%Y-%m-%d %H:%M:%S ")..data.."\n")
    f:close()
end

local function get_form_args()  
    -- 返回args 和 文件md5
    local args = {}  
    local file_args = {}  
    local is_multipart = false  
    local headers = ngx.req.get_headers()
    local error_code = 0
    local error_msg = "未初始化"
    local file_md5 = ""
  
    if string.sub(headers.content_type,1,20) == "multipart/form-data;" then--判断是否是multipart/form-data类型的表单  
        is_multipart = true  
        local body_data = ngx.req.get_body_data()--body_data可是符合http协议的请求体，不是普通的字符串  
        --请求体的size大于nginx配置里的client_body_buffer_size，则会导致请求体被缓冲到磁盘临时文件里，client_body_buffer_size默认是8k或者16k  
        if not body_data then  
            local datafile = ngx.req.get_body_file()
        
            if not datafile then  
                error_code = 1  
                error_msg = "no request body found"  
            else  
                local fh, err = io.open(datafile, "r")  
                if not fh then  
                    error_code = 2  
                    error_msg = "failed to open " .. tostring(datafile) .. "for reading: " .. tostring(err)  
                else  
                    fh:seek("set")  
                    body_data = fh:read("*a") 
                    fh:close()  
                    if body_data == "" then  
                        error_code = 3  
                        error_msg = "request body is empty"  
                    end  
                end  
            end  
        end  
        local new_body_data = {}  
        --确保取到请求体的数据  
        if error_code == 0 then  
            local boundary = "--" .. string.sub(headers.content_type,31)
            -- 兼容处理：当content-type中取不到boundary时，直接从body首行提取。
            local body_data_table = explode(tostring(body_data), boundary)  
            local first_string = table.remove(body_data_table,1)
            local last_string = table.remove(body_data_table)
            -- ngx.log(ngx.ERR, ">>>>>>>>>>>>>>>>>>>>>start\n", table.concat(body_data_table,"<<<<<<>>>>>>"), ">>>>>>>>>>>>>>>>>>>>>end\n")
            for i,v in ipairs(body_data_table) do  
                local start_pos,end_pos,temp_param_name = string.find(v,'Content%-Disposition: form%-data; name="((.+)"; filename="(.*))"')  
                if start_pos then
                    --文件类型的参数，capture是参数名称，capture2是文件名
                    table.insert(file_args, v)                         
                    table.insert(new_body_data,v)
                else
                    --普通参数  
                    local t = explode(v,"\r\n\r\n")  
                    --[[
                        按照双换行切分后得到的table
                        第一个元素，t[1]='
                        Content-Disposition: form-data; name="_data_"
                        Content-Type: text/plain; charset=UTF-8
                        Content-Transfer-Encoding: 8bit
                        '
                        第二个元素，t[2]='{"fileName":"redis-use.png","bizCode":"1099","description":"redis使用范例.png","type":"application/octet-stream"}'
            
                        从第一个元素中提取到参数名称，第二个元素就是参数的值。
                    ]]
                    local param_name_start_pos, param_name_end_pos, temp_param_name = string.find(t[1],'Content%-Disposition: form%-data; name="(.+)"')   
                    local temp_param_value = string.sub(t[2],1,-3)  
                    table.insert(args, {temp_param_name, temp_param_value}) 
                end
                table.insert(new_body_data,1,first_string)
                table.insert(new_body_data,last_string)
                --去掉app_key,app_secret等几个参数，把业务级别的参数传给内部的API
                body_data = table.concat(new_body_data,boundary)--body_data可是符合http协议的请求体，不是普通的字符串
            end  
            -- 找到第一行\r\n\r\n进行切割，将Contentype-*的内容去掉
            local file_pos_start, file_pos_end = string.find(last_string, "\r\n\r\n")
            local temps_table = explode(boundary, "\r\n") 
            -- local boundary_end = temps_table[1] .. "--"
            local boundary_end = temps_table[1]
            -- ngx.log(ngx.ERR, "boundary_end:", boundary_end)
            -- ngx.log(ngx.ERR, "文件报文原文：", last_string)
            local last_boundary_pos_start, last_boundary_pos_end = string.find(last_string, boundary_end)
            -- 减去3是为了：\r\n两个字符，加上sub对end标记的位置是闭合的截取策略，所以还要减去1。
            local file_string = string.sub(last_string, file_pos_end+1, last_boundary_pos_start - 3)
            -- 去掉最后的换行符
            -- file_string
            file_md5 = ngx.md5(file_string)
            -- ngx.log(ngx.ERR, "文件报文原文：", file_string)
            -- ngx.log(ngx.ERR, "\nfile_real_md5:", real_md5)
            -- local lua_md5 = md5.sumhexa(file_string)
            -- ngx.log(ngx.ERR, "字符串长度：", #file_string)
            -- 调试代码，当计算MD5不一致时，直接读取文件，计算长度.
            --[[
            local file = io.open("/var/tmp/readme.txt","r")
            local string_source = file:read("*a")
            file:close()
            local red_md5 = md5.sumhexa(string_source)
            ngx.log(ngx.ERR, "直接读取文件原文：",string_source)
            ngx.log(ngx.ERR, "字符串长度：", #string_source)
            ngx.log(ngx.ERR, "直接读取文件计算md5：", red_md5)
            ]]
        end  
    else  
      -- 普通post请求
      args = ngx.req.get_post_args()
      --[[
        请求体的size大于nginx配置里的client_body_buffer_size，则会导致请求体被缓冲到磁盘临时文件里
        此时，get_post_args 无法获取参数时，需要从缓冲区文件中读取http报文。http报文遵循param1=value1&param2=value2的格式。
      ]]
      if not args then
          args = {}
          -- body_data可是符合http协议的请求体，不是普通的字符串
          local body_data = ngx.req.get_body_data()
          -- client_body_buffer_size默认是8k或者16k
          if not body_data then
              local datafile = ngx.req.get_body_file()
              if not datafile then
                  error_code = 10
                  error_msg = "no request body found"
              else
                  local fh, err = io.open(datafile, "r")
                  if not fh then
                      error_code = 20
                      error_msg = "failed to open " .. tostring(datafile) .. "for reading: " .. tostring(err)
                  else
                      fh:seek("set")
                      body_data = fh:read("*a")
                      fh:close()
                      if body_data == "" then
                          error_code = 30
                          error_msg = "request body is empty"
                      end
                  end
              end
          end
          -- 解析body_data
          local post_param_table = explode(tostring(body_data), "&")
          for i,v in ipairs(post_param_table) do
              local paramEntity = explode(v,"=")
              local tempValue = paramEntity[2]
              -- 对请求参数的value进行unicode解码
              tempValue = unescape(tempValue)
              args[paramEntity[1]] = tempValue
          end
      end
    end 
    return args, file_args, is_multipart, file_md5;
end

function multipart_args_encode(args, file_args)
    local form_str = ""
    local boundary = "--" .. string.sub(ct,31)
    for k, v in pairs(file_args) do
        form_str = form_str .. boundary..v
    end
    for k, v in pairs(args) do
        form_str = form_str .. boundary..'\r\nContent-Disposition: form-data; name="'..v[1]..'"\r\n\r\n'..v[2]..'\r\n'
        form_str = form_str .. boundary..'\r\n'
    end
    return form_str
end

xpcall(function () 
    if(ngx.req.get_method() == 'GET') then
        args = ngx.req.get_uri_args()
        args = enc(args)
        ngx.req.set_uri_args(args)  
    else
        ngx.req.read_body()
        args, file_args, is_multipart = get_form_args()
        if args then
            for k, v in pairs(args) do
                obj = {}
                obj[v[1]] = v[2]
                obj = enc(obj)
                args[k] = {v[1], obj[v[1]]}
            end
            if is_multipart then
                body = multipart_args_encode(args, file_args)
            else
                body = ngx.encode_args(args)
            end
        else
            args = cjson.decode(ngx.req.get_body_data())
            args = enc(args)
            body = cjson.encode(args)
        end
        ngx.req.set_body_data(body)
    end
end, function (err)
    log("enc_error", err)
end)
