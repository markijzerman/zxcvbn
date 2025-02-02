local Track={}

STATE_VTERM=1
STATE_SAMPLE=2
STATE_LOADSCREEN=3
STATE_SOFTSAMPLE=4

TYPE_MXSYNTHS=1
TYPE_INFINITEPAD=2
TYPE_MELODIC=3
TYPE_MXSAMPLES=4
TYPE_SOFTSAMPLE=5
TYPE_DRUM=6
TYPE_CROW=7
TYPE_MIDI=8
TYPE_JF=9
TYPE_WSYN = 10

function string.split(pString,pPattern)
  local Table={} -- NOTE: use {n = 0} in Lua-5.0
  local fpat="(.-)"..pPattern
  local last_end=1
  local s,e,cap=pString:find(fpat,1)
  while s do
    if s~=1 or cap~="" then
      table.insert(Table,cap)
    end
    last_end=e+1
    s,e,cap=pString:find(fpat,last_end)
  end
  if last_end<=#pString then
    cap=pString:sub(last_end)
    table.insert(Table,cap)
  end
  return Table
end

function Track:new(o)
  o=o or {}
  setmetatable(o,self)
  self.__index=self
  o:init()
  return o
end

function Track:init()
  self.lfos={}

  self.loop={pos_play=-1,pos_rec=-1,arm_play=false,arm_rec=false,send_tape=0}

  self.track_type_options={"mx.synths","infinite pad","melodic","mx.samples","softcut","drum","crow","midi","jf", "wsyn"}
  params:add_option(self.id.."track_type","clade",self.track_type_options,1)
  
  params:set_action(self.id.."track_type",function(x)
    local chosenclade = self.track_type_options[x]
    
    -- if JF is chosen, init JF
    if chosenclade=="jf" then
      crow.ii.jf.mode(1)
    end
    
    -- if Wsyn is chosen, init wsyn
     if chosenclade=="wsyn" then
      crow.ii.wsyn.ar_mode(1)
    end
    
    -- rerun show/hiding
    self:select(self.selected)
  end)

  params:add_number(self.id.."sc","softcut voice",1,3,1)
  params:set_action(self.id.."sc",function(x)
    self.states[STATE_SOFTSAMPLE]:update_loop()
  end)
  params:add_option(self.id.."sc_sync","sync play/rec heads",{"no","yes"},1)

  -- mx.samples
  params:add_option(self.id.."mx_sample","instrument",mx_sample_options,1)
  -- crow
  params:add_option(self.id.."crow_type","outputs",{"1+2","3+4"},1)
  
  -- jf
  params:add_option(self.id.."jf_type","jf",{""},1)
  -- jf params to come
  
  -- wsyn
  params:add_option(self.id.."wsyn_type","wsyn",{""},1)
  -- wsyn params to come
  
  -- sliced sample
  params:add_number(self.id.."slices","slices",1,16,16)
  params:add_file(self.id.."sample_file","file",_path.audio.."break-ops")
  params:set_action(self.id.."sample_file",function(x)
    if util.file_exists(x) and string.sub(x,-1)~="/" then
      self:load_sample(x)
    end
  end)
  params:add_option(self.id.."play_through","play through",{"until stop","until next slice"},2)
  params:add_number(self.id.."bpm","bpm",10,600,math.floor(clock.get_tempo()))

  -- midi stuff
  params:add_option(self.id.."midi_dev","device",midi_device_list,1)
  params:add_number(self.id.."midi_ch","channel",1,16,1)

  -- mx.synths stuff
  self.mx_synths={"polyperc","synthy","casio","icarus","epiano","toshiya","malone","kalimba","mdapiano","dreadpiano","aaaaaa","triangles","bigbass","supersaw"}
  params:add_option(self.id.."mx_synths","synth",self.mx_synths)
  local params_menu={
    {id="mod1",name="mod 1",min=-1,max=1,exp=false,div=0.01,default=0},
    {id="mod2",name="mod 2",min=-1,max=1,exp=false,div=0.01,default=0},
    {id="mod3",name="mod 3",min=-1,max=1,exp=false,div=0.01,default=0},
    {id="mod4",name="mod 4",min=-1,max=1,exp=false,div=0.01,default=0},
  }
  for _,pram in ipairs(params_menu) do
    params:add{
      type="control",
      id=self.id..pram.id,
      name=pram.name,
      controlspec=controlspec.new(pram.min,pram.max,pram.exp and "exp" or "lin",pram.div,pram.default,pram.unit or "",pram.div/(pram.max-pram.min)),
      formatter=pram.formatter,
    }
  end

  local params_menu={}

  params_menu={
    {id="loop_end",name="loop duration",min=0,max=60,exp=false,div=0.01,default=30,unit="s",fn=function(x) return x+softcut_offsets[params:get(self.id.."sc")] end},
    {id="rec_level",name="record",min=0,max=1,exp=false,div=0.01,default=0,fn=function(x) return x end},
    {id="level",name="volume (v)",min=-48,max=12,exp=false,div=0.1,default=-6,unit="db",fn=function(x) return util.dbamp(x) end},
    {id="pan",name="pan (w)",min=-1,max=1,exp=false,div=0.01,default=0,fn=function(x) return x end},
    {id="rate",name="rate (u)",min=-2,max=2,exp=false,div=0.01,default=1.0,response=1,formatter=function(param) return string.format("%s%2.1f",param:get()>-0.01 and "+" or "",param:get()*100) end,fn=function(x) return x end},
  }
  for _,pram in ipairs(params_menu) do
    params:add{
      type="control",
      id=self.id.."sc_"..pram.id,
      name=pram.name,
      controlspec=controlspec.new(pram.min,pram.max,pram.exp and "exp" or "lin",pram.div,pram.default,pram.unit or "",pram.div/(pram.max-pram.min)),
      formatter=pram.formatter,
    }
    params:set_action(self.id.."sc_"..pram.id,function(x)
      -- print(pram.id,params:get(self.id.."sc"),x,pram.fn(x))
      if pram.id=="rec_level" then
        softcut.pre_level(params:get(self.id.."sc")+3,1-pram.fn(x))
        softcut.rec_level(params:get(self.id.."sc")+3,pram.fn(x))
      elseif pram.id=="loop_end" then
        softcut[pram.id](params:get(self.id.."sc"),pram.fn(x))
        softcut[pram.id](params:get(self.id.."sc")+3,pram.fn(x))
        softcut.position(params:get(self.id.."sc")+3,pram.fn(x))
        self.states[STATE_SOFTSAMPLE]:update_loop()
      else
        softcut[pram.id](params:get(self.id.."sc"),pram.fn(x))
      end
    end)
  end

  params_menu={
    {id="source_note",name="source_note",min=1,max=127,exp=false,div=1,default=60,formatter=function(param) return musicutil.note_num_to_name(math.floor(param:get()),true)end},
    {id="db",name="volume (v)",min=-48,max=12,exp=false,div=0.1,default=-6,unit="db"},
    {id="db_sub",name="volume sub",min=-48,max=12,exp=false,div=0.1,default=-6,unit="db"},
    {id="pan",name="pan (w)",min=-1,max=1,exp=false,div=0.01,default=0},
    {id="filter",name="filter (i)",min=24,max=127,exp=false,div=0.5,default=127,formatter=function(param) return musicutil.note_num_to_name(math.floor(param:get()),true)end},
    {id="probability",name="probability (q)",min=0,max=100,exp=false,div=1,default=100,unit="%"},
    {id="attack",name="attack (k)",min=5,max=2000,exp=true,div=5,default=1,unit="ms"},
    {id="crow_sustain",name="sustain",min=0,max=10,exp=false,div=0.1,default=10,unit="volt"},
    {id="swell",name="swell (j)",min=0.1,max=2,exp=false,div=0.01,default=1.0,response=1,formatter=function(param) return string.format("%d%%",util.round(100*param:get())) end},
    {id="release",name="release (l)",min=5,max=2000,exp=true,div=5,default=50,unit="ms"},
    {id="monophonic_release",name="mono release",min=0,max=2000,exp=false,div=10,default=0,unit="ms"},
    {id="gate",name="gate (h)",min=0,max=100,exp=false,div=1,default=100,unit="%"},
    {id="decimate",name="decimate (m)",min=0,max=1,exp=false,div=0.01,default=0.0,response=1,formatter=function(param) return string.format("%d%%",util.round(100*param:get())) end},
    {id="drive",name="drive",min=0,max=1,exp=false,div=0.01,default=0.0,response=1,formatter=function(param) return string.format("%d%%",util.round(100*param:get())) end},
    {id="compression",name="compression",min=0,max=1,exp=false,div=0.01,default=0.0,response=1,formatter=function(param) return string.format("%d%%",util.round(100*param:get())) end},
    {id="pitch",name="note (n)",min=-24,max=24,exp=false,div=0.1,default=0.0,response=1,formatter=function(param) return string.format("%s%2.1f",param:get()>-0.01 and "+" or "",param:get()) end},
    {id="rate",name="rate (u)",min=-2,max=2,exp=false,div=0.01,default=1.0,response=1,formatter=function(param) return string.format("%s%2.1f",param:get()>-0.01 and "+" or "",param:get()*100) end},
    {id="compressing",name="compressing",min=0,max=1,exp=false,div=1,default=0.0,response=1,formatter=function(param) return param:get()==1 and "yes" or "no" end},
    {id="compressible",name="compressible",min=0,max=1,exp=false,div=1,default=0.0,response=1,formatter=function(param) return param:get()==1 and "yes" or "no" end},
    {id="stretch",name="stretch",min=0,max=5,exp=false,div=0.01,default=0.0,response=1,formatter=function(param) return string.format("%2.0f%%",param:get()*100) end},
    {id="send_reverb",name="send reverb (z)",min=0,max=1,exp=false,div=0.01,default=0.0,response=1,formatter=function(param) return string.format("%2.0f%%",param:get()*100) end},
    {id="transpose",name="transpose (y)",min=-127,max=127,exp=false,div=1,default=0.0,response=1,formatter=function(param) return string.format("%s%2.0f",param:get()>-0.01 and "+" or "",param:get()) end},
  }
  for _,pram in ipairs(params_menu) do
    params:add{
      type="control",
      id=self.id..pram.id,
      name=pram.name,
      controlspec=controlspec.new(pram.min,pram.max,pram.exp and "exp" or "lin",pram.div,pram.default,pram.unit or "",pram.div/(pram.max-pram.min)),
      formatter=pram.formatter,
    }
  end

  self.note_cache={}
  self.scale_notes={}
  for i=1,127 do
    table.insert(self.scale_notes,127)
  end
  self.scale_names={"chromatic"}
  for i=1,#musicutil.SCALES do
    table.insert(self.scale_names,string.lower(musicutil.SCALES[i].name))
  end
  params:add{type="option",id=self.id.."scale_mode",name="scale mode",
    options=self.scale_names,default=1,
  action=function() self:scale_build() end}
  params:add{type="number",id=self.id.."root_note",name="root note",
    min=0,max=127,default=0,formatter=function(param) return musicutil.note_num_to_name(param:get(),false) end,
  action=function() self:scale_build() end}

  params:add{type="binary",name="find onsets",id=self.id.."get_onsets",behavior="momentary",action=function(v)
    if v==1 and params:get(self.id.."track_type")==TYPE_SOFTSAMPLE then
      self.states[STATE_SOFTSAMPLE]:get_onsets()
    end
  end}

  params:add{type="binary",name="play",id=self.id.."play",behavior="toggle",action=function(v)
    -- reset the clocks if this is the first thing to play
    if v==1 then
      local play_count=0
      for i,_ in ipairs(tracks) do
        play_count=play_count+params:get(i.."play")
      end
      if play_count==1 then
        reset_clocks()
      end
      self:loop_toggle(true)
    else
      self:loop_toggle(false)
    end
  end}
  params:add{type="binary",name="mute",id=self.id.."mute",behavior="toggle",action=function(v)
  end}
  params:add_number(self.id.."mute_group","mute group",1,10,self.id)

  self.params={shared={"track_type","play","db","probability","pitch","mute","mute_group","transpose","scale_mode","root_note"}}
  self.params["drum"]={"sample_file","stretch","rate","slices","bpm","compression","play_through","gate","filter","decimate","drive","pan","compressing","compressible","attack","release","send_reverb"}
  self.params["melodic"]={"sample_file","drive","monophonic_release","attack","release","filter","pan","source_note","compressing","compressible"}
  self.params["infinite pad"]={"attack","swell","filter","pan","release","compressing","compressible","send_reverb"}
  self.params["mx.samples"]={"mx_sample","db","attack","pan","release","compressing","compressible","send_reverb"}
  self.params["crow"]={"crow_type","attack","release","crow_sustain"}
  self.params["jf"]={"jf_type"} -- jf options to come
  self.params["wsyn"]={"wsyn_type"} -- wsyn options to come
  self.params["midi"]={"midi_ch","midi_dev"}
  self.params["mx.synths"]={"db","monophonic_release","filter","db_sub","attack","pan","release","compressing","compressible","mx_synths","mod1","mod2","mod3","mod4","db_sub","send_reverb"}
  self.params["softcut"]={"sc","sc_sync","get_onsets","gate","pitch","play_through","sample_file","sc_level","sc_pan","sc_rec_level","sc_rate","sc_loop_end"}

  -- define the shortcodes here
  self.mods={
    j=function(x,v)
      if v==nil then self.lfos["j"]:stop() end
      if params:get(self.id.."track_type")==TYPE_SOFTSAMPLE then
        params:set(self.id.."sc_rec_level",util.clamp(x,0,100)/100)
      elseif params:get(self.id.."track_type")==TYPE_DRUM then
        params:set(self.id.."decimate",util.clamp(x,0,100)/100)
      elseif params:get(self.id.."track_type")==TYPE_INFINITEPAD then
        params:set(self.id.."swell",util.clamp(x,0,200)/100)
      elseif params:get(self.id.."track_type")==TYPE_MXSYNTHS then
        x=util.clamp(x,0,400)
        local i=math.floor((x-1)/100)+1
        i=i<1 and 1 or i
        x=x-(i-1)*100
        x=(x-50)/50
        params:set(self.id.."mod"..i,x)
      end
    end,
  i=function(x,v) if v==nil then self.lfos["i"]:stop() end;params:set(self.id.."filter",x+30) end,
q=function(x,v) if v==nil then self.lfos["q"]:stop() end;params:set(self.id.."probability",x) end,
h=function(x,v) if v==nil then self.lfos["h"]:stop() end;params:set(self.id.."gate",x) end,
k=function(x,v) if v==nil then self.lfos["k"]:stop() end;params:set(self.id.."attack",x) end,
l=function(x,v) if v==nil then self.lfos["l"]:stop() end;params:set(self.id.."release",x) end,
w=function(x,v) if v==nil then self.lfos["w"]:stop() end;params:set(self.id.."pan",(x/100));params:set(self.id.."sc_pan",x/100) end,
m=function(x) self:setup_lfo(x) end,
n=function(x,v) if v==nil then self.lfos["n"]:stop() end;params:set(self.id.."pitch",x) end,
u=function(x,v) if v==nil then self.lfos["u"]:stop() end;params:set(self.id.."rate",x/100);params:set(self.id.."sc_rate",x/100) end,
z=function(x,v) if v==nil then self.lfos["z"]:stop() end;params:set(self.id.."send_reverb",x/100) end,
y=function(x,v) if v==nil then self.lfos["y"]:stop() end;params:set(self.id.."transpose",x) end,
}
-- setup lfos
self.lfos={}
for k,_ in pairs(self.mods) do
  if k~="m" then
    self.lfos[k]=lfos_:add{
      min=10,
      max=20,
      depth=1,
      mode="clocked",
      period=6,
      action=function(scaled,raw) self.mods[k](scaled,true) end,
    }
  end
