json=require("json")
parse_chain=require("parse_chain")
tli_=require("tli")
tli=tli_:new()
local data,err=tli:parse_tli([[
chain a b
 
w12
 
pattern b
0 0 1 2
 
pattern a
a
  ]],true)

if err~=nil then
  print(err)
else
  print(json.encode(data))
end

-- for i,v in pairs(data.track) do
--   print(i,json.encode(v))
-- end
