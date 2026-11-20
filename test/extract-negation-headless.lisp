;;; -*- Mode: LISP; Syntax: Common-lisp; Base: 10; Lowercase: Yes -*-
;;;
;;; Live NEGATION check: a denied clause becomes a negated context.
;;;
;;;   "the girl does not eat pie ."
;;;       -> ~[[EAT]-(agnt)->[GIRL: #] (obj)->[PIE]]
;;;   "the girl believes the boy does not eat pie ."
;;;       -> [BELIEVE]- ... (prop)->[PROPOSITION: ~[[EAT]-(agnt)->[BOY: #] ...]]
;;;
;;; parsifal's NEGATION rule (*negation-rules*) labels the clause's aux `neg',
;;; for `not' and `n't' alike. Before it, both were lost -- `not' dropped as an
;;; unknown word, `n't' stripped without a word by morpho -- and each of these
;;; sentences came out as the graph of its opposite.
;;;
;;; The round trip is checked too: cgraph's realizer says ~[G] as G with `not'
;;; on its verb, so the sentence comes back as it went in.
;;;
;;; Invocation:
;;;   sbcl --noinform --non-interactive \
;;;     --eval '(ql:quickload :cg-from-parse)' \
;;;     --load test/extract-negation-headless.lisp

(in-package :cg-from-parse)

(load (merge-pathnames "test-setup.lisp"
                       (or *load-truename* *compile-file-truename*)))
(setup-test-cgraph)

(defun %negation-info (sentence)
  "Parse SENTENCE; return (values graph text said), or NILs if it fails."
  (handler-bind ((warning #'muffle-warning))
    (let ((graph (ignore-errors (parse-and-extract sentence :on-missing :create))))
      (values graph
              (and graph (ignore-errors (remove #\Space (string-upcase (cg-text graph)))))
              (and graph (ignore-errors (say-graph graph)))))))

(defun %denied-head-p (graph)
  "GRAPH is a bare ~[G]: one negated concept holding a graph."
  (let ((head (and graph (cg::head graph))))
    (and head (cg::negated head) (cg::graph-referent-p head) t)))

(defun extract-negation-headless-test (&optional (verbose t))
  (let ((results t))
    (flet ((check (name pass &optional detail)
             (when (or verbose (not pass))
               (format t "~&  ~:[FAIL~;pass~]  ~a~@[~%        ~a~]~%" pass name
                       (and (not pass) detail)))
             (setf results (and pass results))))
      ;; Matrix denial, in each auxiliary and both spellings.
      (dolist (case '(("the girl does not eat pie ."    "The girl does not eat a pie.")
                      ("the girl doesn't eat pie ."     "The girl does not eat a pie.")
                      ("the girl did not eat the pie ." "The girl did not eat the pie.")
                      ("the girl is not eating pie ."   "The girl is not eating a pie.")
                      ("the girl will not eat pie ."    "The girl will not eat a pie.")))
        (destructuring-bind (sentence said-expected) case
          (multiple-value-bind (graph text said) (%negation-info sentence)
            (check (format nil "~a is ~~[G]" sentence) (%denied-head-p graph) text)
            (check "  G is the clause" (and text (search "[EAT" text)
                                            (search "(AGNT)→[GIRL" text)) text)
            (check (format nil "  says ~s" said-expected) (equal said said-expected) said))))

      ;; Not denied: the plain clause is untouched.
      (multiple-value-bind (graph text said) (%negation-info "the girl eats pie .")
        (check "the girl eats pie . is not denied"
               (and graph (not (%denied-head-p graph)) (not (search "~" text))) text)
        (check "  says \"The girl eats a pie.\"" (equal said "The girl eats a pie.") said))

      ;; A denied complement: the denial is inside the proposition, and the
      ;; believing is not denied.
      (multiple-value-bind (graph text said)
          (%negation-info "the girl believes the boy does not eat pie .")
        (check "a denied that-clause: the believing is not denied"
               (and graph (not (%denied-head-p graph))) text)
        (check "  the proposition holds ~[G]"
               (and text (search "[PROPOSITION:~[PROPOSITION:[EAT" text)) text)
        (check "  says it back"
               (equal said "The girl believes that the boy does not eat a pie.") said))

      ;; A denied belief: the believing is denied, its complement is not.
      (multiple-value-bind (graph text said)
          (%negation-info "the girl does not believe the boy eats pie .")
        (check "a denied belief is ~[G]" (%denied-head-p graph) text)
        (check "  its complement is not denied"
               (and text (= 1 (count #\~ text))) text)
        (check "  says it back"
               (equal said "The girl does not believe that the boy eats a pie.") said)))
    (format t "~&extract-negation-headless-test: ~:[FAILED <<<~;passed~]~%" results)
    results))

(extract-negation-headless-test t)