end
-- enc3
self.enc3={}
self.enc3[TYPE_CROW]="crow_sustain"
-- self.enc3[TYPE_JF]="something" jf options to come
-- self.enc3[TYPE_WSYN]="something" wsyn options to come
self.enc3[TYPE_DRUM]="drive"
self.enc3[TYPE_INFINITEPAD]="swell"
self.enc3[TYPE_MELODIC]="drive"
self.enc3[TYPE_MIDI]="probability"
self.enc3[TYPE_MXSAMPLES]="pan"
self.enc3[TYPE_MXSYNTHS]="pan"
self.enc3[TYPE_SOFTSAMPLE]="pan"

-- initialize track data
self.state=STATE_VTERM
self.states={}
table.insert(self.states,vterm_:new{id=self.id,on_save=function(x)
  local success=self:parse_tli()
  return success
end,shift_updown=function(d)
  if params:get(self.id.."track_type")==TYPE_MXSAMPLES then
    params:delta(self.id.."mx_sample",d)
  elseif params:get(self.id.."track_type")==TYPE_MXSYNTHS then
    params:delta(self.id.."mx_synths",d)
  elseif params:get(self.id.."track_type")==TYPE_MIDI then
    params:delta(self.id.."midi_dev",d)
  elseif params:get(self.id.."track_type")==TYPE_CROW then
    params:delta(self.id.."crow_type",d)
  elseif params:get(self.id.."track_type")==TYPE_JF then
    params:delta(self.id.."jf_type",d)
  elseif params:get(self.id.."track_type")==TYPE_WSYN then
    params:delta(self.id.."wsyn_type",d)
  elseif params:get(self.id.."track_type")==TYPE_SOFTSAMPLE then
    params:delta(self.id.."sc",d)
  end
end,enc3=function()
  return self.enc3[params:get(self.id.."track_type")]
end})
table.insert(self.states,sample_:new{id=self.id})
table.insert(self.states,viewselect_:new{id=self.id})
table.insert(self.states,softsample_:new{id=self.id})

