---
title: "存储概述"
description: MYSQL、ES、CK。
date: 2024-10-02T14:11:34+08:00
comments: true
categories:
    - 理论内容
tags:
    - storage
---

> 最近工作中一直接触存储相关的内容，感觉对现在的存储分类及各个存储的优缺点等了解的还很少。趁着这个机会整理下相关的内容。相信会有收获。

## 简介

存储是系统设计中不可缺少的一部分，而存储的选择又有很多种，相关的概念也很繁杂：关系型数据库、列数据库、文件型数据库等等。在为系统选择合适的数据库之前，显然需要了解这些数据库的概念及它们的优缺点。这些是笔者还不具备的能力。笔者试着在本文中对这些概念进行总结，并结合实践来论述下使用需要注意的内容。本文主要内容均整理自互联网文档。希望是个引子，后面依据实践，持续补充及修正涉及到的内容。

从工作中的经验来看，笔者对存储系统一般关注系统的存储方式、数据一致性的保障方式、如何进行扩展。部分已确定的内容罗列在下面：

| 系统          | 存储类型     | 存储方式              | CAP满足                                    | 扩展方式                                                                        | 常见优化                                                                     | 价格                               |
|---------------|--------------|-----------------------|--------------------------------------------|---------------------------------------------------------------------------------|------------------------------------------------------------------------------|------------------------------------|
| MySQL         | 关系型数据库 | B+树 (InnoDB引擎)     | CA（同步复制），AP（异步复制、半同步复制） | 一般采用主从同步的方式。通过消费binlog, redolog, undolog 来实现数据间的一致性。 | 加机器（CPU、内存、SSD盘）、集群同步方式修改（异步同步）、读写分离、分库分表 | 均衡                               |
| Elasticsearch | 检索系统     | 索引+JSON为基础的文档 | CA（设置同步配置），AP                     | 扩展 shard 来实现水平扩展                                                       | 增加 Shard，索引优化，加机器                                                 | 涉及到倒排索引的构建，较为耗费 CPU |

## MySQL

本节期望能够回答以下问题：
* MySQL 是否一定是 B+ 树的存储结构。
* InnoDB 为何选择 B+ 树数据结构。
* 一个 InnoDB 实例支持多少条数据记录。
* InnoDB 中索引（含主键）都存储在哪里。

### 2.1 简述

MySQL 是最经典的存储系统了，作为关系型数据库中当之无愧的主流，很难找出一个后端的系统（非某个单独的服务）在运行时可以完全不使用 MySQL（笔者工作的这些年还没有遇到过）。通常认为 MySQL 是行数据库，这通常是指 InnoDB 存储引擎是行数据库。需要注意的是，MySQL 同样是有列数据库引擎[^12]。

### 2.2 InnoDB

MySQL 支持诸多的存储引擎，一般会使用 InnoDB[^7]（当然也支持 MyISAM，CSV，内存等方式的存储引擎）。本文中对 MySQL 的介绍也默认以 InnoDB 作为存储引擎。从分类上来看，MySQL 是典型的关系型数据库了：它的所有数据检索、查询等操作都是以关系组织操作为核心的。在此基础上有诸如外键、多表联查等操作。关系型数据库也是比较贴合实际的各种数据关系并且易于理解的，很多数据库课程中往往会通过构建一个图书管理系统的方式来学习 MySQL，这里书籍种类标签、各种借阅的关系描述也是关系型数据库所擅长的。

InnoDB 引擎默认使用 B+ 树来存储数据[^9]：将索引存储在内存中而将实际的数据存储在磁盘中，而且由于 B+ 树的特点，使得任意记录所在的页均可通过有限次的检索动作来定位到，并加载到内存中做进一步的检索。这一点较好的兼容了数据的查询性能及数据的存储容量。实际的记录会存放在数据页中（一般在磁盘中）。而索引页一般会在 MySQL 进程启动后加载到内存中。值的注意的是，MySQL 实例启动后，可以支持多种通信方式：TCP 连接、管道｜共享内存（需要指定参数）、UNIX 套接字等。

