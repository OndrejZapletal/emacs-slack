;;; slack-buffer.el --- slack buffer                  -*- lexical-binding: t; -*-

;; Copyright (C) 2015  南優也

;; Author: 南優也 <yuyaminami@minamiyuunari-no-MacBook-Pro.local>
;; Keywords:

;; This program is free software; you can redistribute it and/or modify
;; it under the terms of the GNU General Public License as published by
;; the Free Software Foundation, either version 3 of the License, or
;; (at your option) any later version.

;; This program is distributed in the hope that it will be useful,
;; but WITHOUT ANY WARRANTY; without even the implied warranty of
;; MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
;; GNU General Public License for more details.

;; You should have received a copy of the GNU General Public License
;; along with this program.  If not, see <http://www.gnu.org/licenses/>.

;;; Commentary:

;;

;;; Code:

(require 'eieio)
(require 'lui)

(defvar lui-prompt-string "> ")

(defvar slack-mode-map
  (let ((map (make-sparse-keymap)))
    (define-key map (kbd "C-s C-r") #'slack-room-update-message)
    (define-key map (kbd "C-s C-b") #'slack-message-write-another-buffer)
    map))

(define-derived-mode slack-mode lui-mode "Slack"
  ""
  (lui-set-prompt lui-prompt-string)
  (setq lui-time-stamp-position nil)
  (setq lui-fill-type nil)
  (setq lui-input-function 'slack-message--send))

(defvar slack-current-room)
(make-local-variable 'slack-current-room)

(defcustom slack-buffer-emojify nil
  "Show emoji with `emojify' if true."
  :group 'slack)

(defun slack-get-buffer-create (buf-name)
  (let ((buffer (get-buffer buf-name)))
    (unless buffer
      (setq buffer (generate-new-buffer buf-name))
      (with-current-buffer buffer
        (slack-mode)))
    buffer))

(defun slack-buffer-set-current-room (room)
  (set (make-local-variable 'slack-current-room) room))

(defun slack-buffer-enable-emojify ()
  (if slack-buffer-emojify
      (let ((emojify (require 'emojify nil t)))
        (unless emojify
          (error "Emojify is not installed"))
        (emojify-mode t))))

(cl-defun slack-buffer-create (room &optional (insert-func
                                               'slack-buffer-insert-messages))
  (let* ((buf-name (slack-room-buffer-name room))
         (buffer (slack-get-buffer-create buf-name)))
    (with-current-buffer buffer
      (if insert-func
          (funcall insert-func room))
      (slack-buffer-set-current-room room)
      (slack-room-reset-unread-count room)
      (slack-buffer-enable-emojify))
    buffer))

(defun slack-buffer-insert-previous-link (oldest-msg)
  (lui-insert (concat (propertize "(load more message)"
                              'face '(:underline t)
                              'oldest (oref oldest-msg ts)
                              'keymap (let ((map (make-sparse-keymap)))
                                        (define-key map (kbd "RET")
                                          #'slack-room-load-prev-messages)
                                        map))
                  "\n")))

(defun slack-buffer-insert-messages (room)
  (let ((messages (slack-room-latest-messages room)))
    (when messages
      (slack-buffer-insert-previous-link (first messages))
      (mapc (lambda (m)
              (lui-insert (slack-message-to-string m) t))
            messages)
      (let ((latest-message (car (last messages))))
        (slack-room-update-last-read room latest-message)
        (slack-room-update-mark room latest-message)))))

(cl-defun slack-buffer-update (room msg &key replace)
  (cl-labels ((do-update (buf room msg)
                         (with-current-buffer buf
                           (slack-room-update-last-read room msg)
                           (lui-insert (slack-message-to-string msg)))))
    (let* ((buf-name (slack-room-buffer-name room))
           (buffer (get-buffer buf-name))
           (buf-names (mapcar #'buffer-name (mapcar #'window-buffer
                                                    (window-list)))))
      (if (and buffer (cl-member buf-name buf-names :test #'string=))
          (if replace (slack-buffer-replace buffer msg)
            (do-update buffer room msg))
        (slack-room-inc-unread-count room)))))

(defun slack-buffer-replace (buffer msg)
  (with-current-buffer buffer
    (let* ((cur-point (point))
           (beg (text-property-any (point-min) (point-max) 'ts (oref msg ts)))
           (end (next-single-property-change beg 'ts)))
      (if (and beg end)
          (let ((inhibit-read-only t))
            (delete-region beg (+ end 1))
            (set-marker lui-output-marker beg)
            (lui-insert (slack-message-to-string msg))
            (goto-char cur-point)
            (slack-buffer-recover-lui-output-marker))))))

(defun slack-buffer-recover-lui-output-marker ()
  (set-marker lui-output-marker (- (marker-position
                                    lui-input-marker)
                                   (length lui-prompt-string))))

(defun slack-buffer-update-notification (buf-name string)
  (let ((buffer (slack-get-buffer-create buf-name)))
    (with-current-buffer buffer
      (lui-insert string))))

(defun slack-buffer-create-info (buf-name insert-func)
  (let ((buf (get-buffer-create buf-name)))
    (with-current-buffer buf
      (setq buffer-read-only nil)
      (erase-buffer)
      (goto-char (point-min))
      (funcall insert-func)
      (goto-char (point-max))
      (setq buffer-read-only t)
      (slack-buffer-enable-emojify))
    buf))

(provide 'slack-buffer)
;;; slack-buffer.el ends here
