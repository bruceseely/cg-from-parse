;;; -*- Mode: LISP; Syntax: Common-lisp; Base: 10; Lowercase: Yes -*-
;;;
;;; Live ANAPHORA check: a 3rd-person SUBJECT pronoun inside an embedded
;;; that-complement corefers with the MATRIX subject.
;;;   "the man knows that he sees the dog ."
;;;     -> [KNOW]-(expr)->[MAN:#*x1] (stat)->[PROPOSITION:
;;;          [SEE]-(agnt)->[MAN:?x1] (obj)->[DOG:#]]
;;; PARSIFAL does NOT bind pronouns, so the extractor resolves this itself
;;; (anaphor-antecedent) -- but only this ONE binding-theory-safe configuration:
;;; the pronoun is the subject of an embedded complement clause, so it is free in
;;; its own clause (never a co-argument of its antecedent). A resolved pronoun
;;; becomes a :trace bound to the matrix-subject node; emit-trace then realizes the
;;; coreference across the PROPOSITION context boundary as *x/?x, exactly like a
;;; control trace. Resolution is gated by agreement:
;;;   - number + person must match (both 3rd-person singular here);
;;;   - GENDER must not clash -- he/she demand a male/female antecedent (read from
;;;     the antecedent type's canonical (sex) arc), so "the woman knows that he
;;;     sees ..." leaves `he' an indexical [PERSON: He].
;;; And binding is respected: "the man sees him ." keeps `him' indexical (it is a
;;; co-argument of `the man' in the same clause -- resolving it would be wrong).
;;; know/see/man/woman/dog are dictionary + test-type driven, so this runs strict
;;; (:error). (KNOW is the matrix verb because it is a cgraph test-type; `believe'
;;; parses the same but has no concept type.)
;;;
;;;   sbcl --non-interactive --disable-debugger \
;;;     --eval '(ql:quickload :swank)' --eval '(ql:quickload :cg-from-parse)' \
;;;     --load test/extract-anaphora-headless.lisp

(in-package :cg-from-parse)

(load (merge-pathnames "test-setup.lisp"
                       (or *load-truename* *compile-file-truename*)))
(setup-test-cgraph)

(load (merge-pathnames "system/grammar/clause-grammar.lisp"
                       (asdf:system-source-directory :parsifal)))
(pa::load-full-grammar)

(defun %anaphora-graph (sentence &optional (on-missing :error))
  "Parse SENTENCE, return its formatted CG upcased with spaces removed, or NIL."
  (when (pa::parse-sentence sentence
                            :initial-rule (intern "INITIAL-RULE" :parsifal))
    (let ((*on-missing-type* on-missing))
      (handler-bind ((warning #'muffle-warning))
        (let ((text (ignore-errors (cg::format-cgraph (ir->cgraph (parse->ir pa::c))))))
          (values (and (stringp text) (remove #\Space (string-upcase text)))
                  text))))))

(defun extract-anaphora-headless-test (&optional (verbose t))
  (let ((he    (%anaphora-graph "the man knows that he sees the dog ."))   ; subj resolve
        (she   (%anaphora-graph "the woman knows that she sees the dog ."))  ; subj resolve
        (obj   (%anaphora-graph "the man knows that the dog sees him ."))    ; OBJ resolve
        (plur  (%anaphora-graph "the men know that the dog sees them ."))    ; plural OBJ resolve
        (two   (%anaphora-graph "the man knows that he sees him ."))         ; two pronouns (safe)
        (clash (%anaphora-graph "the woman knows that he sees the dog ."))   ; gender clash
        (same  (%anaphora-graph "the man sees him ."))                       ; same clause
        (plain (%anaphora-graph "the man knows that the boy sees the dog ."))); no pronoun
    (let ((pass (and he she obj plur two clash same plain
                     ;; he -> the man: [MAN] appears as BOTH a defining (#*x) and a
                     ;; bound (?x) coreferring occurrence; no indexical [PERSON:He].
                     (search "KNOW" he)
                     (search "[MAN:#*X" he) (search "→[MAN:?X" he)
                     (not (search "PERSON:HE" he))
                     ;; she -> the woman, likewise
                     (search "[WOMAN:#*X" she) (search "→[WOMAN:?X" she)
                     (not (search "PERSON:SHE" she))
                     ;; OBJECT pronoun `him' -> the man (cross-clause, binding-safe):
                     ;; MAN is both defining (#*x) and the bound object (?x).
                     (search "[MAN:#*X" obj) (search "(OBJ)→[MAN:?X" obj)
                     (search "(AGNT)→[DOG" obj) (not (search "PERSON:HIM" obj))
                     ;; plural OBJECT `them' -> the men ([MAN:{}*x] plural defining)
                     (search "[MAN:{}*X" plur) (search "(OBJ)→[MAN:?X" plur)
                     (not (search "PERSON:THEM" plur))
                     ;; two pronouns: `he' resolves to the man, but `him' must stay
                     ;; free (else he = him) -- Principle B inside the embedded clause.
                     (search "(AGNT)→[MAN:?X" two) (search "(OBJ)→[PERSON:HE" two)
                     ;; gender clash: `he' NOT resolved -> stays [PERSON: He]; the
                     ;; woman is left with no coreference variable.
                     (search "→[PERSON:HE" clash)
                     (not (search "WOMAN:?X" clash)) (not (search "WOMAN:#*X" clash))
                     ;; same clause (Principle B): `him' NOT resolved to the man
                     (search "(AGNT)→[MAN:#" same) (search "(OBJ)→[PERSON:HE" same)
                     (not (search "?X" same)) (not (search "*X" same))
                     ;; control: no pronoun -> ordinary complement, boy unchanged
                     (search "→[BOY:#]" plain) (not (search "?X" plain)))))
      (when verbose
        (format t "~&he:    ~a~%she:   ~a~%clash: ~a~%same:  ~a~%plain: ~a~%"
                he she clash same plain))
      (format t "~&extract-anaphora-headless-test: ~:[FAILED <<<~;passed~]~%" pass)
      pass)))

(extract-anaphora-headless-test)
