#luna.nim

`luna.nim` is a convenience library for implementing Lua scripting in the `nim` language.<br>
I created luna with game engines in mind, though it probably has potential for more applications.<br>
If you think something could be done better, please contribute! Even simple suggestions are welcome.

##example

```nim
# example.nim

import lua
import luna

const lua_code = """
function example_lua_function()
	return { hi = "hello" }
end
"""

# set up Lua state like normal
let L = newstate()
openlibs(L)
dostring(L, lua_code)

# call a function from our Lua instance and store the value
let lua_value: LuaVal = callLuaFunc(L, "example_lua_function")

# stringifyLuaVal is a convenient function intended for echoing LuaVal
echo stringifyLuaVal(lua_value)
```

The ouput of this code would then be:

```
$ nim -r c example.nim
...

{
	"hi": "hello"
}
```


You can also pass an array of `LuaVal`s to `callLuaFunc`. They will be used as arguments to the function.<br>
(This can (possibly obviously) be used with `LuaVal`s returned from callLuaFunc)

```nim
# example2.nim

import lua
import luna

const lua_code = """
function sum_values(a, b)
	return a + b
end
"""

...

let lv1 = LuaVal(kind: LVNumber, n: 3)
let lv2 = LuaVal(kind: LVNumber, n: 4)
let lua_value: LuaVal = callLuaFunc(L, "sum_values", [lv1, lv2])

echo stingifyLuaVal(lua_value)
```

output:

```
$ nim -r c example2.nim
...

7
```
