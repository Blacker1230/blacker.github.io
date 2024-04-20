---
title: ebpf采集mysql请求信息及ebpf对应用安全的思考
author: 李岩
tags:
  - bpf
  - mysql
  - safety
categories:
  - bpf
date: 2022-10-21 19:48:00
---
> 本文笔者继续介绍`ebpf` 的应用：使用`bpftrace`采集`mysql`连接信息，包括数据库地址、`db_name`、`user_name`。在展示采集操作的同时，附上对`ebpf`对云时代应用安全的一些思考。
# 目标
使用`bpftrace`对一个运行中进程的`mysql`请求进行采集，目标采集内容包括数据库地址、`db_name`、`user_name`。
<!--more-->
目标进程代码如下:

```
// blog/main.go
package main

import (
	"fmt"
	"log"
	"net/http"
	"time"

	"github.com/gin-gonic/gin"
	_ "github.com/go-sql-driver/mysql"
	"xorm.io/xorm"
)

var sqlE *xorm.Engine

func init() {
	fmt.Println("init from main")
	var err error
	sqlE, err = xorm.NewEngine("mysql",
		"test:mysqltest@tcp(localhost:3306)/test_db?charset=utf8&parseTime=true") // 随便写个数据库信息，假装是正确的
	if err != nil {
		log.Printf("init mysql failed: %+v
", err)
	}
}

type Resp struct {
	Code int    `json:"code"`
	Msg  string `json:"msg"`
}

type SqlInfo struct {
	Id      int64     `json:"id" xorm:"pk bigint(20)"`
	Created time.Time `json:"created" xorm:"created"`
	Info    string    `json:"info"`
}

func (sql *SqlInfo) TableName() string {
	return "sql_info"
}

func Mysql(c *gin.Context) {
	info := c.Query("info")
	if info == "" {
		now := time.Now().Format("2008-01-02 15:04:05")
		info = now
	}
	sqlInfo := SqlInfo{
		Info: info,
	}
	affected, err := sqlE.Insert(&sqlInfo)
	if err != nil {
		log.Printf("insert db with error: %+v
", err)
	} else {
		log.Printf("affect column nums: %d
", affected)
	}

	c.JSON(http.StatusOK, &Resp{Code: 0, Msg: "mysql req over"})
	return
}

func main() {
	r := gin.Default()
	srv := &http.Server{
		Addr: "0.0.0.0:9981",
	}
	log.Println("server start at: 0.0.0.0:9981")
	r.GET("/sql", Mysql)
	srv.Handler = r
	err := srv.ListenAndServe()
	if err != nil {
		log.Fatal("error with start listener")
	}
}
```

# bpftrace 代码
直接上代码了：

```
#! /bin/bpftrace

/* 保存在 blog/blog.bt 里
 这里使用的 uprobe 函数为 go-sql-driver 里的内容。源代码在：
 https://github.com/go-sql-driver/mysql/blob/master/connector.go#L23
 定义为：
 func (c *connector) Connect(ctx context.Context) (driver.Conn, error) {...}
*/
uprobe:./blog:"github.com/go-sql-driver/mysql.(*connector).Connect"
{
    printf("Connect
");
    $cfg_addr = *(uint64*)sarg0; // 获取 c.cfg 的地址
    $user_addr = *(uint64*)($cfg_addr); // 获取 c.cfg.User
    $user_len = *(uint64*)($cfg_addr+8); // 获取 len(c.cfg.User)
    //$pwd_addr = *(uint64*)($cfg_addr+16); // 请注意这里注释掉的内容
    //$pwd_len = *(uint64*)($cfg_addr+24);
    $addr_addr = *(uint64*)($cfg_addr+48);
    $addr_len = *(uint64*)($cfg_addr+56);
    $db_addr = *(uint64*)($cfg_addr+64);
    $db_len = *(uint64*)($cfg_addr+72);
    printf("user: %s
", str($user_addr, $user_len));
    //printf("pwd: %s
", str($pwd_addr, $pwd_len));
    printf("addr: %s
", str($addr_addr, $addr_len));
    printf("db: %s
", str($db_addr, $db_len));
}

```
而后启动应用程序`blog`，启动监听程序`sudo bpftrace ./blog.bt`，请求`blog`的`/sql`接口以触发`blog`对`sql`的请求。整个过程对`blog`程序来说没有任何的不平凡之处，但是我们已经获取了采集结果。
附上执行结果如下：
```
$ ./blog
init from main
[GIN-debug] [WARNING] Creating an Engine instance with the Logger and Recovery middleware already attached.

[GIN-debug] [WARNING] Running in "debug" mode. Switch to "release" mode in production.
 - using env:	export GIN_MODE=release
 - using code:	gin.SetMode(gin.ReleaseMode)

2022/10/21 20:15:38 server start at: 0.0.0.0:9981
[GIN-debug] GET    /sql                      --> main.Mysql (3 handlers)
2022/10/21 20:18:52 insert db with error: dial tcp 127.0.0.1:3306: connect: connection refused
[GIN] 2022/10/21 - 20:18:52 | 200 |    3.679499ms |       127.0.0.1 | GET      "/sql"
```
此时，在采集侧：
```
$ sudo ./blog.bt
Attaching 1 probe...
Connect
user: test
addr: localhost:3306
db: test_db
```
我们已经获取了需要的信息。
# 对采集代码的一些说明
`bpftrace`语法部分，参见[github-bpftrace-reference_guid](https://github.com/iovisor/bpftrace/blob/master/docs/reference_guide.md)。里面有`ebpf`的一些简单介绍以及`bpftrace`的使用说明。代码里的主要逻辑，则需要参见`golang`的语法来理解。部分简述如下：
* 类里的方法，实际调用的时候，第一个参数为对象的地址；
* go-1.16 及之前的版本，参数存储在栈上；

剩下的内容就比较好理解了：`ebpf`提供的核心功能包括按需读取用户空间内的数据。结合[golang-常见类型字节数](https://liyan-ah.github.io/2022/06/06/golang-%E5%B8%B8%E8%A7%81%E7%B1%BB%E5%9E%8B%E5%AD%97%E8%8A%82%E6%95%B0/#more)可以比较快的推导出我们需要的信息在地址内的偏移量。同时，在[bpftrace无侵入遍历golang链表](https://liyan-ah.github.io/2022/07/22/bpfTrace-%E8%BF%BD%E8%B8%AA-uprobe/#more)曾经提到过，如果目标对象比较大，无法在`ebpf`代码里完整定义该对象（内核限制单个`ebpf`的`hook`点程序的栈空间大小在`512B`），我们访问对象里的成员时，使用的方法就是偏移量访问。
# ebpf 与应用安全的一些思考
最后提一点自己的思考。  
请回到`bpftrace`代码里，里面的`pasword`信息获取的操作被注释掉了。其实我们去掉注释，仍然能够按照预期获取结果。这就意味着，如果我们拥有机器上的权限，并且机器满足我们的采集需求，应用里的核心信息（这里是数据库的密码）将被简单的获取。无论数据库密码如何存储：配置文件、源代码、通过网络配置下发等。只要有涉及数据库访问的用户态函数，有涉及数据库密码传递的内容，这些信息存在被获取的风险，只要采集人拥有`root`权限。  
这里引出另外一个问题：如果一个用户拥有机器上的管理员权限，`TA`是否应该拥有机器上所有进程信息的准入权。这里的进程信息，显然是包括机器上容器内的进程信息的，无论是公有云或者私有云。
