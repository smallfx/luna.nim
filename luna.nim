# luna.nim is a convenience library for implementing Lua scripting in the nim language.
#
# Copyright (c) 2016 Jackson Broussard
#
# Permission is hereby granted, free of charge, to any person obtaining a copy
# of this software and associated documentation files (the "Software"), to deal
# in the Software without restriction, including without limitation the rights
# to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
# copies of the Software, and to permit persons to whom the Software is
# furnished to do so, subject to the following conditions:
#
# The above copyright notice and this permission notice shall be included in
# all copies or substantial portions of the Software.
#
# THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
# IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
# FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
# AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
# LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
# OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN
# THE SOFTWARE.

import lua
import tables
import hashes
import strutils

# interal lua type values
const
    TNONE* = - 1
    TNIL* = 0
    TBOOLEAN* = 1
    TNUMBER* = 3
    TSTRING* = 4
    TTABLE* = 5

type
    LVTableKeyType* = enum
        KString, KNumber
    LVTableKey* = ref LVTableKeyObj
    LVTableKeyObj = object
        case kind*: LVTableKeyType
            of KString:
                s*: string
            of KNumber:
                n*: float

# implement hash for LVTableKey by piggybacking on primitive hash
proc hash*(x: LVTableKey): Hash =
    var h: Hash = 0
    case x.kind
        of KString:
            h = x.s.hash
        of KNumber:
            h = x.n.hash
    result = h

# algebraic ("case" object) data types need explicit equality implementation
# "Table" hash comparison doesn't work without this
proc `==`*(a, b: LVTableKey): bool =
    if a.kind != b.kind:
        return false
    else:
        case a.kind
        of KString:
            return a.s == b.s
        of KNumber:
            return a.n == b.n

type
    LuaValType* = enum
        LVNil, LVBoolean, LVString, LVNumber, LVTable, LVError
    LuaVal* = ref LuaValObj
    LuaValObj = object
        case kind*: LuaValType
            of LVNil: nil
            of LVBoolean:
                b*: bool
            of LVString:
                s*: string
            of LVNumber:
                n*: float
            of LVTable:
                t*: Table[LVTableKey, LuaVal]
            of LVError:
                error_message*: string

# convenience LVTable square bracket getters
# TODO: make bracket setters work the same way
proc `[]`*(t: Table[LVTableKey, LuaVal], k: string): LuaVal =
    let key = LVTableKey(kind: KString, s: k)
    return t[key]
proc `[]`*(t: Table[LVTableKey, LuaVal], k: float): LuaVal =
    let key = LVTableKey(kind: KNumber, n: k)
    return t[key]
proc `[]`*(t: Table[LVTableKey, LuaVal], k: int): LuaVal =
    let key = LVTableKey(kind: KNumber, n: float(k))
    return t[key]

proc pullLuaVal*(L: PState, ind: cint): LuaVal =
    case luatype(L, ind)
        of TNIL:
            return LuaVal(kind: LVNil)
        of TBOOLEAN:
            return LuaVal(kind: LVBoolean, b: (toboolean(L, ind) == 1))
        of TNUMBER:
            return LuaVal(kind: LVNumber, n: tonumber(L, ind))
        of TSTRING:
            return LuaVal(kind: LVString, s: tostring(L, ind))
        of TTABLE:
            var t: Table[LVTableKey, LuaVal] = initTable[LVTableKey, LuaVal]()
            let keyind = ind - 1
            pushnil(L)
            while(next(L, keyind) != 0):
                let val = pullLuaVal(L, ind)
                let keytype = luatype(L, keyind)
                var key: LVTableKey
                if keytype == TSTRING:
                    key = LVTableKey(kind: KString, s: tostring(L, keyind))
                elif keytype == TNUMBER:
                    key = LVTableKey(kind: KNumber, n: tonumber(L, keyind))
                t[key] = val
                pop(L, 1)
            return LuaVal(kind: LVTable, t: t)
        else:
            # TODO: handle all lua types (?)
            const message = "only handles string, num, bool, nil and table"
            return LuaVal(kind: LVError, error_message: message)

proc pushLuaVal*(L: PState, lv: LuaVal) =
    case lv.kind
        of LVNil:
            pushnil(L)
        of LVBoolean:
            let b: cint = if lv.b: 1
                    else: 0
            pushboolean(L, b)
        of LVString:
            discard pushstring(L, lv.s)
        of LVNumber:
            pushnumber(L, lv.n)
        of LVTable:
            newtable(L)
            for k,v in lv.t.pairs:
                case k.kind
                    of KString:
                        discard pushstring(L, k.s)
                    of KNumber:
                        pushnumber(L, k.n)
                pushLuaVal(L, v)
                settable(L, -3)
        else:
            # TODO: 'none' case(?), 'LVError' case (??)
            pushnil(L)

proc callLuaFunc*(L: PState, funcname: string, args: openArray[LuaVal] = []): LuaVal =
    getglobal(L, funcname)
    for i in low(args)..high(args):
        pushLuaVal(L, args[i])
    discard pcall(L, cint(len(args)), 1, 0)
    result = pullLuaVal(L, -1)

# convenience functions for logging LuaVal
proc indentString(s: string, indt: int): string =
    var r = ""
    if indt >= 1:
        for i in 1..indt:
            r &= "  "
    result = r & s

proc stringifyLuaVal*(lv: LuaVal, indt: int = 0): string =
    var r = ""
    case lv.kind
        of LVNil:
            r = "nil"
        of LVString:
            r = "\"" & lv.s & "\""
        of LVNumber:
            r = $lv.n
        of LVBoolean:
            r = if (lv.b == true): "true"
                             else: "false"
        of LVError:
            r = "[LVError: \"" & lv.error_message & "\"]"
        of LVTable:
            r &= "{"
            r &= "\n"
            for k,v in lv.t.pairs:
                case k.kind
                    of KString:
                        r &= indentString(k.s, indt + 1)
                    of KNumber:
                        r &= indentString($k.n, indt + 1)
                r &= " = "
                r &= stringifyLuaVal(v, indt + 1)
                r &= "\n"
            r &= indentString("}", indt)
    result = r
