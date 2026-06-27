;;; -*- Mode: LISP; Syntax: Common-lisp; Base: 10; Lowercase: Yes -*-
;;;
;;; Live yes-no question check: "does the dog see the man ?"
;;; A yes-no question has the SAME propositional content as the corresponding
;;; declarative -- it asks whether that proposition holds. So it extracts to the
;;; identical graph (the only parse difference is the sentence-type feature,
;;; YNQUEST vs DECL); semantically it's that proposition used as a boolean /
;;; existence query (run it through cgraph's query engine against a KB).
;;;   "does the dog see the man ?"  ==  "the dog sees the man ."
;;;     -> [SEE]-(agnt)->[DOG: #] (obj)->[MAN: #].
;;;
;;;   sbcl --non-interactive --disable-debugger \
;;;     --eval '(ql:quickload :swank)' --eval '(ql:quickload :cg-from-parse)' \
;;;     --load test/extract-yesno-headless.lisp

(in-package :cg-from-parse)

(load (merge-pathnames "test-setup.lisp"
                       (or *load-truename* *compile-file-truename*)))
(setup-test-cgraph)

(load (merge-pathnames "test/integration/clause-grammar.lisp"
                       (asdf:system-source-directory :parsifal)))
(pa::load-full-grammar)

(defun proposition-text (sentence)
  "Extract SENTENCE and return its formatted CG (uppercased), or NIL."
  (when (pa::parse-sentence sentence :initial-rule (intern "INITIAL-RULE" :parsifal))
    (ignore-errors (string-upcase (cg::format-cgraph (ir->cgraph (parse->ir pa::c)))))))

(defun extract-yesno-headless-test (&optional (verbose t))
  (let* ((q (proposition-text "does the dog see the man ?"))
         (d (proposition-text "the dog sees the man ."))
         (pass (and q (search "SEE" q) (search "DOG" q) (search "MAN" q)
                    (search "AGNT" q) (search "OBJ" q)
                    (equal q d))))   ; yes-no question == declarative proposition
    (when verbose
      (format t "~&question:    ~a~%" q)
      (format t "~&declarative: ~a~%" d))
    (format t "~&extract-yesno-headless-test: ~:[FAILED <<<~;passed~]~%" pass)
    pass))

(extract-yesno-headless-test)
