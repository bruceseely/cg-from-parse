;;; -*- Mode: LISP; Syntax: Common-lisp; Base: 10; Lowercase: Yes -*-
;;;
;;; Live ALIAS check: a word that is an alias of a concept type keeps its
;;; spelling. cgraph's test types declare
;;;
;;;   (:label automobile :supertypes (vehicle) :aliases (car auto))
;;;
;;; so "car" looks up AUTOMOBILE. The concept is of type AUTOMOBILE either
;;; way; what this checks is that the graph SAYS [CAR] when the sentence said
;;; car, as a graph written by hand would. Before CONCEPT-FOR recorded the
;;; spelling, "the girl has a car ." came out as [AUTOMOBILE].
;;;
;;; Invocation:
;;;   sbcl --noinform --non-interactive \
;;;     --eval '(ql:quickload :cg-from-parse)' \
;;;     --load test/extract-alias-headless.lisp

(in-package :cg-from-parse)

(load (merge-pathnames "test-setup.lisp"
                       (or *load-truename* *compile-file-truename*)))
(setup-test-cgraph)

(load (merge-pathnames "system/grammar/clause-grammar.lisp"
                       (asdf:system-source-directory :parsifal)))
(pa::load-full-grammar)

;; Neither word is in Marcus's dictionary; a domain's lexicon.dict would say
;; this. Ordinary count nouns, like BLOCK.
(pa::jlike pa::automobile pa::block)
(pa::jlike pa::car pa::block)

(defun %alias-graph (sentence)
  "Parse SENTENCE, return its formatted CG upcased with spaces removed, or NIL."
  (when (pa::parse-sentence sentence
                            :initial-rule (intern "INITIAL-RULE" :parsifal))
    (let ((*on-missing-type* :error))
      (handler-bind ((warning #'muffle-warning))
        (let ((text (ignore-errors (cg::format-cgraph (ir->cgraph (parse->ir pa::c))))))
          (and (stringp text) (remove #\Space (string-upcase text))))))))

(defun extract-alias-headless-test (&optional (verbose t))
  (let* ((car-graph  (%alias-graph "the girl has a car ."))
         (auto-graph (%alias-graph "the girl has an automobile ."))
         (pass (and car-graph auto-graph
                    ;; the alias is kept ...
                    (search "[CAR" car-graph)
                    (not (search "[AUTOMOBILE" car-graph))
                    ;; ... and the type's own label still says itself
                    (search "[AUTOMOBILE" auto-graph)
                    ;; same structure otherwise
                    (search "(POSS)←[GIRL" car-graph)
                    (search "(POSS)←[GIRL" auto-graph))))
    (when verbose
      (format t "~&car:        ~a~%automobile: ~a~%" car-graph auto-graph))
    (format t "~&extract-alias-headless-test: ~:[FAILED <<<~;passed~]~%" pass)
    pass))

(extract-alias-headless-test t)
