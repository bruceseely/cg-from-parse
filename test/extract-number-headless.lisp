;;; -*- Mode: LISP; Syntax: Common-lisp; Base: 10; Lowercase: Yes -*-
;;;
;;; Live number/plural check:
;;;   "dogs see the man ."        -> [DOG: {}]  (a generic plural set)
;;;   "three dogs see the man ."  -> [DOG: {}]  + cardinality 3 on the referent
;;; A plural NP (NPL) becomes a generic set referent; a leading number adds the
;;; count. cgraph's formatter renders the set ({}) but NOT its cardinality, so
;;; the count is stored as a :measure on the referent (captured, not shown --
;;; like tense/voice) and checked via the slot here.
;;;
;;;   sbcl --non-interactive --disable-debugger \
;;;     --eval '(ql:quickload :swank)' --eval '(ql:quickload :cg-from-parse)' \
;;;     --load test/extract-number-headless.lisp

(in-package :cg-from-parse)

(load (merge-pathnames "test-setup.lisp"
                       (or *load-truename* *compile-file-truename*)))
(setup-test-cgraph)

(load (merge-pathnames "test/integration/clause-grammar.lisp"
                       (asdf:system-source-directory :parsifal)))
(pa::load-full-grammar)

(defun concept-of-type (graph type-name)
  (find-if (lambda (n)
             (and (typep n 'cg::concept)
                  (string-equal (string (cg::label (cg::concept-type n))) type-name)))
           (cg::collect-nodes (cg::head graph))))

(defun dog-referent-info (sentence)
  "Return (values set-p count) for the DOG concept extracted from SENTENCE."
  (when (pa::parse-sentence sentence :initial-rule (intern "INITIAL-RULE" :parsifal))
    (let* ((graph (ir->cgraph (parse->ir pa::c)))
           (dog   (concept-of-type graph "DOG"))
           (ref   (and dog (cg::referent dog))))
      (values (and ref (typep (cg::content ref) 'cg::set) t)
              (and ref (getf (cg::properties ref) :measure))))))

(defun extract-number-headless-test (&optional (verbose t))
  (multiple-value-bind (set3 c3) (dog-referent-info "three dogs see the man .")
    (multiple-value-bind (setp cd) (dog-referent-info "dogs see the man .")
      (let ((pass (and set3 (eql c3 3)     ; three dogs -> plural set, count 3
                       setp (null cd))))   ; dogs -> plural set, no count
        (when verbose
          (format t "~&three dogs -> set=~s count=~s~%" set3 c3)
          (format t "~&dogs       -> set=~s count=~s~%" setp cd))
        (format t "~&extract-number-headless-test: ~:[FAILED <<<~;passed~]~%" pass)
        pass))))

(extract-number-headless-test)
