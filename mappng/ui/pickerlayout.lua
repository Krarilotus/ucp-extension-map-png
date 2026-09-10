-- One geometry contract for native list, scrollbar, clipping and tests.
local M = { width = 700, height = 440, headerBottom = 72,
  listX = 310, listY = 82, listWidth = 340, rowHeight = 20, pageSize = 16,
  scrollWidth = 20 }
M.rowsY = M.listY + M.rowHeight
M.bottom = M.rowsY + M.pageSize * M.rowHeight
M.scrollX = M.listX + M.listWidth
M.trackY = M.rowsY + M.rowHeight
M.trackHeight = (M.pageSize - 2) * M.rowHeight
return M
