--[[
  lancet-preview.lua — reshape the article for the typeset preview.

  Two things have to move, because in a two-column layout they must span both
  columns and LaTeX can only do that from the title block or from a starred
  float:

  1. The Summary section becomes the document's `abstract`, so the title-block
     partial can set it full width. Its bold run-in labels (Background, Methods,
     ...) are recoloured to the journal's crimson.

  2. The Research in context section becomes a full-width tinted float, which is
     where and how the journal prints it.

  Only the preview format loads this filter; the submission docx and pdf keep
  the article in its plain, linear form.
--]]

local PANEL_LABELS = {
  ["Background"] = true, ["Methods"] = true, ["Findings"] = true,
  ["Interpretation"] = true, ["Funding"] = true,
}

local function heading_text(blk)
  return pandoc.utils.stringify(blk.content)
end

-- "**Background.**" at the head of a paragraph -> crimson run-in label
local function recolour_labels(blocks)
  return pandoc.walk_block(pandoc.Div(blocks), {
    Strong = function(el)
      local txt = pandoc.utils.stringify(el.content):gsub("[%.:]%s*$", "")
      if PANEL_LABELS[txt] then
        return pandoc.RawInline("latex",
          "\\summarylabel{" .. txt .. "}")
      end
    end,
  }).content
end

-- Collect the blocks belonging to a level-2 section, given its start index.
local function section_range(blocks, i)
  local out, j = {}, i + 1
  while j <= #blocks do
    local b = blocks[j]
    if b.t == "Header" and b.level <= 2 then break end
    out[#out + 1] = b
    j = j + 1
  end
  return out, j
end

-- Inside the panel, level-3 headings are short labels; set them as bold runs
-- rather than sections so they do not enter the document structure from a float.
local function panel_blocks(blocks)
  local out = {}
  for _, b in ipairs(blocks) do
    if b.t == "Header" then
      out[#out + 1] = pandoc.RawBlock("latex",
        "\\panelsubheading{" .. pandoc.utils.stringify(b.content) .. "}")
    elseif b.t == "Div" then
      for _, inner in ipairs(panel_blocks(b.content)) do out[#out + 1] = inner end
    else
      out[#out + 1] = b
    end
  end
  return out
end

function Pandoc(doc)
  local blocks, out = doc.blocks, {}
  local abstract = nil
  local one_column = false
  local i = 1

  while i <= #blocks do
    local b = blocks[i]
    if b.t == "Header" and b.level == 2 then
      local name = heading_text(b)

      if name == "Summary" then
        local body, nxt = section_range(blocks, i)
        abstract = pandoc.Blocks(recolour_labels(body))
        i = nxt
        goto continue

      elseif name == "Tables" or name == "Figures" then
        -- Pandoc renders tables as longtable, which LaTeX refuses to typeset in
        -- two-column mode, and these tables need the full measure regardless.
        -- Drop to one column here: the journal also runs its large tables and
        -- figures full width.
        if not one_column then
          out[#out + 1] = pandoc.RawBlock("latex", "\\onecolumn")
          one_column = true
        end

      elseif name == "Research in context" then
        local body, nxt = section_range(blocks, i)
        local inner = panel_blocks(body)
        out[#out + 1] = pandoc.RawBlock("latex",
          "\\begin{figure*}[t]\\begin{lancetpanelbox}\\panelheading{Research in context}")
        for _, blk in ipairs(inner) do out[#out + 1] = blk end
        out[#out + 1] = pandoc.RawBlock("latex",
          "\\end{lancetpanelbox}\\end{figure*}")
        i = nxt
        goto continue
      end
    end

    out[#out + 1] = b
    i = i + 1
    ::continue::
  end

  doc.blocks = pandoc.Blocks(out)
  if abstract then
    doc.meta.abstract = pandoc.MetaBlocks(abstract)
  end
  return doc
end