-- keep track of notes
self.midi_notes={}

self.scroll={"","","","","","",""}

-- add playback functions for each kind of engine
self.play_fn={}
-- spliced sample
self.play_fn[TYPE_DRUM]={
  note_on=function(d,mods)
    if d.note_to_emit==nil then
      do return end
    end
    local id=self.id.."_"..d.note_to_emit
    self.states[STATE_SAMPLE]:play{
      on=true,
      id=id,
      ci=(d.note_to_emit-1)%16+1,
      db=mods.v or 0,
      pan=params:get(self.id.."pan"),
      duration=d.duration_scaled,
      rate=clock.get_tempo()/params:get(self.id.."bpm")*params:get(self.id.."rate"),
      watch=(params:get("track")==self.id and self.state==STATE_SAMPLE) and 1 or 0,
      retrig=util.clamp((mods.x or 1)-1,0,30) or 0,
      pitch=params:get(self.id.."pitch"),
      gate=params:get(self.id.."gate")/100,
      send_tape=self.loop.send_tape,
    }
  end,
}
-- melodic sample
self.play_fn[TYPE_MELODIC]={
  note_on=function(d,mods)
    if d.note_to_emit==nil then
      do return end
    end
    local id=self.id.."_"..d.note_to_emit
    self.states[STATE_SAMPLE]:play{
      on=true,
      id=id,
      db=mods.v or 0,
      pitch=d.note_to_emit-params:get(self.id.."source_note")+params:get(self.id.."pitch"),
      duration=d.duration_scaled,
      retrig=util.clamp((mods.x or 1)-1,0,30) or 0,
      watch=(params:get("track")==self.id and self.state==STATE_SAMPLE) and 1 or 0,
      gate=params:get(self.id.."gate")/100,
      send_tape=self.loop.send_tape,
    }
  end,
}
-- mx.samples
self.play_fn[TYPE_MXSAMPLES]={
  note_on=function(d,mods)
    if params:get(self.id.."mx_sample")==1 then
      do return end
    end
    local folder=_path.audio.."mx.samples/"..params:string(self.id.."mx_sample") -- TODO: choose from option
    local note=d.note_to_emit+params:get(self.id.."pitch")
    print("mods.v",mods.v)
    local velocity=util.clamp(util.linlin(-48,12,0,127,params:get(self.id.."db")+(mods.v or 0)),1,127)
    local amp=util.dbamp(params:get(self.id.."db")+(mods.v or 0))
    local pan=params:get(self.id.."pan")
    local attack=params:get(self.id.."attack")/1000
    local release=params:get(self.id.."release")/1000
    local sub=params:get(self.id.."db_sub")
    local mods={}
    for i=1,4 do
      table.insert(mods,params:get(self.id.."mod"..i))
    end
    local duration=d.duration_scaled
    local sendCompressible=0
    local sendCompressing=0
    local sendReverb=params:get(self.id.."send_reverb")
    engine.mx(folder,note,velocity,amp,pan,attack,release,duration,sendCompressible,sendCompressing,sendReverb,self.loop.send_tape)
  end,
}
-- mx.synths
self.play_fn[TYPE_MXSYNTHS]={
  note_on=function(d,mods)
    local synth=params:string(self.id.."mx_synths")
    local note=d.note_to_emit+params:get(self.id.."pitch")
    local db=params:get(self.id.."db")
    local db_add=(mods.v or 0)
    local pan=params:get(self.id.."pan")
    local attack=params:get(self.id.."attack")/1000
    local release=params:get(self.id.."release")/1000
    local duration=d.duration_scaled
    local retrig=util.clamp((mods.x or 1)-1,0,30) or 0
    engine.mx_synths(synth,note,db,params:get(self.id.."db_sub"),pan,attack,release,
      params:get(self.id.."mod1"),params:get(self.id.."mod2"),params:get(self.id.."mod3"),params:get(self.id.."mod4"),
    duration,params:get(self.id.."compressible"),params:get(self.id.."compressing"),params:get(self.id.."send_reverb"),params:get(self.id.."filter"),params:get(self.id.."monophonic_release")/1000,self.id,self.loop.send_tape,retrig,db_add)
  end,
}
-- infinite pad
self.play_fn[TYPE_INFINITEPAD]={
  note_on=function(d,mods)
    local note=d.note_to_emit+params:get(self.id.."pitch")
    engine.note_on(note,
      params:get(self.id.."db")+util.clamp((mods.v or 0)/10,0,10),
      params:get(self.id.."attack")/1000,
      params:get(self.id.."release")/1000,
      d.duration_scaled,
      params:get(self.id.."swell"),params:get(self.id.."send_reverb"),
    params:get(self.id.."pan"),params:get(self.id.."filter"),self.loop.send_tape)
  end,
}
-- softsample
self.play_fn[TYPE_SOFTSAMPLE]={
  note_on=function(d,mods)
    if d.note_to_emit==nil then
      do return end
    end
    local id=self.id.."_"..d.note_to_emit
    mods.x=mods.x or 1
    self.states[STATE_SOFTSAMPLE]:play{
      on=true,
      id=id,
      ci=(d.note_to_emit-1)%16+1,
      db=mods.v or 0,
      pan=params:get(self.id.."pan"),
      duration=d.duration_scaled,
      rate=params:get(self.id.."rate"),
      watch=(params:get("track")==self.id and self.state==STATE_SAMPLE) and 1 or 0,
      retrig=util.clamp((mods.x or 1)-1,0,30) or 0,
      pitch=params:get(self.id.."pitch"),
      gate=params:get(self.id.."gate")/100,
    }
  end,
}
-- crow
self.play_fn[TYPE_CROW]={
  note_on=function(d,mods)
    local i=(params:get(self.id.."crow_type")-1)*2+1
    local level=util.linlin(-48,12,0,10,params:get(self.id.."db")+(mods.v or 0))
    local note=d.note_to_emit+params:get(self.id.."pitch")
    if level>0 then
      -- local crow_asl=string.format("adsr(%3.3f,0,%3.3f,%3.3f,'linear')",params:get(self.id.."attack")/1000,level,params:get(self.id.."release")/1000)
      local crow_asl=string.format("{to(%3.3f,%3.3f), to(%3.3f,%3.3f), to(0,%3.3f)}",level,params:get(self.id.."attack")/1000,params:get(self.id.."crow_sustain"),d.duration_scaled,params:get(self.id.."release")/1000)
      print(i+1,crow_asl)
      crow.output[i+1].action=crow_asl
      crow.output[i].volts=(note-24)/12
      crow.output[i+1]()
    end
    -- TODO use debounce_fn
    if mods.x~=nil and mods.x>1 then
      clock.run(function()
        for i=1,mods.x do
          clock.sleep(d.duration_scaled/mods.x)
          crow.output[i+1](false)
          level=util.linlin(-48,12,0,10,params:get(self.id.."db")+(mods.v or 0)*(i+1))
          note=d.note_to_emit+params:get(self.id.."pitch")*(i+1)
          if level>0 then
            crow.output[i].volts=(note-24)/12
            crow.output[i+1]()
          end
        end
      end)
    end
  end,
}

