--[[
  tct-titleblock.lua — the Word and PDF manuscript carries an explicit title page
  (authors with degrees, affiliations, corresponding-author contact details and
  short title, as Transplantation and Cellular Therapy asks), so the automatic
  author and date lines under the title are dropped. Only documents containing a
  `.title-page` block are touched (the appendix keeps its author line), and the
  website keeps its author block. Runs after Quarto's own filters, which is where
  the author block is assembled.
--]]
function Pandoc(doc)
  if not (FORMAT:match("docx") or FORMAT:match("latex")) then return nil end
  local has_title_page = false
  doc.blocks:walk({
    Div = function(el)
      if el.classes:includes("title-page") then has_title_page = true end
    end,
  })
  if not has_title_page then return nil end
  doc.meta.author = nil
  doc.meta.authors = nil
  doc.meta["by-author"] = nil
  doc.meta.date = nil
  return doc
end
