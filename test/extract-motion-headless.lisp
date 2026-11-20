;;; -*- Mode: LISP; Syntax: Common-lisp; Base: 10; Lowercase: Yes -*-
;;;
;;; Live MOTION check: origin, destination, and place names.
;;;
;;;   "dave drives a car from Baltimore to Boston ."
;;;     -> [DRIVE]- (agnt)->[PERSON: Dave] (dest)->[PLACE: Boston]
;;;                 (obj)->[AUTOMOBILE...] (src)->[CITY: Baltimore]
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
  (dolist (form '("(df drive feats (mainverb pres tnsless v-3s) cf (neut (pfrom) (pto) agt) markers act)"
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
                 (equal said "Dave drives a car from Baltimore to Boston.") said))

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
