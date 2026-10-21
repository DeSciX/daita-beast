// plugin/scripts/pandoc/latex-crossrefs.lua: a roster license render names it. Each case renders a small LaTeX document
// through pandoc with the filter, as license.sh does (the source on stdin, LATEX_CROSSREFS_SOURCE naming its file), and
// reads the Markdown it writes. Needs pandoc 3 on PATH. The real-source case renders the roster's license with license.sh
// and is skipped, saying why, where the roster or its source checkout is absent (CI, the public mirror).
//   node --test plugin/tests/
import { test } from "node:test";
import assert from "node:assert/strict";
import { spawnSync } from "node:child_process";
import { fileURLToPath } from "node:url";
import { dirname, join } from "node:path";
import { existsSync, mkdtempSync, readFileSync, writeFileSync } from "node:fs";
import { tmpdir } from "node:os";

const HERE = dirname(fileURLToPath(import.meta.url));
const FILTER = join(HERE, "..", "scripts", "pandoc", "latex-crossrefs.lua");
const ROOT = join(HERE, "..", "..");
const TMP = mkdtempSync(join(tmpdir(), "latex-crossrefs-"));
let n = 0;

function renderTex(tex, { source = true } = {}) {
  const file = join(TMP, `doc${n++}.tex`);
  writeFileSync(file, tex);
  const env = { ...process.env, LATEX_CROSSREFS_SOURCE: source ? file : "" };
  const r = spawnSync("pandoc", ["-f", "latex", "-t", "markdown_strict", "--wrap=none", "-L", FILTER], { input: tex, encoding: "utf8", env });
  assert.ok(!r.error, `pandoc did not run: ${r.error}`);
  return r;
}
function render(body, title = "\\title{Acme Community License}\n", { cls = "article", preamble = "", source = true } = {}) {
  return renderTex(`\\documentclass{${cls}}\n${preamble}${title}\\begin{document}\n\\maketitle\n${body}\n\\end{document}\n`, { source });
}
function ok(body, title, opts) {
  const r = render(body, title, opts);
  assert.equal(r.status, 0, r.stderr);
  return r.stdout;
}

const DOC = String.raw`
\section{Preamble}
Text.
\subsection*{Aside} \label{sec:aside}
\subsection{Definitions} \label{sec:defs}
\section{Terms} \label{sec:terms}
\begin{enumerate}
  \item \textbf{Use}. See Section \ref{sec:defs} and Section \ref{sec:aside}.
  \item \textbf{Rights} \label{sec:rights}
  \begin{enumerate}
    \item \textbf{General}. Text.
    \item \textbf{License}. \label{sec:license} Under Section \ref{sec:rights}.2 and Section \ref{sec:license}.
  \end{enumerate}
\end{enumerate}
(a) \textbf{Notice}. Given in Section \ref{sec:terms}.
`;

test("the \\title is the one H1 and the headings move down a level", () => {
  const md = ok(DOC);
  assert.deepEqual(md.split("\n").filter((l) => l.startsWith("#")), [
    "# Acme Community License",
    "## 1 Preamble",
    "### Aside",
    "### 1.1 Definitions",
    "## 2 Terms",
  ]);
});

