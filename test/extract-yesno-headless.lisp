;;; -*- Mode: LISP; Syntax: Common-lisp; Base: 10; Lowercase: Yes -*-
;;;
;;; Live yes-no question check: "does the dog see the man ?"
;;; A yes-no question has the SAME propositional content as the corresponding
;;; declarative -- it asks whether that proposition holds (the only parse
;;; difference is the sentence-type feature, YNQUEST vs DECL). But it is a QUERY
;;; PATTERN, not a fact, so its event is left generic: [SEE: #3] would match
;;; only that one event. So the question extracts to exactly the graph the
;;; declarative gives as a pattern (*individuate-events* NIL), and ASK runs it.
;;;   "does the dog see the man ?"  ==  "the dog sees the man ." as a pattern
;;;     -> [SEE]-(agnt)->[DOG: #] (obj)->[MAN: #].
;;;
;;;   sbcl --non-interactive --disable-debugger \
;;;     --eval '(ql:quickload :swank)' --eval '(ql:quickload :cg-from-parse)' \
;;;     --load test/extract-yesno-headless.lisp

(in-package :cg-from-parse)

(load (merge-pathnames "test-setup.lisp"
                       (or *load-truename* *compile-file-truename*)))
(setup-test-cgraph)

(load (merge-pathnames "system/grammar/clause-grammar.lisp"
                       (asdf:system-source-directory :parsifal)))
(pa::load-full-grammar)

(defun proposition-text (sentence)
  "Extract SENTENCE and return its formatted CG (uppercased), or NIL."
  (when (pa::parse-sentence sentence :initial-rule (intern "INITIAL-RULE" :parsifal))
    (ignore-errors (string-upcase (cg::format-cgraph (ir->cgraph (parse->ir pa::c)))))))

(defun extract-yesno-headless-test (&optional (verbose t))
  (let* ((q (proposition-text "does the dog see the man ?"))
         (d (proposition-text "the dog sees the man ."))
         (p (let ((*individuate-events* nil))
              (proposition-text "the dog sees the man .")))
         (pass (and q (search "SEE" q) (search "DOG" q) (search "MAN" q)
                    (search "AGNT" q) (search "OBJ" q)
                    ;; Same content as the declarative taken as a pattern --
                    ;; identical text, no markers to strip.
                    (equal q p)
                    ;; ... and the declarative itself is still a fact: its
                    ;; event is individuated, the question's is not.
                    d (search "[SEE:#" d) (not (search "[SEE:#" q)))))
    (when verbose
      (format t "~&question:              ~a~%" q)
      (format t "~&declarative:           ~a~%" d)
      (format t "~&declarative, pattern:  ~a~%" p))
    (format t "~&extract-yesno-headless-test: ~:[FAILED <<<~;passed~]~%" pass)
    pass))

(extract-yesno-headless-test)
