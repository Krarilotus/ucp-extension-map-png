-- Observe native map IO, not picker text or preview changes. Framework detours
-- retain the displaced instructions/registers. Callbacks never unwind into C.
local paths=require('mappng.paths')
local model=require('mappng.links')
local native=require('mappng.native')
local M={}
local state={enabled=false}
function M.initialize(ffi,folder)
  if state.installed then
    state.links.open(nil); state.pendingLoad=nil; state.pendingSave=nil
    state.enabled=true; return
  end
  local bindings=native.resolve()
  local sidecar=folder..'\\map-png-links.json'
  local function exists(name) return paths.exists(paths.resolve(folder,name)) end
  state.links=model.new(function(data)
    paths.writeAtomic(sidecar,json:encode(data))
  end,function(name) return pcall(paths.resolve,folder,name) end,exists)
  if paths.exists(sidecar) then
    local ok,err=pcall(function() state.links.restore(json:decode(paths.readBinary(sidecar,1024*1024))) end)
    if not ok then log(WARNING,'map-png: ignored invalid link sidecar: '..tostring(err)) end
  end
  local getName=ffi.cast('char * (__thiscall *)(void *)',bindings.resourceName)
  local function identity()
    local name=ffi.string(getName(ffi.cast('void *',bindings.resource)))
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
    saveBegin=function() state.pendingSave=identity() end,
    saveDone=function()
      -- Normal write/close path, not the allocation/open failure returns.
      if state.pendingSave then state.links.saved(state.pendingSave) end
      state.pendingSave=nil
    end,
  }
  local sizes={newMap=5,loadBegin=5,loadDone=9,saveBegin=5,saveDone=10}
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
          log(WARNING,'map-png: link lifecycle '..name..': '..tostring(err))
        end
      end
      return registers
    end,bindings.hooks[name],sizes[name])
  end
  state.installed=true; state.enabled=true
end
function M.link(kind,name)
  local ok,err=pcall(state.links.link,kind,name)
  if not ok then log(WARNING,'map-png: PNG imported, but link could not be saved: '..tostring(err)) end
end
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
