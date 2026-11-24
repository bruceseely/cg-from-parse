;;; -*- Mode: LISP; Syntax: Common-lisp; Base: 10; Lowercase: Yes -*-
;;;
;;; Live TELL / ASK check: yes/no questions are true/false queries.
;;;
;;;   (tell "dave drives a car from Baltimore to Boston .")
;;;   (ask  "does dave drive a car ?")      => T
;;;   (ask  "does the girl drive a car ?")  => NIL
;;;   (ask  "who drives a car ?")           => ("[PERSON:Dave]")
;;;
;;; The KB keeps one graph per sentence; ASK answers from a copy joined on
;;; shared individuals (JOINED-VIEW), so a question can span sentences.
;;;
;;; A question's graph is a query pattern: its events are generic, where a
;;; statement's are individuated -- [DRIVE: #9] would match only itself. ASK
;;; runs cgraph's QUERY (projection into each KB graph): a yes/no question
;;; holds when it projects somewhere, a wh-question's answers are what its
;;; variable binds to. Projection is as strict as the graphs -- (src) is not
;;; (dest), and a belief is not a fact -- and ASK adds the one thing projection
;;; skips: the predicate's tense.
;;;
;;; Runs in a fresh environment on cgraph's test types, so the shared catalog
;;; and any KB of yours are untouched.
;;;
;;;   sbcl --noinform --non-interactive \
;;;     --eval '(ql:quickload :cg-from-parse)' \
;;;     --load test/extract-ask-headless.lisp

(in-package :cg-from-parse)

(load (merge-pathnames "test-setup.lisp"
                       (or *load-truename* *compile-file-truename*)))
(setup-test-cgraph)

;; The words a domain lexicon would give (as in the motion test).
(let ((*package* (find-package :parsifal)))
  (dolist (form '("(df drive feats (mainverb pres tnsless v-3s) cf ((*obj ins) (neut) (ins) (pfrom) (pto) agt) neut (|#| hanim |#|) markers act)"
                  "(df drove irreg (drive (past vspl) (tnsless v-3s pres)))"
                  "(df baltimore feats (noun ns n3p propnoun place city) markers (place))"
                  "(df zelda feats (noun ns n3p propnoun name woman) markers (hanim))"
                  "(jlike car block)"))
    (eval (read-from-string form))))

