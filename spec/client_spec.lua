package.path = "./?.lua;./?/init.lua;" .. package.path

local checks = 0
local function expect(condition, message)
    checks = checks + 1
    if not condition then error(message or ("check " .. checks .. " failed")) end
end

local timeout_calls = {}
local reset_count = 0
local requests = {}
local responses = {}

package.preload["ltn12"] = function()
    return {
        source = {
            string = function(value)
                return function() return value end
            end,
        },
    }
end
package.preload["socketutil"] = function()
    return {
        set_timeout = function(_self, block, total)
            timeout_calls[#timeout_calls + 1] = { block, total }
        end,
        reset_timeout = function()
            reset_count = reset_count + 1
        end,
        table_sink = function(target)
            return function(chunk)
                if chunk then target[#target + 1] = chunk end
                return 1
            end
        end,
    }
end
package.preload["socket.http"] = function()
    return {
        request = function(options)
            requests[#requests + 1] = options
            local response = table.remove(responses, 1)
            if response.raise then error(response.raise) end
            if options.sink then options.sink(response.body or "") end
            return 1, response.code, response.headers or {}, response.status
        end,
    }
end
package.preload["weread.lib.protocol"] = function()
    return { USER_AGENT = "WeRead client spec" }
end

local Client = require("weread.lib.client")
local merged_cookies = {}
local settings = {
    get = function(_self, key, default)
        if key == "cookies" then
            return { wr_skey = "XXX-cookie-value" }
        end
        return default
    end,
    merge_set_cookie = function(_self, value)
        merged_cookies[#merged_cookies + 1] = value
    end,
}
local client = Client:new(settings)

responses[#responses + 1] = {
    body = "ok",
    code = 200,
    headers = { ["Set-Cookie"] = "wr_ticket=new-ticket; Path=/" },
}
local body, code = client:request({
    url = "https://weread.qq.com/web/test",
    timeout = { 3, 7 },
})
expect(body == "ok" and code == 200, "basic request result was wrong")
expect(requests[1].headers.Cookie == "wr_skey=XXX-cookie-value",
    "WeRead cookie was not attached")
expect(timeout_calls[1][1] == 3 and timeout_calls[1][2] == 7,
    "request timeout was not applied")
expect(reset_count == 1, "timeout was not reset after successful request")
expect(merged_cookies[1] == "wr_ticket=new-ticket; Path=/",
    "response cookies were not persisted")

responses[#responses + 1] = { body = "public", code = 200 }
client:request({ url = "https://example.com/public" })
expect(requests[2].headers.Cookie == nil,
    "WeRead cookie leaked to a non-WeRead host")

responses[#responses + 1] = { raise = "transport failed" }
local ok, err = pcall(function()
    client:request({ url = "https://weread.qq.com/web/fail" })
end)
expect(not ok and tostring(err):find("transport failed", 1, true),
    "transport error was not propagated")
expect(reset_count == 3, "timeout was not reset after transport error")

responses[#responses + 1] = {
    body = "",
    code = 303,
    headers = { location = "https://cdn.example.net/book" },
}
responses[#responses + 1] = { body = "book", code = 200 }
local redirected, redirected_code, _, _, final_url = client:request_follow({
    url = "https://weread.qq.com/web/export",
    method = "POST",
    body = "{}",
    headers = {
        Authorization = "Bearer secret",
        Cookie = "manual=secret",
        Origin = "https://weread.qq.com",
        ["Content-Length"] = "2",
    },
})
expect(redirected == "book" and redirected_code == 200,
    "redirected response was not returned")
expect(final_url == "https://cdn.example.net/book",
    "final redirect URL was wrong")
local redirected_request = requests[#requests]
expect(redirected_request.method == "GET" and redirected_request.body == nil,
    "303 redirect did not switch POST to GET")
for key in pairs(redirected_request.headers) do
    local lower = tostring(key):lower()
    expect(lower ~= "authorization" and lower ~= "cookie"
        and lower ~= "origin" and lower ~= "content-length",
        "sensitive/entity header survived a cross-origin 303: " .. lower)
end

responses[#responses + 1] = {
    body = "",
    code = 302,
    headers = { location = "/again" },
}
responses[#responses + 1] = {
    body = "",
    code = 302,
    headers = { location = "/again" },
}
ok, err = pcall(function()
    client:request_follow({ url = "https://weread.qq.com/start" }, 1)
end)
expect(not ok and tostring(err):find("Too many redirects", 1, true),
    "redirect limit was not enforced")

print(("client_spec: %d checks"):format(checks))
