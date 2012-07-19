;;; Copyright © 2012, Mathieu Lemoine <mlemoine@mentel.com>, Mentel Inc.
;;; All rights reserved.
;;; 
;;; Redistribution and use in source and binary forms, with or without
;;; modification, are permitted provided that the following conditions are met:
;;;     * Redistributions of source code must retain the above copyright
;;;       notice, this list of conditions and the following disclaimer.
;;;     * Redistributions in binary form must reproduce the above copyright
;;;       notice, this list of conditions and the following disclaimer in the
;;;       documentation and/or other materials provided with the distribution.
;;;     * Neither the name of "Mentel Inc." nor the names of its contributors may be
;;;       used to endorse or promote products derived from this software without
;;;       specific prior written permission.
;;; 
;;; THIS SOFTWARE IS PROVIDED BY THE COPYRIGHT HOLDERS AND CONTRIBUTORS "AS IS" AND
;;; ANY EXPRESS OR IMPLIED WARRANTIES, INCLUDING, BUT NOT LIMITED TO, THE IMPLIED
;;; WARRANTIES OF MERCHANTABILITY AND FITNESS FOR A PARTICULAR PURPOSE ARE
;;; DISCLAIMED. IN NO EVENT SHALL <COPYRIGHT HOLDER> BE LIABLE FOR ANY
;;; DIRECT, INDIRECT, INCIDENTAL, SPECIAL, EXEMPLARY, OR CONSEQUENTIAL DAMAGES
;;; (INCLUDING, BUT NOT LIMITED TO, PROCUREMENT OF SUBSTITUTE GOODS OR SERVICES;
;;; LOSS OF USE, DATA, OR PROFITS; OR BUSINESS INTERRUPTION) HOWEVER CAUSED AND
;;; ON ANY THEORY OF LIABILITY, WHETHER IN CONTRACT, STRICT LIABILITY, OR TORT
;;; (INCLUDING NEGLIGENCE OR OTHERWISE) ARISING IN ANY WAY OUT OF THE USE OF THIS
;;; SOFTWARE, EVEN IF ADVISED OF THE POSSIBILITY OF SUCH DAMAGE.

(cl:in-package :cl-chessire-cat)

