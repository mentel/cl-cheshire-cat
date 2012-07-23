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

(cl:in-package :cl-user)

;; Load the config parser and the config
(asdf:load-system :py-configparser)
(use-package :py-configparser)

(defparameter *chessire-config* (make-config)
  "Chessire configuration holder")

(read-files *chessire-config* `(,(or (nth 1 sb-ext:*posix-argv*)
                                     "/etc/chessire.conf")))

(defun get-chessire-config (option-name &key (section-name "Chessire") default-value (type :string) (config *chessire-config*))
  "Try to find the option in this section for this config. Type may be one
of :boolean, :integer or :string. Two values are returned: The value of the
option (or the default value if the option was not found) and whether the option
was found or not."
  (if (and (has-section-p config section-name)
           (has-option-p config section-name option-name))
      (values
       (let ((type (if (eq type :string)
                       nil
                       type)))
         (get-option config section-name option-name :type type :expand nil))
       t)
      default-value))

;; Load and start Chessire
(asdf:load-system :cl-chessire-cat)
(use-package :chessire)

(defparameter *chessire*
  (make-instance 'redirection-acceptor
                 :port           (get-chessire-config "port"          :default-value 80   :type :integer)
                 :address        (get-chessire-config "address"       :default-value "0.0.0.0")
                 :admin-allowed (chessire::parse-cidr-list
                                 (get-chessire-config "admin_allowed" :default-value "127.0.0.1"))
                 :admin-host     (get-chessire-config "admin_host"    :default-value "management.invalid"))
  "Chessire cat acceptor")

;; debugging bookeeping
(setq hunchentoot:*show-lisp-errors-p* t)

(defparameter *chessire-debugp* (get-chessire-config "debug" :type :boolean))
(if *chessire-debugp*
    (setq hunchentoot:*show-lisp-backtraces-p* t
          hunchentoot:*catch-errors-p* nil)
    (setq hunchentoot:*show-lisp-backtraces-p* nil
          hunchentoot:*catch-errors-p* t))

(hunchentoot:start *chessire*)

;; Daemonize Chessire
#+sbcl (asdf:load-system :sb-daemon)
(when (get-chessire-config "daemonize" :section-name "daemon" :type :boolean)
  #+sbcl
  (sb-daemon:daemonize :exit-parent t
                       :pidfile (get-chessire-config "pid_file"  :section-name "daemon" :default-value "/var/run/chessire.pid")
                       :output  (get-chessire-config "log"       :section-name "daemon")
                       :error   (get-chessire-config "error_log" :section-name "daemon")
                       :user    (get-chessire-config "user"      :section-name "daemon")
                       :group   (get-chessire-config "group"     :section-name "daemon")
                       :disable-debugger (not *chessire-debugp*))
  #-sbcl
  (error "Daemonize facility is supported only using SBCL and sb-daemon. Any compatibility improvment patch is welcome."))

;; Start swank server if requested
(when (get-chessire-config "enable" :section-name "swank" :type :boolean)
  (asdf:load-system :swank)
  (defparameter *swank-server*
    (swank:create-server :port (get-chessire-config "port" :section-name "swank" :type :integer)
                         :coding-system "utf-8-unix"
                         :dont-clost t)))

;; Load redirection rules
(let ((rules-file (get-chessire-config "rules_file")))
  (when rules-file
    (load-rules *chessire* rules-file)))

;; Sleeping loop
(loop (sleep 10))