# org-graph
Graph visualization for Org notes

<img width="1826" height="897" alt="graph" src="https://github.com/user-attachments/assets/14613469-d0d8-4001-b67c-d8fd223395ee" />

- Interactive graph of .org notes.
- Links automatically created from tags and org mode links.
- Lightweight, minimal, and self-contained.
- Clustering reflect the number of connections.
- Works fully offline after initial setup.

## Installation

1. Copy `org-graph.el` to your Emacs `load-path`.  
2. Add to your `init.el` or `config.el`:

   ```elisp
   (load "~/path/to/org-graph.el")

## Set your org directory 

```(setq org-graph-notes-directory "~/") ```

## Generate a Graph

```M-x org-graph-open```
