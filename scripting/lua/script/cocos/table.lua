table = table or {}

-- connect table elements to a string, separated by given separator
function table.join(t, sep)
    local s = ""
    for _,item in ipairs(t) do
        if string.len(s) > 0 then
            s = s .. sep
        end
        s = s .. tostring(item)
    end
    return s
end

-- print all table elements including nested table
function table.print(value, ...)
    local indent = ...
    if indent == nil then
        indent = ""
    end
    table.foreach(value,
                  function(i, v)
                    if type(v) == "table" and v ~= value then
                        print(indent .. i)
                        table.print(v, indent .. "\t")
                    else
                        print(indent .. i .. " = " .. tostring(v))
                    end
                  end)
end