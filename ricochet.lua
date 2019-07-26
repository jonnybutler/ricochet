-- Ricochet
-- Generative sequencer based on cellular automation.
-- Inspired by Bongo and Batuhan Bozkurt

y_max = 8
x_max = 16

local cells = {}
local temp_cells = {}
local MusicUtil = require "musicutil"
local BeatClock = require 'beatclock'
local cs = require 'controlspec'
local clk = BeatClock.new()
local clk_midi = midi.connect()
local running = false
local reset = false
local alt = false
local transpose = 60

engine.name = 'PolyPerc'

local scale_notes = {}
local grid_scale = {}
local note_queue = {}
local note_off_queue = {}

local min_note = 0
local max_note = 127

local m = midi.connect()
local g = grid.connect()

function init()
  g:all(0)
  clk_midi.event = clk.process_midi
  clk.on_step = step
  clk.on_select_internal = function() clk:stop() end
  clk.on_select_external = reset_pattern
  clk:add_clock_params()
  
  params:add_separator()

  local scales = {}
  for i=1,#MusicUtil.SCALES do
    scales[i] = MusicUtil.SCALES[i].name
  end
  params:add_option("scale", "scale", scales)
  params:set_action("scale", build_scale)

  params:add_option("root", "root", MusicUtil.NOTE_NAMES)
  params:set_action("root", build_scale)

  params:add_separator()

  cs.AMP = cs.new(0,1,'lin',0,0.5,'')
  params:add_control("amp", "amp", cs.AMP)
  params:set_action("amp",
  function(x) engine.amp(x) end)

  cs.PW = cs.new(0,100,'lin',0,80,'%')
  params:add_control("pw", "pw", cs.PW)
  params:set_action("pw",
  function(x) engine.pw(x/100) end)

  cs.REL = cs.new(0.1,3.2,'lin',0,0.2,'s')
  params:add_control("release", "release", cs.REL)
  params:set_action("release",
  function(x) engine.release(x) end)

  cs.CUT = cs.new(50,5000,'exp',0,555,'hz')
  params:add_control("cutoff", "cutoff", cs.CUT)
  params:set_action("cutoff",
  function(x) engine.cutoff(x) end)

  cs.GAIN = cs.new(0,4,'lin',0,1,'')
  params:add_control("gain", "gain", cs.GAIN)
  params:set_action("gain",
  function(x) engine.gain(x) end)

  params:bang()
  
end

function reset_pattern()
  reset = true
  clk:reset()
end

function step()
  count()
end

function play_notes()
  -- send note off for previously played notes
  while #note_off_queue > 0 do
    m.send({type='note_off', note=table.remove(note_off_queue)})
  end
  -- play queued notes
  while #note_queue > 0 do
    local n = table.remove(note_queue)
    engine.hz(MusicUtil.note_num_to_freq(grid_scale[n]+transpose))
    m.send({type='note_on', note=n})
    table.insert(note_off_queue, n)
  end
end

function grid_scale_copy ()          
  local new_grid_scale = {}           
  local i, v = next(scale_notes, nil)  
  local k = 0
  while i <= x_max do
    new_grid_scale[i] = v
    i, v = next(scale_notes, i)        
    k = k + 1
  end
  grid_scale = new_grid_scale
end

function build_scale()
  scale_notes = MusicUtil.generate_scale_of_length(params:get("root") - 1, params:get("scale"), x_max+1)
  grid_scale_copy()
end

function enqueue_note(n)
  table.insert(note_queue, n)
end