(defun extract-ask-headless-test (&optional (verbose t))
  (let ((results t))
    (flet ((check (name pass &optional detail)
             (when (or verbose (not pass))
               (format t "~&  ~:[FAIL~;pass~]  ~a~@[~%        ~s~]~%" pass name
                       (and (not pass) detail)))
             (setf results (and pass results))))
      (cg:with-environment ((cg::make-environment
                             :types (namestring (asdf:system-relative-pathname
                                                 :cgraph "test/test-types/"))))
        (handler-bind ((warning #'muffle-warning))
          (let ((cg::*allow-dynamic-individual-creation* t))
            (tell "dave drives a car from Baltimore to Boston .")
            (tell "zelda drove dave to Boston .")
            (tell "dave believes zelda drives a car .")
            (flet ((ask* (q) (handler-case (ask q) (error (e) (princ-to-string e)))))
              ;; The mood comes back with the graph, and a question is generic.
              (multiple-value-bind (g mood) (parse-and-extract "does dave drive a car ?")
                (check "a yes/no question has mood :yes-no" (eq mood :yes-no) mood)
                (check "  and its event is generic, not individuated"
                       (not (search "#" (cg-text g))) (cg-text g)))
              (check "a wh-question has mood :wh"
                     (eq (nth-value 1 (parse-and-extract "who drives a car ?")) :wh))
              (check "a statement has mood :declarative"
                     (eq (nth-value 1 (parse-and-extract "dave drives a car .")) :declarative))

              ;; Yes/no: true when it holds, false when it does not.
              (check "told it: does dave drive a car ? => T"
                     (eq (ask* "does dave drive a car ?") t) (ask* "does dave drive a car ?"))
              (check "someone never mentioned: does the girl drive a car ? => NIL"
                     (null (ask* "does the girl drive a car ?")) (ask* "does the girl drive a car ?"))
              (check "part of what was told: does dave drive to Boston ? => T"
                     (eq (ask* "does dave drive to Boston ?") t) (ask* "does dave drive to Boston ?"))
              (check "src is not dest: does dave drive to Baltimore ? => NIL"
                     (null (ask* "does dave drive to Baltimore ?")) (ask* "does dave drive to Baltimore ?"))
              (check "the person driven: did zelda drive dave ? => T"
                     (eq (ask* "did zelda drive dave ?") t) (ask* "did zelda drive dave ?"))
              ;; Tense is the predicate's, and projection does not look at it.
              (check "tense counts: does zelda drive dave ? => NIL (she drove him)"
                     (null (ask* "does zelda drive dave ?")) (ask* "does zelda drive dave ?"))
              ;; A belief is not a fact: zelda's car is inside dave's belief.
              (check "a belief is not a fact: does zelda drive a car ? => NIL"
                     (null (ask* "does zelda drive a car ?")))
              ;; Asking does not tell.
              (check "asking adds nothing to the KB" (= 3 (length (cg::graphs (kb))))
                     (length (cg::graphs (kb))))
              ;; A statement ASKed is "is it true that ...?".
              (check "a statement asked: dave drives a car . => T"
                     (eq (ask* "dave drives a car .") t) (ask* "dave drives a car ."))

              ;; Wh: the answers are what the variable binds to.
              (check "who drives a car ? => Dave"
                     (equal (ask* "who drives a car ?") '("[PERSON:Dave]")) (ask* "who drives a car ?"))
              (check "who drove dave ? => Zelda"
                     (equal (ask* "who drove dave ?") '("[WOMAN:Zelda]")) (ask* "who drove dave ?"))

              ;; Questions and commands go where they belong.
              (check "TELLing a question is refused"
                     (search "is a question" (handler-case (progn (tell "does dave drive a car ?") "")
                                               (error (e) (princ-to-string e)))))
              (check "ASKing a command is refused"
                     (search "is a command" (ask* "drive the car !")))

              ;; The KB is the record; ASK joins a copy.
              (check "the KB keeps one graph per sentence told"
                     (= 3 (length (cg::graphs (kb)))) (length (cg::graphs (kb))))
              (let ((view (joined-view)))
                (check "the joined view: one Dave ties the three together"
                       (= 1 (length (cg::graphs view))) (length (cg::graphs view))))
              (check "  and joining it left the KB as told"
                     (= 3 (length (cg::graphs (kb)))) (length (cg::graphs (kb))))
              ;; What the view buys: no one sentence has zelda driving someone
              ;; who drives a car; "zelda drove dave" and "dave drives a car" do.
              (check "across sentences: did zelda drive a person who drives a car ? => T"
                     (eq (ask* "did zelda drive a person who drives a car ?") t)
                     (ask* "did zelda drive a person who drives a car ?"))
              (check "across sentences: who drove a person who drives a car ? => Zelda"
                     (equal (ask* "who drove a person who drives a car ?") '("[WOMAN:Zelda]"))
                     (ask* "who drove a person who drives a car ?"))
              (check ":join nil asks the record: no one sentence says it => NIL"
                     (null (ignore-errors
                            (ask "did zelda drive a person who drives a car ?" :join nil))))

              ;; Generic concepts do not join: two pies stay two pies.
              (tell "a girl eats a pie .")
              (tell "a boy eats a pie .")
              (check "generic concepts do not join: the view has two more graphs"
                     (= 3 (length (cg::graphs (joined-view)))) (length (cg::graphs (joined-view))))
              ;; ... but an entity the discourse linked does.
              (tell "the girl sees the dog .")
              (check "the discourse's girl joins the girl's graph in the view"
                     (= 3 (length (cg::graphs (joined-view)))) (length (cg::graphs (joined-view)))))))))
    (format t "~&extract-ask-headless-test: ~:[FAILED <<<~;passed~]~%" results)
    results))

(extract-ask-headless-test t)
