;;; -*- Mode: LISP; Syntax: Common-lisp; Base: 10; Lowercase: Yes -*-
;;;
;;; Live genitive/possessive check: "the man 's dog sees the woman ."
;;; PARSIFAL now parses genitives (parsifal *genitive-rules*: POSS-NP attaches the
;;; possessive clitic `'s to a completed NP and re-labels it a poss-np;
;;; POSSESSIVE-DET wraps that poss-np in a POSS-DET determiner of the head noun).
;;; The extractor reads the possessor off the head NP's poss-det (np-possessor)
;;; and emits [POSSESSOR]->(poss)->[NOUN] -- the possessor is the ANIMATE source,
;;; the possessed noun the ENTITY dest (cgraph `poss': ANIMATE -> ENTITY). So:
;;;   [SEE]-(agnt)->[DOG: #]<-(poss)<-[MAN: #] (obj)->[WOMAN: #].
;;; (i.e. MAN->(poss)->DOG: the man possesses the dog.) man/dog/woman/see are all
;;; in test-types, so this runs strict (:error) -- MAN really is the ontology's
;;; ANIMATE-conforming type, not invented.
;;;
;;; Also exercises a PROPER-NAME possessor ("mitch 's dog" -> [DOG]<-(poss)<-
;;; [PERSON: Mitch]); mitch is in the dict. (A possessive pronoun "my dog" ->
;;; [DOG]<-(poss)<-[PERSON: I] works too, but "I" isn't in test-types so it needs
;;; :create; kept out of the strict assertion.)
;;;
;;;   sbcl --non-interactive --disable-debugger \
;;;     --eval '(ql:quickload :swank)' --eval '(ql:quickload :cg-from-parse)' \
;;;     --load test/extract-genitive-headless.lisp

(in-package :cg-from-parse)

(load (merge-pathnames "test-setup.lisp"
                       (or *load-truename* *compile-file-truename*)))
(setup-test-cgraph)

(load (merge-pathnames "system/grammar/clause-grammar.lisp"
                       (asdf:system-source-directory :parsifal)))
(pa::load-full-grammar)

(defun %genitive-graph (sentence &optional (on-missing :error))
  "Parse SENTENCE, return its formatted CG upcased with spaces removed, or NIL."
  (when (pa::parse-sentence sentence
                            :initial-rule (intern "INITIAL-RULE" :parsifal))
    (let ((*on-missing-type* on-missing))
      (handler-bind ((warning #'muffle-warning))
        (let ((text (ignore-errors (cg::format-cgraph (ir->cgraph (parse->ir pa::c))))))
          (values (and (stringp text) (remove #\Space (string-upcase text)))
                  text))))))

(defun extract-genitive-headless-test (&optional (verbose t))
  (multiple-value-bind (common text1) (%genitive-graph "the man 's dog sees the woman .")
    (multiple-value-bind (named text2) (%genitive-graph "mitch 's dog sees the woman .")
      (let ((pass (and common named
                       ;; common-noun possessor: [DOG]<-(poss)<-[MAN]
                       (search "SEE" common) (search "WOMAN" common)
                       (search "(AGNT)→[DOG" common)
                       (search "[DOG:#]←(POSS)←[MAN" common)
                       ;; proper-name possessor: [DOG]<-(poss)<-[PERSON:Mitch]
                       (search "[DOG:#]←(POSS)←[PERSON:MITCH" named))))
        (when verbose
          (format t "~&common-noun genitive:~%~a~%proper-name genitive:~%~a~%"
                  text1 text2))
        (format t "~&extract-genitive-headless-test: ~:[FAILED <<<~;passed~]~%" pass)
        pass))))

(extract-genitive-headless-test)
