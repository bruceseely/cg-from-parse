;;; -*- Mode: LISP; Syntax: Common-lisp; Base: 10; Lowercase: Yes -*-
;;;
;;; ROUND-TRIP fidelity: English -> conceptual graph -> English. The extractor and
;;; cgraph's realizer (say) are separate halves; this gates their consistency, so a
;;; change to extraction that the realizer can't verbalize faithfully is caught.
;;; sentence->say realizes coreference-aware (say-graph binds *anaphora-cross-coref*),
;;; so the coreference the extractor encodes for a resolved pronoun ([MAN:?x] bound to
;;; [MAN:*x]) comes back as a PRONOUN, not a fresh NP:
;;;   "the man knows that he sees the dog ."   -> "...he sees the dog"   (not "a man")
;;;   "the man knows that the dog sees him ."  -> "...the dog sees him"  (not "a man")
;;; Plain clauses round-trip verbatim. Assertions are on the downcased text (articles
;;; and capitalization are the realizer's business); the point is that coreference and
;;; the clause survive the round trip.
;;;
;;; INFINITIVAL complements now round-trip too ("the boy wants to go ." -> "The boy
;;; wants to go."): the extractor wraps them as (prop)->[SITUATION:[GO]...], and the
;;; cgraph realizer renders a SITUATION complement as a 'to <verb>' infinitive (a
;;; PROPOSITION stays a 'that'-clause). This was previously dropped -- `prop' was
;;; unmapped in the realizer's syntax table -- exactly the extractor/realizer
;;; mismatch this round-trip gate exists to catch.
;;;
;;;   sbcl --non-interactive --disable-debugger \
;;;     --eval '(ql:quickload :swank)' --eval '(ql:quickload :cg-from-parse)' \
;;;     --load test/extract-roundtrip-headless.lisp

(in-package :cg-from-parse)

(load (merge-pathnames "test-setup.lisp"
                       (or *load-truename* *compile-file-truename*)))
(setup-test-cgraph)

(defun %say (sentence)
  "Round-trip SENTENCE to text (downcased), or NIL on failure. Uses :create so
out-of-test-type verbs (want) resolve -- this gates REALIZATION fidelity, not typing."
  (handler-bind ((warning #'muffle-warning))
    (let ((text (ignore-errors (sentence->say sentence :on-missing :create))))
      (and (stringp text) (string-downcase text)))))

(defun extract-roundtrip-headless-test (&optional (verbose t))
  (let ((subj  (%say "the man knows that he sees the dog ."))    ; coref subject pronoun
        (obj   (%say "the man knows that the dog sees him ."))   ; coref object pronoun
        (plain (%say "the man sees the dog ."))                  ; no coref, verbatim
        (two   (%say "the man knows that he sees the woman ."))   ; coref + distinct NP
        (inf   (%say "the boy wants to go .")))                   ; infinitival complement
    (let ((pass (and subj obj plain two inf
                     ;; subject pronoun survives; the embedded subject is NOT re-nouned
                     (search "he sees the dog" subj)
                     (not (search "a man" subj))
                     ;; object pronoun survives as "him", not "a man"
                     (search "the dog sees him" obj)
                     (not (search "a man" obj))
                     ;; plain clause round-trips faithfully
                     (search "the man sees the dog" plain)
                     ;; coref pronoun + a genuinely distinct NP (the woman) coexist
                     (search "he sees the woman" two)
                     (not (search "a man" two))
                     ;; infinitival complement -> "to go" (not dropped, not "that")
                     (search "wants to go" inf)
                     (not (search "that" inf)))))
      (when verbose
        (format t "~&subj:  ~a~%obj:   ~a~%plain: ~a~%two:   ~a~%inf:   ~a~%"
                subj obj plain two inf))
      (format t "~&extract-roundtrip-headless-test: ~:[FAILED <<<~;passed~]~%" pass)
      pass)))

(extract-roundtrip-headless-test)
