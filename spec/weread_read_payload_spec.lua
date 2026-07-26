-- Focused tests for Web Reader enter/report payload shape.
-- Run from the repo root with:
--   lua spec/weread_read_payload_spec.lua

package.path = "./?.lua;" .. package.path
package.preload["bit"] = function()
    return {
        band = function(a, b) return a & b end,
        bxor = function(a, b) return a ~ b end,
        lshift = function(a, b) return a << b end,
    }
end
package.preload["lib.crypto"] = function()
    return {
        md5_hex = function()
            return "0123456789abcdef0123456789abcdef"
        end,
        sha256_hex = function(value)
            return "sha256:" .. tostring(value)
        end,
    }
end

local WeRead = require("lib.weread")
local failures, checks = 0, 0

local function eq(got, want, label)
    checks = checks + 1
    if got ~= want then
        failures = failures + 1
        print(string.format("FAIL %s: got %s, want %s",
            label, tostring(got), tostring(want)))
    end
end

local common = {
    book_id = "22691208",
    chapter_uid = 57,
    chapter_idx = 2,
    chapter_offset = 389,
    progress = 74.9,
    summary = "摄影笔记",
    psvts = "ps",
    pclts = "pc",
    token = "token",
    now = 100,
    ts = 100001,
    rn = 7,
}

local enter = WeRead.make_enter_read_payload(common)
eq(enter.pr, 74, "enter progress is integer")
eq(enter.co, 389, "enter offset")
eq(enter.rt, nil, "enter omits rt")
eq(enter.ts, nil, "enter omits ts")
eq(enter.rn, nil, "enter omits rn")
eq(enter.sg, nil, "enter omits sg")
eq(type(enter.s), "string", "enter has web signature")

local report = WeRead.make_read_payload(common)
eq(report.pr, 74, "report progress is integer")
eq(report.rt, 0, "report defaults rt to zero")
eq(report.ts, 100001, "report ts")
eq(report.rn, 7, "report rn")
eq(report.sg, "sha256:1000017token", "report token signature")
eq(type(report.s), "string", "report has web signature")

print(string.format(
    "weread_read_payload_spec: %d checks, %d failure(s)",
    checks,
    failures
))
os.exit(failures == 0 and 0 or 1)
