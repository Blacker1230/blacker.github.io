---
title: emacs! start org-mode! --org-mode使用备注
author: 李岩
tags:
  - emacs
  - org-mode
categories:
  - code
date: 2021-01-10 20:30:00
---
> 为了更好的`live in emacs`，一款合适的日程管理工具总是需要的。在挣扎了若干次后，最终还是把`org-mode`这一优秀的日程管理工具捡起来了。本文简单记录下使用的方法。

# org-mode介绍
在`神的编辑器emacs`的传说中，往往有`org-mode`的身影。虽然按照(org官网)[orgmode](https://orgmode.org/)官网的描述，`org-mode`并不仅限于在`emacs`中使用，如[开始使用 Org 模式吧，在没有 Emacs 的情况下](https://zhuanlan.zhihu.com/p/57800574)这篇文章就详细讲解了在`vscode`中使用`org-mode`的方式，但是配合`emacs`的万物皆系于`kbd`之上的使用习惯，`org-mode`确实能够发挥最大的功能。  
`org-mode`的基本功能包括设置待办事项、设置待办的标签、查看日历、查看某一天的待办及进度。基本上，满足了对优秀日程管理工具的所有想象。
<!--more-->
这里贴一下[开源世界旅行手册](https://wizardforcel.gitbooks.io/os-world-trip/content/42.html)中涉及的`org-mode`与`oneNote`的对比，能够更加直观的了解`org-mode`的功能：

| org-mode vs oneNote |            |          |
|---------------------|------------|----------|
|                     | Org-mode   | OneNote  |
| 标签                | 强大       | 不支持   |
| 日程表              | 强大       | 不支持   |
| 界面                | 字符       | 漂亮     |
| TablePC             | 不支持     | 非常好   |
| 摘录                | 保持源格式 |          |
| 便捷                | Emacs 内置 | 安装麻烦 |



# 基本使用流程
目前还处于探索阶段了，简单描述下`org-mode`的配置流程。
0. 版本
使用的是`emacs-27.1`版本，默认内置了`org-mode`(值得一提的是，当我在写一篇文章时，发现hexo#admin编辑器是支持部分`emacs`快捷键的，又反映了`emacs`影响之广)。
1. 设置  
`org-mode`在使用时，一般是在文本文档中编辑待办内容，将待办内容加入`org-mode`的日程表。而后通过`org-agenda`来查看指定日期的待办内容，并随着待办内容设置事务的进度。  
使用前，如果是使用`emacs`进行编辑的话，可以在`emacs`配置文件中作如下设置：  
```
;; 将.org结尾的文档，均以org-mode打开
(add-to-list 'auto-mode-alist '("\.org\'" . org-mode))
;; 将org-agenda绑定为Ctrl-c a 快捷键
(global-set-key (kbd "C-c a") 'org-agenda)
```
重新打开`emacs`使配置生效，重新载入`emacs`配置文件即可。
使用时，可以单独建立一个文件夹，来存储不同需求的日程文档（如，笔者在`~/.org/`目录下创建了`2021.org`,`learn.org`等多个文档）。以下是一个简单的待办文档内容（引用自[文章3](https://wizardforcel.gitbooks.io/os-world-trip/content/42.html)）：
```
#+STARTUP: overview  
#+TAGS: { 桌面(d) 服务器(s) }  编辑器(e) 浏览器(f) 多媒体(m) 压缩(z)
#+TAGS:  { @Windows(w)  @Linux(l) }    
#+TAGS:  { 糟糕(1) 凑合(2) 不错(3) 很好(4) 极品(5) }  
#+SEQ_TODO: TODO(T) WAIT(W) | DONE(D!) CANCELED(C@)  
#+COLUMNS: %10ITEM  %10PRIORITY %15TODO %65TAGS  
* 工作  <2021-01-10>-<2022-01-10>
** Emacs  <2021-01-10 21:00 ++1d>
   神之编辑器  
*** org-mode  
    组织你的意念  
```
（更多的内容可以查看下[原文](https://wizardforcel.gitbooks.io/os-world-trip/content/42.html)，本文仅简单介绍）
以`#+`开头的可以认为是本地设置内容。`#+TAGS: `后设置的内容，是本日程中预设的日程标签，标签`()`中的是该标签的缩写，需要保持唯一。在下面的日程（或者`标题`，可以很容易的看出来，和`markdown`是类似的语法）上使用快捷键`Ctrl-c Ctrl-c`(或者说，`C-c C-c`)，即可给日程打上标签。每个`{}`内的标签是互斥的，在设置时，可以注意下。  
下面的日程中,`<2021-01-10>-<2022-01-10>`表示该事件时间范围为`2021-01-10`至`2022-01-10`结束。`<2021-01-10 21:00 ++1d>`表示这个子任务的时间开始于`2021-01-10 21:00`而后每天重复一次(++1w，++1m为周、月，以此类推)。  
而后，保存文件。使用`Ctrl-c [`将当前日程文件纳入`org-mode`的日程表。使用前面配置的快捷键`C-c a`唤出日历，会出现如下提示：

|Press key for an agenda command:|
|----|----|
|a|	本周事件|
|t|	显示所有事件|
|m|	查询标签|
|L|	当前缓冲区时间线|
|s|	查询关键词|
|T|	查询带 TODO 关键词的项|
|M|	查询带 TODO 关键词的标签|
|#|	显示已停止事件|
|q|	退出日程表|
选择`a`，可以查看本周的事件。如果已经到了所设置的事件区间，即可看到我们设置的事件内容。  
以上算是简单的入门了。

# 相关文章
1. [使用org-mode 管理日常事务- 日知录](https://victor72.github.io/blog/2016/06/20/with-org-page-manage-lives/)  
2. [用Org-mode实现GTD](https://www.cnblogs.com/holbrook/archive/2012/04/17/2454619.html)  
3. [组织你的意念：Emacs org mode](https://wizardforcel.gitbooks.io/os-world-trip/content/42.html).