(defun update-rule% (rule update-specs)
  "Updates a rule, each update spec should be (\"new-{ATTRIBUTE}\"
  . \"{NEW-VALUE}\")."
  (loop for (name . new-value) in update-specs
     do (multiple-value-bind (match-p attribute-name)
            (starts-with-subseq "new-" name)
          (when (not match-p)
            (send-bad-request (format nil "Invalid update specification (~A).~%Update specification should be of the form: \"new-{ATTRIBUTE}\"={NEW-VALUE}." name)))
          (let* ((accessor-symbol (ensure-symbol (string-upcase (concatenate 'string "rr-" attribute-name)) :redirection-server))
                 (writer          (fdefinition `(setf ,accessor-symbol)))
                 (new-value       (case accessor-symbol
                                    ((rr-kind)      (make-keyword (string-upcase new-value)))
                                    ((rr-http-code) (parse-integer-or-nil new-value))
                                    (t             new-value))))
            (funcall writer new-value rule)))))

(defun admin-domain-name-rules-handler% (path redirection-acceptor)
  "Handler for domain name rules management"
  (cond
    ((starts-with-subseq "/add" path)
     (add-domain-name-rule (redirection-acceptor-rules redirection-acceptor)
                           (make-instance 'domain-redirection-rule
                                          :kind (make-keyword (string-upcase (post-parameter "kind")))
                                          :match (post-parameter "match")
                                          :replacement (post-parameter "replacement")
                                          :http-code (parse-integer-or-nil (post-parameter "http-code")))
                           :position (parse-integer-or-nil (post-parameter "position")))
     "OK")

    ((starts-with-subseq "/remove" path)
     (when (post-parameter "confirmed")
       (remove-domain-name-rule (redirection-acceptor-rules redirection-acceptor)
                                (make-keyword (string-upcase (get-parameter "kind")))
                                (get-parameter "match")))
     "OK")
    
    ((starts-with-subseq "/list" path)
     (let ((kind        (when-let (kind (get-parameter "kind"))
                          (make-keyword (string-upcase kind))))
           (match       (when-let (match (get-parameter "match"))
                          (create-scanner match :single-line-mode t)))
           (replacement (when-let (replacement (get-parameter "replacement"))
                          (create-scanner replacement :single-line-mode t))))
       (format nil "~S" (remove-if (lambda (rule)
                                     (or (when kind
                                           (not (eq kind (rr-kind rule))))
                                         (when match
                                           (not (scan match (rr-match rule))))
                                         (when replacement
                                           (not (scan replacement (rr-replacement rule))))))
                                   (redirection-acceptor-rules redirection-acceptor)))))

    ((starts-with-subseq "/update" path)
     (let ((rule (find-domain-name-rule (redirection-acceptor-rules redirection-acceptor)
                                        (make-keyword (string-upcase (get-parameter "kind")))
                                        (get-parameter "match")
                                        :error-p t)))
       (update-rule% rule (post-parameters* *request*)))
     "OK")))

(defun admin-uri-rules-handler% (path domain-name-rule)
  "Handler for URI rules management."
  (cond
    ((starts-with-subseq "/add" path)
     (add-uri-rule domain-name-rule
                   (make-instance 'uri-redirection-rule
                                  :kind (make-keyword (string-upcase (post-parameter "kind")))
                                  :match (post-parameter "match")
                                  :replacement (post-parameter "replacement")
                                  :http-code (parse-integer-or-nil (post-parameter "http-code")))
                   :position (parse-integer-or-nil (post-parameter "position")))
     "OK")

    ((starts-with-subseq "/remove" path)
     (when (post-parameter "confirmed")
       (remove-uri-rule domain-name-rule
                        (make-keyword (string-upcase (post-parameter "kind")))
                        (post-parameter "match")))
     "OK")

    ((starts-with-subseq "/list" path)
     (let ((kind        (get-parameter "kind"))
           (match       (when-let (match (get-parameter "match"))
                          (create-scanner match :single-line-mode t)))
           (replacement (when-let (replacement (get-parameter "replacement"))
                          (create-scanner replacement :single-line-mode t))))
       (format nil "~S" (remove-if (lambda (rule)
                                     (or (when kind
                                           (not (eq kind (rr-kind rule))))
                                         (when match
                                           (not (scan match (rr-match rule))))
                                         (when replacement
                                           (not (scan replacement (rr-replacement rule))))))
                                   (drr-uri-rules domain-name-rule)))))

    ((starts-with-subseq "/update" path)
     (let ((rule (find-uri-rule domain-name-rule
                                (make-keyword (string-upcase (get-parameter "kind")))
                                (get-parameter "match")
                                :error-p t)))
       (update-rule% rule (post-parameters* *request*)))
     "OK")))

(defun admin-handler (redirection-acceptor)
  "Management handler."
  (setf (content-type* *reply*) "text/plain")

  (unless (some (lambda (cidr-spec)
                  (apply #'ip-cidr-match-p (remote-addr* *request*) cidr-spec))
                (redirection-acceptor-admin-allowed redirection-acceptor))
    (send-bad-request "You are not authorized to manange this server." +http-forbidden+))

  (handler-case
      (cond

        ((starts-with-subseq "/save-rules" (script-name* *request*))
         (store (redirection-acceptor-rules redirection-acceptor)
                (or (post-parameter "file" *request*)
                    (redirection-acceptor-rule-file redirection-acceptor)))
         "OK")

        ((starts-with-subseq "/domain-name-rule/" (script-name* *request*))
         (admin-domain-name-rules-handler% (subseq (script-name* *request*) 17)
                                           redirection-acceptor))

        ((starts-with-subseq "/uri-rule/" (script-name* *request*))
         (let ((domain-name-rule  (find-domain-name-rule (redirection-acceptor-rules redirection-acceptor)
                                                         (make-keyword (string-upcase (get-parameter "domain-name-kind" *request*)))
                                                         (get-parameter "domain-name-match" *request*)
                                                         :error-p t)))
           (handler-case (admin-uri-rules-handler% (subseq (script-name* *request*) 9)
                                                   domain-name-rule)
             (rs-no-such-uri-rule (condition)
               (setf (urr-domain-name-rule condition) domain-name-rule)
               (signal condition))))))

    (rs-no-such-domain-rule (condition)
      (send-bad-request (format nil "No such domain name rule (~A ~A)."
                                (rr-kind condition) (rr-match condition))
                        +http-not-found+))
    (rs-no-such-uri-rule (condition)
      (send-bad-request (format nil "No such URI rule (~A ~A) for domain name rule (~A ~A)."
                                (rr-kind condition) (rr-match condition)
                                (rr-kind (urr-domain-name-rule condition)) (rr-match (urr-domain-name-rule condition)))
                        +http-not-found+))))