InnoDB 引擎中，明确声明为主键的字段（或者在没有明确生命为主键的情况下，第一个被声明为索引的字段）会存储在聚集索引表中（B+树）。而非主键的索引则存储在辅助索引表中（同样为 B+ 树）。不同的是，与聚集索引表中会存储数据页的地址不同，辅助索引表中存储的是目标数据的聚集索引信息，即主键信息。当使用非主键索引查询数据时，需要先从辅助索引表中检索出主键的值，再到聚集索引中检索出实际数据页的内容并加载到内存中。在硬盘足够大的情况下，B+ 树中索引的设计决定了单个 InnoDB 实例能够存储多少数据[^11]。需要注意的是， B+ 树并不是二叉树，父节点可能会有很多子节点。限制内存非叶节点中能够存储索引条数的因素包括索引字段的大小、InnoDB 自身的叶结构等。从理论上看，单个 InnoDB 实例能存储多少数据取决于单个 B+ 树能存储多少数据。

### 2.3 待确认
* 一条记录的写入、同步、查询的过程。

## Elasticsearch

本节期望能够回答以下问题：
* ES 的数据存储方式。
* ES 的数据同步方式。
* ES 的数据存储、查询过程。

### 3.1 简述
Elasticsearch，ES，也是经典的存储了，其本身基于 Lucene 进行构建。ES 强大的全文索引能力使得其经常运用在很多检索的场景中，比如视频网站或者简单的文档检索就可以直接使用 ES，从这一点看，预期说 ES 是存储系统，不如说 ES 是检索系统。因为其强大的检索能力，以 ES 为基础的 ELK 生态系统也是日志存储中可以开箱即用的解决方案。

### 3.2 系统组成
ES 对外通过 index 提供查询能力，index 又可以通过设置 shard 数目来达到横向扩展的能力。当一个 ES 集群的读写压力很大时，可以通过调大 shard 数来使得单个 shard 的读写压力更小。当然，如果每个 node 节点启动了很多的 shard，比如已经到了机器的性能极限，此时即使扩充 shard，物理机的限制也会使得 ES 的查询效果有优化效果。除了横向扩展，ES 还通过 Replicas 备份的方式来实现容灾备份的效果。当 index 中的某个 shard 出现异常时，可以切换到备份的分片中[^14]。值的注意的是，index 中包含了正倒排的索引，而基础数据仍然是基于 JSON 的展示结构[^19]。

### 3.3 数据处理过程
数据的写入动作会由 Coordinate Node 来处理，该 Node 可能是集群中的任一 Node。而后会依据文档 ID 来路由到对应的 shard 组（包含其备份）中的一个 node1 上。node1 在处理完成本节点的操作后，会将请求并行发送到其他副本中，在确认其他副本写入完成后，会将写成功的结果发送回去（可以通过参数控制，满足了 C）[^18]。

数据在检索时，同样会将请求发送到 Coordinating Node，并在该 Node 上进行分词等操作。而后将分词结果发送到所有的 shard 上去检索 doc 的排序字段。排序字段检索结果依旧会汇聚到该 Node 上，排序后找到所需要的 doc id 并到该 doc 的 shard 上取获取实际的 doc，返回给 Client[^20]。

### 3.4 待确认
* 完整的架构图。
* 完整的数据处理流程。

## ClickHouse

本节期望能够回答以下问题：
* CK 的数据存储方式，横向扩展方式。
* CK 的数据同步方式。
* CK 的数据存储、查询过程。

### 4.1 简述

ClickHouse 是近几年比较火的列式存储数据库。其与行式存储的区别可以认为是：列式存储是以列为单位的存储。当一行中往往仅需要读取少数几个列的情况下，列存储能够获得更好的读取效果。而且，由于每列的数据往往是相同的类型，按照列进行存储可以更方便的进行压缩。这样的特性使得列存储在 OLAP 的场景下可以获得更好的检索效果及更好的资源利用率[^22]。

### 4.2 系统组成

CK 同样有诸多的表引擎，使用比较广泛的是 MergeTree。一般来说，每个 Table 可以按照多个 Partition 来进行划分。

