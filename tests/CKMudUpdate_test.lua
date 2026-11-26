-- tools/shared/CKMudUpdate.lua: download first, swap only when the download worked
local fails = 0
local function check(c, m) if c then print("ok   " .. m) else fails = fails + 1; print("FAIL " .. m) end end

local handlers, calls, timers, installed, downloads
local function reset(pkgs)
  handlers, calls, timers, downloads = {}, {}, {}, {}
  installed = pkgs
end
local hid = 0
function registerAnonymousEventHandler(ev, fn) hid = hid + 1; handlers[hid] = { ev = ev, fn = fn }; return hid end
function killAnonymousEventHandler(id) handlers[id] = nil end
local function raise(ev, ...) for id, h in pairs(handlers) do if h.ev == ev then h.fn(ev, ...) end end end
function tempTimer(_, fn) timers[#timers + 1] = fn end
local function runTimers() local t = timers; timers = {}; for _, fn in ipairs(t) do fn() end end
function cecho() end
function getMudletHomeDir() return "/profile" end
function getPackages() return installed end
function getPackageInfo() return "9.9.9" end
function uninstallPackage(n) calls[#calls + 1] = "uninstall " .. n end
function installPackage(p) calls[#calls + 1] = "install " .. p end
function downloadFile(file, url) downloads[#downloads + 1] = { file = file, url = url } end
os.remove = function() end

dofile("tools/shared/CKMudUpdate.lua")

reset({ "Majerska", "Chores" })
CKMudUpdate("Majerska")
check(#downloads == 1 and downloads[1].url:match("/releases/latest/download/Majerska%.mpackage$"), "downloads the latest release asset")
check(#calls == 0, "nothing removed before the download finishes")
raise("sysDownloadDone", "/profile/other.mpackage")
check(#calls == 0, "ignores other downloads")
raise("sysDownloadDone", downloads[1].file); runTimers()
check(calls[1] == "uninstall Majerska" and calls[2] == "install " .. downloads[1].file, "then uninstalls and installs the download")
check(next(handlers) == nil, "handlers cleaned up")

reset({ "Majerska" })
CKMudUpdate("Majerska")
raise("sysDownloadError", "404 Not Found", downloads[1].file); runTimers()
check(#calls == 0, "a failed download leaves the installed copy alone")
check(next(handlers) == nil, "handlers cleaned up after a failure")

reset({ "dl2" })
CKMudUpdate("DataLords2")
raise("sysDownloadDone", downloads[1].file); runTimers()
check(calls[1] == "uninstall dl2" and calls[2]:match("^install "), "removes the old dl2 copy, skips the absent DataLords2")

downloadFile = nil
reset({})
CKMudUpdate("Gumshoe")
check(#calls == 0, "no downloadFile (CKMud client): just a message")

if fails > 0 then os.exit(1) end
