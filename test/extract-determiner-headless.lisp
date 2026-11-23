;;; -*- Mode: LISP; Syntax: Common-lisp; Base: 10; Lowercase: Yes -*-
;;;
;;; Live determiner/definiteness check: "the man gives the woman a book ."
;;; A definite NP ("the") gets a numbered individual of the discourse ([X: #3],
;;; system/discourse.lisp); an indefinite NP ("a") stays bare ([X]). So
;;; man/woman -> [MAN: #3]/[WOMAN: #4], book -> [BOOK].
;;;
;;;   sbcl --non-interactive --disable-debugger \
;;;     --eval '(ql:quickload :swank)' --eval '(ql:quickload :cg-from-parse)' \
;;;     --load test/extract-determiner-headless.lisp

(in-package :cg-from-parse)

(load (merge-pathnames "test-setup.lisp"
                       (or *load-truename* *compile-file-truename*)))
(setup-test-cgraph)

(load (merge-pathnames "system/grammar/clause-grammar.lisp"
                       (asdf:system-source-directory :parsifal)))
(pa::load-full-grammar)

(defun extract-determiner-headless-test
    (&optional (sentence "the man gives the woman a book .") (verbose t))
  (let ((ok (pa::parse-sentence sentence
                                :initial-rule (intern "INITIAL-RULE" :parsifal))))
    (cond
      ((not ok)
       (format t "~&extract-determiner-headless-test: parse FAILED for ~s <<<~%" sentence)
       nil)
      (t
       (let* ((graph (ir->cgraph (parse->ir pa::c)))
              (text  (ignore-errors (cg::format-cgraph graph)))
              (up    (and (stringp text) (string-upcase text)))
              ;; Space-stripped, so the assertions do not depend on *concise*.
              (flat  (and up (remove #\Space up)))
              ;; the man + the woman -> two definite "#" referents; a book -> bare.
              ;; Named per-NP rather than counted: the PREDICATE now carries an
              ;; individual marker of its own (event individuation), so a global
              ;; count of "#" no longer says anything about the noun phrases.
              ;; ... and a definite is a NUMBERED individual of the discourse
              ;; ([MAN: #3], discourse.lisp), never the bare # any more.
              (norm  (and flat (without-individual-ids flat)))
              (pass  (and flat
                          (search "[MAN:#]"   norm) (not (search "[MAN:#]"   flat))
                          (search "[WOMAN:#]" norm) (not (search "[WOMAN:#]" flat))
                          (search "[BOOK]"    flat)      ; a book -> bare ...
                          (not (search "[BOOK:" flat))))) ; ... no referent
         (when verbose (format t "~&sentence: ~a~%graph:~%~a~%" sentence text))
         (format t "~&extract-determiner-headless-test: ~:[FAILED <<<~;passed~]~%" pass)
         pass)))))

(extract-determiner-headless-test)
