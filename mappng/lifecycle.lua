-- Observe native map IO, not picker text or preview changes. Framework detours
-- retain the displaced instructions/registers. Callbacks never unwind into C.
local paths=require('mappng.paths')
local model=require('mappng.links')
local native=require('mappng.native')
local M={}
local state={enabled=false}
function M.initialize(folder)
  if state.installed then
    state.links.open(nil); state.pendingLoad=nil; state.pendingSave=nil
    state.enabled=true; return
  end
  local bindings=native.resolve()
  assert(bindings.hooks,bindings.linkError)
  local store=assert(userdata.interface(),'map-png: user data folder unavailable')
  local function exists(name) return paths.exists(paths.resolve(folder,name)) end
  state.links=model.new(function(data)
    local text=json:encode(data)
    local file=assert(store:open('links.json.tmp','wb'))
    local written,err=file:write(text)
    local closed,closeErr=file:close()
    assert(written and closed,err or closeErr)
    assert(store:rename('links.json.tmp','links.json'))
  end,function(name) return pcall(paths.resolve,folder,name) end,exists)
  -- Earlier versions kept the index beside the PNGs; it is read, never written.
  local legacy=folder..'\\map-png-links.json'
  local file=store:open('links.json','rb')
  local text=file and file:read('*a')
  if file then file:close() end
  local ok,err=pcall(function()
    if not text and paths.exists(legacy) then text=paths.readBinary(legacy,1024*1024) end
    if text then state.links.restore(json:decode(text)) end
  end)
  if not ok then log(WARNING,'ignored invalid link index: '..tostring(err)) end
  local getName=core.exposeCode(bindings.resourceName,1,CallingConvention.THISCALL)
  local function identity()
    local address=getName(bindings.resource)
    if address==0 then return nil end
    local name=core.readString(address,0x3E9):match('^([^%z]*)%z')
    if not name then return nil end
    return paths.mapIdentity(paths.fromGameText(name))
  end
  local callbacks={
    newMap=function() state.pendingLoad=nil; state.pendingSave=nil; state.links.open(nil) end,
    loadBegin=function() state.pendingLoad=identity(); state.links.open(nil) end,
    loadDone=function()
      -- This site follows the section decoding loop, not the allocation/open
      -- failure returns. Header-only preview loading uses a different function.
      state.links.open(state.pendingLoad); state.pendingLoad=nil
    end,
    saveBegin=function()
      local autosave=modules and modules.autosave
      if autosave and autosave.isSavingEditorMap and autosave:isSavingEditorMap() then
        state.pendingSave=nil
      else
        state.pendingSave=identity()
      end
    end,
    saveDone=function()
      -- Normal write/close path, not the allocation/open failure returns.
      if state.pendingSave then state.links.saved(state.pendingSave) end
      state.pendingSave=nil
    end,
  }
  local sizes={newMap=5,loadBegin=7,loadDone=9,saveBegin=7,saveDone=10}
  -- Resolve all sites before installing any hook. The spans contain complete
  -- non-branching instructions: no relative calls/jumps need relocation.
  for _,name in ipairs({'newMap','loadBegin','loadDone','saveBegin','saveDone'}) do
    core.detourCode(function(registers)
      if state.enabled then
        local ok,err=pcall(callbacks[name],registers)
        if not ok then
          -- Detach on uncertain lifecycle state. Never refresh stale map links.
          state.pendingLoad=nil; state.pendingSave=nil
          state.links.open(nil)
          log(WARNING,'link lifecycle '..name..': '..tostring(err))
        end
      end
      return registers
    end,bindings.hooks[name],sizes[name])
  end
  state.installed=true; state.enabled=true
end
function M.link(kind,name)
  if not state.enabled then return end
  local ok,err=pcall(state.links.link,kind,name)
  if not ok then log(WARNING,'PNG imported, but link could not be saved: '..tostring(err)) end
end
function M.available() return state.enabled end
function M.names() return state.enabled and state.links.names() or {} end
function M.refresh()
  assert(state.enabled,'map-png: map link tracking unavailable')
  local names,missing=state.links.forRefresh()
  assert(names, 'map-png: missing linked PNG; link invalidated: '..tostring(missing and (missing.height or missing.terrain)))
  if not next(names) then return false end
  require('mappng.actions').importLinked(names)
  return true
end
function M.disable() state.enabled=false end
return M