function g.key(x,y,z)
  if running == false and z == 1 then
    exists = false
    for i=1,#cells do
      --check to see if this cell exists
      if cells[i].x == x and cells[i].y == y then
        exists = true
        exist_cell = i
        break
      end
    end
    if exists == false then
      add_cell(x, y)
      if y > 1 then
        add_temp_cell(x, y-1)
      end
    elseif exists == true and cells[exist_cell].direction ~= 1 then
      change_direction(exist_cell)
    else
      remove_cell(exist_cell)
    end
  end
  if running == false and z == 0 then
    for i=1,#cells do
      --check to get cell
      if cells[i].x == x and cells[i].y == y then
        exist_cell = i
        -- then check the direction of the cell
        local direction = cells[exist_cell].direction
        local chk_x
        local chk_y
        if direction == 3 then
          chk_x = x
          chk_y = y-1
        elseif direction == 2 then
          chk_x = x+1
          chk_y = y
        elseif direction == 4 then
          chk_x = x
          chk_y = y+1
        elseif direction == 1 then
          chk_x = x-1
          chk_y = y
        end
        for i=1, #temp_cells do
          if temp_cells[i].x == chk_x and temp_cells[i].y == chk_y then
            remove_temp_cell(i)
            break
          end
        end
        break
      end
    end
  end
end

function add_cell(new_x, new_y)
  cells[#cells+1] = {
    x = new_x,
    y = new_y,
    direction = 3,
    brightness = 8,
    initial = {x = new_x, y = new_y}
    }
    grid_redraw()
end

function add_temp_cell(new_x, new_y)
  temp_cells[#temp_cells+1] = {
    x = new_x,
    y = new_y,
  }
  grid_redraw()
end

function evaluate_cells()

  for i=1, #cells do
    for k=i+1, #cells do
      if cells[i].x == cells[k].x and cells[i].y == cells[k].y then
        collision(i)
        collision(k)
        cells[i].brightness = 15
        cells[k].brightness = 15
      elseif cells[i].direction == 1 and cells[k].direction == 2 then
        if cells[i].x - 1 == cells[k].x and cells[i].y == cells[k].y then
          collision(i)
          collision(k)
          cells[i].brightness = 15
          cells[k].brightness = 15
        end
      elseif cells[i].direction == 2 and cells[k].direction == 1 then
        if cells[i].x + 1 == cells[k].x and cells[i].y == cells[k].y then
          collision(i)
          collision(k)
          cells[i].brightness = 15
          cells[k].brightness = 15
        end
      elseif cells[i].direction == 3 and cells[k].direction == 4 then
        if cells[i].y - 1 == cells[k].y and cells[i].x == cells[k].x then
          collision(i)
          collision(k)
          cells[i].brightness = 15
          cells[k].brightness = 15
        end
      elseif cells[i].direction == 4 and cells[k].direction == 3 then
        if cells[i].y + 1 == cells[k].y and cells[i].x == cells[k].x then
          collision(i)
          collision(k)
          cells[i].brightness = 15
          cells[k].brightness = 15
        end
      end
    end
  end
end


function change_direction(exist_cell)
  if cells[exist_cell].direction == 3 then
    cells[exist_cell].direction = 2
    if not (cells[exist_cell].x >= x_max) then
      add_temp_cell(cells[exist_cell].x+1, cells[exist_cell].y)
    end
  elseif cells[exist_cell].direction == 2 then
    cells[exist_cell].direction = 4
    if not (cells[exist_cell].y >= y_max) then
      add_temp_cell(cells[exist_cell].x, cells[exist_cell].y+1)
    end
  elseif cells[exist_cell].direction == 4 then
    cells[exist_cell].direction = 1
    if not (cells[exist_cell].x <= 1) then
      add_temp_cell(cells[exist_cell].x-1, cells[exist_cell].y)
    end
  end
end

function collision(exist_cell)
  if cells[exist_cell].direction == 1 then
    cells[exist_cell].direction = 2
  elseif cells[exist_cell].direction == 2 then
    cells[exist_cell].direction = 1
  elseif cells[exist_cell].direction == 3 then
    cells[exist_cell].direction = 4
  elseif cells[exist_cell].direction == 4 then
    cells[exist_cell].direction = 3
  end
end
  

