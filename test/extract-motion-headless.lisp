;;; -*- Mode: LISP; Syntax: Common-lisp; Base: 10; Lowercase: Yes -*-
;;;
;;; Live MOTION check: origin, destination, and place names.
;;;
;;;   "dave drives a car from Baltimore to Boston ."
;;;     -> [DRIVE]- (agnt)->[PERSON: Dave] (dest)->[PLACE: Boston]
;;;                 (inst)->[CAR] (src)->[CITY: Baltimore]
;;;   "dave drives zelda from Baltimore to Boston ."
;;;     -> ... (obj)->[WOMAN: Zelda] ...
;;;
;;; Three things were wrong, and the second hid the first:
;;;
;;;  1. `pfrom', Marcus's origin case, mapped to no relation (there was none
;;;     that fit); it now maps to `src', added to the type sets for it.
;;;  2. A PP the verb's frame does not license sends PARSIFAL's frame-fitting to
;;;     the clause for EVERY PP, and the extractor had no relation for a loose
;;;     to/from -- so one phrase that did not fit lost the one that did, and the
;;;     two warnings saying so were SIMPLE-WARNINGs, which a common init-file
;;;     setting muffles. Loose to/from now fall back to dest/src, and what is
;;;     still dropped is reported with a DROPPED-PHRASE-WARNING.
;;;  3. A place name ("Boston", Marcus's `chicago' class) became a TYPE,
;;;     [BOSTON]. It is now a named individual, [PLACE: Boston] -- or, when its
;;;     lexicon entry names a kind of place among its features (`city'),
;;;     [CITY: Baltimore]. A person's name is refined the same way (`woman').
;;;
;;; And what fills drive's object: a vehicle is the INSTRUMENT, (inst), a person
;;; the one driven, (obj) -- DRIVE's canonical graph. One frame does both:
;;; `(*obj ins)' lets the object try `ins' as well as the first open case, and
;;; the markers decide -- ins takes only the inanimate, and drive's own `neut'
;;; list only humans. (neut) must be optional, or "drives a car" leaves an
;;; obligatory slot empty; (ins) too, or "drives zelda" drops her.
;;;
;;; Runs in a fresh environment on cgraph's test types, so the shared test
;;; catalog is untouched.
;;;
;;; Invocation:
;;;   sbcl --noinform --non-interactive \
;;;     --eval '(ql:quickload :cg-from-parse)' \
;;;     --load test/extract-motion-headless.lisp

(in-package :cg-from-parse)

(load (merge-pathnames "test-setup.lisp"
                       (or *load-truename* *compile-file-truename*)))
(setup-test-cgraph)

;; The words a domain lexicon would give: drive with an origin and a
;; destination (as cgraph-types' lexicon.dict now does), a verb with only a
;; destination (for the fallback), and a place name of our own.
(let ((*package* (find-package :parsifal)))
  (dolist (form '("(df drive feats (mainverb pres tnsless v-3s) cf ((*obj ins) (neut) (ins) (pfrom) (pto) agt) neut (|#| hanim |#|) markers act)"
                  "(df haul feats (mainverb pres tnsless v-3s) cf (neut (pto) agt) markers act)"
                  "(df baltimore feats (noun ns n3p propnoun place city) markers (place))"
                  ;; a person's name that says which kind of person
                  "(df zelda feats (noun ns n3p propnoun name woman) markers (hanim))"
                  ;; the kind of place INSTEAD of the `place' feature: the
                  ;; marker still says it is a place
                  "(df gotham feats (noun ns n3p propnoun city) markers (place))"
                  ;; a place name with a feature naming no kind of PLACE
                  "(df oz feats (noun ns n3p propnoun place girl) markers (place))"
                  "(jlike car block)"))
    (eval (read-from-string form))))

(defun extract-motion-headless-test (&optional (verbose t))
  (let ((results t)
        (dropped '()))
    (flet ((check (name pass &optional detail)
             (when (or verbose (not pass))
               (format t "~&  ~:[FAIL~;pass~]  ~a~@[~%        ~a~]~%" pass name
                       (and (not pass) detail)))
             (setf results (and pass results)))
           (extract (sentence)
             (handler-bind ((dropped-phrase-warning
                              (lambda (w) (push (princ-to-string w) dropped) (muffle-warning w)))
                            (warning #'muffle-warning))
               (let ((graph (ignore-errors (parse-and-extract sentence :on-missing :create))))
                 (values (and graph (remove #\Space (string-upcase (cg-text graph))))
                         (and graph (ignore-errors (say-graph graph))))))))
      (cg:with-environment ((cg::make-environment
                             :types (namestring (asdf:system-relative-pathname
                                                 :cgraph "test/test-types/"))))

        ;; Licensed origin and destination; place names as individuals.
        (multiple-value-bind (text said) (extract "dave drives a car from Baltimore to Boston .")
          (check "from Baltimore is (src)->[CITY: Baltimore]"
                 (and text (search "(SRC)→[CITY:BALTIMORE]" text)) text)
          (check "to Boston is (dest)->[PLACE: Boston]"
                 (and text (search "(DEST)→[PLACE:BOSTON]" text)) text)
          (check "no type BOSTON was made" (null (ignore-errors (cg::get-concept-type 'cg::boston))))
          (check "nor BALTIMORE: a city is an individual"
                 (null (ignore-errors (cg::get-concept-type 'cg::baltimore))))
          (check "says it back, from before to"
                 (equal said "Dave drives a car from Baltimore to Boston.") said)
          (check "a car driven is the instrument: (inst)->[CAR]"
                 (and text (search "(INST)→[CAR]" text)) text)
          (check "  not the object" (and text (not (search "(OBJ)" text))) text))

        ;; A person driven is the object -- the same frame, the markers decide.
        (setf dropped '())
        (let ((text (extract "dave drives zelda from Baltimore to Boston .")))
          (check "a person driven is the object: (obj)->[WOMAN: Zelda]"
                 (and text (search "(OBJ)→[WOMAN:ZELDA]" text)) text)
          (check "  not the instrument" (and text (not (search "(INST)" text))) text)
          (check "  and the places still land"
                 (and text (search "(SRC)→[CITY:BALTIMORE]" text)
                      (search "(DEST)→[PLACE:BOSTON]" text)) text)
          (check "  nothing dropped" (null dropped) dropped))
        (let ((text (extract "dave drives a car .")))
          (check "the instrument without a destination: (inst)->[CAR]"
                 (and text (search "(INST)→[CAR]" text)) text))

        ;; Other prepositions for the same instrument. BY and IN can each mean
        ;; (loc) or (inst); a car is no PLACE, so it is the instrument, whatever
        ;; the preposition -- and a city after the same IN is still where.
        (setf dropped '())
        (let ((by (extract "dave drives from Baltimore to Boston by car ."))
              (in (extract "dave drives to Boston in a car ."))
              (where (extract "dave drives to Boston in Baltimore .")))
          (check "by car -> (inst)->[CAR]" (and by (search "(INST)→[CAR]" by)) by)
          (check "in a car -> (inst)->[CAR]" (and in (search "(INST)→[CAR]" in)) in)
          (check "in Baltimore -> (loc), not (inst)"
                 (and where (search "(LOC)→[CITY:BALTIMORE]" where)
                      (not (search "(INST)" where))) where)
          (check "  nothing dropped" (null dropped) dropped))

        ;; A complement clause keeps its PPs: they hang on the S inside the
        ;; COMP-NP, and were read off the wrapper, which has none.
        (let ((text (extract "zelda believes dave drives to Boston in a car .")))
          (check "a PP inside a complement clause is kept: (inst)->[CAR]"
                 (and text (search "(INST)→[CAR]" text)) text))

        ;; The canonical graphs choose when the object fits more than one
        ;; candidate. A HOUSEBOAT is a VEHICLE and a PLACE: SEE's graph takes any
        ;; OBJECT as (inst), but PLACE's takes anything as the source of (loc), so
        ;; both are supported and IN's usual (loc) stands. A RAFT's own graph has
        ;; only PERSONs in it, so for PILOT -- whose graph takes a VEHICLE as
        ;; (inst) -- the instrument is the one supported.
        (cg::ensure-concept-types-exist
         '((:label cg::houseboat :supertypes (cg::vehicle cg::place))
           (:label cg::raft :supertypes (cg::vehicle cg::place)
            :canonical-graph "[RAFT]←(loc)←[PERSON].")
           (:label cg::pilot :supertypes (cg::act)
            :canonical-graph "[PILOT]- (agnt)→[PERSON] (inst)→[VEHICLE].")))
        (flet ((choose (pred obj)
                 (choose-adjunct-relation (cg::make-concept pred nil) (cg::make-concept obj nil)
                                          '(cg::loc cg::inst))))
          (check "both ends support: candidate order keeps (loc) -- sees in a houseboat"
                 (eq (choose 'cg::see 'cg::houseboat) 'cg::loc) (choose 'cg::see 'cg::houseboat))
          (check "only the predicate's graph supports: (inst) -- pilots in a raft"
                 (eq (choose 'cg::pilot 'cg::raft) 'cg::inst) (choose 'cg::pilot 'cg::raft))
          (check "no support either way: the first that fits -- (loc) for a city"
                 (eq (choose 'cg::eat 'cg::city) 'cg::loc) (choose 'cg::eat 'cg::city))
          (check "a type no candidate fits is chosen by none"
                 (null (choose-adjunct-relation (cg::make-concept 'cg::see nil)
                                                (cg::make-concept 'cg::automobile nil)
                                                '(cg::loc)))))

        ;; The lexicon says what kind of thing a name names.
        (multiple-value-bind (text said) (extract "zelda drives a car to Oz .")
          (check "a `woman' feature makes a person's name [WOMAN: Zelda]"
                 (and text (search "(AGNT)→[WOMAN:ZELDA]" text)) text)
          (check "a feature naming no kind of place is ignored: [PLACE: Oz]"
                 (and text (search "(DEST)→[PLACE:OZ]" text)) text)
          (check "  says it back" (equal said "Zelda drives a car to Oz.") said))
        (multiple-value-bind (text said) (extract "zelda drives a car to Gotham .")
          (declare (ignore said))
          (check "`city' in place of `place' still names a city: [CITY: Gotham]"
                 (and text (search "(DEST)→[CITY:GOTHAM]" text)) text))

        ;; A frame with no origin: both PPs go loose, and both still land.
        (setf dropped '())
        (multiple-value-bind (text said) (extract "dave hauls a car from Baltimore to Boston .")
          (check "loose from -> (src)" (and text (search "(SRC)→[CITY:BALTIMORE]" text)) text)
          (check "loose to -> (dest)" (and text (search "(DEST)→[PLACE:BOSTON]" text)) text)
          (check "nothing dropped" (null dropped) dropped)
          (check "says it back" (equal said "Dave hauls a car from Baltimore to Boston.") said))

        ;; What is still dropped is reported in a warning that survives
        ;; simple-warning muffling: a loose `to' whose object is no place.
        (setf dropped '())
        (extract "dave hauls a car to the girl .")
        (check "a dropped phrase signals DROPPED-PHRASE-WARNING" dropped)
        (check "  and it is not a simple-warning"
               (not (subtypep 'dropped-phrase-warning 'simple-warning)))))
    (format t "~&extract-motion-headless-test: ~:[FAILED <<<~;passed~]~%" results)
    results))

(extract-motion-headless-test t)
