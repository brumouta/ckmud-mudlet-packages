-- CKMudUpdate("<Package>"): the `<prefix> update` command of every package in
-- brumouta/ckmud-mudlet-packages. Downloads the package's .mpackage from the latest release first
-- and only then swaps it in, so a failed download (offline, or the repo not public yet) leaves the
-- installed copy alone. The same file ships in every package (tools/build.py adds it to the simple
-- ones, the muddler ones keep a copy that tests/run.sh checks against tools/shared/CKMudUpdate.lua).
CKMudUpdate_RELEASES = "https://github.com/brumouta/ckmud-mudlet-packages/releases/latest/download/"
-- Names older copies were installed under: uninstalled too, so the update doesn't leave two copies
CKMudUpdate_LEGACY = { DataLords2 = { "dl2" }, Gumshoe = { "gumshoe" } }

local function say(color, msg) cecho("\n<" .. color .. ">[update] <white>" .. msg .. "\n") end

function CKMudUpdate(pkg)
  if type(downloadFile) ~= "function" or type(installPackage) ~= "function" then
    return say("yellow", pkg .. ": update it from the client's own package list")
  end
  local file = getMudletHomeDir() .. "/" .. pkg .. "-update.mpackage"
  local url = CKMudUpdate_RELEASES .. pkg .. ".mpackage"
  local done, failed
  local function forget()
    killAnonymousEventHandler(done)
    killAnonymousEventHandler(failed)
  end
  done = registerAnonymousEventHandler("sysDownloadDone", function(_, path)
    if path ~= file then return end
    forget()
    -- from a timer, so it doesn't run inside the package it is removing
    tempTimer(0, function()
      local installed = {}
      for _, name in ipairs(getPackages()) do installed[name] = true end
      for _, old in ipairs(CKMudUpdate_LEGACY[pkg] or {}) do
        if installed[old] then uninstallPackage(old) end
      end
      if installed[pkg] then uninstallPackage(pkg) end
      installPackage(file)
      local version = type(getPackageInfo) == "function" and getPackageInfo(pkg, "version") or nil
      say("green", pkg .. " updated" .. ((version and version ~= "") and (" to " .. version) or ""))
      tempTimer(5, function() os.remove(file) end)
    end)
  end)
  failed = registerAnonymousEventHandler("sysDownloadError", function(_, err, path)
    if path and path ~= file then return end
    forget()
    say("red", "Couldn't download " .. pkg .. " (" .. tostring(err) .. "); the installed copy is unchanged")
  end)
  say("cyan", "Downloading the latest " .. pkg .. "...")
  downloadFile(file, url)
end