function remove_cell(cell_num)
  local tmp = {}
  for i=1,#cells do
    if i ~= cell_num then
      tmp[#tmp+1] = cells[i]
    end
  end
  cells = tmp
  grid_redraw()
end

function remove_last()
  local cell = #cells
  remove_cell(cell)
end

function remove_all()
  cells = {}
  grid_redraw()
end

function remove_temp_cell(cell_num)
  local tmp = {}
  for i=1,#temp_cells do
    if i ~= cell_num then
      tmp[#tmp+1] = temp_cells[i]
    end
  end
  temp_cells = tmp
  grid_redraw()
end  

function reset_to_initial()
  for i=1,#cells do
    cells[i].x = cells[i].initial.x
    cells[i].y = cells[i].initial.y
  end
  grid_redraw()
end

function grid_redraw()
  g:all(0)
  
  for i=1,#cells do
    g:led(cells[i].x, cells[i].y, cells[i].brightness)
  end
  
  for i=1,#temp_cells do
    g:led(temp_cells[i].x, temp_cells[i].y, 15)
  end
  
  g:refresh()
end

function count()
  cell_logic()
  evaluate_cells()
  grid_redraw()
  play_notes()
end

function cell_logic()
  
  for i=1,#cells do
    cells[i].brightness = 8
    
    if cells[i].x == 1 and cells[i].direction == 1 then
      cells[i].direction = 2
      cells[i].x = cells[i].x + 1
      enqueue_note(cells[i].y)
    elseif cells[i].x == x_max and cells[i].direction == 2 then
      cells[i].direction = 1
      cells[i].x = cells[i].x - 1
      enqueue_note(cells[i].y)
    elseif cells[i].y == 1 and cells[i].direction == 3 then
      cells[i].direction = 4
      cells[i].y = cells[i].y + 1
      enqueue_note(cells[i].x)
    elseif cells[i].y == y_max and cells[i].direction == 4 then
      cells[i].direction = 3
      cells[i].y = cells[i].y - 1
      enqueue_note(cells[i].x)
    elseif cells[i].direction == 4 then
      cells[i].y = cells[i].y + 1
    elseif cells[i].direction == 3 then
      cells[i].y = cells[i].y - 1
    elseif cells[i].direction == 2 then
      cells[i].x = cells[i].x + 1
    elseif cells[i].direction == 1 then
      cells[i].x = cells[i].x - 1
    end
    
    if cells[i].x == x_max and cells[i].direction == 2 then
      cells[i].brightness = 15
    elseif cells[i].x == 1 and cells[i].direction == 1 then
      cells[i].brightness = 15
    elseif cells[i].y == y_max and cells[i].direction == 4 then
      cells[i].brightness = 15
    elseif cells[i].y == 1 and cells[i].direction == 3 then
      cells[i].brightness = 15
    end
      
  end
end

function enc(n,d)
  if n==1 then
    params:delta("bpm", d)
  end
  redraw()
end

function key(n,z)
  if n == 1 and z == 1 then
      alt = true
      redraw()
  elseif n == 1 and z == 0 then
      alt = false
      redraw()
  end
  
  if n == 2 and z == 1 and alt == false then
    reset_to_initial()
  end
  
  if n == 2 and z == 1 and alt == true then
    remove_last()
  end
  
  if n == 3 and z == 1 and alt == false then
    if running == true then
      clk:stop()
      running = false
      redraw()
    else
      clk:start()
      running = true
      redraw()
    end
  end
  
  if alt == true and n == 3 and z == 1 then
    remove_all()
  end
end

function redraw()
  screen.aa(0)
  screen.clear()
  screen.move(0,10)
  screen.level(4)
  if params:get("clock") == 1 then
    screen.text("bpm: " .. params:get("bpm"))
  end
  if alt == false then
    screen.move(100,60)
    screen.level(4)
    if running then
        screen.text("stop")
    else
        screen.text("start")
    end
    screen.move(50,60)
    screen.level(4)
    screen.text("reset")
  else
    screen.move(10,60)
    screen.level(1)
    screen.text("remove:")
    screen.move(100,60)
    screen.level(4)
    screen.text("all")
    screen.move(50,60)
    screen.level(4)
    screen.text("last")
  end
  screen.update()
end

