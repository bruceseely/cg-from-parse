;;; -*- Mode: LISP; Syntax: Common-lisp; Base: 10; Lowercase: Yes -*-
;;;
;;; driver.lisp -- one-call ergonomics: string -> conceptual graph.
;;;
;;; parse-and-extract hides the boilerplate (load + register PARSIFAL's full
;;; grammar, parse-sentence with the initial rule, then extract-graph) so a
;;; caller can go straight from English to a cgraph graph. The grammar is
;;; loaded/registered once per session and cached.
;;;
;;; It self-initializes both cgraph (the type catalog + *context*) and the
;;; PARSIFAL grammar on first use, each a no-op if already set up -- so it works
;;; right after (ql:quickload :cg-from-parse) without disturbing a running session.

(in-package :cg-from-parse)

(defvar *grammar-loaded* nil
  "T once PARSIFAL's full grammar has been loaded + registered this session.")

(defun cgraph-ready-p ()
  "True when cgraph is initialized: the type catalog is loaded (top type bound)
and a *context* exists."
  (and (boundp 'cg::*concept-type-top*)
       cg::*concept-type-top*
       cg::*context*))

(defun ensure-cgraph ()
  "Make sure cgraph is initialized -- type catalog loaded from the user's
~/.cgraph/types and *context* bound. No-op if already initialized, so a running
session isn't disturbed. (*package* must be :cg while loading: cgraph's type
loaders use plain READ.)"
  (unless (cgraph-ready-p)
    (let ((*package* (find-package :conceptual-graphs)))
      (cg::setup-cgraph (asdf:system-source-directory :cgraph))
      (cg::reset-cgraph)))
  t)

(defun ensure-grammar (&optional force)
  "Load and register PARSIFAL's full grammar so parse-sentence can handle any
supported construction. Done once per session (pass FORCE to redo). The grammar
lives in parsifal's system/grammar/clause-grammar.lisp; load-full-grammar
there composes and registers it."
  (when (or force (not *grammar-loaded*))
    (load (asdf:system-relative-pathname :parsifal
                                         "system/grammar/clause-grammar.lisp"))
    (funcall (intern "LOAD-FULL-GRAMMAR" :parsifal))
    (setf *grammar-loaded* t))
  t)

(defun parse-and-extract (sentence &key (on-missing *on-missing-type*))
  "Parse SENTENCE with PARSIFAL and return its conceptual graph (a cgraph graph).
Loads + registers the full grammar on first use. Signals an error if PARSIFAL
can't parse SENTENCE. ON-MISSING binds *on-missing-type* for out-of-ontology
lemmas (:error / :create / :top).

  (parse-and-extract \"the man gives the woman the book .\")
  (parse-and-extract \"the man sees the dog in the park .\" :on-missing :create)"
  (ensure-cgraph)
  (ensure-grammar)
  (let ((*on-missing-type* on-missing))
    (if (pa:parse-sentence sentence :initial-rule (intern "INITIAL-RULE" :parsifal))
        (extract-graph)
        (error "cg-from-parse: PARSIFAL could not parse ~s" sentence))))

(defun sentence->cg-text (sentence &key (on-missing *on-missing-type*))
  "Convenience: parse-and-extract SENTENCE and return the formatted CG string.
Routes through cg-text, so a promoted [EXCHANGE] graph gets the block renderer
(render.lisp) and everything else the engine's format-cgraph."
  (cg-text (parse-and-extract sentence :on-missing on-missing)))

(defun say-graph (graph)
  "Realize GRAPH back to English via cgraph's realizer (say), with cross-context
coreference generation enabled. cgraph's *anaphora-cross-coref* defaults to NIL, so
by default a coreferring occurrence in an embedded context (what the extractor emits
for a resolved pronoun or a control trace, [MAN:?x] bound to [MAN:*x]) would surface
as a fresh NP (\"a man\") instead of a pronoun. Binding it here keeps the round-trip
faithful to the coreference the extractor encoded (\"...the dog sees him\", not
\"...sees a man\") -- without changing cgraph's global default for other callers."
  (let ((cg::*anaphora-cross-coref* t))
    (cg::say graph)))

(defun sentence->say (sentence &key (on-missing *on-missing-type*))
  "Round-trip: parse SENTENCE, extract its conceptual graph, and realize that graph
back to English (coreference-aware -- see say-graph). English in -> graph -> English
out; the natural-language counterpart of sentence->cg-text.

  (sentence->say \"the man knows that the dog sees him .\")
  ;; => \"The man knows that the dog sees him.\""
  (say-graph (parse-and-extract sentence :on-missing on-missing)))

(defun browse-types (&key (port 8060))
  "Start cgraph's web concept-type browser on THIS session's live type catalog and
return the URL to open. Loads the cgraph-web system (Hunchentoot) on demand and
ensures cgraph is initialized first, so the browser shows exactly the ontology this
cg-from-parse session is using -- including any types created during extraction under
:create, since cgraph's type catalog is process-global and shared in this image.

Keep the REPL alive: the server runs inside this Lisp image and dies when it exits,
so starting it from a one-shot/non-interactive process is a common cause of a dead
page. Stop it with (cg::stop-web-server) (or restart on a new PORT).

IMPORTANT -- open http://127.0.0.1:<port>, NOT http://localhost:<port>. The server
binds IPv4 127.0.0.1, and `localhost' can resolve to IPv6 ::1 first (nothing listens
there), which shows as `Unable to connect' in the browser."
  (ensure-cgraph)
  (asdf:load-system :cgraph-web)
  (funcall (intern "START-WEB-SERVER" :cg) :port port)
  (let ((url (format nil "http://127.0.0.1:~a" port)))
    (format t "~&Concept-type browser ready: ~a~%~
                 (open that exact URL -- 127.0.0.1, not localhost; ~
                 stop with (cg::stop-web-server))~%" url)
    url))

(defun browse-lexicon (&key all (stream *standard-output*) (columns 6))
  "Print the words PARSIFAL can currently parse -- the live lexicon this session
is using -- and return the list of word-name strings (sorted). This is the lexicon
counterpart to BROWSE-TYPES: the lexicon (what words parse at all) and the concept-type
ontology (what a parsed lemma maps to) are independent catalogs, and a word can be in
one without the other -- e.g. `want' is in the lexicon but has no concept type. A REPL
lister rather than a web page; STREAM/COLUMNS control the printed layout.

By default the punctuation tokens and clitic fragments (`.', `'d', `'s', ...) that
are also lexicon entries are omitted, leaving the words one would add to a sentence;
pass ALL non-nil to include them and get the complete inventory.

  (browse-lexicon)             ; content words: prints the table, returns the list
  (browse-lexicon :all t)      ; everything, incl. punctuation + clitics
  (member \"want\" (browse-lexicon) :test #'string=)"
  (ensure-grammar)
  (let* ((words (mapcar (lambda (s) (string-downcase (symbol-name s)))
                        (pa:lexicon-words :sort t :all all)))
         (n (length words)))
    (format stream "~&Lexicon: ~a ~a  (add more in ~
                    parsifal/system/core/runtime/supplement.dict~
                    ~@[; content words only -- :all t for everything~])~%~%"
            n (if all "entries" "words") (not all))
    (loop for w in words
          for i from 1
          do (format stream "  ~va" 18 w)
             (when (zerop (mod i columns)) (terpri stream)))
    (unless (zerop (mod n columns)) (terpri stream))
    words))
