;;; -*- Mode: LISP; Syntax: Common-lisp; Base: 10; Lowercase: Yes -*-
;;;
;;; Live check of the parse-failure diagnosis: a sentence PARSIFAL cannot parse
;;; must come back with a REPORT (which word it stalled on, what fired, what
;;; could have fired), not just a bare "could not parse" -- and the same report
;;; must ride along with parse-and-extract's error.
;;;
;;; The two failures exercised are the two kinds:
;;;   * a MISSING GRAMMAR RULE -- "the girl is eating pie ." (no progressive
;;;     rule in BUILD-AUX, so aux-complete/main-verb take `is' as the verb and
;;;     `eating' is stranded);
;;;   * a MISSING WORD -- read-sentence drops what the lexicon lacks, and the
;;;     report has to say so rather than blaming the grammar.
;;;
;;;   sbcl --non-interactive --disable-debugger \
;;;     --eval '(ql:quickload :swank)' --eval '(ql:quickload :cg-from-parse)' \
;;;     --load test/extract-diagnose-headless.lisp

(in-package :cg-from-parse)

(load (merge-pathnames "test-setup.lisp"
                       (or *load-truename* *compile-file-truename*)))
(setup-test-cgraph)

(defun extract-diagnose-headless-test (&optional (verbose t))
  (handler-bind ((warning #'muffle-warning))
    (let* (;; --- a construction the grammar has no rule for ---
           (rule-gap (with-output-to-string (s)
                       (diagnose-parse "the girl is eating pie ." :stream s)))
           ;; --- a word the lexicon does not have ---
           (word-gap (with-output-to-string (s)
                       (diagnose-parse "the girl zorks pie ." :stream s)))
           ;; --- a sentence that DOES parse: no report, and T ---
           (parsed nil)
           (good (with-output-to-string (s)
                   (setf parsed (diagnose-parse "the girl eats pie ." :stream s))))
           ;; --- the same report reaches the caller through the error ---
           (err (handler-case (progn (parse-and-extract "the girl is eating pie .") nil)
                  (error (e) (princ-to-string e))))
           (pass (and (search "PARSE FAILED" rule-gap)
                      ;; morphology line: surface -> root
                      (search "eating" rule-gap)
                      (search "-> eat" rule-gap)
                      ;; the stall point and the rules that led there
                      (search "no rule matched: eating" rule-gap)
                      (search "main-verb" rule-gap)
                      (search "active packets" rule-gap)
                      ;; a missing word is called out as such
                      (search "NOT IN THE LEXICON" word-gap)
                      (search "zorks" word-gap)
                      ;; a good parse returns T and reports no failure
                      parsed
                      (search "parsed:" good)
                      (not (search "PARSE FAILED" good))
                      ;; and parse-and-extract's error carries the report
                      err (search "could not parse" err)
                      (search "no rule matched: eating" err)
                      (search "diagnose-parse" err))))
      (when verbose
        (format t "~&--- (diagnose-parse \"the girl is eating pie .\") ---~%~a" rule-gap)
        (format t "~&--- unknown word: first lines of the report ---~%~{~a~%~}"
                (subseq (uiop:split-string word-gap :separator '(#\Newline)) 0 8)))
      (format t "~&extract-diagnose-headless-test: ~:[FAILED <<<~;passed~]~%" pass)
      pass)))

(extract-diagnose-headless-test)