-- jf
self.play_fn[TYPE_JF]={
  note_on=function(d,mods)
    local level=util.linlin(-48,12,0,10,params:get(self.id.."db")+(mods.v or 0))
    local note=(d.note_to_emit+params:get(self.id.."pitch")-48)
    if level>0 then
      crow.ii.jf.play_note(note/12,level)
    end
      
    --end
    -- TODO use debounce_fn
  end,
}

-- wsyn
self.play_fn[TYPE_WSYN]={
  note_on=function(d,mods)
    local level=util.linlin(-48,12,0,10,params:get(self.id.."db")+(mods.v or 0))
    local note=(d.note_to_emit+params:get(self.id.."pitch")-48)
    if level>0 then
      crow.ii.wsyn.play_note(note/12,level)
    end
      
    --end
    -- TODO use debounce_fn
  end,
}

-- midi device
self.play_fn[TYPE_MIDI]={
  note_on=function(d,mods)
    if params:get(self.id.."midi_dev")==1 then
      do return end
    end
    local vel=util.linlin(-48,12,0,127,params:get(self.id.."db")+(mods.v or 0))
    local note=d.note_to_emit+params:get(self.id.."pitch")
    local trigs=mods.x or 1
    if vel>0 then
      -- print(note,vel,params:get(self.id.."midi_ch"))
      midi_device[params:get(self.id.."midi_dev")].note_on(note,vel,params:get(self.id.."midi_ch"))
      self.midi_notes[note]={device=params:get(self.id.."midi_dev"),duration=util.round(d.duration/trigs)}
    end
    -- TODO use debouncing
    if trigs>1 then
      clock.run(function()
        for i=2,trigs do
          clock.sleep(d.duration_scaled/trigs)
          midi_device[params:get(self.id.."midi_dev")].note_off(note,0,params:get(self.id.."midi_ch"))
          vel=util.linlin(-48,12,0,127,params:get(self.id.."db")+(mods.v or 0)*(i+1))
          note=d.note_to_emit+params:get(self.id.."pitch")*(i+1)
          if vel>0 then
            -- print(d.note_to_emit,vel,params:get(self.id.."midi_ch"))
            midi_device[params:get(self.id.."midi_dev")].note_on(d.note_to_emit,vel,params:get(self.id.."midi_ch"))
            self.midi_notes[note]={device=params:get(self.id.."midi_dev"),duration=util.round(d.duration/trigs)}
          end
        end
      end)
    end
  end,
}

