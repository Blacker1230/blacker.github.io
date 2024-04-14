---
title: redisgo 连接报错
author: 李岩
tags:
  - go
  - redisgo
  - debug
categories:
  - code
date: 2021-08-18 17:26:00
---
> 记一次`redisgo`库使用时，连接远程`redis`服务写数据报错的问题。

 `redis`写数据时，出现报错`write: broken pipe`及`write: connection reset by peer`。看着都是网络的问题，使用`redis-cli`可以登陆并且执行查询等操作。经过排查，是写的数据量过大，导致写数据持续时间过长，排查的思路是猜想->验证`@A@`。  
 对于多个数据可以进行拆分。对于单个完整的数据，还没有太好的拆分思路（或许基于 `pb` 进行压缩，会是个好方式？）
 
 # 参考文章
 [python redis读写报错：Broken Pipe Error Redis](https://blog.csdn.net/xieganyu3460/article/details/82884346)
