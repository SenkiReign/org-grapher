;;; org-grapher.el --- Graph visualization for Org notes -*- lexical-binding: t; -*-

;;; Commentary:
;; Graph visualization for Org journal notes with tags and links.

;;; Code:
(require 'json)
(require 'url)
(require 'org)
(require 'org-element)

(defgroup org-grapher nil
  "Graph visualization for Org notes."
  :group 'org
  :prefix "org-grapher-")

(defcustom org-grapher-notes-directory (expand-file-name "~/org/")
  "Directory containing Org journal notes."
  :type 'directory
  :group 'org-grapher)

(defcustom org-grapher-output-file (expand-file-name "~/.emacs.d/org-grapher.html")
  "Path to the generated graph HTML file."
  :type 'file
  :group 'org-grapher)

(defcustom org-grapher-d3-cache-file (expand-file-name "~/.emacs.d/org-d3.js")
  "Path to cached D3.js library."
  :type 'file
  :group 'org-grapher)

(defvar org-grapher--tag-colors
  '("emacs" "#b8926d"
    "programming" "#8f9a5e"
    "research" "#c55d55"
    "idea" "#c57841"
    "work" "#b07695"
    "personal" "#6f9668"
    "project" "#c57841"
    "note" "#6a9589"
    "todo" "#c55d55"
    "meeting" "#928374")
  "Alist of tag names to colors - muted gruvbox inspired.")

(defvar org-grapher--color-cache (make-hash-table :test 'equal)
  "Cache for generated tag colors.")

(defun org-grapher--get-tag-color (tag)
  "Get color for TAG or generate a consistent one."
  (or (plist-get org-grapher--tag-colors tag)
      (gethash tag org-grapher--color-cache)
      (let ((color (format "#%02x%02x%02x"
                          (+ 100 (mod (sxhash tag) 156))
                          (+ 100 (mod (ash (sxhash tag) -8) 156))
                          (+ 100 (mod (ash (sxhash tag) -16) 156)))))
        (puthash tag color org-grapher--color-cache)
        color)))

(defun org-grapher--parse-notes ()
  "Parse all Org notes and return nodes and links."
  (let ((nodes '())
        (links '())
        (note-ids (make-hash-table :test 'equal))
        (tag-ids (make-hash-table :test 'equal))
        (note-counter 0)
        (tag-counter 0)
        (files (directory-files org-grapher-notes-directory t "\\.org\\'")))
    
    ;; First: collect all headings
    (dolist (file files)
      (condition-case err
          (let ((fname (file-name-nondirectory file)))
            (with-temp-buffer
              (insert-file-contents file)
              (delay-mode-hooks (org-mode))
              (org-element-map (org-element-parse-buffer 'headline) 'headline
                (lambda (headline)
                  (let* ((raw-heading (org-element-property :raw-value headline))
                         (heading (when raw-heading
                                   (replace-regexp-in-string "\\[\\[.*?\\]\\(?:\\[.*?\\]\\)?\\]" "" raw-heading)))
                         (tags (org-element-property :tags headline))
                         (begin (org-element-property :begin headline))
                         (end (org-element-property :end headline)))
                    (when (and heading begin end)
                      (let* ((raw-content (buffer-substring-no-properties 
                                      (save-excursion 
                                        (goto-char begin)
                                        (forward-line 1)
                                        (point))
                                      end))
                             (content (replace-regexp-in-string "\\[\\[\\(file:[^]]+\\)\\]\\(?:\\[[^]]*\\]\\)?\\]" "\\1" raw-content))
                             (note-id (format "note%d" note-counter))
                             (note-key (concat heading "__" fname)))
                
                        (push (list (cons 'id note-id)
                                   (cons 'heading heading)
                                   (cons 'content (string-trim content))
                                   (cons 'file fname)
                                   (cons 'type "note")
                                   (cons 'color (if tags 
                                                   (org-grapher--get-tag-color (car tags))
                                                   "#1f77b4")))
                              nodes)
                
                        (puthash note-key note-id note-ids)
                        (puthash heading note-id note-ids)
                        (setq note-counter (1+ note-counter))
                
                        (when tags
                          (dolist (tag tags)
                            (unless (gethash tag tag-ids)
                              (let ((tag-id (format "tag%d" tag-counter)))
                                (push (list (cons 'id tag-id)
                                           (cons 'heading tag)
                                           (cons 'content "")
                                           (cons 'file "")
                                           (cons 'type "keyword")
                                           (cons 'color (org-grapher--get-tag-color tag)))
                                      nodes)
                                (puthash tag tag-id tag-ids)
                                (setq tag-counter (1+ tag-counter))))
                    
                            (push (list (cons 'source note-id)
                                       (cons 'target (gethash tag tag-ids)))
                                  links))))))))))
        (error (message "Error parsing %s: %s" file err))))
    
    ;; Second: parse all links (headings and body)
    (dolist (file files)
      (let ((fname (file-name-nondirectory file)))
        (with-temp-buffer
          (insert-file-contents file)
          (goto-char (point-min))
          (let ((current-heading nil)
                (current-note-id nil))
            (while (not (eobp))
              (cond
               ((looking-at "^\\*+ \\(.*\\)$")
                (let ((full-heading (match-string 1)))
                  (setq current-heading (replace-regexp-in-string "[ \t]+:[[:alnum:]_@:]+:[ \t]*$" "" full-heading))
                  (setq current-heading (replace-regexp-in-string "\\[\\[.*?\\]\\(?:\\[.*?\\]\\)?\\]" "" current-heading))
                  (setq current-note-id (gethash (concat current-heading "__" fname) note-ids))
                  
                  ;; Parse links in the heading line itself
                  (when current-note-id
                    (with-temp-buffer
                      (insert full-heading)
                      (goto-char (point-min))
                      (while (re-search-forward "\\[\\[\\(?:file:\\([^]]+\\)::\\)?\\*?\\([^]]+?\\)\\]\\(?:\\[\\([^]]+\\)\\]\\)?\\]" nil t)
                        (let* ((target-file (match-string 1))
                               (target-heading (match-string 2))
                               (target-file-name (if target-file
                                                   (file-name-nondirectory target-file)
                                                   fname))
                               (target-key (concat target-heading "__" target-file-name))
                               (target-note-id (gethash target-key note-ids)))
                          (when target-note-id
                            (push (list (cons 'source current-note-id)
                                       (cons 'target target-note-id))
                                  links))))))))
               
               ;; Parse links in body
               (current-note-id
                (let ((line-end (line-end-position)))
                  (while (re-search-forward "\\[\\[\\(?:file:\\([^]]+\\)::\\)?\\*?\\([^]]+?\\)\\]\\(?:\\[\\([^]]+\\)\\]\\)?\\]" line-end t)
                    (let* ((target-file (match-string 1))
                           (target-heading (match-string 2))
                           (target-file-name (if target-file
                                               (file-name-nondirectory target-file)
                                               fname))
                           (target-key (concat target-heading "__" target-file-name))
                           (target-note-id (gethash target-key note-ids)))
                      (when target-note-id
                        (push (list (cons 'source current-note-id)
                                   (cons 'target target-note-id))
                              links)))))))
              (forward-line 1))))))
    
    (list :nodes (nreverse nodes) :links (nreverse links))))

(defun org-grapher--fetch-d3 ()
  "Fetch D3.js library, using cache if available."
  (if (file-exists-p org-grapher-d3-cache-file)
      (with-temp-buffer
        (insert-file-contents org-grapher-d3-cache-file)
        (buffer-string))
    (message "Downloading D3.js (one-time download)...")
    (let ((d3-url "https://d3js.org/d3.v7.min.js"))
      (with-current-buffer (url-retrieve-synchronously d3-url t)
        (goto-char (point-min))
        (re-search-forward "^$")
        (let ((d3-content (buffer-substring (point) (point-max))))
          (with-temp-file org-grapher-d3-cache-file
            (insert d3-content))
          (message "D3.js cached to %s" org-grapher-d3-cache-file)
          d3-content)))))

(defun org-grapher--make-html-content ()
  "Generate the HTML content."
  (concat
   "<!DOCTYPE html>\n<html>\n<head>\n<meta charset=\"UTF-8\">\n<title>Org Graph</title>\n"
   "<script>REPLACE_D3_HERE</script>\n"
   "<style>\n"
   "body { margin: 0; display: flex; font-family: sans-serif; height: 100vh; overflow: hidden; background: #f9f5d7; }\n"
   "#graph { flex: 1; background: #f9f5d7; transition: background 0.3s; }\n"
   "#sidebar { width: 300px; min-width: 200px; max-width: 600px; border-left: 2px solid #d5c4a1; padding: 20px; overflow-y: auto; background: #fbf1c7; position: relative; transition: all 0.3s; }\n"
   "#resizer { position: absolute; left: 0; top: 0; bottom: 0; width: 5px; cursor: ew-resize; background: transparent; z-index: 10; }\n"
   "#resizer:hover { background: #d4a574; }\n"
   "h2 { margin: 15px 0 10px 0; font-size: 1.1em; color: #3c3836; }\n"
   ".btn { padding: 8px 16px; margin: 5px 5px 5px 0; background: #d4a574; color: #3c3836; border: none; border-radius: 4px; cursor: pointer; flex: 1; font-weight: 500; }\n"
   ".btn:hover { background: #b8926d; }\n"
   ".btn.secondary { background: #a89984; color: #282828; }\n"
   ".btn.secondary:hover { background: #928374; }\n"
   ".btn.active { background: #ea6962; color: #fbf1c7; }\n"
   "#details { padding: 15px; background: #f2e5bc; border-radius: 8px; border-left: 4px solid #d4a574; line-height: 1.8; }\n"
   "#details h3 { margin-top: 0; margin-bottom: 12px; color: #3c3836; font-size: 1.15em; word-wrap: break-word; }\n"
   "#details p { margin: 10px 0; white-space: pre-wrap; word-wrap: break-word; overflow-wrap: break-word; color: #504945; }\n"
   "#details em { display: block; margin-top: 15px; padding-top: 10px; border-top: 1px solid #d5c4a1; color: #7c6f64; font-size: 0.9em; word-wrap: break-word; }\n"
   "</style>\n</head>\n<body>\n"
   "<div id=\"graph\"></div>\n"
   "<div id=\"sidebar\">\n<div id=\"resizer\"></div>\n<h2>Controls</h2>\n"
   "<div style=\"display: flex; gap: 5px; margin-bottom: 10px;\">\n"
   "<button id=\"btn-dark\" class=\"btn\">Dark Mode</button>\n"
   "<button id=\"btn-orphan\" class=\"btn secondary\">Hide Orphans</button>\n"
   "<button id=\"btn-label\" class=\"btn secondary\">Hide Labels</button>\n"
   "</div>\n<h2>Search</h2>\n"
   "<input type=\"text\" id=\"search\" placeholder=\"Search nodes...\" style=\"width: 100%; padding: 8px; border: 2px solid #d5c4a1; border-radius: 4px; margin-bottom: 10px; box-sizing: border-box; background: #f9f5d7; color: #3c3836;\">\n"
   "<div id=\"search-results\" style=\"font-size: 0.9em; color: #7c6f64; margin-bottom: 10px;\"></div>\n"
   "<h2>Stats</h2>\n<div id=\"stats\"></div>\n<h2>Details</h2>\n<div id=\"details\">Click a node</div>\n"
   "</div>\n<script>\n"
   "const graph = REPLACE_DATA_HERE;\n"
   "let width = window.innerWidth - 300, height = window.innerHeight;\n"
   "const svg = d3.select('#graph').append('svg').attr('width', width).attr('height', height);\n"
   "const container = svg.append('g'), resizer = document.getElementById('resizer'), sidebar = document.getElementById('sidebar');\n"
   "let isResizing = false;\n"
   "resizer.addEventListener('mousedown', () => isResizing = true);\n"
   "document.addEventListener('mousemove', e => {\n"
   "  if (!isResizing) return;\n"
   "  const w = window.innerWidth - e.clientX;\n"
   "  if (w >= 200 && w <= 600) {\n"
   "    sidebar.style.width = w + 'px';\n"
   "    width = window.innerWidth - w;\n"
   "    svg.attr('width', width);\n"
   "    simulation.force('center', d3.forceCenter(width/2, height/2).strength(0.1)).force('x', d3.forceX(width/2).strength(0.05)).alpha(0.3).restart();\n"
   "  }\n});\n"
   "document.addEventListener('mouseup', () => isResizing = false);\n"
   "graph.nodes.forEach(n => n.degree = 0);\n"
   "graph.links.forEach(l => {\n"
   "  const s = typeof l.source === 'object' ? l.source.id : l.source, t = typeof l.target === 'object' ? l.target.id : l.target;\n"
   "  graph.nodes.find(n => n.id === s).degree++;\n"
   "  graph.nodes.find(n => n.id === t).degree++;\n"
   "});\n"
   "document.getElementById('stats').innerHTML = '<p>Nodes: ' + graph.nodes.length + '<br>Links: ' + graph.links.length + '</p>';\n"
   "const simulation = d3.forceSimulation(graph.nodes)\n"
   "  .force('link', d3.forceLink(graph.links).id(d => d.id).distance(d => d.target.type === 'keyword' ? 80 : 100).strength(d => d.target.type === 'keyword' ? 0.7 : 0.5))\n"
   "  .force('charge', d3.forceManyBody().strength(d => -150 - (d.degree || 0)*15))\n"
   "  .force('center', d3.forceCenter(width/2, height/2).strength(0.1))\n"
   "  .force('collide', d3.forceCollide(d => d.type === 'keyword' ? 20 : 18))\n"
   "  .force('x', d3.forceX(width/2).strength(0.05))\n"
   "  .force('y', d3.forceY(height/2).strength(0.05));\n"
   "const link = container.append('g').selectAll('line').data(graph.links).join('line').attr('stroke', '#bdae93').attr('stroke-width', 1.5).attr('stroke-opacity', 0.6);\n"
   "const node = container.append('g').selectAll('circle').data(graph.nodes).join('circle')\n"
   "  .attr('r', d => (d.type === 'keyword' ? 8 : 6) + Math.sqrt(d.degree + 1) * 2)\n"
   "  .attr('fill', d => d.type === 'keyword' || d.degree > 0 ? d.color : '#a89984')\n"
   "  .attr('stroke', '#fbf1c7').attr('stroke-width', 2).style('cursor', 'pointer')\n"
   "  .call(d3.drag().on('start', dragstarted).on('drag', dragged).on('end', dragended))\n"
   "  .on('mouseover', function(e, d) { d3.select(this).attr('stroke-width', 4); if (hideLabels) labels.filter(l => l === d).attr('opacity', 1).attr('font-weight', 'bold'); })\n"
   "  .on('mouseout', function(e, d) { d3.select(this).attr('stroke-width', 2); if (hideLabels) labels.filter(l => l === d).attr('opacity', 0).attr('font-weight', 'normal'); })\n"
   "  .on('click', (e,d) => {\n"
   "    const content = (d.content || 'No content').replace(/file:\\/+([^\\s]+\\.(png|jpg|jpeg|gif|svg|webp))/gi, (m, p) => '<br><img src=\"file:///' + p.replace(/^\\/+/, '') + '\" style=\"max-width: 100%; height: auto; margin: 10px 0; border-radius: 4px;\"><br>');\n"
   "    const el = document.getElementById('details');\n"
   "    el.innerHTML = '<h3>' + d.heading + '</h3><p>' + content + '</p>' + (d.file ? '<em>' + d.file + '</em>' : '');\n"
   "    if (darkMode) { el.querySelectorAll('h3').forEach(h => h.style.color = '#ebdbb2'); el.querySelectorAll('p').forEach(p => p.style.color = '#d5c4a1'); el.querySelectorAll('em').forEach(em => em.style.color = '#a89984'); }\n"
   "  });\n"
   "const labels = container.append('g').selectAll('text').data(graph.nodes).join('text').text(d => d.heading).attr('font-size', '11px').attr('text-anchor', 'middle').attr('dy', d => d.type === 'keyword' ? -12 : -10).attr('fill', '#3c3836').attr('pointer-events', 'none').style('font-weight', '500');\n"
   "simulation.on('tick', () => { link.attr('x1', d => d.source.x).attr('y1', d => d.source.y).attr('x2', d => d.target.x).attr('y2', d => d.target.y); node.attr('cx', d => d.x).attr('cy', d => d.y); labels.attr('x', d => d.x).attr('y', d => d.y); });\n"
   "svg.call(d3.zoom().scaleExtent([0.2, 4]).on('zoom', e => container.attr('transform', e.transform)));\n"
   "let darkMode = false, hideOrphans = false, hideLabels = false;\n"
   "const setTheme = (dark) => {\n"
   "  const styles = dark ? {bg:'#282828',graph:'#282828',sidebar:'#1d2021',border:'#d4a574',text:'#ebdbb2',details:'#32302f',search:'#282828',link:'#504945',stroke:'#1d2021',orphan:'#665c54',borderTop:'#504945',searchRes:'#a89984',detailsText:'#d5c4a1',detailsEm:'#a89984'} : {bg:'#f9f5d7',graph:'#f9f5d7',sidebar:'#fbf1c7',border:'#d5c4a1',text:'#3c3836',details:'#f2e5bc',search:'#f9f5d7',link:'#bdae93',stroke:'#fbf1c7',orphan:'#a89984',borderTop:'#d5c4a1',searchRes:'#7c6f64',detailsText:'#504945',detailsEm:'#7c6f64'};\n"
   "  document.body.style.background = styles.bg;\n"
   "  document.getElementById('graph').style.background = styles.graph;\n"
   "  sidebar.style.background = sidebar.style.color = styles.sidebar;\n"
   "  sidebar.style.borderLeftColor = styles.border;\n"
   "  document.querySelectorAll('#sidebar h2, #sidebar').forEach(e => e.style.color = styles.text);\n"
   "  const det = document.getElementById('details');\n"
   "  det.style.background = styles.details;\n"
   "  det.style.borderLeftColor = styles.border;\n"
   "  det.style.color = styles.text;\n"
   "  det.querySelectorAll('h3').forEach(h => h.style.color = styles.text);\n"
   "  det.querySelectorAll('p').forEach(p => p.style.color = styles.detailsText);\n"
   "  det.querySelectorAll('em').forEach(em => { em.style.color = styles.detailsEm; em.style.borderTopColor = styles.borderTop; });\n"
   "  const search = document.getElementById('search');\n"
   "  search.style.background = styles.search;\n"
   "  search.style.color = styles.text;\n"
   "  search.style.borderColor = dark ? '#504945' : styles.border;\n"
   "  document.getElementById('search-results').style.color = styles.searchRes;\n"
   "  document.getElementById('stats').style.color = styles.text;\n"
   "  node.attr('fill', d => d.type === 'keyword' || d.degree > 0 ? d.color : styles.orphan).attr('stroke', styles.stroke);\n"
   "  link.attr('stroke', styles.link);\n"
   "  labels.attr('fill', styles.text);\n"
   "};\n"
   "document.getElementById('btn-dark').onclick = () => { darkMode = !darkMode; setTheme(darkMode); };\n"
   "document.getElementById('btn-orphan').onclick = function() { hideOrphans = !hideOrphans; this.textContent = hideOrphans ? 'Show Orphans' : 'Hide Orphans'; this.classList.toggle('active', hideOrphans); node.attr('opacity', d => hideOrphans && d.degree === 0 ? 0 : 1); labels.attr('opacity', d => hideOrphans && d.degree === 0 ? 0 : hideLabels ? 0 : 1); };\n"
   "document.getElementById('btn-label').onclick = function() { hideLabels = !hideLabels; this.textContent = hideLabels ? 'Show Labels' : 'Hide Labels'; this.classList.toggle('active', hideLabels); labels.attr('opacity', d => hideLabels ? 0 : hideOrphans && d.degree === 0 ? 0 : 1); };\n"
   "function dragstarted(e,d) { if (!e.active) simulation.alphaTarget(0.3).restart(); d.fx = d.x; d.fy = d.y; }\n"
   "function dragged(e,d) { d.fx = e.x; d.fy = e.y; }\n"
   "function dragended(e,d) { if (!e.active) simulation.alphaTarget(0); d.fx = null; d.fy = null; }\n"
   "document.getElementById('search').addEventListener('input', e => {\n"
   "  const q = e.target.value.toLowerCase().trim();\n"
   "  if (q === '') { node.attr('opacity', 1); link.attr('opacity', 0.6); labels.attr('opacity', hideLabels ? 0 : 1); document.getElementById('search-results').innerHTML = ''; return; }\n"
   "  const matches = graph.nodes.filter(n => n.heading.toLowerCase().includes(q)), matchIds = new Set(matches.map(n => n.id)), connectedIds = new Set();\n"
   "  graph.links.forEach(l => { const s = l.source.id || l.source, t = l.target.id || l.target; if (matchIds.has(s)) connectedIds.add(t); if (matchIds.has(t)) connectedIds.add(s); });\n"
   "  node.attr('opacity', d => matchIds.has(d.id) ? 1 : connectedIds.has(d.id) ? 0.5 : 0.1);\n"
   "  link.attr('opacity', l => { const s = l.source.id || l.source, t = l.target.id || l.target; return matchIds.has(s) || matchIds.has(t) ? 0.8 : 0.05; });\n"
   "  labels.attr('opacity', d => hideLabels ? 0 : matchIds.has(d.id) ? 1 : connectedIds.has(d.id) ? 0.6 : 0.2);\n"
   "  document.getElementById('search-results').innerHTML = 'Found ' + matches.length + ' node(s)';\n"
   "});\n"
   "</script>\n</body>\n</html>\n"))

(defun org-grapher--generate-html ()
  "Generate HTML file with graph."
  (let* ((graph-data (org-grapher--parse-notes))
         (json-str (let ((json-encoding-pretty-print nil)) (json-encode graph-data)))
         (d3-script (org-grapher--fetch-d3))
         (html (org-grapher--make-html-content))
         (coding-system-for-write 'utf-8))
    
    (setq html (replace-regexp-in-string "REPLACE_D3_HERE" d3-script html t t))
    (setq html (replace-regexp-in-string "REPLACE_DATA_HERE" json-str html t t))
    
    (with-temp-file org-grapher-output-file
      (insert html))
    
    (message "Generated graph: %d nodes, %d links"
             (length (plist-get graph-data :nodes))
             (length (plist-get graph-data :links)))
    org-grapher-output-file))

;;;###autoload
(defun org-grapher-open ()
  "Show Org graph."
  (interactive)
  (let ((file (org-grapher--generate-html)))
    (browse-url (concat "file://" file))))

(provide 'org-grapher)
;;; org-grapher.el ends here
