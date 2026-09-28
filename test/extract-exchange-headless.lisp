;;; -*- Mode: LISP; Syntax: Common-lisp; Base: 10; Lowercase: Yes -*-
;;;
;;; Commercial-transaction (exchange) frame + block renderer:
;;;   "I will gladly pay you Tuesday for a hamburger today ."
;;;
;;; A commercial verb (`pay') doesn't name a flat act -- it profiles one side of
;;; a two-sided exchange. emit-exchange (extract.lisp) promotes the flat PAY
;;; clause to Fillmore's exchange frame: an [EXCHANGE] with two reciprocal
;;; transfers linked by (part) --
;;;
;;;   [EXCHANGE]-
;;;     (part)->[GIVE]- (agnt)->[PERSON: You] (obj)->[HAMBURGER]
;;;                         (rcpt)->[PERSON: I]   (time)->[TODAY]
;;;     (part)->[PAY]-  (agnt)->[PERSON: I]   (rcpt)->[PERSON: You]
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

(defun %exchange-graph (sentence &optional (on-missing :create))
  "Parse SENTENCE and return its extracted cgraph graph, or NIL."
  (when (pa::parse-sentence sentence
                            :initial-rule (intern "INITIAL-RULE" :parsifal))
    (let ((*on-missing-type* on-missing))
      (handler-bind ((warning #'muffle-warning))
        (ignore-errors (ir->cgraph (parse->ir pa::c)))))))

(defun extract-exchange-headless-test (&optional (verbose t))
  (let* ((graph (%exchange-graph
                 "i will gladly pay you tuesday for a hamburger today ."))
         (text (and graph (cg-text graph)))
         ;; the value RETURNED by parse-and-extract prints via print-object; it
         ;; must route through the block renderer, i.e. equal (cg-text graph)
         (printed (and graph (let ((cg::*always-format-nodes* t))
                               (princ-to-string graph))))
         (flat (and (stringp text) (remove #\Space (string-upcase text))))
         ;; split the block text at [PAY so we can check each transfer's contents
         (pay-pos  (and flat (search "(PART)→[PAY" flat)))
         (give-part (and pay-pos (subseq flat 0 pay-pos)))
         (pay-part  (and pay-pos (subseq flat pay-pos)))
         ;; RECONCILIATION: the same sentence with the goods transfer stated
         ;; EXPLICITLY as a relative clause ("a hamburger you give me today")
         ;; must fold into the SAME single goods transfer -- render identically,
         ;; with exactly one GIVE (not a duplicate of the synthesized one)
         (rel-graph (%exchange-graph
                     "i will gladly pay you tuesday for a hamburger you give me today ."))
         (rel-text  (and rel-graph (cg-text rel-graph)))
         (rel-gives (and rel-graph
                         (count "GIVE"
                                (remove nil
                                        (mapcar (lambda (n)
                                                  (and (typep n 'cg::concept)
                                                       (string (cg::label (cg::concept-type n)))))
                                                (cg::nodes rel-graph)))
                                :test #'string-equal)))
         ;; FILLMORE PERSPECTIVE PAYOFF: pay/buy/sell are three surface framings
         ;; of ONE commercial event, so all three must render as the SAME
         ;; [EXCHANGE] (buyer=I, seller=you, goods=hamburger, money implicit)
         (pay-x  (let ((g (%exchange-graph "i pay you for a hamburger ."))) (and g (cg-text g))))
         (buy-x  (let ((g (%exchange-graph "i buy a hamburger from you ."))) (and g (cg-text g))))
         (sell-x (let ((g (%exchange-graph "you sell me a hamburger ."))) (and g (cg-text g))))
         (pass
          (and flat pay-pos
               ;; promoted to a COMMERCIAL-EXCHANGE of two (part) transfers
               ;; the frame concept is an event, so it carries its own marker
               (search "[COMMERCIAL-EXCHANGE:#" flat)
               (search "(PART)→[GIVE" flat)
               (search "(PART)→[PAY" flat)
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
               (search "[PERSON:YOU*" give-part) (search "[PERSON:YOU*" pay-part)
               ;; CG linear form: the first sub-event block ends with a branch
               ;; comma (after [TODAY]) separating it from the PAY block
               (search "[TODAY]," give-part)
               ;; parse-and-extract's returned graph PRINTS as the block form
               (equal text printed)
               ;; reconciliation: explicit-transfer version renders identically
               ;; to the inferred one, and has exactly ONE give (no duplicate)
               (equal (without-individual-ids rel-text)
                      (without-individual-ids text))
               (eql rel-gives 1)
               ;; perspective payoff: buy and sell yield the SAME exchange as pay
               (stringp pay-x)
               ;; modulo markers: three separate extractions, three counters
               (equal (without-individual-ids buy-x)  (without-individual-ids pay-x))
               (equal (without-individual-ids sell-x) (without-individual-ids pay-x)))))
    (when verbose (format t "~&~a~%" text))
    (format t "~&extract-exchange-headless-test: ~:[FAILED <<<~;passed~]~%" pass)
    pass))

(extract-exchange-headless-test)