集群部署时，一般使用 ZooKeeper 来维护集群的关系，启动多个节点并按照节点的角色划分来实现主备及横向扩展。


### 4.3 待确认
* CK 数据同步方式。
* CK 数据处理过程。


## 后记

存储是一个很广大的领域。仅本文中设计到的 MySQL、ES、CK 这三种典型的存储系统就消耗了笔者两天的时间来准备文档，而且涉及的内容还很浅。而本文中未涉及到的 Druid、HDFS、Redis、RocksDB、Cassandra 等涉及的存储内容更多。感觉笔者一时怕是无法有效的整理完成。本次且这样吧。

在本次整理的过程中，笔者同样感觉到资料的缺失：MySQL 的文档及图书资料较为丰富，到后面的 ES、CK 等就开始缺少内容了。希望笔者能够贡献若干篇有深度的文章。


[^1]: https://draveness.me/mysql-innodb/。较为详细的介绍了 InnoDB 的一些概念。
[^2]: https://www.cnblogs.com/wtzbk/p/14410608.html。介绍了 MySQL 数据写入时的处理过程。
[^3]: https://www.cnblogs.com/danielzzz/p/16852877.html。MySQL 如何保障数据一致性。
[^4]: https://juejin.cn/post/6895761455358935053。MySQL 的 CAP 取舍介绍。
[^5]: https://stackoverflow.com/questions/64578822/cap-theorm-why-mysql-is-ca。
[^6]: https://www.cnblogs.com/kylinlin/p/5258719.html。MySQL 主从同步过程介绍。
[^7]: https://dev.mysql.com/doc/refman/8.4/en/innodb-introduction.html。InnoDB introduction。
[^8]: https://cloud.tencent.com/developer/article/1899186。InnoDB 为什么要选择 B+ 树来存储数据。
[^9]: https://medium.com/@relieved_gold_mole_613/why-does-mysql-use-b-trees-7807ed3090bc。 why does mysql use b+ tree。
[^10]: https://book.douban.com/subject/24708143/。MySQL 技术内幕（InnoDB 存储引擎）。
[^11]: https://cloud.tencent.com/developer/article/2123136。单表最大 2000 万行数据。
[^12]: https://www.cnblogs.com/dhName/p/14233938.html。mysql 的存储引擎和 infobright 引擎说明。
[^13]: https://elasticsearch.cn/article/6178。ES 中数据是如何存储的。
[^14]: https://zhuanlan.zhihu.com/p/32990496。从 Elasticsearch 来看分布式架构系统设计。
[^15]: https://www.cnblogs.com/fxh0707/p/17126196.html。ES 文档存储流程。
[^16]: https://cloud.tencent.com/developer/article/2398626。Elasticsearch 数据写入、检索流程及底层原理全方位解析。
[^17]: https://www.elastic.co/guide/en/elasticsearch/reference/current/docs-replication.html。Reading and Writing documents。
[^18]: https://www.cnblogs.com/jimoer/p/15573952.html。ES 写入数据的过程是怎样的？以及是如何快速更新索引数据的？
[^19]: https://www.knowi.com/blog/what-is-elastic-search/。what is elastic search。
[^20]: https://www.cnblogs.com/liuzhihang/p/elasticsearch-4.html。ES 查询检索数据的过程。
[^21]: https://xie.infoq.cn/article/9f325fb7ddc5d12362f4c88a8。行式存储与列式存储。
[^22]: https://www.cnblogs.com/ya-qiang/p/13680283.html。ClickHouse 的特性。
[^23]: https://clickhouse.com/docs/zh/development/architecture。ClickHouse 架构概述。
[^24]: https://www.cnblogs.com/crazymakercircle/p/16718469.html。
[^25]: https://cloud.tencent.com/developer/article/1953788。常见 ClickHouse 集群部署架构。
[^26]: https://xie.infoq.cn/article/cc6415931f2f9aa26b6ae12e2。ClickHouse 常见集群部署架构。
[^27]: https://www.cnblogs.com/eedbaa/p/14512803.html。ClickHouse 数据存储结构。 
