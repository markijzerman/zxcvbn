local Tracker={}

function Tracker:new(o)
  o=o or {}
  setmetatable(o,self)
  self.__index=self
  o:init()
  return o
end

function Tracker:init()
  self.ctrl_on=false
  self.shift_on=false
  self.alt_on=false
  self.meta_on=false
  self.norns_keyboard=0

  self.codes_keyboard={}
  for i,v in pairs(keyboard.codes) do
    self.codes_keyboard[v]=tonumber(i)
  end
end

function Tracker:keyboard(k,v)
  -- print(self.codes_keyboard[k])
  if string.find(k,"CTRL") then
    self.ctrl_on=v>0
    if self.norns_keyboard>0 then
      osc.send({other_norns[self.norns_keyboard],10111},"/remote/brd",{self.codes_keyboard[k],v})
    end
    do return end
  elseif string.find(k,"SHIFT") then
    self.shift_on=v>0
    if self.norns_keyboard>0 then
      osc.send({other_norns[self.norns_keyboard],10111},"/remote/brd",{self.codes_keyboard[k],v})
    end
    do return end
  elseif string.find(k,"ALT") then
    self.alt_on=v>0
    if self.norns_keyboard>0 then
      osc.send({other_norns[self.norns_keyboard],10111},"/remote/brd",{self.codes_keyboard[k],v})
    end
    do return end
  elseif string.find(k,"META") then
    self.meta_on=v>0
    do return end
  end
  if self.meta_on and tonumber(k)~=nil and tonumber(k)>=0 and tonumber(k)<=9 then
    self.norns_keyboard=tonumber(k)-1
    if self.norns_keyboard==0 then
      show_message("keyboard -> local",3)
    else
      if self.norns_keyboard>#other_norns then
        self.norns_keyboard=0
      else
        show_message("keyboard -> "..other_norns[self.norns_keyboard],3)
      end
    end
    do return end
  end
  if self.norns_keyboard>0 then
    osc.send({other_norns[self.norns_keyboard],10111},"/remote/brd",{self.codes_keyboard[k],v})
    do return end
  end
  if self.alt_on and tonumber(k)~=nil and tonumber(k)>=0 and tonumber(k)<=9 then
    if v==1 then
      -- mute group
      local mute_group=tonumber(k)
      if mute_group==0 then
        mute_group=10
      end
      local do_mute=-1
      for i,_ in ipairs(tracks) do
        if params:get(i.."mute_group")==mute_group then
          if do_mute<0 then
            do_mute=1-params:get(i.."mute")
            break
          end
        end
      end
      for i,_ in ipairs(tracks) do
        if params:get(i.."mute_group")==mute_group then
          params:set(i.."mute",do_mute)
        end
      end
      print("MUTE",self.alt_on,tonumber(k),mute_group,do_mute)
      if do_mute>-1 then
        show_message((do_mute==1 and "muted" or "unmuted").." group "..mute_group)
      end
    end
    do return end
  end
  k=self.shift_on and "SHIFT+"..k or k
  k=self.ctrl_on and "CTRL+"..k or k
  k=self.alt_on and "ALT+"..k or k
  if k:sub(1,5)=="CTRL+" and tonumber(k:sub(6))~=nil then
    if v==1 then
      local track=tonumber(k:sub(6))
      if track==0 then
        track=10
      end
      params:set("track",track)
      do return end
    end
  elseif k=="CTRL+I" then
    if v==1 then
      for i,k in ipairs({"pitch_in_l","pitch_in_l"}) do
        if pitch_poll_on then
          print("stopping poll")
          pitch_polls[i]:stop()
        else
          print("starting poll")
          pitch_polls[i]:start()
        end
      end
      pitch_poll_on=not pitch_poll_on
    end
    do return end
  elseif k=="CTRL+P" then
    if v==1 then
      params:set(params:get("track").."play",1-params:get(params:get("track").."play"))
      show_message((params:get(params:get("track").."play")==0 and "stopped" or "playing").." track "..params:get("track"))
    end
    do return end
  end
  tracks[params:get("track")]:keyboard(k,v)
end

function Tracker:enc(k,d)
  tracks[params:get("track")]:enc(k,d)
end

function Tracker:key(k,z)
  tracks[params:get("track")]:key(k,z)
end

function Tracker:redraw()
  tracks[params:get("track")]:redraw()
  screen.level(5)
  screen.rect(0,8,6,66)
  screen.fill()
  screen.level(params:get(params:get("track").."play")==0 and 5 or 12)
  screen.rect(0,0,6,7)
  screen.fill()
  screen.level(params:get(params:get("track").."play")==0 and 1 or 0)
  screen.move(3,6)
  screen.text_center(params:get("track"))
  screen.level(params:get(params:get("track").."play")==0 and 3 or 0)
  for i,v in ipairs(tracks[params:get("track")].scroll) do
    screen.move(3,6+(i*8))
    screen.text_center(v)
  end
end

return Tracker
