;;; -*- Mode: LISP; Syntax: Common-lisp; Base: 10; Lowercase: Yes -*-
;;;
;;; UNDER-DECLARATION self-check by RUNTIME CAPTURE. validate-ontology checks that
;;; every label the manifest DECLARES exists in the ontology; this checks the other
;;; direction -- that the manifest declares every framework label the extractor
;;; actually EMITS. It runs a battery spanning every construction with capture
;;; active (*captured-relations* / *captured-types* bound), then asserts the emitted
;;; framework relations and types are all present in *ontology-requirements*. If
;;; someone adds an emission (a new case role, adjunct relation, type-hint, ...)
;;; without a manifest entry, a battery sentence emits it and this test fails.
;;;
;;; Relations are captured automatically (every one goes through make-relation*).
;;; Framework TYPES are captured at their literal sites (type-hint, complement
;;; wrapper, predicate/exchange root, the STATE probe); the lemma-derived concept-for
;;; path is not captured, so DOMAIN types (man/dog/pay/hamburger) and entailed
;;; relation dest-types stay out of scope, exactly as the manifest intends.
;;; Runs under :create so domain words resolve; only framework labels are asserted.
;;;
;;;   sbcl --non-interactive --disable-debugger \
;;;     --eval '(ql:quickload :swank)' --eval '(ql:quickload :cg-from-parse)' \
;;;     --load test/extract-ontology-capture-headless.lisp

(in-package :cg-from-parse)

(load (merge-pathnames "test-setup.lisp"
                       (or *load-truename* *compile-file-truename*)))
(setup-test-cgraph)

(load (merge-pathnames "system/grammar/clause-grammar.lisp"
                       (asdf:system-source-directory :parsifal)))
(pa::load-full-grammar)
;; small dfs for PP objects not in PARSIFAL's dictionary (as the pp-adjunct test does)
(pa::df pa::city pa::feats (pa::noun pa::ns pa::n3p) pa::markers (pa::physob))
(pa::expandsim 'pa::city)
(pa::df pa::telescope pa::feats (pa::noun pa::ns pa::n3p) pa::markers (pa::physob))
(pa::expandsim 'pa::telescope)

(defparameter *capture-battery*
  '("the man sees the dog ."                          ; agnt obj + predicate root
    "the man gives the woman the book ."              ; rcpt
    "the big dog sees the man ."                      ; attr
    "the man sees the dog quickly ."                  ; manr
    "the man sees the dog in the city ."              ; loc
    "the man sees the dog with the telescope ."       ; inst
    "the man sees the dog on monday ."                ; time
    "the man sees him ."                              ; person (pronoun type-hint)
    "mitch sees the dog ."                            ; person (proper-name type-hint)
    "who sees the dog ?"                              ; person (wh query type-hint)
    "the man knows that the boy sees the dog ."       ; state, proposition, expr
    "the boy wants to go ."                           ; situation
    "the man 's dog sees the woman ."                 ; poss
    "i pay you for a hamburger .")                    ; event, has-part (exchange)
  "One or more sentences per emission path, so capture exercises every framework
relation and type the extractor mints.")

(defun %capture-extract (sentence)
  "Parse and extract SENTENCE (under :create), for its side effect of exercising
the emission hooks. Returns nothing useful."
  (when (pa::parse-sentence sentence
                            :initial-rule (intern "INITIAL-RULE" :parsifal))
    (let ((*on-missing-type* :create))
      (handler-bind ((warning #'muffle-warning))
        (ignore-errors (ir->cgraph (parse->ir pa::c)))))))

(defun %hash-keys (h) (loop for k being the hash-keys of h collect k))

(defun extract-ontology-capture-headless-test (&optional (verbose t))
  (let ((cap-rels  (make-hash-table))
        (cap-types (make-hash-table)))
    ;; 1. run the battery with capture active
    (let ((*captured-relations* cap-rels)
          (*captured-types*     cap-types))
      (dolist (s *capture-battery*) (%capture-extract s)))
    (let* ((rels   (%hash-keys cap-rels))
           (types  (%hash-keys cap-types))
           ;; allowed = declared in the manifest, PLUS the self-provided relations
           ;; (prop), which are emitted but auto-created if absent -- neither required
           ;; nor an under-declaration.
           (allowed-rels (append (manifest-relations)
                                 (mapcar #'label->cg *self-provided-relations*)))
           (undecl-rels  (set-difference rels  allowed-rels))
           (undecl-types (set-difference types (manifest-concept-types)))
           ;; 2. the diff really discriminates: a bogus emitted label is flagged
           (probe (let ((*captured-relations* (make-hash-table)))
                    (note-relation-label 'cg::not-a-declared-relation)
                    (set-difference (%hash-keys *captured-relations*)
                                    (manifest-relations))))
           (pass (and
                  ;; capture actually happened (not a vacuous pass)
                  (>= (length rels) 8) (>= (length types) 4)
                  ;; every emitted framework label is declared in the manifest
                  (null undecl-rels) (null undecl-types)
                  ;; and the detector is not always-empty
                  probe)))
      (when verbose
        (format t "~&captured relations (~d): ~{~a~^ ~}~%" (length rels) (sort (copy-list rels) #'string<))
        (format t "~&captured types (~d): ~{~a~^ ~}~%" (length types) (sort (copy-list types) #'string<))
        (when undecl-rels  (format t "~&UNDECLARED relations: ~a~%" undecl-rels))
        (when undecl-types (format t "~&UNDECLARED types: ~a~%" undecl-types)))
      (format t "~&extract-ontology-capture-headless-test: ~:[FAILED <<<~;passed~]~%" pass)
      pass)))

(extract-ontology-capture-headless-test)
