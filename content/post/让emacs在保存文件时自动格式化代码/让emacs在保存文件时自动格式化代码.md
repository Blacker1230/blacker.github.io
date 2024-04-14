---
title: 让emacs在保存文件时自动格式化代码
author: 李岩
tags:
  - emacs
  - lsp
  - c-mode
  - clang-format
categories:
  - 程序人生
date: 2022-07-15 20:34:00
---
> [liam](https://liam.page/)同学在[让 Vim 在保存文件时自动格式化代码](https://liam.page/2020/11/04/Vim-auto-format-codes-on-save/)一文中展示了保存时自动化格式代码的`vim`配置。作为`emacs`用户，自然有自己的解决方案。以下呈现。

<!--more-->

# 配置
`emacs`进行`c/c++`的开发，离不开支持代码自动补全、库函数联想等功能，所以本文顺带把[`lsp`](https://microsoft.github.io/language-server-protocol/)配置也一并带上了，不同于[emacs-若干语言 lsp 配置备注](https://blacker1230.github.io/2021/10/12/emacs-%E8%8B%A5%E5%B9%B2%E8%AF%AD%E8%A8%80-lsp-%E9%85%8D%E7%BD%AE%E5%A4%87%E6%B3%A8/)里的`eglot`，这里使用的是`ccls`。直接上配置吧，比较简单：
```
;; 使用国内 elpa 源来加速插件安装
(defun w-install(pkg)
  ;; would be a wrapper for package-install
  (require 'package)
  (setq package-archives
	'(("gnu"   . "http://mirrors.tuna.tsinghua.edu.cn/elpa/gnu/")
	   ("melpa" . "http://mirrors.tuna.tsinghua.edu.cn/elpa/melpa/")))
  (package-initialize)
  (package-refresh-contents)
  (unless (package-installed-p pkg)
    (package-install pkg)))

;; 辅助判断插件安装通用函数
(defun ensure-package-installed (&rest packages)
  "Assure every package was installed, ask for installation if it's not.
a list of installed packages or nil for every skipped package."
  (mapcar
   (lambda (package)
          (if (package-installed-p package)
              nil
            (if (y-or-n-p (format "Package %s is missing. Install it?" package))
                (w-install package)
              package)))
   packages))

;; clang-format 在文件保存时格式化代码
(ensure-package-installed 'clang-format)
(defun clang-format-on-save-hook()
  "Create a buffer local save hook."
  (add-hook 'before-save-hook
            (lambda ()
              (when (locate-dominating-file "." ".clang-format")
                (clang-format-buffer))
              ;; Continue to save
              nil)
            nil
            ;; Buffer local hook.
            t))

;; Run this hook for c-mode-hook and c++-mode-hook
(add-hook 'c-mode-hook   (lambda () (clang-format-on-save-hook)))
(add-hook 'c++-mode-hook (lambda () (clang-format-on-save-hook)))
;; create default clang-format file
;; https://releases.llvm.org/3.6.2/tools/docs/ClangFormatStyleOptions.html
;; clang-format -style=llvm -dump-config > .clang-format

;; 另外，这里列出使用的 lsp-language-server 配置。
;; 服务端使用 ccls，客户端则使用 ccls.el。同时将 ccls 作为 c-mode 的hook运行
;; https://github.com/MaskRay/ccls/wiki/Build
;; set up lsp-mode for c/c++
(ensure-package-installed 'ccls)
(use-package ccls
  :hook ((c-mode c++-mode objc-mode cuda-mode) .
         (lambda() (require 'ccls) (lsp))))

```
代码格式部分则主要由`.clang-format`文件控制。其配置方法可以参见官网：[ClangFormat](https://clang.llvm.org/docs/ClangFormat.html)。
