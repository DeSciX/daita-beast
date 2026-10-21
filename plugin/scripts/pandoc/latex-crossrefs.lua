-- latex-crossrefs.lua: a pandoc filter for a LaTeX document rendered to Markdown (license.sh names it in a roster's
-- license.source.render as "$BEAST_SCRIPTS/pandoc/latex-crossrefs.lua"). It changes labels, references and markup only,
-- never a word of the text, and prints every number as the PDF prints it:
--   source      the filter reads the LaTeX source itself: the file LATEX_CROSSREFS_SOURCE names (license.sh render sets it
--               to the source it pipes to pandoc), else pandoc's one input file; neither fails the render. Its
--               \documentclass (article or report) gives the class's \the<counter> formats, secnumdepth and counter
--               resets; its preamble's \renewcommand\the<counter>{...} replaces a format. A format is built from \arabic,
--               \Roman, \roman, \Alph, \alph, \the<counter> and plain characters; any other command, or a command that
--               changes the counters (\setcounter, \appendix, \part, \p@<counter>, \setlist, ...), fails the render naming it
--   title       the document's \title becomes the one H1 and every heading moves down one level (no \title: unchanged)
--   numbers     each numbered heading carries its number as \the<level> prints it ("III Terms", "A Definitions"); a starred
--               heading, or one deeper than secnumdepth, carries none and steps no counter
--   \ref        every \ref becomes plain text, the text LaTeX writes for it: a numbered heading's \the<level>; an enumerate
--               item's \p@enum<n>\theenum<n> ("7", "4a"); a starred heading's label, the number in force where it sits (the
--               last numbered heading's). A \ref to a label the document does not define, a label defined twice, a label
--               on neither a heading nor an enumerate item, or another reference type fails the render
--   \label      the anchors \label leaves in the text are dropped (Markdown has no anchor without raw HTML)
--   escapes     a paragraph opening "(a)" is written as is for a Markdown flavour where it is not a list marker
local stringify = pandoc.utils.stringify

local function fail(msg)
  error("latex-crossrefs.lua: " .. msg, 0)
end

-- The LaTeX classes this filter models: each counter's \the format, its depth, what resets it, and secnumdepth.
local ENUM_P = { enumi = "", enumii = "\\theenumi", enumiii = "\\theenumi(\\theenumii)", enumiv = "\\theenumi(\\theenumii)\\theenumiii" }
local CLASSES = {
  article = {
    secnumdepth = 3,
    the = {
      section = "\\arabic{section}", subsection = "\\thesection.\\arabic{subsection}",
      subsubsection = "\\thesubsection.\\arabic{subsubsection}", paragraph = "\\thesubsubsection.\\arabic{paragraph}",
      subparagraph = "\\theparagraph.\\arabic{subparagraph}",
      enumi = "\\arabic{enumi}", enumii = "\\alph{enumii}", enumiii = "\\roman{enumiii}", enumiv = "\\Alph{enumiv}",
    },
    resets = { section = { "subsection" }, subsection = { "subsubsection" }, subsubsection = { "paragraph" }, paragraph = { "subparagraph" } },
  },
  report = {
    secnumdepth = 2,
    the = {
      chapter = "\\arabic{chapter}", section = "\\thechapter.\\arabic{section}", subsection = "\\thesection.\\arabic{subsection}",
      subsubsection = "\\thesubsection.\\arabic{subsubsection}", paragraph = "\\thesubsubsection.\\arabic{paragraph}",
      subparagraph = "\\theparagraph.\\arabic{subparagraph}",
      enumi = "\\arabic{enumi}", enumii = "\\alph{enumii}", enumiii = "\\roman{enumiii}", enumiv = "\\Alph{enumiv}",
    },
    resets = { chapter = { "section" }, section = { "subsection" }, subsection = { "subsubsection" }, subsubsection = { "paragraph" }, paragraph = { "subparagraph" } },
  },
}
local DEPTH = { chapter = 0, section = 1, subsection = 2, subsubsection = 3, paragraph = 4, subparagraph = 5 }
local ENUMS = { "enumi", "enumii", "enumiii", "enumiv" }
local COUNTER_CMDS = { "setcounter", "addtocounter", "stepcounter", "refstepcounter", "counterwithin", "counterwithout", "numberwithin", "@addtoreset" }

-- read_source(): the LaTeX source text, comments stripped.
local function read_source()
  local path = os.getenv("LATEX_CROSSREFS_SOURCE")
  if path == "" then path = nil end
  if not path then
    local files = PANDOC_STATE.input_files or {}
    if #files == 1 and files[1] ~= "-" then path = files[1] end
  end
  if not path then
    fail("the LaTeX source is unknown: set LATEX_CROSSREFS_SOURCE to its file (license.sh render does), or give pandoc the file; the filter reads its \\documentclass and \\the<counter> definitions there")
  end
  local f = io.open(path, "r")
  if not f then fail("cannot read the LaTeX source " .. path .. " (LATEX_CROSSREFS_SOURCE)") end
  local text = f:read("a"); f:close()
  local out = {}
  for line in (text .. "\n"):gmatch("(.-)\n") do
    local i = 1
    while true do
      local p = line:find("%", i, true)
      if not p then break end
      if p > 1 and line:sub(p - 1, p - 1) == "\\" then i = p + 1 else line = line:sub(1, p - 1); break end
    end
    table.insert(out, line)
  end
  return table.concat(out, "\n"), path
end

-- skip_ws(s, i): the index of the first non-space character at or after i.
local function skip_ws(s, i) return (s:find("[^%s]", i)) or (#s + 1) end

-- braced(s, i): the text of the balanced {...} group opening at s[i], and the index after it.
local function braced(s, i, what)
  if s:sub(i, i) ~= "{" then fail(what .. ": expected '{' in the source") end
  local depth = 0
  for j = i, #s do
    local c = s:sub(j, j)
    if c == "\\" then
      -- an escaped character is never a brace
    elseif c == "{" and s:sub(j - 1, j - 1) ~= "\\" then depth = depth + 1
    elseif c == "}" and s:sub(j - 1, j - 1) ~= "\\" then
      depth = depth - 1
      if depth == 0 then return s:sub(i + 1, j - 1), j + 1 end
    end
  end
  fail(what .. ": an unbalanced '{' in the source")
end

-- compile(counter, text): a format's tokens; any command outside the supported set fails, naming it.
local NUMBERERS = { arabic = true, Roman = true, roman = true, Alph = true, alph = true }
local function compile(counter, text)
  local toks, i = {}, 1
  while i <= #text do
    local c = text:sub(i, i)
    if c == "\\" then
      local name = text:match("^[%a@]+", i + 1) or text:sub(i + 1, i + 1)
      local j = i + 1 + #name
      if NUMBERERS[name] then
        local arg; arg, j = braced(text, skip_ws(text, j), "\\" .. name .. " in \\the" .. counter)
        table.insert(toks, { fn = name, counter = arg })
      elseif name:match("^the%a+$") then
        table.insert(toks, { the = name:sub(4) })
      elseif name:match("^p@") then
        table.insert(toks, { p = name:sub(3) })
      else
        fail("\\the" .. counter .. " uses \\" .. name .. ", a command this filter does not print (it prints \\arabic, \\Roman, \\roman, \\Alph, \\alph and \\the<counter>)")
      end
      i = j
    elseif c == "{" or c == "}" then
      fail("\\the" .. counter .. " holds a brace group '" .. text .. "', which this filter does not print")
    else
      table.insert(toks, { lit = c }); i = i + 1
    end
  end
  return toks
end

local ROMAN = { { 1000, "m" }, { 900, "cm" }, { 500, "d" }, { 400, "cd" }, { 100, "c" }, { 90, "xc" }, { 50, "l" }, { 40, "xl" }, { 10, "x" }, { 9, "ix" }, { 5, "v" }, { 4, "iv" }, { 1, "i" } }
local function roman(n)
  local s = ""
  for _, p in ipairs(ROMAN) do while n >= p[1] do s = s .. p[2]; n = n - p[1] end end
  return s
end
local function alph(n, counter)
  if n <= 0 then return "" end
  if n > 26 then fail("the counter " .. counter .. " is " .. n .. ": \\alph and \\Alph stop at 26 (LaTeX: Counter too large)") end
  return string.char(96 + n)
end
local NUMBER = {
  arabic = function(n) return tostring(n) end,
  roman = function(n) return n > 0 and roman(n) or "" end,
  Roman = function(n) return n > 0 and roman(n):upper() or "" end,
  alph = function(n, c) return alph(n, c) end,
  Alph = function(n, c) return alph(n, c):upper() end,
}

-- The model, built from the source in Pandoc() below.
local M = { the = {}, p = {}, value = {}, resets = {}, secnumdepth = nil }

local function expand(toks, depth)
  if depth > 20 then fail("the \\the<counter> definitions refer to each other in a loop") end
  local out = {}
  for _, t in ipairs(toks) do
    if t.lit then table.insert(out, t.lit)
    elseif t.fn then
      local v = M.value[t.counter]
      if v == nil then fail("\\" .. t.fn .. "{" .. t.counter .. "}: " .. t.counter .. " is not a counter this filter models") end
      table.insert(out, NUMBER[t.fn](v, t.counter))
    elseif t.the then
      if not M.the[t.the] then fail("\\the" .. t.the .. ": " .. t.the .. " is not a counter this filter models") end
      table.insert(out, expand(M.the[t.the], depth + 1))
    else
      if M.p[t.p] == nil then fail("\\p@" .. t.p .. ": " .. t.p .. " is not a counter this filter models") end
      table.insert(out, expand(M.p[t.p], depth + 1))
    end
  end
  return table.concat(out)
end
local function ref_text(counter) return expand(M.p[counter], 0) .. expand(M.the[counter], 0) end

local function step(counter)
  M.value[counter] = M.value[counter] + 1
  local function reset(c)
    for _, r in ipairs(M.resets[c] or {}) do M.value[r] = 0; reset(r) end
  end
  reset(counter)
end

-- model(src): the class, its formats overridden by the preamble, and the body's sectioning commands, enumerates and
-- labels, in source order.
local function model(src)
  local b = src:find("\\begin{document}", 1, true)
  if not b then fail("the LaTeX source has no \\begin{document}") end
  local pre, body = src:sub(1, b - 1), src:sub(b)
  local cls = pre:match("\\documentclass%s*%b[]%s*{(%w+)}") or pre:match("\\documentclass%s*{(%w+)}")
  if not cls then fail("the LaTeX source has no \\documentclass") end
  local C = CLASSES[cls]
  if not C then fail("\\documentclass{" .. cls .. "}: this filter models the article and report classes only") end
  M.secnumdepth, M.resets = C.secnumdepth, C.resets
  for k, v in pairs(C.the) do M.the[k] = compile(k, v); M.value[k] = 0 end
  for k, v in pairs(ENUM_P) do M.p[k] = compile("p@" .. k, v) end
  for k in pairs(DEPTH) do if C.the[k] then M.p[k] = {} end end

  local function modeled(name) return M.the[name] ~= nil or name == "secnumdepth" end
  -- the commands that change counters or their formats, anywhere in the source
  for _, cmd in ipairs(COUNTER_CMDS) do
    local pat = "\\" .. cmd:gsub("@", "%%@") .. "%*?%s*{([%a@]+)}"
    for arg in src:gmatch(pat) do
      if modeled(arg) then fail("\\" .. cmd .. "{" .. arg .. "}: this filter does not follow a counter changed by hand") end
    end
  end
  if src:find("\\appendix%f[^%a]") then fail("\\appendix: this filter does not follow the numbering it switches") end
  for name in src:gmatch("\\[dgex]?def%s*\\([%a@]+)") do
    if name:match("^the%a+$") and modeled(name:sub(4)) or name:match("^p@") then fail("\\def\\" .. name .. ": define it with \\renewcommand in the preamble") end
  end
  for name in src:gmatch("\\let%s*\\([%a@]+)") do
    if name:match("^the%a+$") and modeled(name:sub(4)) or name:match("^p@") then fail("\\let\\" .. name .. ": define it with \\renewcommand in the preamble") end
  end
  -- \renewcommand\the<counter>{...} in the preamble: the format; in the body it would change mid-document
  local function renews(text, where)
    local i = 1
    while true do
      local s, e = text:find("\\renewcommand%*?", i)
      if not s then break end
      local j, name = skip_ws(text, e + 1), nil
      if text:sub(j, j) == "{" then
        local inner; inner, j = braced(text, j, "\\renewcommand")
        name = inner:match("^%s*\\([%a@]+)%s*$")
      else
        name = text:match("^\\([%a@]+)", j); if name then j = j + 1 + #name end
      end
      i = j
      if name and name:match("^p@") then fail("\\renewcommand\\" .. name .. ": this filter prints the class's \\p@<counter>") end
      if name and name:match("^the%a+$") and modeled(name:sub(4)) then
        local c = name:sub(4)
        if where == "body" then fail("\\renewcommand\\the" .. c .. " after \\begin{document}: define it in the preamble") end
        j = skip_ws(text, j)
        if text:sub(j, j) == "[" then fail("\\renewcommand\\the" .. c .. " takes arguments: a format takes none") end
        local fmt; fmt, i = braced(text, j, "\\renewcommand\\the" .. c)
        M.the[c] = compile(c, fmt)
      end
    end
  end
  renews(pre, "preamble"); renews(body, "body")

  -- the body's sectioning commands, enumerates and labels, in order
  local heads, enums, labels = {}, {}, {}
  for name, star in body:gmatch("\\(%a+)(%*?)%s*[%[{]") do
    if name == "part" then fail("\\part: this filter does not number parts") end
    if DEPTH[name] then
      if not C.the[name] then fail("\\" .. name .. " is not a sectioning command of the " .. cls .. " class") end
      table.insert(heads, { name = name, star = star == "*" })
    end
  end
  for after in body:gmatch("\\begin%s*{enumerate}()") do
    table.insert(enums, { options = body:sub(skip_ws(body, after), skip_ws(body, after)) == "[" })
  end
  for l in body:gmatch("\\label%s*{([^}]*)}") do
    if labels[l] then fail("the label '" .. l .. "' is defined twice") end
    labels[l] = true
  end
  return heads, enums, labels, src:find("\\setlist%f[^%a]") ~= nil
end

local PLAIN_PAREN = { markdown_strict = true, commonmark = true, gfm = true }

function Pandoc(doc)
  local src, srcpath = read_source()
  local heads, enums, srclabels, setlist = model(src)

  -- targets[label] = <ref text>; stray[label]: a \label on neither a heading nor an enumerate item
  local targets, stray = {}, {}
  local function define(label, text)
    if not srclabels[label] then fail("the document carries the label '" .. label .. "', which " .. srcpath .. " does not: is it the source pandoc read?") end
    if targets[label] or stray[label] then fail("the label '" .. label .. "' is defined twice") end
    targets[label] = text
  end
  local function labels_in(block)
    local found = {}
    block:walk({ Span = function(s) if s.attributes.label then table.insert(found, s.attributes.label) end end })
    return found
  end

  -- every list on the path to a label, in document order, zipped with the source's \begin{enumerate}
  local nlists = 0
  local function scan(blocks, trail, optioned)
    for _, b in ipairs(blocks) do
      if b.t == "OrderedList" then
        nlists = nlists + 1
        local src_list = enums[nlists]
        if not src_list then fail("pandoc reads more enumerate lists than " .. srcpath .. " opens") end
        local depth = #trail + 1
        if depth > 4 then fail("an enumerate nested " .. depth .. " deep (LaTeX: Too deeply nested)") end
        local counter = ENUMS[depth]
        local start = b.listAttributes.start or b.start or 1
        for i, item in ipairs(b.content) do
          M.value[counter] = start + i - 1
          local p = { table.unpack(trail) }; table.insert(p, counter)
          scan(item, p, optioned or src_list.options)
        end
        M.value[counter] = 0
      elseif b.t == "BulletList" then
        for _, item in ipairs(b.content) do scan(item, trail, optioned) end
      elseif b.t == "Div" or b.t == "BlockQuote" then
        scan(b.content, trail, optioned)
      elseif b.t == "Header" then
        fail("a heading inside a list or a block: this filter numbers top-level headings only")
      else
        for _, l in ipairs(labels_in(b)) do
          if #trail == 0 then
            if not srclabels[l] then fail("the document carries the label '" .. l .. "', which " .. srcpath .. " does not") end
            stray[l] = true
          elseif optioned then
            fail("\\label{" .. l .. "} sits in an enumerate given options (\\begin{enumerate}[...]): this filter does not print enumitem's labels")
          elseif setlist then
            fail("\\label{" .. l .. "} sits in an enumerate and the source uses \\setlist: this filter does not print enumitem's labels")
          else
            define(l, ref_text(trail[#trail]))
          end
        end
      end
    end
  end

  -- headings: zipped with the source's sectioning commands; numbers, and the labels they carry
  local nheads, current = 0, nil
  local total = 0
  doc:walk({ Header = function() total = total + 1 end })
  if total ~= #heads then fail(srcpath .. " has " .. #heads .. " sectioning commands, pandoc reads " .. total .. " headings") end
  for _, b in ipairs(doc.blocks) do
    if b.t == "Header" then
      nheads = nheads + 1
      local h = heads[nheads]
      if h.star ~= b.classes:includes("unnumbered") then
        fail("heading " .. nheads .. " ('" .. stringify(b.content) .. "'): the source and pandoc disagree on whether it is starred")
      end
      local label = srclabels[b.identifier] and b.identifier or nil
      if h.star or DEPTH[h.name] > M.secnumdepth then
        if label then
          if not current then fail("\\ref{" .. label .. "}: its unnumbered heading follows no numbered one, so LaTeX prints nothing for it") end
          define(label, current)
        end
      else
        step(h.name)
        local num = ref_text(h.name)
        current = num
        if label then define(label, num) end
        b.content:insert(1, pandoc.Space()); b.content:insert(1, pandoc.Str(expand(M.the[h.name], 0)))
      end
    else
      scan({ b }, {}, false)
    end
  end
  local walked = 0
  doc:walk({ OrderedList = function() walked = walked + 1 end })
  if nlists ~= #enums or walked ~= #enums then
    fail(srcpath .. " opens " .. #enums .. " enumerate lists, pandoc reads " .. walked .. " (" .. nlists .. " outside tables and the like)")
  end
  for l in pairs(srclabels) do
    if not targets[l] and not stray[l] then fail("\\label{" .. l .. "} in " .. srcpath .. " is not in the document pandoc read") end
  end

  doc = doc:walk({
    Link = function(l)
      local rt = l.attributes["reference-type"]
      if not rt then return nil end
      local label = l.attributes.reference
      if rt ~= "ref" then fail("\\" .. rt .. "{" .. tostring(label) .. "} is not a reference this filter resolves") end
      local t = targets[label]
      if not t and stray[label] then fail("\\ref{" .. label .. "}: its \\label sits on neither a heading nor an enumerate item") end
      if not t then fail("\\ref{" .. tostring(label) .. "} names a label the document does not define (add the \\label)") end
      return pandoc.Str(t)
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
