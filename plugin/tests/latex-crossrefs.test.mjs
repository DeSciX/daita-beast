// plugin/scripts/pandoc/latex-crossrefs.lua: a roster license render names it. Each case renders a small LaTeX document
// through pandoc with the filter, as license.sh does, and reads the Markdown it writes. Needs pandoc 3 on PATH.
//   node --test plugin/tests/
import { test } from "node:test";
import assert from "node:assert/strict";
import { spawnSync } from "node:child_process";
import { fileURLToPath } from "node:url";
import { dirname, join } from "node:path";

const FILTER = join(dirname(fileURLToPath(import.meta.url)), "..", "scripts", "pandoc", "latex-crossrefs.lua");

function render(body, title = "\\title{Acme Community License}\n") {
  const tex = `\\documentclass{article}\n${title}\\begin{document}\n\\maketitle\n${body}\n\\end{document}\n`;
  const r = spawnSync("pandoc", ["-f", "latex", "-t", "markdown_strict", "--wrap=none", "-L", FILTER], { input: tex, encoding: "utf8" });
  assert.ok(!r.error, `pandoc did not run: ${r.error}`);
  return r;
}
function ok(body, title) {
  const r = render(body, title);
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

test("every \\ref is plain text: a heading's number, an unnumbered heading's text, an item's path", () => {
  const md = ok(DOC);
  assert.match(md, /See Section 1\.1 and Section Aside\./);
  assert.match(md, /Under Section 2\.2 and Section 2\.2\./);
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