test("no \\title: the headings stay where they are", () => {
  const md = ok(DOC, "");
  assert.match(md, /^# 1 Preamble$/m);
  assert.doesNotMatch(md, /^# Acme/m);
});

test("every \\ref is plain text, as LaTeX prints it: a heading's number, a starred heading's enclosing number, an item's \\p@enum\\theenum", () => {
  const md = ok(DOC);
  assert.match(md, /See Section 1\.1 and Section 1\./);
  assert.match(md, /Under Section 2\.2 and Section 2b\./);
  assert.match(md, /Given in Section 2\.$/m);
  assert.doesNotMatch(md, /\[sec:|\]\(#|<a |<span|\{#|\\/);
});

test("a paragraph opening (a) is written without an escape", () => {
  assert.match(ok(DOC), /^\(a\) \*\*Notice\*\*/m);
});

test("a \\ref to an undefined label fails the render, naming it", () => {
  const r = render(String.raw`\section{One} See Section \ref{sec:missing}.`);
  assert.notEqual(r.status, 0);
  assert.match(r.stderr, /\\ref\{sec:missing\} names a label the document does not define/);
});

test("a \\ref to a label on neither a heading nor an item fails the render", () => {
  const r = render(String.raw`\section{One} Text \label{sec:stray}. See \ref{sec:stray}.`);
  assert.notEqual(r.status, 0);
  assert.match(r.stderr, /\\ref\{sec:stray\}: its \\label sits on neither a heading nor an enumerate item/);
});

test("a label defined twice fails the render", () => {
  const r = render(String.raw`\section{One} \label{sec:x} \section{Two} \label{sec:x}`);
  assert.notEqual(r.status, 0);
  assert.match(r.stderr, /the label 'sec:x' is defined twice/);
});

// The DCMA's own numbering (its preamble, lines 46-48), on a skeleton of its structure. The letters are the ones latexmk's
// PDF prints for the real source (its .aux: sec:dcsl A, sec:preexisting C, sec:dpaas_definitions D, an item 4a).
const ROMAN_PREAMBLE = String.raw`\renewcommand\thesection{\Roman{section}}
\renewcommand\thesubsection{\Alph{subsection}}
\renewcommand\thesubsubsection{\roman{subsubsection}}
`;
const SKELETON = String.raw`
\section{Preamble} Text.
\section{Membership}
\section{Community Licenses}
\subsection{DCSL} \label{sec:dcsl}
\subsubsection{Terms}
\subsection{Unauthorized Use}
\subsection{Pre-existing Material} \label{sec:preexisting}
Clause 7 of the DCSL (Section~\ref{sec:dcsl}).
\subsection{DPLA} \label{sec:dpaas}
\begin{enumerate}
  \item One. \item Two. \item Three.
  \item \textbf{Your Responsibilities} \label{sec:resp}
  \begin{enumerate}
    \item \textbf{Your Content}. \label{sec:content} See Section \ref{sec:resp}.2.
  \end{enumerate}
\end{enumerate}
\subsubsection*{Definitions} \label{sec:dpaas_definitions}
See Sections \ref{sec:preexisting}, \ref{sec:content} and \ref{sec:dpaas_definitions}.
`;

test("the source's \\the<level> formats number the headings and the references (Roman, Alph, roman)", () => {
  const md = ok(SKELETON, undefined, { preamble: ROMAN_PREAMBLE });
  assert.deepEqual(md.split("\n").filter((l) => l.startsWith("#")), [
    "# Acme Community License",
    "## I Preamble",
    "## II Membership",
    "## III Community Licenses",
    "### A DCSL",
    "#### i Terms",
    "### B Unauthorized Use",
    "### C Pre-existing Material",
    "### D DPLA",
    "#### Definitions",
  ]);
  assert.match(md, /Clause 7 of the DCSL \(Section\sA\)\./);
  assert.match(md, /See Section 4\.2\./);
  assert.match(md, /See Sections C, 4a and D\./);
});

test("a source that redefines \\thesubsection as \\arabic{section}.\\arabic{subsection} still prints 3.1", () => {
  const md = ok(String.raw`\section{A} \section{B} \section{C} \subsection{X} \label{sec:x} See Section \ref{sec:x}.`, undefined,
    { preamble: String.raw`\renewcommand{\thesubsection}{\arabic{section}.\arabic{subsection}}` + "\n" });
  assert.match(md, /^### 3\.1 X$/m);
  assert.match(md, /See Section 3\.1\./);
});

test("the report class: chapters number sections, and a subsubsection is past secnumdepth", () => {
  const md = ok(String.raw`\chapter{One} \chapter{Two} \section{S} \label{sec:s} \subsection{T} \subsubsection{U} \label{sec:u} See \ref{sec:s} and \ref{sec:u}.`,
    undefined, { cls: "report" });
  assert.match(md, /^### 2\.1 S$/m);
  assert.match(md, /^#### 2\.1\.1 T$/m);
  assert.match(md, /^##### U$/m);
  assert.match(md, /See 2\.1 and 2\.1\.1\./);
});

test("an unsupported command in a \\the<level> format fails the render, naming it", () => {
  const r = render(String.raw`\section{One}`, undefined, { preamble: String.raw`\renewcommand\thesection{\fnsymbol{section}}` + "\n" });
  assert.notEqual(r.status, 0);
  assert.match(r.stderr, /\\thesection uses \\fnsymbol, a command this filter does not print/);
});

test("a counter changed by hand, \\appendix, an unmodelled class or an optioned enumerate fails the render, naming it", () => {
  let r = render(String.raw`\setcounter{section}{4} \section{One}`);
  assert.notEqual(r.status, 0); assert.match(r.stderr, /\\setcounter\{section\}/);
  r = render(String.raw`\section{One} \appendix \section{Two}`);
  assert.notEqual(r.status, 0); assert.match(r.stderr, /\\appendix/);
  r = render(String.raw`\section{One}`, undefined, { cls: "book" });
  assert.notEqual(r.status, 0); assert.match(r.stderr, /\\documentclass\{book\}/);
  r = render(String.raw`\section{One} \begin{enumerate}[label=\alph*)] \item A \label{i:a} \end{enumerate} See \ref{i:a}.`, undefined,
    { preamble: "\\usepackage{enumitem}\n" });
  assert.notEqual(r.status, 0); assert.match(r.stderr, /\\begin\{enumerate\}\[\.\.\.\]/);
});

test("without its source the filter fails the render, naming LATEX_CROSSREFS_SOURCE", () => {
  const r = render(String.raw`\section{One}`, undefined, { source: false });
  assert.notEqual(r.status, 0);
  assert.match(r.stderr, /LATEX_CROSSREFS_SOURCE/);
});

test("the roster's own license (the real DCMA source, through license.sh render) prints the PDF's letters", (t) => {
  const roster = join(ROOT, ".beast", "roster.json");
  if (!existsSync(roster)) return t.skip(`no roster at ${roster} (the public mirror carries none)`);
  const lic = JSON.parse(readFileSync(roster, "utf8")).license;
  if (!lic?.source?.checkout) return t.skip("the roster's license names no source checkout");
  if (!existsSync(join(lic.source.checkout, lic.source.path))) return t.skip(`the license source checkout is not on this machine`);
  const out = join(TMP, "LICENSE.md");
  const r = spawnSync("bash", [join(HERE, "..", "scripts", "license.sh"), "render", "-o", out], { cwd: ROOT, encoding: "utf8" });
  assert.equal(r.status, 0, r.stderr + r.stdout);
  const md = readFileSync(out, "utf8");
  assert.match(md, /^### A DeSciX Community Source Code License \(DCSL\)$/m);
  assert.match(md, /^### C Pre-existing Material Under Separate Licenses/m);
  assert.match(md, /Clause 7 of the DCSL \(Section\sA\)/);
  assert.match(md, /Section\sC \(Pre-existing Material Under Separate Licenses\)/);
  assert.doesNotMatch(md, /Section\s3\.[13]\b/);
});
