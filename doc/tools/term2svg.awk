# term2svg.awk - render captured terminal output as a standalone SVG.
#
# Used to produce the images in README.md from real ncdu output, so the
# documentation cannot drift from what the tool actually draws.
#
#   tmux capture-pane -p -t session | awk -v title=... -f doc/tools/term2svg.awk
#
# Variables: title, cols, fontsize, pad, radius.
#
# Every run of text is placed at an exact column and given a textLength, so the
# columns line up whatever monospace face the viewer happens to have.

function xml(s) {
  gsub(/&/, "\\&amp;", s)
  gsub(/</, "\\&lt;", s)
  gsub(/>/, "\\&gt;", s)
  gsub(/"/, "\\&quot;", s)
  return s
}

function span(text, col, row, class,   x, y, n) {
  n = length(text)
  if (n == 0 || text ~ /^ +$/) return
  x = padx + col * cw
  y = pady + row * lh + baseline
  printf("  <text class=\"%s\" x=\"%.2f\" y=\"%.2f\" textLength=\"%.2f\" lengthAdjust=\"spacingAndGlyphs\" xml:space=\"preserve\">%s</text>\n",
         class, x, y, n * cw, xml(text))
}

function bar(row, class,   y) {
  y = pady + row * lh
  printf("  <rect class=\"%s\" x=\"%.2f\" y=\"%.2f\" width=\"%.2f\" height=\"%.2f\"/>\n",
         class, padx - 6, y + 3, cols * cw + 12, lh)
}

BEGIN {
  if (cols == "") cols = 92
  if (fontsize == "") fontsize = 14
  cw = fontsize * 0.6
  lh = fontsize * 1.45
  padx = 22
  pady = 44
  baseline = lh * 0.75
  if (title == "") title = "zfs-ncdu"
  body = ""
}

{
  lines[nl++] = $0
}

END {
  # Trim the blank filler tmux pads a pane with.
  while (nl > 0 && lines[nl - 1] ~ /^ *$/) nl--

  width = cols * cw + padx * 2
  height = pady + nl * lh + 26

  printf("<svg xmlns=\"http://www.w3.org/2000/svg\" width=\"%.0f\" height=\"%.0f\" viewBox=\"0 0 %.0f %.0f\" role=\"img\" aria-label=\"%s\">\n",
         width, height, width, height, xml(title))
  print  "  <style>"
  printf("    text { font-family: ui-monospace, SFMono-Regular, \"SF Mono\", Menlo, Consolas, \"DejaVu Sans Mono\", monospace; font-size: %dpx; white-space: pre; }\n", fontsize)
  print  "    .bg { fill: #10141a; }"
  print  "    .chrome { fill: #1b2029; }"
  print  "    .title { fill: #7c8797; font-size: 12px; }"
  print  "    .dot1 { fill: #ff5f57; } .dot2 { fill: #febc2e; } .dot3 { fill: #28c840; }"
  print  "    .headbar { fill: #2a68d8; }"
  print  "    .head { fill: #eef2f8; }"
  print  "    .path { fill: #6fa8ff; font-weight: 600; }"
  print  "    .rule { fill: #3d4859; }"
  print  "    .size { fill: #d7dee8; }"
  print  "    .graph { fill: #4ade80; }"
  print  "    .graphdim { fill: #3a5a4b; }"
  print  "    .dir { fill: #6fa8ff; }"
  print  "    .special { fill: #d9a441; }"
  print  "    .file { fill: #aab4c2; }"
  print  "    .footbar { fill: #1b2029; }"
  print  "    .foot { fill: #9aa5b4; }"
  print  "  </style>"
  print  "  <defs><filter id=\"shadow\" x=\"-10%\" y=\"-10%\" width=\"120%\" height=\"130%\">"
  print  "    <feDropShadow dx=\"0\" dy=\"2\" stdDeviation=\"6\" flood-color=\"#000\" flood-opacity=\"0.35\"/>"
  print  "  </filter></defs>"
  printf("  <g filter=\"url(#shadow)\">\n")
  printf("  <rect class=\"bg\" x=\"0.5\" y=\"0.5\" width=\"%.0f\" height=\"%.0f\" rx=\"10\" stroke=\"#39424f\" stroke-width=\"1\"/>\n", width - 1, height - 1)
  printf("  <path class=\"chrome\" d=\"M0 10a10 10 0 0 1 10-10h%.0f a10 10 0 0 1 10 10v20H0z\"/>\n", width - 20)
  print  "  <circle class=\"dot1\" cx=\"18\" cy=\"15\" r=\"5\"/>"
  print  "  <circle class=\"dot2\" cx=\"36\" cy=\"15\" r=\"5\"/>"
  print  "  <circle class=\"dot3\" cx=\"54\" cy=\"15\" r=\"5\"/>"
  printf("  <text class=\"title\" x=\"%.0f\" y=\"19\" text-anchor=\"middle\">%s</text>\n", width / 2, xml(title))
  print  "  </g>"

  for (i = 0; i < nl; i++) {
    line = lines[i]

    if (i == 0) {                       # ncdu's top status bar
      bar(i, "headbar")
      span(line, 0, i, "head")
      continue
    }

    if (line ~ /^--- /) {               # breadcrumb rule: --- tank/home ------
      p = index(substr(line, 5), " ")
      name = substr(line, 5, p - 1)
      span("---", 0, i, "rule")
      span(name, 4, i, "path")
      span(substr(line, 5 + length(name)), 4 + length(name), i, "rule")
      continue
    }

    if (line ~ /^\*/) {                 # footer totals
      bar(i, "footbar")
      span(line, 0, i, "foot")
      continue
    }

    # Body: "  640.0 GiB [#####     ] /backups"
    lb = index(line, "[")
    rb = index(line, "]")
    if (lb > 0 && rb > lb) {
      span(substr(line, 1, lb - 1), 0, i, "size")
      span("[", lb - 1, i, "graphdim")
      graph = substr(line, lb + 1, rb - lb - 1)
      hashes = graph
      sub(/ +$/, "", hashes)
      span(hashes, lb, i, "graph")
      span(substr(graph, length(hashes) + 1), lb + length(hashes), i, "graphdim")
      span("]", rb - 1, i, "graphdim")
      rest = substr(line, rb + 1)
      class = "file"
      if (rest ~ /^ *\//) class = "dir"
      if (rest ~ /\[/) class = "special"
      span(rest, rb, i, class)
      continue
    }

    span(line, 0, i, "file")
  }

  print "</svg>"
}
