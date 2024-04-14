---
title: shell-访问字符串同名变量
author: Blacker
tags:
  - shell
categories:
  - code
date: 2019-06-04 21:53:00
---
考虑以下场景：  
期望通过给定的变量名称<code>var_str</code>，打印出该名称对应的变量值<code>${var_str}</code>。使用指令<code>eval</code>可以很方便的实现：  
```
var_str="1213";
ned_param_name="var_str";
eval echo '$'"${ned_param_name}";
```
输出结果为<code>1213</code>;
<!--more-->
<code>eval</code>命令解释如下：
```
eval [arg ...]
    The  args  are read and concatenated together into a single command. 
    This command is then read and executed by the shell, and its exit status is returned as
the value of eval.  If there are no args, or only null arguments, eval returns 0.
eval [参数 ...]
    参数将会被读取并作为一个指令被读入。然后这个指令将会被shell读取并执行，执行结果
将会作为eval的结果。如果没有参数传入，或者只有空参数，eval指令将会返回0。
```
对于上述的例子，<code>echo $var_str</code>将会被读入，并被shell重新执行。输出结果为<code>1213</code>。该结果即作为<code>eval</code>的输出结果。
