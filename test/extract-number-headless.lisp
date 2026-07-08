;;; -*- Mode: LISP; Syntax: Common-lisp; Base: 10; Lowercase: Yes -*-
;;;
;;; Live number/plural check:
;;;   "dogs see the man ."        -> [DOG: {}]  (a generic plural set)
;;;   "three dogs see the man ."  -> [DOG: @3]  (a generic plural with a count)
;;; A plural NP (NPL) becomes a generic set referent; a leading number adds the
;;; count, stored as a :measure on the referent. cgraph's formatter renders a
;;; generic plural with a count as just @N (the empty {} adds nothing); a set
;;; with named members would render [X: {...}@N]. Checked here both in the
;;; rendered text and via the referent slot.
;;;
;;;   sbcl --non-interactive --disable-debugger \
;;;     --eval '(ql:quickload :swank)' --eval '(ql:quickload :cg-from-parse)' \
;;;     --load test/extract-number-headless.lisp

(in-package :cg-from-parse)

(load (merge-pathnames "test-setup.lisp"
                       (or *load-truename* *compile-file-truename*)))
(setup-test-cgraph)

(load (merge-pathnames "system/grammar/clause-grammar.lisp"
                       (asdf:system-source-directory :parsifal)))
(pa::load-full-grammar)

(defun concept-of-type (graph type-name)
  (find-if (lambda (n)
             (and (typep n 'cg::concept)
                  (string-equal (string (cg::label (cg::concept-type n))) type-name)))
           (cg::collect-nodes (cg::head graph))))

(defun dog-referent-info (sentence)
  "Return (values set-p count rendered-text) for the DOG concept of SENTENCE."
  (when (pa::parse-sentence sentence :initial-rule (intern "INITIAL-RULE" :parsifal))
    (let* ((graph (ir->cgraph (parse->ir pa::c)))
           (dog   (concept-of-type graph "DOG"))
           (ref   (and dog (cg::referent dog))))
      (values (and ref (typep (cg::content ref) 'cg::set) t)
              (and ref (getf (cg::properties ref) :measure))
              (ignore-errors (string-upcase (cg::format-cgraph graph)))))))

(defun extract-number-headless-test (&optional (verbose t))
  (multiple-value-bind (set3 c3 t3) (dog-referent-info "three dogs see the man .")
    (multiple-value-bind (setp cd td) (dog-referent-info "dogs see the man .")
      (let ((pass (and set3 (eql c3 3)             ; three dogs -> set, count 3
                       t3 (search "@3" t3)         ; ...rendered as a count (@3)
                       setp (null cd)              ; dogs -> set, no count
                       td (search "{}" td)         ; ...renders as a plain set
                       (not (search "@" td)))))    ; ...with no count
        (when verbose
          (format t "~&three dogs -> set=~s count=~s  text=~a~%" set3 c3 t3)
          (format t "~&dogs       -> set=~s count=~s  text=~a~%" setp cd td))
        (format t "~&extract-number-headless-test: ~:[FAILED <<<~;passed~]~%" pass)
        pass))))

(extract-number-headless-test)
