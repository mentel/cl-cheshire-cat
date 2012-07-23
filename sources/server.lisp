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

(defclass redirection-acceptor (acceptor)
  ((admin-host    :accessor redirection-acceptor-admin-host
                  :initarg :admin-host :initform "management.invalid"
                  :type string
                  :documentation "The domain name used to manage this
                  redirection acceptor.")
   (admin-allowed :accessor redirection-acceptor-admin-allowed
                  :initarg :admin-allowed :initform '(("127.0.0.1"))
                  :type list
                  :documentation "A list of CIDR block specifications. Each item
                  of this list is a pair (IP prefix-length). IP is recommended
                  to a string using the decimal dotted notation but could also
                  be an host order 32 bytes integer or an host order byte
                  vector.")
   (rules         :accessor redirection-acceptor-rules
                  :initform '()
                  :type list
                  :documentation "The list of redirection rules used by this
                  acceptor.")
   (rule-file     :reader redirection-acceptor-rule-file
                  :type (or string null)
                  :documentation "The default file used to store the rules. This
                  is set when loading the rules from the file."))
  (:documentation "Custom hunchentoot:acceptor implementing the behavior of the
  redirection server."))

(defmethod initialize-instance :after ((instance redirection-acceptor) &rest initargs &key &allow-other-keys)
  "Ensures the initialization of the <pre>matcher</pre> slot."
  (declare (ignore initargs))
  (setf (acceptor-error-template-directory instance) nil))

(defmethod acceptor-dispatch-request ((acceptor redirection-acceptor) request)
  "This request dispatcher processes each HTTP request and handle adequatly the
request."
  (if (string-equal (redirection-acceptor-admin-host acceptor)
                    (host *request*))
      (admin-handler acceptor)
      (handler-case
          (destructuring-bind (domain-name uri &optional (http-status-code 302))
              (compute-redirection (redirection-acceptor-rules acceptor)
                                   (host *request*) (script-name* *request*))
            (redirect uri :host domain-name :code http-status-code))
        (rs-loop-detected ()
          (setf (return-code* *reply*) +http-not-found+)))))

(defun load-rules (acceptor file)
  "This function restore the list of rules from file and set them as the list of
  rules for this acceptor. It's also registering the rule-file for future
  references."
  (setf (redirection-acceptor-rules acceptor) (restore file)
        (slot-value acceptor 'rule-file)      file))