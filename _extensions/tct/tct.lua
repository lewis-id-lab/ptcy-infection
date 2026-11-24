--[[
  tct.lua — checks for Transplantation and Cellular Therapy (TCT).

  1. Word counts. Reports the structured abstract against the journal's
     250–500-word range, and the main-text count (Introduction to the end of
     the Discussion/Conclusions), which the cover letter must state. Reference
     lists, tables, figure legends and declarations are excluded.

  2. Column widths for the nine-column pooled-results table (LaTeX only).
--]]

local opts = { abs_min = 250, abs_max = 500 }

-- Sections counted as main text (lower-cased, punctuation removed).
local BODY = {
  ["introduction"] = true, ["materials and methods"] = true,
  ["results"] = true, ["discussion"] = true, ["conclusions"] = true,
}

local function norm(s)
  return (pandoc.utils.stringify(s):gsub("[^%w%s]", ""):gsub("%s+", " ")
                                   :gsub("^%s*(.-)%s*$", "%1"):lower())
end

function Meta(meta)
  local t = meta.tct
  if t then
    if t["abstract-min-words"] then
      opts.abs_min = tonumber(pandoc.utils.stringify(t["abstract-min-words"]))
    end
    if t["abstract-max-words"] then
      opts.abs_max = tonumber(pandoc.utils.stringify(t["abstract-max-words"]))
    end
  end
  return meta
end

local function count_words(blocks)
  -- Drop what is not counted before counting (the walk is bottom-up).
  local stripped = pandoc.walk_block(pandoc.Div(blocks), {
    Cite = function() return {} end,
    Table = function() return {} end,
    Figure = function() return {} end,
  })
  local n = 0
  pandoc.walk_block(stripped, {
    Str = function(el) if el.text:match("[%w]") then n = n + 1 end end,
  })
  return n
end

function Pandoc(doc)
  local abstract, body, current = {}, {}, nil
  for _, blk in ipairs(doc.blocks) do
    if blk.t == "Header" and blk.level <= 2 then
      current = norm(blk.content)
    else
      if current == "abstract" then
        abstract[#abstract + 1] = blk
      elseif current and BODY[current] then
        body[#body + 1] = blk
      end
    end
  end
  local na, nb = count_words(abstract), count_words(body)
  local flag = ""
  if na < opts.abs_min then flag = string.format("  UNDER by %d", opts.abs_min - na)
  elseif na > opts.abs_max then flag = string.format("  OVER by %d", na - opts.abs_max) end
  io.stderr:write("[tct] word count\n",
    string.format("  Abstract  %5d words (range %d-%d)%s\n", na, opts.abs_min, opts.abs_max, flag),
    string.format("  Main text %5d words (Introduction to Conclusions; state in cover letter)\n", nb))
  return doc
end

local RESULTS_WIDTHS = { 0.18, 0.10, 0.08, 0.05, 0.09, 0.17, 0.07, 0.15, 0.11 }

local function widen_results_table(tbl)
  if not FORMAT:match("latex") then return nil end
  if #tbl.colspecs ~= #RESULTS_WIDTHS then return nil end
  if not pandoc.utils.stringify(tbl.head):match("95%% PI") then return nil end
  for i, w in ipairs(RESULTS_WIDTHS) do
    tbl.colspecs[i] = { tbl.colspecs[i][1], w }
  end
  return tbl
end

return { { Meta = Meta }, { Pandoc = Pandoc }, { Table = widen_results_table } }
