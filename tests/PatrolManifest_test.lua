-- pm: Merus's prisoner manifest. Run from the repo root: lua tests/PatrolManifest_test.lua
local sent = {}
function send(c) sent[#sent + 1] = c end
function cecho(s) LOG = (LOG or "") .. s end
local function ok(c, what) assert(c, what); print("OK  " .. what) end
dofile("packages/PatrolManifest/src/PatrolManifest.lua")

ok(pm.decode("Ydqwd", "A", "D") == "Vanta", "A reads as D: Ydqwd is Vanta")
pm.line("Merus says, 'Here is the prisoner manifest and a Patrol rebreather. The breach scrambled the five priority names; the key is printed on the broken seal. Use 'look prisonmanifest', then 'decipher <name>' for each name you work out.'")
ok(sent[1] == "look prisonmanifest", "Merus hands it over: looks at it")
sent, LOG = {}, ""
local names = pm.line("Prisoner manifest. The broken seal prints the Patrol key: A reads as D. Priority names: Ydqwd, Eudnnd, Ulphedfn, Whnwhn, Vdjdqer. 0 of 5 deciphered.")
ok(table.concat(names, ",") == "Vanta,Brakka,Rimeback,Tektek,Saganbo", "the five names: " .. table.concat(names, ","))
ok(LOG:find("Vanta, Brakka, Rimeback, Tektek, Saganbo", 1, true) and #sent == 0, "shown, nothing sent")
pm.command("go")
ok(table.concat(sent, "|") == "decipher Vanta|decipher Brakka|decipher Rimeback|decipher Tektek|decipher Saganbo", "pm go: " .. table.concat(sent, "|"))
-- wrapped over lines, another key (B reads as Z: a shift back of 2)
sent = {}
pm.line("Prisoner manifest. The broken seal prints the Patrol key: B reads as Z. Priority names: Tyllyx,")
pm.line("Zpyiiy, Pgkcze. 1 of 3 deciphered.")
ok(table.concat(pm.names, ",") == "Vannaz,Brakka,Rimebg", "wrapped, B reads as Z: " .. table.concat(pm.names, ","))
pm.command("auto", "on"); sent = {}
pm.line("Prisoner manifest. The broken seal prints the Patrol key: A reads as D. Priority names: Ydqwd. 0 of 1 deciphered.")
ok(sent[1] == "decipher Vanta", "pm auto on: sends them by itself")
pm.line(nil); pm.line("Some other line.")
ok(true, "other lines and nil are ignored")
print("\npm: ALL PASSED")