end

function Track:scale_build()
  if params:get(self.id.."scale_mode")==1 then
    local notes={}
    for i=1,127 do
      table.insert(notes,i)
    end
    self.scale_notes=notes
  else
    self.scale_notes=musicutil.generate_scale_of_length(params:get(self.id.."root_note")%12,params:get(self.id.."scale_mode")-1,127)
  end
end

function Track:note_in_scale(note)
  local key=string.format("%d_%d_%d",params:get(self.id.."scale_mode"),params:get(self.id.."root_note"),note)
  if self.note_cache[key]==nil then
    if note>self.scale_notes[#self.scale_notes] then
      note=note%#self.scale_notes
    end
    self.note_cache[key]=musicutil.snap_note_to_array(note,self.scale_notes)
  end
  return self.note_cache[key]
end

function Track:description()
  local s=params:string(self.id.."track_type")
  if params:get(self.id.."track_type")==TYPE_MXSYNTHS then
    s=s..string.format(" (%s)",params:string(self.id.."mx_synths"))
  elseif params:get(self.id.."track_type")==TYPE_DRUM or params:get(self.id.."track_type")==TYPE_MELODIC then
    local fname=params:string(self.id.."sample_file")
    if string.find(fname,".wav") or string.find(fname,".flac") then
      if (#fname>12) then
        fname=fname:sub(1,12).."..."
      end
    else
      fname="not loaded"
    end
    s=s..string.format(" (%s)",fname)
  elseif params:get(self.id.."track_type")==TYPE_MXSAMPLES then
    s=s..string.format(" (%s)",params:string(self.id.."mx_sample"))
  elseif params:get(self.id.."track_type")==TYPE_MIDI then
    s=s..string.format(" (%s:%d)",params:string(self.id.."midi_dev"),params:get(self.id.."midi_ch"))
  elseif params:get(self.id.."track_type")==TYPE_CROW then
    s=s..string.format(" (%s)",params:string(self.id.."crow_type"))
  elseif params:get(self.id.."track_type")==TYPE_JF then
    s=s..string.format(" (%s)",params:string(self.id.."jf_type"))
  elseif params:get(self.id.."track_type")==TYPE_WSYN then
    s=s..string.format(" (%s)",params:string(self.id.."wsyn_type"))
  elseif params:get(self.id.."track_type")==TYPE_SOFTSAMPLE then
    s=s..string.format(" (%s)",params:string(self.id.."sc"))
  end
  return s
end

function Track:setup_lfo(x)
  print("setup_lfo",x)
  if x==nil or tonumber(x)~=nil then
    do return end
  end
  local mod=x:sub(1,1)
  if mod=="m" or self.mods[mod]==nil then
    do return end
  end
  local nums={}
  for _,v in ipairs(string.split(x:sub(2),",")) do
    if tonumber(v)~=nil then
      table.insert(nums,tonumber(v))
    end
  end
  if #nums<1 then
    do return end
  end
  if nums[1]~=nil then
    self.lfos[mod]:set("period",nums[1])
  end
  if nums[2]~=nil then
    self.lfos[mod]:set("min",nums[2])
  end
  if nums[3]~=nil then
    self.lfos[mod]:set("max",nums[3])
  end
  self.lfos[mod]:start()
end

function Track:dumps()
  local data={states={}}
  for i,v in ipairs(self.states) do
    if i==STATE_SAMPLE or i==STATE_VTERM then
      data.states[i]=v:dumps()
    end
  end
  data.state=self.state
  engine.loop_save(self.id,_path.data.."zxcvbn/tapes/"..params:get("random_string").."_")
  return json.encode(data)
end

function Track:loads(s)
  local data=json.decode(s)
  if data==nil then
    do return end
  end
  for i,v in ipairs(data.states) do
    if i==STATE_SAMPLE or i==STATE_VTERM then
      if v~="{}" then
        -- print("track: loads",i,v)
        self.states[i]:loads(v)
      end
    end
  end
  engine.loop_load(self.id,_path.data.."zxcvbn/tapes/"..params:get("random_string").."_")
  self.state=data.state
end

function Track:load_text(text)
  self.states[STATE_VTERM]:load_text(text)
  self:parse_tli()
end

function Track:got_onsets(data)
  if params:get(self.id.."track_type")==TYPE_SOFTSAMPLE then
    self.states[STATE_SOFTSAMPLE]:got_onsets(data)
  elseif params:get(self.id.."track_type")==TYPE_DRUM then
    self.states[STATE_SAMPLE]:got_onsets(data)
  end
end

function Track:parse_tli()
  print("parsing",self.id)
  local text=self.states[STATE_VTERM]:get_text()
  local tli_parsed=nil
  local is_hex=false
  is_hex=params:get(self.id.."track_type")==TYPE_SOFTSAMPLE or params:get(self.id.."track_type")==TYPE_DRUM
  tli_parsed,err=tli:parse_tli(text,is_hex)
  if err~=nil then
    print("error: "..err)
    local foo=string.split(err,":")
    show_message(foo[#foo])
    do return end
  end
  self.tli=tli_parsed
  self.track={}
  for i,v in ipairs(tli_parsed.track) do
    if self.track[v.start]==nil then
      self.track[v.start]={}
    end
    table.insert(self.track[v.start],v)
  end
  -- update the meta
  if self.tli.meta~=nil then
    for k,v in pairs(self.tli.meta) do
      if params.lookup[self.id..k]~=nil then
        local ok,err=pcall(function()
          print("setting "..k.." = "..v)
          params:set(self.id..k,v)
        end)
        if not ok then
          show_message("error setting "..k)
        end
      end
      if params.name_to_id[k]~=nil and params.lookup[self.id..params.name_to_id[k]]~=nil then
        local ok,err=pcall(function()
          print("setting "..params.name_to_id[k].." = "..v)
          params:set(self.id..params.name_to_id[k],v)
        end)
        if not ok then
          show_message("error setting "..params.name_to_id[k])
        end
      end
    end
    show_message("parsed track "..self.id,1)
  end
  -- add flag to turn off on notes
  self.flag_parsed=true
  return true
end

function Track:emit(beat)
  -- turn off any midi notes
  if next(self.midi_notes)~=nil then
    local to_remove={}
    for note,v in pairs(self.midi_notes) do
      v.duration=v.duration-1
      if v.duration==0 then
        -- note off
        midi_device[v.device].note_off(note,0,params:get(self.id.."midi_ch"))
        table.insert(to_remove,note)
      end
    end
    for _,note in ipairs(to_remove) do
      self.midi_notes[note]=nil
    end
  end
  if params:get(self.id.."play")==0 then
    do return end
  end
  if self.tli~=nil and self.track~=nil and self.tli.pulses>0 then
    local i=(beat-1)%self.tli.pulses+1
    if i==1 then
      if self.loop.arm_play then
        print("track: disarming play")
        self.loop.arm_play=false
        engine.loop_start(self.id,params:get("ambisonics")-1)
      elseif self.loop.arm_rec then
        print("track: disarming rec")
        self.loop.arm_rec=false
        if self.tli~=nil and self.tli.pulses~=nil then
          local duration=self.tli.pulses/24.0*clock.get_beat_sec()
          local crossfade=duration>0.1 and 0.1 or duration/2
          print("recording "..self.tli.pulses.." pulses ".." for "..duration.." seconds")
          engine.loop_record(self.id,duration,crossfade,params:get(self.id.."track_type")<TYPE_CROW and 3 or 2) 
          -- something with jf / wsyn here?
          self.loop.arm_play=true
          self.loop.send_tape=1
        end
      end
    end
    local t=self.track[i]
    if t==nil then
      do return end
    end
    -- print("beati",beat,i,self.tli.pulses,json.encode(t))
    for k,d in ipairs(t) do
      -- print(k,json.encode(d))
      local mods={}
      if next(d.mods)~=nil then
        for _,vvv in ipairs(d.mods) do
          k=vvv[1]
          v=vvv[2]
          mods[k]=tli.numdashcomr(v) or v
          if self.mods[k]~=nil and mods[k]~=nil then
            pcall(
              function()
                self.mods[k](k=="m" and vvv[2] or mods[k])
              end
            )
          end
        end
      end
      if self.flag_parsed then
        self.flag_parsed=nil
      end
      d.duration_scaled=d.duration*(clock.get_beat_sec()/24)
      --print("d.duration_scaled",d.duration_scaled,"d.duration",d.duration)
      local note_to_emit=d.m
      if note_to_emit~=nil then
        -- add transposition to note before getting scale
        note_to_emit=self:note_in_scale(note_to_emit+params:get(self.id.."transpose"))
        self:scroll_add((params:get(self.id.."track_type")==TYPE_DRUM or params:get(self.id.."track_type")==TYPE_SOFTSAMPLE) and note_to_emit or string.lower(musicutil.note_num_to_name(note_to_emit)))
      end
      if note_to_emit==nil or params:get(self.id.."mute")==1 then
        do return end
      end
      if math.random(0,100)<=params:get(self.id.."probability") then
        d.note_to_emit=note_to_emit
        self.play_fn[params:get(self.id.."track_type")].note_on(d,mods)
      end
    end
  end
end

function Track:select(selected)
  self.selected=selected
  -- first hide parameters
  for k,ps in pairs(self.params) do
    for _,p in ipairs(ps) do
      if selected and (k=="shared" or k==params:string(self.id.."track_type")) then
      else
        params:hide(self.id..p)
      end
    end
  end
  -- then show them (so that some things can share the same parameters)
  for k,ps in pairs(self.params) do
    for _,p in ipairs(ps) do
      if selected and (k=="shared" or k==params:string(self.id.."track_type")) then
        params:show(self.id..p)
      end
    end
  end
  debounce_fn["menu"]={
    1,function()
      _menu.rebuild_params()
    end
  }
end

function Track:scroll_add(m)
  for i=1,6 do
    self.scroll[i]=self.scroll[i+1]
  end
  self.scroll[7]=m
end

function Track:set_position(pos)
  self.states[STATE_SAMPLE]:set_position(pos)
end

function Track:load_sample(path)
  print(string.format("track %d: load sample %s",self.id,path))
  if params:get(self.id.."track_type")==TYPE_SOFTSAMPLE then
    self.states[STATE_SOFTSAMPLE]:load_sample(path,true)
  else
    self.states[STATE_SAMPLE]:load_sample(path,params:get(self.id.."track_type")==TYPE_MELODIC,params:get(self.id.."slices"))
  end
end

function Track:loop_record()
  print(string.format("track %d: recording armed",self.id))
  self.loop.pos_rec=-1
  self.loop.pos_play=-1
  self.loop.arm_rec=true
end

function Track:loop_toggle(on)
  if self.loop.pos_rec<0 then
    do return end
  end
  on=on or self.loop.pos_play<0
  print(string.format("track %d: loop toggle %s",self.id,on and "on" or "off"))
  if on then
    if self.loop.pos_rec>-1 then
      self.loop.arm_play=true
    end
  else
    engine.loop_stop(self.id)
  end
end

-- base functions

function Track:keyboard(k,v)
  if k=="TAB" then
    if v==1 and (params:get(self.id.."track_type")==TYPE_DRUM or params:get(self.id.."track_type")==TYPE_MELODIC) then
      if self.state==STATE_VTERM then
        self.state=STATE_SAMPLE
      else
        self.state=STATE_VTERM
      end
    elseif v==1 and params:get(self.id.."track_type")==TYPE_SOFTSAMPLE then
      if self.state>1 then
        self.state=1
        softcut.phase_quant(params:get(self.id.."sc"),2)
        softcut.phase_quant(params:get(self.id.."sc")+3,2)
      else
        self.state=STATE_SOFTSAMPLE
        softcut.phase_quant(params:get(self.id.."sc"),0.1)
        softcut.phase_quant(params:get(self.id.."sc")+3,0.1)
      end
    end
    do return end
  elseif k=="CTRL+M" then
    if v==1 then
      params:set(self.id.."mute",1-params:get(self.id.."mute"))
      show_message((params:get(self.id.."mute")==1 and "muted" or "unmuted").." track "..self.id)
    end
    do return end
  elseif k=="CTRL+O" and (params:get(self.id.."track_type")==TYPE_DRUM or params:get(self.id.."track_type")==TYPE_MELODIC or params:get(self.id.."track_type")==TYPE_SOFTSAMPLE) then
    if v==1 then
      if self.state==STATE_LOADSCREEN then
        self.state=STATE_SAMPLE
      else
        self.state=STATE_LOADSCREEN
      end
    end
    do return end
  end
  self.states[self.state]:keyboard(k,v)
end

function Track:enc(k,d)
  self.states[self.state]:enc(k,d)
end

function Track:key(k,z)
  self.states[self.state]:key(k,z)
end

function Track:redraw()
  self.states[self.state]:redraw()
end

return Track
