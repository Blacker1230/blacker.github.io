---
title: 如何追踪golang channel?
author: 李岩
tags:
  - golang
  - channel
  - bpf
  - observe
categories:
  - BPF
date: 2023-12-08 19:43:00
---
> 2023年就要结束了，算起来距离上一次更新也有很久了。搜肠刮肚，总得在23年结束前再搞两篇总结，算是有始有终。总结今年，总还是绕不过 BPF，golang。既然如此，就对BPF观测golang这个话题再往下挖掘下，先做第一篇文章。下旬如果有时间并且顺利的话，希望能把BPF的原理总结完成。

在[无侵入观测服务拓扑四元组的一种实现](https://liyan-ah.github.io/2023/03/29/cljb83dmh003dkcs61joe1kfh/#more)中，笔者有提到追踪`golang`处理过程的两个无法解决的问题是`golang`里的`channel`处理以及`goroutine pool`。再深究下，这两个问题实际上都可以归纳到对`channel`的处理，因为很多`goroutine pool`都离不了`channel`的使用，比如[Jeffail/tunny](https://github.com/Jeffail/tunny)这个库。  
本文将会构建一个`channel`的追踪的方案。

<!--more-->

# 一、追踪效果
按照惯例，我们还是来看下效果。
```
// terminal 1，启动服务
$ ./drink-srv

// terminal 2，启动追踪脚本
$ sudo bpftrace ./drink.bt
Attaching 7 probes...  // 启动后停止在这里
serve HTTP: /alcohol   // 触发接口后输出
caller: /alcohol, callee: :/unknown/prepare/hotel
serve HTTP: /tea
caller: /tea, callee: :/unknown/prepare/club

// terminal 3，触发服务接口
$ curl "localhost:1423/alcohol?age=22"
$ curl "localhost:1423/tea?age=12"

```


# 二、方案设计
关于`golang channel`的实现及设计，可以参见[图解Go的channel底层实现](https://i6448038.github.io/2019/04/11/go-channel/)，里面有非常生动的动图实现；搭配源码食用更好[runtime/chan.go](https://github.com/golang/go/blob/master/src/runtime/chan.go)。  
笔者在这里再简单的总结下，对`send`及`recv`两种操作设计的状态做一个简单的概述：
`chan-send`的状态：
![overwrote existing file](chan-send.png)
`chan-recv`的状态：
![overwrote existing file](chan-recv.png)

比如，对于下面的代码，派生出的`g1`在开启`select`后，由于`ticketChan`是空的，会触发`g1`让出`m`里的执行权限，进入`gopark`状态。同时，`ticketChan`会将`g1`封装成`sudog`，放到`recvq`队列中。当一段时间之后，其他的`g`将数据写入`channel`里时，会在`chansend`时，检查到`recvq`不为空，会直接将数据拷贝到空闲的`sudog`中。

```
var ticketChan = make(chan TicketInfo, 10)
func HandleDrink() {
    for {
        select {
        case info, ok := <-ticketChan:
			...
            }
        }
    }
}
func main() {
    go HandleDrink()
    ...
}

```

`chanrecv`进入`recvq`对应的`golang`处理逻辑在这里：
```
// runtime/chan.go
	...
	// no sender available: block on this channel.
	gp := getg()
	mysg := acquireSudog()
	mysg.releasetime = 0
	if t0 != 0 {
		mysg.releasetime = -1
	}
	// No stack splits between assigning elem and enqueuing mysg
	// on gp.waiting where copystack can find it.
	mysg.elem = ep
	mysg.waitlink = nil
	gp.waiting = mysg
	mysg.g = gp
	mysg.isSelect = false
	mysg.c = c
	gp.param = nil
	c.recvq.enqueue(mysg)
    ...
    
```

`chansend`直接将数据拷贝到`recvq`对应的`golang`处理逻辑在这里：

```
// runtime/chan.go
	...
	if sg := c.recvq.dequeue(); sg != nil {
		// Found a waiting receiver. We pass the value we want to send
		// directly to the receiver, bypassing the channel buffer (if any).
		send(c, sg, ep, func() { unlock(&c.lock) }, 3)
		return true
	}
    ...
    
```

# 三、方案实现
了解了`channel`的处理流程，追踪的方案就比较明确了，直接在关键的函数处设置`hook`点即可。先来看下目标服务：

```
package main

import (
	"log"
	"net/http"
	"strconv"

	"github.com/gin-gonic/gin"
)

const (
	ALCOHOL = iota + 1001
	COCO
	COFFEE
	TEA
)

type TicketInfo struct {
	Age  int
	Name string
	Type int
}

var ticketChan = make(chan TicketInfo, 10)

func AlcoholH(c *gin.Context) {
	var ticket = TicketInfo{}
	var err error
	ticket.Age, err = strconv.Atoi(c.Query("age"))
	if err != nil {
		c.String(http.StatusOK, "handle failed")
		return
	}
	ticket.Name = c.Query("name")
	ticket.Type = ALCOHOL
	ticketChan <- ticket
	return
}

func TeaH(c *gin.Context) {
	var ticket = TicketInfo{}
	var err error
	ticket.Age, err = strconv.Atoi(c.Query("age"))
	if err != nil {
		log.Println("handle failed, ", err.Error())
		c.String(http.StatusOK, "handle failed")
		return
	}
	ticket.Name = c.Query("name")
	ticket.Type = TEA
	ticketChan <- ticket
	c.String(http.StatusOK, "okay")
	return
}

func HandleDrink() {
	for {
		select {
		case info, ok := <-ticketChan:
			if !ok {
				log.Println("chan closed.")
				return
			}
			log.Println("get ticket")
			switch info.Type {
			case ALCOHOL:
				Alcohol(info)
			case COCO:
				SoftDrink(info)
			case COFFEE, TEA:
				Tea(info)
			default:
				log.Println("unknown drink type")
			}
		}
	}
}

func Alcohol(ticket TicketInfo) {
	var url = "http://localhost/unknown/prepare/hotel"
	http.DefaultClient.Get(url)
	return
}

func SoftDrink(ticket TicketInfo) {
	log.Printf("[%s, %d] drink %d", ticket.Name, ticket.Age, ticket.Type)
	return
}

func Tea(ticket TicketInfo) {
	var url = "http://localhost/unknown/prepare/club"
	http.DefaultClient.Get(url)
	return
}

func main() {
	defer func() {
		close(ticketChan)
	}()

	go HandleDrink()

	var r = gin.Default()
	r.GET("/alcohol", AlcoholH)
	r.GET("/tea", TeaH)

	var srv = &http.Server{
		Addr:    "127.0.0.1:1423",
		Handler: r,
	}
	if srv.ListenAndServe() != nil {
		log.Println("failed to handle service listen")
		return
	}
}

```

对于这样的一个服务，希望达到示例中的追踪效果，对应的方案为：

```
#define OFF_TASK_THRD 4992
#define OFF_THRD_FSBASE 40
#define GOID_OFFSET 152

uprobe:./drink-srv:"runtime.runqput"
{
  $prob_mark = "runqput";
  @prob[$prob_mark] = @prob[$prob_mark] + 1;

  if (@new_go[tid, pid] == 0){
    return;
  }
  $p_goid = @new_go[tid, pid];

  $g = (uint64)(reg("bx"));
  $goid = *(uint64*)($g+GOID_OFFSET);
  @caller_addr[$goid] = @caller_addr[$p_goid];
  @caller_len[$goid]  = @caller_len[$p_goid];
}

uprobe:./drink-srv:"runtime.newproc1"
{
  $prob_mark = "newproc1";
  @prob[$prob_mark] = @prob[$prob_mark] + 1;

  $g = (uint64)(reg("bx"));
  $goid = *(uint64*)($g+GOID_OFFSET);
  if (@caller_addr[$goid] == 0){
    return;
  }
  @new_go[tid, pid] = $goid;
}

// 这里，将 caller 信息和写入 channel 信息的 key 关联起来
uprobe:./drink-srv:"runtime.chansend"
{
  $prob_mark = "chansend";
  @prob[$prob_mark] = @prob[$prob_mark] + 1;

  $cur = (uint64)curtask;
  $fsbase = *(uint64*)($cur+OFF_TASK_THRD+OFF_THRD_FSBASE);
  $g = *(uint64*)($fsbase-8);
  $goid = *(uint64*)($g+GOID_OFFSET);

  // 如果当前执行goroutine中没有caller，跳过
  if(@caller_addr[$goid] == 0){
    return;
  }

  $chan = (uint64)reg("ax");
  $qcount = *(uint32*)($chan + 0);
  $buf = *(uint64*)($chan+16);
  @send_addr[$chan, $qcount] = @caller_addr[$goid];
  @send_len[$chan, $qcount]  = @caller_len[$goid];

  return;
}


uprobe:./drink-srv:"runtime.chanrecv"
{
  $prob_mark = "chanrecv";
  @prob[$prob_mark] = @prob[$prob_mark] + 1;

  $cur = (uint64)curtask;
  $fsbase = *(uint64*)($cur+OFF_TASK_THRD+OFF_THRD_FSBASE);
  $g = *(uint64*)($fsbase-8);
  $goid = *(uint64*)($g+GOID_OFFSET);

  $chan = (uint64)reg("ax");
  $qcount = *(uint32*)($chan + 0);
  $buf = *(uint64*)($chan+16);
  if (@send_addr[$chan, $qcount] == 0){
    return;
  }
  @caller_addr[$goid] = @send_addr[$chan, $qcount];
  @caller_len[$goid]  = @send_len[$chan, $qcount];

  return;
}

uprobe:./drink-srv:"runtime.send"
{
  $prob_mark = "send";
  @prob[$prob_mark] = @prob[$prob_mark] + 1;

  $chan = (uint64)reg("ax");
  $sg = (uint64)reg("bx");
  $g = *(uint64*)($sg+0);
  $goid = *(uint64*)($g+GOID_OFFSET);

  $qcount = *(uint32*)($chan+0);

  @caller_addr[$goid] = @send_addr[$chan, $qcount];
  @caller_len[$goid]  = @send_len[$chan, $qcount];

  return;
}


/*
type serverHandler struct {
	srv *Server
}
func (sh serverHandler) ServeHTTP(rw ResponseWriter, req *Request) {
*/
uprobe:./drink-srv:"net/http.serverHandler.ServeHTTP"
{
  $prob_mark = "ServeHTTP";
  @prob[$prob_mark] = @prob[$prob_mark] + 1;

  $cur = (uint64)curtask;
  $fsbase = *(uint64*)($cur+OFF_TASK_THRD+OFF_THRD_FSBASE);
  $g = *(uint64*)($fsbase-8);
  $goid = *(uint64*)($g+GOID_OFFSET);

  $req_addr = reg("di");
  // offset(Request.URL) = 16
  $url_addr = *(uint64*)($req_addr+16);
  // offset(URL.Path) = 56
  $path_addr = *(uint64*)($url_addr+56);
  $path_len  = *(uint64*)($url_addr+64);

  @caller_addr[$goid] = $path_addr;
  @caller_len[$goid]  = $path_len;

  printf("serve HTTP: %s
", str($path_addr, $path_len));

  return;
}

/*
func (c *Client) do(req *Request) (retres *Response, reterr error) {
*/
uprobe:./drink-srv:"net/http.(*Client).do"
{
  $prob_mark = "do";
  @prob[$prob_mark] = @prob[$prob_mark] + 1;

  $cur = (uint64)curtask;
  $fsbase = *(uint64*)($cur+OFF_TASK_THRD+OFF_THRD_FSBASE);
  $g = *(uint64*)($fsbase-8);
  $goid = *(uint64*)($g+GOID_OFFSET);

  if (@caller_addr[$goid] == 0){
    printf("%d: has no caller.
", $goid);
    return;
  }

  $req_addr = reg("bx");
  // offset(Request.URL) = 16
  $url_addr = *(uint64*)($req_addr+16);
  // offset(URL.Host) = 40
  $host_addr = *(uint64*)($req_addr+40);
  $host_len  = *(uint64*)($req_addr+48);
  // offset(URL.Path) = 56
  $path_addr = *(uint64*)($url_addr+56);
  $path_len  = *(uint64*)($url_addr+64);

  $c_addr = @caller_addr[$goid];
  $c_len  = @caller_len[$goid];

  printf("caller: %s, callee: %s:%s
", str($c_addr, $c_len),
    str($host_addr, $host_len), str($path_addr, $path_len));
}

```

# 四、追踪的风险
至此，看起来`golang channel`是可以追踪的。但是实际上并非如此。比如如下这个示例：

```
func HandleDrink() {
    for {
        select {
        case info, ok := <-ticketChan:
			...
        default: // 注意这个 stop
        	// no stop here
        }
    }
}

```

这段逻辑在代码编写、编译阶段均无问题，是一段完全合理的逻辑。当我们试图追踪这段代码时：
```
$ sudo bpftrace ./drink.bt
Attaching 7 probes...
^C  // 直接停止，没有请求
@prob[chanrecv]: 908571

```

注意，此时并没有做任何的操作，但是这个`chanrecv`这个`hook`点已经触发了数十万次。而我们知道，`BPF hook`点的触发并非没有开销的。因此，目标的代码在完全合理的情况下，我们的追踪程序会给系统带来很大的负载。这显然是我们需要避免的。  

以上，周末愉快～
