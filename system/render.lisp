;;; -*- Mode: LISP; Syntax: Common-lisp; Base: 10; Lowercase: Yes -*-
;;;
;;; render.lisp -- block renderer for promoted [EXCHANGE] graphs.
;;;
;;; The cgraph engine's linear formatter (cg::format-cgraph) decomposes a graph
;;; into segments and, at a concept shared by several paths, expands that
;;; concept's subtree at whichever path reaches it FIRST -- rendering the other
;;; occurrences as coref `*x' leaves. That works for a single shared node, but
;;; our emit-exchange graph defeats it: an [EXCHANGE] with two (has-part)
;;; sub-events (PAY, GIVE) that SHARE both participants (the same [PERSON: I] and
;;; [PERSON: You]) has two cycles through the PAY/GIVE pair, so the formatter
;;; dumps one whole sub-event inline under a shared participant -- a correct but
;;; unreadable tangle.
;;;
;;; This graph has a fixed, regular shape, so we render it directly: the
;;; [EXCHANGE] head, then each (has-part) sub-event as its own indented block,
;;; with any participant shared across the two sub-events shown as a coref leaf
;;; ([PERSON: I *b]). Each sub-event on its own is a clean tree, so its leaves
;;; reuse the engine's own cg::format-node.
;;;
;;; Deliberately NARROW -- only the exchange shape -- so it carries no risk to the
;;; engine formatter or its tests. The general fix (teach the engine formatter to
;;; coref-leaf any multiply-shared node) is DEFERRED; see the decision note.
;;; `cg-text' dispatches here for an exchange graph and to format-cgraph otherwise;
;;; `sentence->cg-text' (driver.lisp) goes through `cg-text'.

(in-package :cg-from-parse)

(defun exchange-concept-p (concept)
  "True if CONCEPT is an [EXCHANGE] -- the head of a promoted commercial graph."
  (and (typep concept 'cg::concept)
       (string-equal (princ-to-string (cg::label (cg::concept-type concept)))
                     "EXCHANGE")))

;;; In cgraph's object model a binary relation's arcs are (DEST . SOURCES): the
;;; destination sits at the outarc (position 0, set by set-arc-from-relation) and
;;; the source concept is added at position 1+ (add-arc-into-relation). So the
;;; relations EMANATING from a concept (concept -(rel)-> dest) are the ones where
;;; it is NOT the outarc == (cg::outarcs c), and a relation's destination is its
;;; (cg::outarc rel).

(defun cgfp-rel-dest (relation)
  "The destination concept of RELATION (concept it points TO), or NIL."
  (cg::outarc relation))

(defun cgfp-rel-label (relation)
  "RELATION's type label as a lowercase string, e.g. \"agnt\"."
  (string-downcase (princ-to-string (cg::label (cg::relation-type relation)))))

(defun cgfp-out-relations (concept)
  "Relations sourced at CONCEPT, in deterministic order: by relation label, then
by destination type -- so coref labels and block order are stable across runs."
  (flet ((dlabel (r) (let ((d (cgfp-rel-dest r)))
                       (if d (princ-to-string (cg::label (cg::concept-type d))) ""))))
    (sort (copy-list (cg::outarcs concept))
          (lambda (a b)
            (let ((la (cgfp-rel-label a)) (lb (cgfp-rel-label b)))
              (if (string= la lb)
                  (string-lessp (dlabel a) (dlabel b))
                  (string-lessp la lb)))))))

(defun cgfp-splice-coref (node-string coref)
  "Insert COREF (\"*a\") just before a formatted concept's closing bracket:
\"[PERSON: I]\" -> \"[PERSON: I *a]\"; \"[MONEY]\" -> \"[MONEY *a]\"."
  (let ((pos (position #\] node-string :from-end t)))
    (if pos
        (concatenate 'string (subseq node-string 0 pos) " " coref (subseq node-string pos))
        node-string)))

(defun cgfp-leaf (concept counts labels counter)
  "Formatted leaf for CONCEPT (via the engine's format-node). A concept shared
across the exchange (COUNTS > 1) gets a stable coref label (*a, *b, ...) assigned
on first encounter and reused thereafter."
  (let ((base (cg::format-node concept)))
    (if (> (gethash concept counts 0) 1)
        (let ((lbl (gethash concept labels)))
          (unless lbl
            (setf lbl (format nil "*~a"
                              (char "abcdefghijklmnopqrstuvwxyz" (mod (car counter) 26))))
            (setf (gethash concept labels) lbl)
            (incf (car counter)))
          (cgfp-splice-coref base lbl))
        base)))

(defun render-exchange (exchange)
  "Render a promoted [EXCHANGE] concept as a block-graph string (no trailing dot):
the head, then one indented block per (has-part) sub-event, participants shared
between the sub-events shown as coref leaves."
  (let* ((part-rels (cgfp-out-relations exchange))
         (subevents (remove nil (mapcar #'cgfp-rel-dest part-rels)))
         (counts    (make-hash-table :test 'eq))
         (labels    (make-hash-table :test 'eq))
         (counter   (list 0)))
    ;; how many times each participant is a destination across the sub-events
    ;; (> 1  =>  shared  =>  gets a coref label)
    (dolist (se subevents)
      (dolist (r (cgfp-out-relations se))
        (let ((d (cgfp-rel-dest r))) (when d (incf (gethash d counts 0))))))
    (with-output-to-string (out)
      (format out "~a-" (cg::format-node exchange))
      ;; one block per (has-part) sub-event; in CG linear form every branch off a
      ;; node except the last ends with a comma, so all but the final block do.
      (loop for (rel . more) on part-rels
            for se = (cgfp-rel-dest rel)
            do (format out "~%   (~a)→~a-"
                       (cgfp-rel-label rel)
                       (cgfp-leaf se counts labels counter))
               (dolist (r (cgfp-out-relations se))
                 (format out "~%      (~a)→~a"
                         (cgfp-rel-label r)
                         (cgfp-leaf (cgfp-rel-dest r) counts labels counter)))
               (when more (format out ","))))))

(defun cg-text (graph)
  "Formatted CG text for GRAPH: the block renderer for a promoted [EXCHANGE],
otherwise the engine's cg::format-cgraph. Honors cg::*always-print-ascii-arrows*
just as format-cgraph does."
  (let ((head (typecase graph
                (cg::graph (cg::head graph))
                (cons      (cg::head graph))
                (t         graph))))
    (if (exchange-concept-p head)
        (let ((result (concatenate 'string (render-exchange head) ".")))
          (if cg::*always-print-ascii-arrows* (cg::arrows-to-ascii result) result))
        (cg::format-cgraph graph))))

;;; Route a graph's REPL/print representation through cg-text, so a value RETURNED
;;; by parse-and-extract (not just sentence->cg-text) shows the block form for an
;;; [EXCHANGE]. This REPLACES the engine's identically-specialized print-object
;;; (cgraph/system/core/graph.lisp) -- but only its FORMATTING SOURCE changes:
;;; cg-text is format-cgraph verbatim for every non-exchange graph, so all other
;;; output (and the engine's own format tests) is byte-for-byte unchanged; only an
;;; [EXCHANGE]-headed graph renders as blocks. We mirror the engine method's two
;;; branches (*always-format-nodes* raw vs. the #<...> unreadable wrapper) exactly.
(defmethod print-object ((object cg::graph) stream)
  (cond (cg::*always-format-nodes*
         (princ (cg-text object) stream))
        (t
         (print-unreadable-object (object stream :type t :identity nil)
           (format stream "~a" (cg::flatten-cgraph (cg-text object)))))))
