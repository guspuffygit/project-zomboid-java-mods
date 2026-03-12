---@param uri string
---@param text string
---@return nil|diff[]
function OnSetText(uri, text)
    local diffs = {}

    -- Inject ---@class for the derive() pattern: ClassName = ParentClass:derive("ClassName")
    for start, className, parent in text:gmatch('()([%w_]+)%s*=%s*([%w_]+):derive%s*%(') do
        local lineStart = start
        while lineStart > 1 and text:sub(lineStart - 1, lineStart - 1) ~= '\n' do
            lineStart = lineStart - 1
        end

        diffs[#diffs + 1] = {
            start  = lineStart,
            finish = lineStart - 1,
            text   = '---@class ' .. className .. ' : ' .. parent .. '\n',
        }
    end

    -- Inject ---@cast for instanceof() type narrowing
    -- Finds lines ending with `then` that contain instanceof(var, "Class")
    local pos = 1
    while pos <= #text do
        local lineEnd = text:find('\n', pos) or (#text + 1)
        local line = text:sub(pos, lineEnd - 1)

        if line:match('then%s*$') or line:match('then%s*%-%-') then
            local casts = {}
            for varName, className in line:gmatch('instanceof%s*%(([%w_%.]+)%s*,%s*"([%w_]+)"%)') do
                casts[#casts + 1] = '---@cast ' .. varName .. ' ' .. className
            end
            if #casts > 0 and lineEnd <= #text then
                diffs[#diffs + 1] = {
                    start  = lineEnd + 1,
                    finish = lineEnd,
                    text   = table.concat(casts, '\n') .. '\n',
                }
            end
        end

        pos = lineEnd + 1
    end

    if #diffs == 0 then
        return nil
    end

    return diffs
end
