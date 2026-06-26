;;; -*- Mode: LISP; Syntax: Common-lisp; Base: 10; Lowercase: Yes -*-
;;;
;;; driver.lisp -- one-call ergonomics: string -> conceptual graph.
;;;
;;; parse-and-extract hides the boilerplate (load + register PARSIFAL's full
;;; grammar, parse-sentence with the initial rule, then extract-graph) so a
;;; caller can go straight from English to a cgraph graph. The grammar is
;;; loaded/registered once per session and cached.
;;;
;;; Requires a running cgraph (a type catalog + *context*, as in any normal
;;; session); it does NOT set those up -- use the headless test-setup for that.

(in-package :cg-from-parse)

(defvar *grammar-loaded* nil
  "T once PARSIFAL's full grammar has been loaded + registered this session.")

(defun ensure-grammar (&optional force)
  "Load and register PARSIFAL's full grammar so parse-sentence can handle any
supported construction. Done once per session (pass FORCE to redo). The grammar
lives in parsifal's test/integration/clause-grammar.lisp; load-full-grammar
there composes and registers it."
  (when (or force (not *grammar-loaded*))
    (load (asdf:system-relative-pathname :parsifal
                                         "test/integration/clause-grammar.lisp"))
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
  (ensure-grammar)
  (let ((*on-missing-type* on-missing))
    (if (pa:parse-sentence sentence :initial-rule (intern "INITIAL-RULE" :parsifal))
        (extract-graph)
        (error "cg-from-parse: PARSIFAL could not parse ~s" sentence))))

(defun sentence->cg-text (sentence &key (on-missing *on-missing-type*))
  "Convenience: parse-and-extract SENTENCE and return the formatted CG string."
  (cg::format-cgraph (parse-and-extract sentence :on-missing on-missing)))
