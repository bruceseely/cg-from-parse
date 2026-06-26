;;; -*- Mode: LISP; Syntax: Common-lisp; Base: 10; Lowercase: Yes -*-
;;;
;;; Live quantifier check: "all dogs see the man ." / "some dogs see the man ."
;;; A leading quantifier word maps to the concept's quantifier: all/every/each/
;;; any -> :universal, some -> :existential. Like tense/voice, the quantifier is
;;; a stored slot (concept-quantifier), NOT shown in linear form, so it's checked
;;; on the IR / slot rather than the formatted string.
;;;
;;; NB: PARSIFAL's loaded lexicon has `all'/`some'/`any' but not `every'/`each',
;;; so those are used here.
;;;
;;;   sbcl --non-interactive --disable-debugger \
;;;     --eval '(ql:quickload :swank)' --eval '(ql:quickload :cg-from-parse)' \
;;;     --load test/extract-quantifier-headless.lisp

(in-package :cg-from-parse)

(load (merge-pathnames "test-setup.lisp"
                       (or *load-truename* *compile-file-truename*)))
(setup-test-cgraph)

(load (merge-pathnames "test/integration/clause-grammar.lisp"
                       (asdf:system-source-directory :parsifal)))
(pa::load-full-grammar)

(defun concept-of-type (graph type-name)
  "The first concept in GRAPH whose type label is TYPE-NAME (a string)."
  (find-if (lambda (n)
             (and (typep n 'cg::concept)
                  (string-equal (string (cg::label (cg::concept-type n))) type-name)))
           (cg::collect-nodes (cg::head graph))))

(defun subject-quantifier (sentence)
  "Parse SENTENCE, extract, and return (values reader-quantifier concept-quantifier)
for the agent DOG NP -- so we check both the IR and the emitted concept slot."
  (when (pa::parse-sentence sentence :initial-rule (intern "INITIAL-RULE" :parsifal))
    (let* ((ir   (parse->ir pa::c))
           (agnt (find 'pa::agt (getf ir :cases) :key (lambda (c) (getf c :role))))
           (ir-q (getf (getf agnt :filler) :quantifier))
           (graph (ir->cgraph ir))
           (dog   (concept-of-type graph "DOG")))
      (values ir-q (and dog (cg::concept-quantifier dog))))))

(defun extract-quantifier-headless-test (&optional (verbose t))
  (multiple-value-bind (u-ir u-slot) (subject-quantifier "all dogs see the man .")
    (multiple-value-bind (e-ir e-slot) (subject-quantifier "some dogs see the man .")
      (let ((pass (and (eq u-ir :universal)   (eq u-slot :universal)
                       (eq e-ir :existential) (eq e-slot :existential))))
        (when verbose
          (format t "~&all  dogs -> IR ~s / slot ~s~%" u-ir u-slot)
          (format t "~&some dogs -> IR ~s / slot ~s~%" e-ir e-slot))
        (format t "~&extract-quantifier-headless-test: ~:[FAILED <<<~;passed~]~%" pass)
        pass))))

(extract-quantifier-headless-test)
