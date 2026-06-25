;;; -*- Mode: LISP; Syntax: Common-lisp; Base: 10; Lowercase: Yes -*-
;;;
;;; Live ditransitive check: double-object "the man gives the woman the book ."
;;; give fills three thematic cases -- AGT (subj), DAT (1st object = recipient),
;;; NEUT (2nd object = theme) -- which map to agnt / rcpt / obj. All of
;;; give/man/woman/book are in test-types, so this runs under strict :error.
;;;
;;;   sbcl --non-interactive --disable-debugger \
;;;     --eval '(ql:quickload :swank)' --eval '(ql:quickload :cg-from-parse)' \
;;;     --load test/extract-ditransitive-headless.lisp

(in-package :cg-from-parse)

(load (merge-pathnames "test-setup.lisp"
                       (or *load-truename* *compile-file-truename*)))
(setup-test-cgraph)

(load (merge-pathnames "test/integration/clause-grammar.lisp"
                       (asdf:system-source-directory :parsifal)))
(pa::reset-rule-table)
;; *pp-rules* lets the prepositional-dative form ("... to the woman") parse too.
(pa::register-grammar pa::*np-rules* pa::*clause-rules* pa::*vp-np-rule*
                      pa::*pronoun-rule* pa::*pp-rules*)

(defun ditransitive-graph-ok (sentence verbose)
  "Parse SENTENCE and check it extracts give with agent=man, recipient=woman,
theme=book -- regardless of double-object vs prepositional-dative surface form."
  (let ((ok (pa::parse-sentence sentence
                                :initial-rule (intern "INITIAL-RULE" :parsifal))))
    (cond
      ((not ok) (format t "~&  parse FAILED for ~s <<<~%" sentence) nil)
      (t
       (let* ((graph (ir->cgraph (parse->ir pa::c)))
              (text  (ignore-errors (cg::format-cgraph graph)))
              (up    (and (stringp text) (string-upcase text)))
              (pass  (and graph (typep graph 'cg::graph) up
                          (search "GIVE" up)
                          (search "AGNT" up) (search "MAN"   up)   ; agent
                          (search "RCPT" up) (search "WOMAN" up)   ; recipient
                          (search "OBJ"  up) (search "BOOK"  up)))) ; theme
         (when verbose (format t "~&  ~a~%    ~a~%" sentence
                               (substitute #\Space #\Newline (or text ""))))
         pass)))))

(defun extract-ditransitive-headless-test (&optional (verbose t))
  ;; Both surface forms must yield the same agnt/rcpt/obj graph: the double
  ;; object, and the prepositional dative (give's `to' PP fills the DAT case).
  (let ((pass (and (ditransitive-graph-ok "the man gives the woman the book ." verbose)
                   (ditransitive-graph-ok "the man gives the book to the woman ." verbose))))
    (format t "~&extract-ditransitive-headless-test: ~:[FAILED <<<~;passed~]~%" pass)
    pass))

(extract-ditransitive-headless-test)
