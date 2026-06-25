;;; -*- Mode: LISP; Syntax: Common-lisp; Base: 10; Lowercase: Yes -*-
;;;
;;; Headless integration check for the EMISSION half (IR -> cgraph).
;;; Needs a live cgraph image with the test-types catalog loaded; does NOT
;;; need the parser (it feeds a hand-written IR). Run with:
;;;
;;;   sbcl --non-interactive --disable-debugger \
;;;     --eval '(ql:quickload :swank)' \
;;;     --eval '(ql:quickload :cg-from-parse)' \
;;;     --load test/extract-emit-headless.lisp
;;;
;;; Builds the IR for "the dog eats the cake" — EAT with agt=DOG, neut=CAKE —
;;; and checks the emitted graph renders as the expected conceptual graph.

(in-package :cg-from-parse)

;; Bring up the TEST-TYPES catalog non-destructively (eat/dog/cake live there).
(load (merge-pathnames "test-setup.lisp"
                       (or *load-truename* *compile-file-truename*)))
(setup-test-cgraph)

(defun extract-emit-headless-test (&optional (verbose t))
  (let* ((ir (list :kind :clause :pred 'pa::eat
                   :cases (list (list :role 'pa::agt
                                      :filler (list :kind :entity :lemma 'pa::dog))
                                (list :role 'pa::neut
                                      :filler (list :kind :entity :lemma 'pa::cake)))))
         (graph (ir->cgraph ir))
         (text  (ignore-errors (cg::format-cgraph graph)))
         (pass  (and graph
                     (typep graph 'cg::graph)
                     (stringp text)
                     (search "EAT" (string-upcase text))
                     (search "AGNT" (string-upcase text))
                     (search "DOG" (string-upcase text))
                     (search "OBJ" (string-upcase text))
                     (search "CAKE" (string-upcase text)))))
    (when verbose
      (format t "~&IR:    ~s~%" ir)
      (format t "~&graph: ~s~%" graph)
      (format t "~&text:  ~a~%" text))
    (format t "~&extract-emit-headless-test: ~:[FAILED <<<~;passed~]~%" pass)
    pass))

(extract-emit-headless-test t)
