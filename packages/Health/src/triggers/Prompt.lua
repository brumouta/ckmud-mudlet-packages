local pct = HP:calc()

selectString("|", 1)
if pct > 75 then
    fg("green")
elseif pct > 50 then
    fg("yellow")
elseif pct > 25 then
    fg("orange")
else
    fg("red")
end
replace(f"{pct}% |")

selectString("|", 1)
fg("ansiLightBlack")
deselect()
