-- latex-crossrefs.lua: a pandoc filter for a LaTeX document rendered to Markdown (license.sh names it in a roster's
-- license.source.render as "$BEAST_SCRIPTS/pandoc/latex-crossrefs.lua"). It changes labels, references and markup only,
-- never a word of the text:
--   title       the document's \title becomes the one H1 and every heading moves down one level (no \title: unchanged)
--   numbers     each numbered heading (not \section*) carries its number, "2.2 Definitions", so a "Section 2.2" resolves
--   \ref        every \ref becomes plain text: a numbered heading's number (asserted equal to pandoc's own), an
--               unnumbered heading's text, an enumerate item's path of item numbers ("7", "9.4"); a \ref to a label
--               the document does not define, a label defined twice, or another reference type fails the render
--   \label      the anchors \label leaves in the text are dropped (Markdown has no anchor without raw HTML)
--   escapes     a paragraph opening "(a)" is written as is for a Markdown flavour where it is not a list marker
local stringify = pandoc.utils.stringify

local function fail(msg)
  error("latex-crossrefs.lua: " .. msg, 0)
end

-- targets[label] = {kind = "heading" | "item", text = <inlines>}; stray[label]: a \label on neither
local targets, stray = {}, {}
local function define(label, kind, text)
  if targets[label] then fail("the label '" .. label .. "' is defined twice") end
  targets[label] = { kind = kind, text = text }
end

-- labels_in(block): the \label anchors in one block, outside any list nested in it.
local function labels_in(block)
  local found = {}
  block:walk({
    Span = function(s)
      if s.attributes.label then table.insert(found, s.attributes.label) end
    end,
  })
  return found
end

-- scan(blocks, path): define every \label sitting in an enumerate item as the item's path of numbers.
local function scan(blocks, path)
  for _, b in ipairs(blocks) do
    if b.t == "OrderedList" then
      local start = b.listAttributes.start or b.start or 1
      for i, item in ipairs(b.content) do
        local n = tostring(start + i - 1)
        scan(item, path and (path .. "." .. n) or n)
      end
    elseif b.t == "BulletList" then
      for _, item in ipairs(b.content) do scan(item, path) end
    elseif b.t == "Div" or b.t == "BlockQuote" then
      scan(b.content, path)
    elseif b.t ~= "Header" then
      for _, l in ipairs(labels_in(b)) do
        if path then define(l, "item", { pandoc.Str(path) }) else stray[l] = true end
      end
    end
  end
end

local PLAIN_PAREN = { markdown_strict = true, commonmark = true, gfm = true }

function Pandoc(doc)
  -- headings: numbers, and the labels they carry as identifiers
  local count, numbered = {}, {}
  for _, b in ipairs(doc.blocks) do
    if b.t == "Header" then
      if b.classes:includes("unnumbered") then
        if b.identifier ~= "" then define(b.identifier, "heading", b.content:clone()) end
      else
        count[b.level] = (count[b.level] or 0) + 1
        for l = b.level + 1, 10 do count[l] = nil end
        local parts = {}
        for l = 1, b.level do table.insert(parts, tostring(count[l] or 0)) end
        local num = table.concat(parts, ".")
        if b.identifier ~= "" then define(b.identifier, "heading", { pandoc.Str(num) }); numbered[b.identifier] = num end
        b.content:insert(1, pandoc.Space()); b.content:insert(1, pandoc.Str(num))
      end
    end
  end
  scan(doc.blocks, nil)

  doc = doc:walk({
    Link = function(l)
      local rt = l.attributes["reference-type"]
      if not rt then return nil end
      local label = l.attributes.reference
      if rt ~= "ref" then fail("\\" .. rt .. "{" .. tostring(label) .. "} is not a reference this filter resolves") end
      local t = targets[label]
      if not t and stray[label] then fail("\\ref{" .. label .. "}: its \\label sits on neither a heading nor an enumerate item") end
      if not t then fail("\\ref{" .. tostring(label) .. "} names a label the document does not define (add the \\label)") end
      if numbered[label] and stringify(l.content) ~= numbered[label] then
        fail("pandoc numbers \\ref{" .. label .. "} '" .. stringify(l.content) .. "', the headings here say '" .. numbered[label] .. "'")
      end
      return t.text
    end,
    Span = function(s)
      if s.attributes.label then return s.content end
    end,
  })

  if PLAIN_PAREN[FORMAT] then
    local fix = function(b)
      local first = b.content[1]
      if first and first.t == "Str" and first.text:match("^%(%w+%)$") then
        b.content[1] = pandoc.RawInline("markdown", first.text)
        return b
      end
    end
    doc = doc:walk({ Para = fix, Plain = fix })
  end

  local title = doc.meta.title
  if title then
    doc = doc:walk({ Header = function(h) h.level = h.level + 1; return h end })
    local inl = pandoc.utils.type(title) == "Inlines" and title or pandoc.Inlines(stringify(title))
    doc.blocks:insert(1, pandoc.Header(1, inl))
    doc.meta.title = nil
  end
  return doc
end
