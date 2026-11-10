--[[
  lancet-haematology.lua — house-style helpers for the Lancet family.

  1. Word counts.  Reports the Summary and the main-body word counts against
     the limits in the format metadata, so an over-length draft is caught at
     render time rather than at submission.  Reference lists, tables, figure
     legends and the panel are excluded, matching how the journal counts.

  2. Middle-dot decimals (opt-in).  The Lancet sets decimal points as a middle
     dot: 0·79, not 0.79.  Enabled with `lancet: {middot: true}`.  Only a digit
     .digit run is touched, and a run with two or more dots (a software version
     such as 2.23.0) is left alone.
--]]

local opts = { middot = false, summary_words = 300, body_words = 4500 }

-- Sections excluded from the body word count (lower-cased, no punctuation).
local NOT_BODY = {
  ["summary"] = true, ["abstract"] = true, ["research in context"] = true,
  ["references"] = true, ["contributors"] = true,
  ["declaration of interests"] = true, ["acknowledgments"] = true,
  ["acknowledgements"] = true, ["data sharing"] = true,
  ["use of artificial intelligence"] = true,
  -- tables and figure legends do not count towards the journal limit
  ["tables"] = true, ["figures"] = true,
}

local function norm(s)
  return (pandoc.utils.stringify(s):gsub("[^%w%s]", ""):gsub("%s+", " ")
                                   :gsub("^%s*(.-)%s*$", "%1"):lower())
end

function Meta(meta)
  local l = meta.lancet
  if l then
    if l.middot ~= nil then opts.middot = l.middot == true end
    if l["summary-words"] then
      opts.summary_words = tonumber(pandoc.utils.stringify(l["summary-words"]))
    end
    if l["body-words"] then
      opts.body_words = tonumber(pandoc.utils.stringify(l["body-words"]))
    end
  end
  return meta
end

-- ── 1. middle-dot decimals ────────────────────────────────────────────────
local function to_middot(s)
  -- A software version is three or more dot-separated numbers with nothing
  -- between them (2.23.0, 1.10.18); leave those alone. A parenthesised interval
  -- such as (0.73-0.85) also holds two decimals but is separated by a dash, so
  -- it must still be converted -- match the version shape itself, not a count.
  if s:match("%d+%.%d+%.%d") then return s end
  return (s:gsub("(%d)%.(%d)", "%1\u{00B7}%2"))
end

-- ── 2. word counting ──────────────────────────────────────────────────────
local function count_words(blocks)
  -- Remove what the journal does not count *before* counting: a single walk
  -- is bottom-up, so Str tokens inside these elements would already have been
  -- counted by the time the element itself is dropped. Citation markers are
  -- not words (their keys would otherwise count, one per reference).
  local stripped = pandoc.walk_block(pandoc.Div(blocks), {
    Cite = function() return {} end,
    Table = function() return {} end,
    Figure = function() return {} end,
  })
  local n = 0
  pandoc.walk_block(stripped, {
    Str = function(el)
      -- a token counts as a word if it contains at least one letter or digit
      if el.text:match("[%w]") then n = n + 1 end
    end,
  })
  return n
end

function Pandoc(doc)
  -- middle dots first, so counting sees final text
  if opts.middot then
    doc.blocks = doc.blocks:walk({
      Str = function(el)
        if el.text:match("%d%.%d") then return pandoc.Str(to_middot(el.text)) end
      end,
      -- never rewrite code, links or raw output
      Code = function(el) return el end,
      CodeBlock = function(el) return el end,
      RawInline = function(el) return el end,
      RawBlock = function(el) return el end,
    })
  end

  -- split the document at level-1/2 headings and tally
  local summary, body, current = {}, {}, nil
  for _, blk in ipairs(doc.blocks) do
    if blk.t == "Header" and blk.level <= 2 then
      current = norm(blk.content)
    else
      local bucket = nil
      if current == "summary" or current == "abstract" then
        bucket = summary
      elseif current and not NOT_BODY[current] then
        bucket = body
      end
      if bucket then bucket[#bucket + 1] = blk end
    end
  end

  local ns, nb = count_words(summary), count_words(body)
  local function line(label, n, limit)
    local flag = (limit and n > limit) and
                 string.format("  OVER by %d", n - limit) or ""
    return string.format("  %-9s %5d words (limit %d)%s", label, n, limit or 0, flag)
  end
  io.stderr:write("[lancet-haematology] word count\n",
                  line("Summary", ns, opts.summary_words), "\n",
                  line("Body", nb, opts.body_words), "\n")
  return doc
end

-- ── 3. column widths for the pooled-results table (LaTeX only) ────────────
-- Pandoc gives the nine columns of table 2 equal widths, so in the PDF the
-- prediction-interval column ran into the GRADE column. Word and HTML are
-- left alone.
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

-- Meta must run before Pandoc
return { { Meta = Meta }, { Pandoc = Pandoc }, { Table = widen_results_table } }
