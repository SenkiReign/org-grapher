# org-grapher
Graph visualization for Org notes

<img width="1826" height="897" alt="graph" src="https://github.com/user-attachments/assets/14613469-d0d8-4001-b67c-d8fd223395ee" />

- Interactive graph of .org notes.
- Links automatically created from tags and org mode links.
- Lightweight, minimal, and self-contained. 
- Clustering reflect the number of connections.
- Works fully offline after initial setup. (D3 cached after first use)
- Works with single file workflows too. (The screenshot above generated from a single org file)

## Installation

1. Copy `org-grapher.el` to your Emacs `load-path`.  
2. Add to your `init.el` or `config.el`:

   ```elisp
   (load "~/path/to/org-grapher.el")

## Set your org directory 

```(setq org-grapher-notes-directory "~/") ```

## Generate a Graph

- `M-x org-grapher-open` - Generate and open graph for your configured org directory
- `M-x org-grapher-open-here` - Generate and open graph for current directory / local graph

### Example Config
```elisp
;; Customize colors
(setq org-grapher--tag-colors
  '("emacs" "#d65d0e"
    "work" "#458588"
    "personal" "#98971a"))

;; Configure directories
(setq org-grapher-notes-directory "~/org/"
      org-grapher-recursive t
      org-grapher-output-file "~/.cache/org-graph.html")

;; Load package
(require 'org-grapher)

