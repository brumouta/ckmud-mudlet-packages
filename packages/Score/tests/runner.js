const { lua, lauxlib, lualib, to_luastring } = require("fengari");
const fs = require("fs");
const path = require("path");

const L = lauxlib.luaL_newstate();
lualib.luaL_openlibs(L);

lua.lua_pushstring(L, to_luastring(path.resolve(__dirname, "..", "src")));
lua.lua_setglobal(L, to_luastring("SRC_ROOT"));

lua.lua_pushjsfunction(L, (L) => {
  const p = lua.lua_tojsstring(L, 1);
  try {
    lua.lua_pushstring(L, to_luastring(fs.readFileSync(p, "utf8")));
  } catch (e) {
    lua.lua_pushnil(L);
  }
  return 1;
});
lua.lua_setglobal(L, to_luastring("readfile"));

const driver = fs.readFileSync(path.resolve(__dirname, process.argv[2] || "driver.lua"), "utf8");
if (lauxlib.luaL_dostring(L, to_luastring(driver))) {
  console.log("DRIVER ERROR:", lua.lua_tojsstring(L, -1));
  process.exit(2);
}
