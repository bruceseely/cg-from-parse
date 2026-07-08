;;; -*- Mode: LISP; Syntax: Common-lisp; Base: 10; Lowercase: Yes -*-
;;;
;;; Live manner-adverb check: "the man sees the dog quickly ."
;;; A manner adverb is the adverbial analog of an adjective: where an adjective
;;; modifies its noun ([NOUN]-(attr)->[ADJ]), a manner adverb modifies the
;;; predicate ([PRED]-(manr)->[MANNER]). This needed BOTH sides of an extension:
;;;   - lexicon: quickly/slowly added to parsifal's supplement.dict as `(adv
;;;     manner)' -- manner adverbs were not in Marcus's dictionary (dropped as
;;;     unknown), and his own `df1' adverbs are commented-out/inert.
;;;   - grammar: the ADVERB-ADJUNCT rule (parsifal *adverb-rules*, our
;;;     *grammar-extensions*) attaches the adverb as an `adv' daughter of the
;;;     clause -- gram1-gram5 have no adverb-attachment rule, so without it the
;;;     adverb stalls the parse.
;;; The extractor reads the clause's `adv' daughters (clause-adverb-lemmas) and
;;; emits [PRED]-(manr)->[MANNER] via emit-modifier:
;;;   [SEE]-(agnt)->[MAN: #] (obj)->[DOG: #] (manr)->[QUICKLY].
;;; `quickly' isn't in test-types, so this runs with *on-missing-type* :create
;;; (QUICKLY is created under MANNER, the manr relation's dest) -- exactly as the
;;; adjective check creates BIG under ATTRIBUTE. man/dog/see are dictionary-driven.
;;;
;;;   sbcl --non-interactive --disable-debugger \
;;;     --eval '(ql:quickload :swank)' --eval '(ql:quickload :cg-from-parse)' \
;;;     --load test/extract-adverb-headless.lisp

(in-package :cg-from-parse)

(load (merge-pathnames "test-setup.lisp"
                       (or *load-truename* *compile-file-truename*)))
(setup-test-cgraph)

(load (merge-pathnames "system/grammar/clause-grammar.lisp"
                       (asdf:system-source-directory :parsifal)))
(pa::load-full-grammar)

(defun %adverb-graph (sentence &optional (on-missing :create))
  "Parse SENTENCE, return its formatted CG upcased with spaces removed, or NIL."
  (when (pa::parse-sentence sentence
                            :initial-rule (intern "INITIAL-RULE" :parsifal))
    (let ((*on-missing-type* on-missing))
      (handler-bind ((warning #'muffle-warning))
        (let ((text (ignore-errors (cg::format-cgraph (ir->cgraph (parse->ir pa::c))))))
          (values (and (stringp text) (remove #\Space (string-upcase text)))
                  text))))))

(defun extract-adverb-headless-test (&optional (verbose t))
  (multiple-value-bind (adv text1) (%adverb-graph "the man sees the dog quickly .")
    (multiple-value-bind (plain text2) (%adverb-graph "the man sees the dog .")
      (let ((pass (and adv plain
                       ;; manner adverb -> (manr)->[QUICKLY]
                       (search "SEE" adv) (search "(AGNT)→[MAN" adv)
                       (search "(OBJ)→[DOG" adv) (search "(MANR)→[QUICKLY" adv)
                       ;; control: no adverb -> no manr arc, still a clean parse
                       (search "SEE" plain) (not (search "MANR" plain)))))
        (when verbose
          (format t "~&with adverb:~%~a~%without:~%~a~%" text1 text2))
        (format t "~&extract-adverb-headless-test: ~:[FAILED <<<~;passed~]~%" pass)
        pass))))

(extract-adverb-headless-test)
