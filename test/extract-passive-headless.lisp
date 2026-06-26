;;; -*- Mode: LISP; Syntax: Common-lisp; Base: 10; Lowercase: Yes -*-
;;;
;;; Live passive check: "a meeting seems to have been scheduled ."
;;; PARSIFAL has no copular "was"/agentive "by", so the available passive is the
;;; agentless participle inside a perfect infinitive. Its case frame already puts
;;; the logical object (the meeting) in NEUT with no agent -- so roles need no
;;; new code; what's new is VOICE: the embedded "scheduled" is a passive
;;; participle, so the reader marks that clause :voice :passive and the emitter
;;; sets concept-voice on it. (Voice, like tense, isn't shown in linear form, so
;;; it's checked on the IR / concept slot.)
;;;
;;;   sbcl --non-interactive --disable-debugger \
;;;     --eval '(ql:quickload :swank)' --eval '(ql:quickload :cg-from-parse)' \
;;;     --load test/extract-passive-headless.lisp

(in-package :cg-from-parse)

(load (merge-pathnames "test-setup.lisp"
                       (or *load-truename* *compile-file-truename*)))
(setup-test-cgraph)

(load (merge-pathnames "test/integration/clause-grammar.lisp"
                       (asdf:system-source-directory :parsifal)))
(pa::load-full-grammar)

(defun extract-passive-headless-test
    (&optional (sentence "a meeting seems to have been scheduled .") (verbose t))
  (let ((ok (pa::parse-sentence sentence
                                :initial-rule (intern "INITIAL-RULE" :parsifal))))
    (cond
      ((not ok)
       (format t "~&extract-passive-headless-test: parse FAILED for ~s <<<~%" sentence)
       nil)
      (t
       (let* ((*on-missing-type* :create)
              (ir          (parse->ir pa::c))
              (matrix-voice (getf ir :voice))                      ; SEEM: active
              (embedded     (getf (first (getf ir :cases)) :filler)) ; SCHEDULE clause
              (emb-voice    (getf embedded :voice))                ; passive
              ;; build the graph too, to confirm emission handles it
              (graph (handler-bind ((warning #'muffle-warning)) (ir->cgraph ir)))
              (pass  (and graph
                          (null matrix-voice)        ; matrix verb is active
                          (eq emb-voice :passive)    ; embedded participle is passive
                          (eq (getf embedded :pred) 'pa::schedule))))
         (when verbose
           (format t "~&sentence:       ~a~%" sentence)
           (format t "~&matrix voice:   ~s   embedded (~a) voice: ~s~%"
                   matrix-voice (getf embedded :pred) emb-voice))
         (format t "~&extract-passive-headless-test: ~:[FAILED <<<~;passed~]~%" pass)
         pass)))))

(extract-passive-headless-test)
