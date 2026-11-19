;;; -*- Mode: LISP; Syntax: Common-lisp; Base: 10; Lowercase: Yes -*-
;;;
;;; Live LEXICON RELOAD check: a word added to the mounted domain's
;;; lexicon.dict works at the next parse, in the same image.
;;;
;;; ENSURE-DOMAIN-LEXICON used to read the file once per session, and its flag
;;; is a DEFVAR -- so even reloading cg-from-parse kept the old vocabulary, and
;;; a word added to lexicon.dict went on failing to parse until a fresh image.
;;; It now re-reads the file when its write date moves on.
;;;
;;; The domain is a temporary copy of cgraph's test types plus a lexicon.dict,
;;; so nothing outside the temp directory is read or written.
;;;
;;; Invocation:
;;;   sbcl --noinform --non-interactive \
;;;     --eval '(ql:quickload :cg-from-parse)' \
;;;     --load test/extract-lexicon-reload-headless.lisp

(in-package :cg-from-parse)

(load (merge-pathnames "test-setup.lisp"
                       (or *load-truename* *compile-file-truename*)))

(defvar *reload-test-runs* 0
  "Counts calls, so each one teaches the parser a word no earlier call did.")

(defun %fresh-word ()
  "A word the parser has never been taught in this image: JALOPYB, JALOPYC, ...
Words are never unloaded (see ENSURE-DOMAIN-LEXICON), so a second call reusing
the first one's word would find it already known -- and the test is run twice,
once by loading this file and once by the headless runner."
  (format nil "jalopy~a" (code-char (+ (char-code #\b) (mod (incf *reload-test-runs*) 24)))))

(defun extract-lexicon-reload-headless-test (&optional (verbose t))
  (let* ((word (%fresh-word))
         (dir (uiop:ensure-directory-pathname
               (merge-pathnames (format nil "cfp-lexicon-reload-~a-~d/" word (get-universal-time))
                                (uiop:temporary-directory))))
         (test-types (asdf:system-relative-pathname :cgraph "test/test-types/"))
         (lexicon (merge-pathnames "lexicon.dict" dir))
         ;; Restored afterwards: they say which file THIS image has loaded, and
         ;; the temp domain is gone once the test is over.
         (saved-file *domain-lexicon-loaded*)
         (saved-date *domain-lexicon-write-date*)
         before after)
    (ensure-directories-exist dir)
    (unwind-protect
         (progn
           (dolist (name '("concept-types.lisp" "relation-types.lisp"))
             (uiop:copy-file (merge-pathnames name test-types) (merge-pathnames name dir)))
           ;; The type is there from the start: what is missing is only the WORD.
           (with-open-file (out (merge-pathnames "concept-types.lisp" dir)
                                :direction :output :if-exists :append)
             (format out "~&(:label ~a :supertypes (automobile))~%" word))
           (with-open-file (out lexicon :direction :output :if-exists :supersede)
             (format out ";;; a domain lexicon with nothing in it yet~%"))
           (setf *domain-lexicon-loaded* nil
                 *domain-lexicon-write-date* nil)
           (cg:with-environment ((cg::make-environment :types (namestring dir)))
             (flet ((try ()
                      (handler-case
                          (let ((cg::*allow-dynamic-individual-creation* t))
                            (sentence->cg-text (format nil "the girl has a ~a ." word)))
                        (error () nil))))
               (setf before (try))
               ;; File dates are whole seconds: wait for the next one, or the
               ;; edit could carry the date the file was read with.
               (sleep 1.1)
               (with-open-file (out lexicon :direction :output :if-exists :append)
                 (format out "(jlike ~a block)~%" word))
               (setf after (try)))))
      (setf *domain-lexicon-loaded* saved-file
            *domain-lexicon-write-date* saved-date)
      (uiop:delete-directory-tree dir :validate t :if-does-not-exist :ignore))
    (let ((pass (and (null before)
                     (stringp after)
                     (search (format nil "[~:@(~a~)" word) after))))
      (when verbose
        (format t "~&before the edit: ~a~%after the edit:  ~a~%"
                (or before "parse failed") after))
      (format t "~&extract-lexicon-reload-headless-test: ~:[FAILED <<<~;passed~]~%" pass)
      pass)))

(extract-lexicon-reload-headless-test t)
