---
title: PlantUML-文本化绘制UML多类图表
author: 李岩
tags:
  - emacs
  - plantuml
categories:
  - 程序人生
date: 2023-04-21 20:51:00
---
> 笔者一直都是文本编辑器教派的忠实拥趸：期望将所有的任务都通过文本编辑，而非鼠标/触摸板等，进行实现。从早年的`Vim`，到现而今的`Emacs`，对文本化完成需求是越来越习惯，也越来越依赖了。最近刚好有了些时间，把最近的一些实践整理下。

在之前的文章，[emacs org-mode 绘制思维导图](https://liyan-ah.github.io/2023/02/10/emacs-org-mode%E7%BB%98%E5%88%B6%E6%80%9D%E7%BB%B4%E5%AF%BC%E5%9B%BE/)，中，笔者有提到在探索不跳出`Emacs`这一文本编辑器的情况下，完成思维导图绘制的需求。在翻了一些文章后，找到了一款神器：[PlantUML](https://plantuml.com/zh/)。其完美的匹配了笔者的需求：
1. 不仅是思维导图，工程、文档常用的`UML`图像也能全部支持文本化表示；
2. 功能强大，颜色、文本等格式均能支持；
3. `Emacs`友好，而且可以集成到`Org-mode`里使用。

而且，`PlantUML`支持在线使用，意味着能够很方便的获取、使用。这里做下介绍。  
<!--more-->

## 一、依赖内容
这里先列一下笔者使用时的配置：
1. `plantuml.jar`，安装在本地后，可以通过配置，在本地进行文本->多格式输出的编译。[plantuml.jar 下载](https://plantuml.com/zh/download)；
2. `plantuml` 配置。由于笔者还是使用的`Emacs`，这里列一下参照官网配置的`Emacs`设置。  
```  
;; plantuml
;; 安装 plantuml-mode
(ensure-package-installed 'plantuml-mode) 
;; 设置 plantuml.jar 的本地路径
(setq org-plantuml-jar-path (expand-file-name "~/.emacs.d/tools/plantuml.jar")) 
;; 将 .plantuml 后缀文件默认以 plantuml-mode 打开。非必需，后面都在 org-mode 里使用了
(add-to-list 'auto-mode-alist '("\.plantuml\'" . plantuml-mode)) 
;; 比较重要，在 org-mode 里声明 plantuml 
(org-babel-do-load-languages 'org-babel-load-languages '((plantuml . t)))  
```
配置很简单。下面就可以愉快的使用了。

## 二、plantuml 介绍
[plantuml官网](https://plantuml.com/zh/)，目前支持的部分图标类型：
* UML 图
  1. 时序图
  2. 用例图
  3. 状态图
  4. 活动图
  5. 类图
  6. 用例图
  7. 等等
* 非UML图
  1. 思维导图
  2. 甘特图
  3. 工作分解结构图
  4. 等等
  
在官网中，对每种图都给出了教程及示例，可以通过[在线生成](http://www.plantuml.com/plantuml/uml/SyfFKj2rKt3CoKnELR1Io4ZDoSa70000) 进行感受。  
`PlantUML`的输入是文本，输出可以是`ASCII, PNG, SVG`等等格式。满足日常工作的需求。

## 三、思维导图
### 3.1 一个简单的思维导图
```
#+begin_src plantuml :file mindmap.png
@startmindmap
  <style>
  mindmapDiagram {
    .green {
      BackgroundColor lightgreen
     }
    .yellow {
      BackgroundColor yellow
    }
    .rose{
      BackgroundColor #FFBBCC
    }
  }
  </style>

  * emacs planuml 介绍 <<rose>>
  left side
  ** 依赖内容 <<yellow>>
  ***_ plantuml.jar 安装
  ***_ plantuml 配置
  ** plantuml 介绍 <<yellow>>
  ***_ 支持多种UML文本化编辑
\
  多种格式文件输出的组件
  ***_ 在线体验

  right side
  ** 思维导图 <<green>>
  ***_ 一个简单的思维导图
  ***_ 编译输出
  ** 时序图 <<green>>
  ***_ 一个简单的时序图
  ***_ 编译输出
@endmindmap
#+end_src
```
由于笔者已经在`Org-mode`里配置了`plantuml`，因此只要在`begin_src`后声明`plantuml`即可。通过`:file mindmap.png`指定了输出的文件为`png`格式内容。`C-c C-e`或者`org-export-dispatch`即可通过`org-mode`的输出界面触发编译、输出。

### 3.2 编译输出

输出结果：
mindmap.png
![upload successful](mindmap.png)

## 四、时序图
### 4.1 一个简单的时序图
这里来一点展示内容更丰富的`UML`时序图实际使用示例：
```
#+begin_src plantuml :file ngx_request.png
    @startuml
        title: nginx+php请求处理示例
      [->nginx: <font color=blue>/caller_path
      note right of nginx
      nginx 视角:
      caller=nginx,
      caller_func=/caller_path,
      callee=php,
      callee_func=/index.php/caller_path
      end note
      activate nginx #yellow
      nginx->php: <font color=red>/index.php/caller_path
      activate php #yellow
      note right of php #gray
      laravel
      end note
      php->callee: <font color=blue>/callee_path
      note right of php
      php 视角:
      caller=php,
      caller_func=/index.php/caller_path,
      callee=callee,
      callee_func=callee_path
      end note
      activate callee
      callee->php: response
      deactivate callee
      php->nginx: response
      deactivate php
      nginx->[: response
      deactivate nginx
      note over nginx, php #aqua: 实际四元组:
\
    caller=nginx
caller_func=/caller_path,
callee=callee,
callee_func=callee_path,
  @enduml
#+end_src
```
### 4.2 编译输出
输出结果如下：
ngx_request.png
![upload successful](ngx_request.png)
可以看到，基本上能够满足一般工程文档使用的需求。

以上是本次介绍的内容。周末愉快～
