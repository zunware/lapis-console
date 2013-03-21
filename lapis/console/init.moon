
lapis = require "lapis.init"
config = require"lapis.config".get!

{
  :respond_to, :capture_errors, :capture_errors_json, :assert_error,
  :yield_error
} = require "lapis.application"

import assert_valid from require "lapis.validate"
import insert from table

raw_tostring = (o) ->
  if meta = type(o) == "table" and getmetatable o
    setmetatable o, nil
    with tostring o
      setmetatable o, meta
  else
    tostring o

encode_value = (val, seen=nil) ->
  seen or= {}

  t = type val
  switch t
    when "table"
      if seen[val]
        return { "recursion", raw_tostring(val) }

      seen[val] = true

      tuples = for k,v in pairs val
        { encode_value(k, seen), encode_value(v, seen) }

      if meta = getmetatable val
        insert tuples, {
          { "metatable", "metatable" }
          encode_value meta, seen
        }

      { t, tuples }
    else
      { t, raw_tostring val }

run = (fn using nil) ->
  lines = {}
  queries = {}

  scope = setmetatable {
    print: (...) ->
      insert lines, [ encode_value v for v in *{...} ]
  }, __index: _G

  db = require "lapis.db"
  old_logger = db.get_logger!
  db.set_logger {
    query: (q) ->
      insert queries, q
      old_logger.query q if old_logger
  }

  setfenv fn, scope
  ret = { pcall fn }
  return unpack ret, 1, 2 unless ret[1]

  db.set_logger old_logger
  lines, queries

make = (opts={}) ->
  unless config._name == "development"
    return -> status: 404, layout: false
  
  view = require"lapis.console.views.console"

  respond_to {
    GET: =>
      render: view, layout: false

    POST: capture_errors_json =>
      @params.lang or= "moonscript"
      @params.code or= ""

      assert_valid @params, {
        { "lang", one_of: {"lua", "moonscript"} }
      }

      if @params.lang == "moonscript"
        moonscript = require "moonscript.base"
        fn, err = moonscript.loadstring @params.code
        if err
          { json: { error: err } }
        else
          lines, queries = run fn
          if lines
            { json: { :lines, :queries } }
          else
            { json: { error: queries } }
  }


{ :make, :encode_value, :run, :raw_tostring }
