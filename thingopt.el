;;; thingopt.el --- Thing at Point optional utilities

;; Copyright (C) 2008, 2009, 2010, 2011  Tomohiro Matsuyama

;; Author: Tomohiro Matsuyama <tomo@cx4a.org>
;; Keywords: convenience

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

;; my configuration for thingopt.el
;; ;;; 用于选中thing的绑定,如选中word line sentence 等
;; (global-set-key (kbd "C-M-u") 'upward-mark-thing);多次按下效果不同
;; (global-set-key (kbd "C-M-d") 'kill-thing)
;; ;;
;; (defun set-value-for--upward-mark-thing-list(value)
;;   (make-local-variable 'upward-mark-thing-list)
;;   (setq upward-mark-thing-list value))

;; ;;(print (list-thing))
;; (setq-default upward-mark-thing-list  '(word symbol email sexp filename url (up-list . *) buffer))
;; (add-hook 'c-mode-common-hook '(lambda() (set-value-for--upward-mark-thing-list  '(word symbol email filename url (up-list . *) buffer)) ))
;; ;; (add-hook 'emacs-lisp-mode-hook '(lambda() (set-value-for--upward-mark-thing-list '(word symbol sexp (up-list . *))) ))
;; (add-hook 'text-mode-hook '(lambda() (set-value-for--upward-mark-thing-list '(word email filename url sentence paragraph buffer)) ))

;; TODO documentation
;; TODO forward-string by syntax (?)

;;; Commands:
;;
;; Below are complete command list:
;;
;;
;;; Customizable Options:
;;
;; Below are customizable option list:
;;

;;; Code:

(eval-when-compile
  (require 'cl))

(require 'thingatpt)

(defvar thing-list-cache nil)
(defvar upward-mark-thing-index 0)
(defvar upward-mark-thing-list '(string symbol (up-list . *)))
(defvar upward-mark-thing-trial 0)
(defvar upward-mark-thing-original-position)
(defvar last-marked-bounds nil)

(defun thingp (thing)
  (or (get thing 'bounds-of-thing-at-point)
      (get thing 'forward-op)
      (get thing 'beginning-op)
      (get thing 'end-op)
      (fboundp (intern-soft (concat "forward-" (symbol-name thing))))))

(defun list-thing ()
  (let (things)
    (mapatoms
     (lambda (atom)
       (if (thingp atom)
           (push atom things))))
    things))

(defun read-thing ()
  (or thing-list-cache
      (setq thing-list-cache (list-thing)))
  (completing-read "Thing: " (mapcar 'list thing-list-cache)
                   nil nil nil nil "sexp"))

;;;###autoload
(defun kill-thing (thing)
  (interactive (list (read-thing)))
  (if (stringp thing)
      (setq thing (intern thing)))
  (let ((bounds (bounds-of-thing-at-point thing)))
    (if bounds
        (kill-region (car bounds) (cdr bounds)))))

;;;###autoload
(defun copy-thing (thing)
  (interactive (list (read-thing)))
  (if (stringp thing)
      (setq thing (intern thing)))
  (let ((bounds (bounds-of-thing-at-point thing)))
    (if bounds
        (copy-region-as-kill (car bounds) (cdr bounds)))))

;;;###autoload
(defun mark-thing (thing)
  (interactive (list (read-thing)))
  (if (stringp thing)
      (setq thing (intern thing)))
  (let ((bounds (bounds-of-thing-at-point thing)))
    (when bounds
      (goto-char (car bounds))
      (push-mark (cdr bounds) nil transient-mark-mode)
      (setq deactivate-mark nil))))

;;;###autoload
(defun upward-mark-thing ()
  (interactive)
  (if (or  (not (eq last-command this-command))
           (and (eq last-command this-command) (not mark-active)))
      (setq upward-mark-thing-index 0
            upward-mark-thing-trial 0
            upward-mark-thing-original-position (point)))
  (let ((index upward-mark-thing-index)
        (length (length upward-mark-thing-list))
        bounds)
    (let ( thing (limit '*))
      (while (and (null bounds)
                  (< index length))
        (setq thing (nth index upward-mark-thing-list))
        (if (consp thing)
            (setq limit (cdr thing)
                  thing (car thing)))
        (setq bounds (bounds-of-thing-at-point thing))
        (when (or (null bounds)
                  (and (not (eq limit '*)) (>= upward-mark-thing-trial limit))
                  (eq (car bounds) (cdr bounds))
                  (and bounds last-marked-bounds (equal last-marked-bounds bounds))
                  (and mark-active
                       (eq (car bounds) (point))
                       (eq (cdr bounds) (mark))))
          (setq bounds nil
                index (1+ index)
                upward-mark-thing-index (1+ upward-mark-thing-index)
                upward-mark-thing-trial 0)
          (goto-char upward-mark-thing-original-position)))
      (message (concat (prin1-to-string thing) "  selected")))
    (when bounds
      (setq  last-marked-bounds bounds)
      (setq upward-mark-thing-trial (1+ upward-mark-thing-trial))
      (goto-char (car bounds))
      (push-mark (cdr bounds) t 'activate)
      (setq deactivate-mark nil))))

(defun define-thing-commands ()
  (dolist (thing (list-thing))
    (dolist (op '(mark kill copy))
      (let ((symbol (intern (format "%s-%s" op thing))))
        (if (and (fboundp symbol)
                 (not (get symbol 'thingopt)))
            (setq symbol (intern (format "%s-%s*" op thing))))
        (put symbol 'thingopt t)
        (fset symbol `(lambda () (interactive) (,(intern (format "%s-thing" op)) ',thing)))))))

(defvar kill-thing-map
  '((?w . word)
    (?e . sexp)
    (?s . symbol)
    (?t . sentence)
    (?p . paragraph)
    (?f . defun)
    (?F . filename)
    (?l . list)
    (?L . up-list)
    (?S . string)
    (?U . url)
    (?P . page)))

(defun kill-region-dwim-1 (function)
  (if (and transient-mark-mode mark-active)
      (call-interactively function)
    (let* ((c (read-char))
           (thing (assoc-default c kill-thing-map))
           (bounds (if thing (bounds-of-thing-at-point thing))))
      (cond
       (bounds
        (funcall function (car bounds) (cdr bounds))
        (message "Saved %s." thing))
       (thing
        (message "There is no %s here." thing))
       (t
        (message "Nothing here."))))))

;;;###autoload
(defun kill-region-dwim ()
  (interactive)
  (kill-region-dwim-1 'kill-region))

;;;###autoload
(defun kill-ring-save-dwim ()
  (interactive)
  (kill-region-dwim-1 'kill-ring-save))

(defun string-face-p (face)
  (let (result)
    (or (consp face)
        (setq face (list face)))
    (while (and face (null result))
      (if (memq (car face) '(font-lock-string-face font-lock-doc-face))
          (setq result t)
        (setq face (cdr face))))
    result))

(defun forward-string (&optional arg)
  (interactive "p")
  (if (null arg)
      (setq arg 1))
  (ignore-errors
    (cond
     ((> arg 0)
      (dotimes (i arg)
        (while (and (re-search-forward "\\s\"")
                    (string-face-p (get-text-property (point) 'face))))))
     ((< arg 0)
      (dotimes (i (- arg))
        (while (and (re-search-backward "\\s\"")
                    (string-face-p (get-text-property (1- (point)) 'face)))))))))

(defun backward-string (&optional arg)
  (interactive "p")
  (forward-string (- (or arg 1))))

(defun bounds-of-up-list-at-point ()
  (ignore-errors
    (save-excursion
      (let ((pos (scan-lists (point) -1 1)))
        (goto-char pos)
        (forward-list)
        (cons pos (point))))))

(put 'up-list 'bounds-of-thing-at-point
     (symbol-function 'bounds-of-up-list-at-point))

(defun forward-defun (&optional arg)
  (interactive "p")
  (if (null arg)
      (setq arg 1))
  (ignore-errors
    (cond
     ((< arg 0)
      (beginning-of-defun (- arg)))
     ((> arg 0)
      (end-of-defun arg)))))

(defun backward-defun (&optional arg)
  (interactive "p")
  (forward-defun (- (or arg 1))))

(provide 'thingopt)
;;; thingopt.el ends here
