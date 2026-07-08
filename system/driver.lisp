;;; -*- Mode: LISP; Syntax: Common-lisp; Base: 10; Lowercase: Yes -*-
;;;
;;; driver.lisp -- one-call ergonomics: string -> conceptual graph.
;;;
;;; parse-and-extract hides the boilerplate (load + register PARSIFAL's full
;;; grammar, parse-sentence with the initial rule, then extract-graph) so a
;;; caller can go straight from English to a cgraph graph. The grammar is
;;; loaded/registered once per session and cached.
;;;
;;; It self-initializes both cgraph (the type catalog + *context*) and the
;;; PARSIFAL grammar on first use, each a no-op if already set up -- so it works
;;; right after (ql:quickload :cg-from-parse) without disturbing a running session.

(in-package :cg-from-parse)

(defvar *grammar-loaded* nil
  "T once PARSIFAL's full grammar has been loaded + registered this session.")

(defun cgraph-ready-p ()
  "True when cgraph is initialized: the type catalog is loaded (top type bound)
and a *context* exists."
  (and (boundp 'cg::*concept-type-top*)
       cg::*concept-type-top*
       cg::*context*))

(defun ensure-cgraph ()
  "Make sure cgraph is initialized -- type catalog loaded from the user's
~/.cgraph/types and *context* bound. No-op if already initialized, so a running
session isn't disturbed. (*package* must be :cg while loading: cgraph's type
loaders use plain READ.)"
  (unless (cgraph-ready-p)
    (let ((*package* (find-package :conceptual-graphs)))
      (cg::setup-cgraph (asdf:system-source-directory :cgraph))
      (cg::reset-cgraph)))
  t)

(defun ensure-grammar (&optional force)
  "Load and register PARSIFAL's full grammar so parse-sentence can handle any
supported construction. Done once per session (pass FORCE to redo). The grammar
lives in parsifal's system/grammar/clause-grammar.lisp; load-full-grammar
there composes and registers it."
  (when (or force (not *grammar-loaded*))
    (load (asdf:system-relative-pathname :parsifal
                                         "system/grammar/clause-grammar.lisp"))
    (funcall (intern "LOAD-FULL-GRAMMAR" :parsifal))
    (setf *grammar-loaded* t))
  t)

(defun parse-and-extract (sentence &key (on-missing *on-missing-type*))
  "Parse SENTENCE with PARSIFAL and return its conceptual graph (a cgraph graph).
Loads + registers the full grammar on first use. Signals an error if PARSIFAL
can't parse SENTENCE. ON-MISSING binds *on-missing-type* for out-of-ontology
lemmas (:error / :create / :top).

  (parse-and-extract \"the man gives the woman the book .\")
  (parse-and-extract \"the man sees the dog in the park .\" :on-missing :create)"
  (ensure-cgraph)
  (ensure-grammar)
  (let ((*on-missing-type* on-missing))
    (if (pa:parse-sentence sentence :initial-rule (intern "INITIAL-RULE" :parsifal))
        (extract-graph)
        (error "cg-from-parse: PARSIFAL could not parse ~s" sentence))))

(defun sentence->cg-text (sentence &key (on-missing *on-missing-type*))
  "Convenience: parse-and-extract SENTENCE and return the formatted CG string.
Routes through cg-text, so a promoted [EXCHANGE] graph gets the block renderer
(render.lisp) and everything else the engine's format-cgraph."
  (cg-text (parse-and-extract sentence :on-missing on-missing)))
