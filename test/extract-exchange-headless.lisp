;;; -*- Mode: LISP; Syntax: Common-lisp; Base: 10; Lowercase: Yes -*-
;;;
;;; Commercial-transaction (exchange) frame + block renderer:
;;;   "I will gladly pay you Tuesday for a hamburger today ."
;;;
;;; A commercial verb (`pay') doesn't name a flat act -- it profiles one side of
;;; a two-sided exchange. emit-exchange (extract.lisp) promotes the flat PAY
;;; clause to Fillmore's exchange frame: an [EXCHANGE] with two reciprocal
;;; transfers linked by (has-part) --
;;;
;;;   [EXCHANGE]-
;;;     (has-part)->[GIVE]- (agnt)->[PERSON: You] (obj)->[HAMBURGER]
;;;                         (rcpt)->[PERSON: I]   (time)->[TODAY]
;;;     (has-part)->[PAY]-  (agnt)->[PERSON: I]   (rcpt)->[PERSON: You]
;;;                         (obj)->[MONEY]        (manr)->[GLADLY] (time)->[TUESDAY]
;;;
;;; -- agents SWAP (reciprocity); [MONEY] and the whole [GIVE] transfer are
;;; frame-supplied; the two times route by surface position (Tuesday before the
;;; goods -> payment; today after -> goods). render.lisp's block renderer prints
;;; each sub-event as its own block with the shared participants ([PERSON: I],
;;; [PERSON: You]) as coref leaves -- the engine's linear formatter tangles on
;;; this doubly-shared topology (see the deferral note).
;;;
;;; The exchange path emits no `exch' relation (the goods filler becomes GIVE's
;;; obj), so test-types (which lacks `exch') suffices; the missing leaf concepts
;;; (exchange/pay/money/hamburger/tuesday/today) are made under *on-missing-type*
;;; :create, as in the adverb check. pay/hamburger/gladly/tuesday/today are
;;; parsifal supplement-dict words; the frame + TIME cases are our extensions.
;;;
;;;   sbcl --non-interactive --disable-debugger \
;;;     --eval '(ql:quickload :swank)' --eval '(ql:quickload :cg-from-parse)' \
;;;     --load test/extract-exchange-headless.lisp

(in-package :cg-from-parse)

(load (merge-pathnames "test-setup.lisp"
                       (or *load-truename* *compile-file-truename*)))
(setup-test-cgraph)

(load (merge-pathnames "system/grammar/clause-grammar.lisp"
                       (asdf:system-source-directory :parsifal)))
(pa::load-full-grammar)

(defun %exchange-text (sentence &optional (on-missing :create))
  "Parse SENTENCE and return its block-rendered CG text (via cg-text), or NIL."
  (when (pa::parse-sentence sentence
                            :initial-rule (intern "INITIAL-RULE" :parsifal))
    (let ((*on-missing-type* on-missing))
      (handler-bind ((warning #'muffle-warning))
        (ignore-errors (cg-text (ir->cgraph (parse->ir pa::c))))))))

(defun extract-exchange-headless-test (&optional (verbose t))
  (let* ((text (%exchange-text
                "i will gladly pay you tuesday for a hamburger today ."))
         (flat (and (stringp text) (remove #\Space (string-upcase text))))
         ;; split the block text at [PAY so we can check each transfer's contents
         (pay-pos  (and flat (search "(HAS-PART)→[PAY" flat)))
         (give-part (and pay-pos (subseq flat 0 pay-pos)))
         (pay-part  (and pay-pos (subseq flat pay-pos)))
         (pass
          (and flat pay-pos
               ;; promoted to an EXCHANGE of two (has-part) transfers
               (search "[EXCHANGE]" flat)
               (search "(HAS-PART)→[GIVE" flat)
               (search "(HAS-PART)→[PAY" flat)
               ;; GIVE (goods) transfer: you give me the hamburger today
               (search "(OBJ)→[HAMBURGER" give-part)
               (search "(TIME)→[TODAY"    give-part)
               ;; PAY (money) transfer: I gladly pay you money on tuesday
               (search "(OBJ)→[MONEY"    pay-part)
               (search "(MANR)→[GLADLY"  pay-part)
               (search "(TIME)→[TUESDAY" pay-part)
               ;; times routed to the RIGHT transfer (not conflated onto pay)
               (not (search "TODAY"   pay-part))
               (not (search "TUESDAY" give-part))
               ;; coreference: the SAME I and You appear (coref-marked) in BOTH
               ;; transfers -- the reciprocity of the exchange
               (search "[PERSON:I*"   give-part) (search "[PERSON:I*"   pay-part)
               (search "[PERSON:YOU*" give-part) (search "[PERSON:YOU*" pay-part))))
    (when verbose (format t "~&~a~%" text))
    (format t "~&extract-exchange-headless-test: ~:[FAILED <<<~;passed~]~%" pass)
    pass))

(extract-exchange-headless-test)
