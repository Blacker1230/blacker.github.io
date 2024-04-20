---
title: ebpf 采集ebpf 采集tag+tcp五元组
author: 李岩
date: 2023-02-24 21:44:49
tags:
  - bpf
  - tcp
categories:
  - bpf
---
> 在这里对文章题目作一些说明。笔者想了很长时间也无法给这篇文章想个恰当的表意题目。实际上使用`ebpf`来进行服务观测是有在进行的，比如获取目前`l1s`上的常见的四元组。但是本文不是介绍这部分可观测实践的。文章希望阐述的场景是：采集请求触发里的一些信息（诸如`trace`及其他`header`等）并和服务请求下游的传输层五元组(protocol, src-ip, src-port, dst-ip, dst-port)进行关联。这也是最近工作中实际遇到的问题。

基于`ebpf`的丰富的特性能够获取服务很多的信息，不同特性的组合更是可以达到极强的数据整合能力。比如通过`uprobe`便捷的获取业务信息后，结合`kprobe`来获取系统调用里的内容，可以获取一般侵入式可观测代码无法获取的内容。笔者最近遇到的一个实际问题是：获取服务`A`的接口`/a`响应后，向下游`B`发起的请求时，所使用的传输层五元组，同时带上结合一些`/a`触发时的一些内容，比如`caller_fun`或者`traceId`。  
这里值得说明的是，用户态请求的是一个域名。域名的解析是在`golang`的`http`里完成的。但是请注意，`golang`发起`tcp`请求时，`local port`设置的是`0`，然后由内核态的`tpc`处理来选择一个空闲的`port`作为`socket`里的`lport`。这部分的信息通过代码的埋点显然是无法获取的（详情可参考[TCP连接中客户端的端口号是如何确定的？](https://mp.weixin.qq.com/s?__biz=MjM5Njg5NDgwNA==&mid=2247485577&idx=1&sn=24220fcc3782f61b4a691585251f1c27&chksm=a6e309b2919480a4696c8a2944ad887951100b5068050d354eab40cf0c8f1124b6367176a0a6&scene=21#wechat_redirect)）。  
下面介绍下实现效果及思路。  
> 关于`bpftrace`使用的介绍，可以参见：[bpftrace 无侵入遍历golang链表](https://liyan-ah.github.io/2022/07/22/bpfTrace-%E8%BF%BD%E8%B8%AA-uprobe/#more)，关于`ebpf`来进行数据采集的实践，可以参见[ebpf采集mysql请求信息及ebpf对应用安全的思考](https://liyan-ah.github.io/2022/10/21/ebpf%E9%87%87%E9%9B%86mysql%E8%AF%B7%E6%B1%82%E4%BF%A1%E6%81%AF%E5%8F%8Aebpf%E5%AF%B9%E5%BA%94%E7%94%A8%E5%AE%89%E5%85%A8%E7%9A%84%E6%80%9D%E8%80%83/)。


<!--more-->

# 实现效果

服务端启动、触发的效果：

```  
# 启动目标服务
./caller_tuple
[GIN-debug] [WARNING] Creating an Engine instance with the Logger and Recovery middleware already attached.

[GIN-debug] [WARNING] Running in "debug" mode. Switch to "release" mode in production.
 - using env:	export GIN_MODE=release
 - using code:	gin.SetMode(gin.ReleaseMode)

[GIN-debug] GET    /echo                     --> main.Echo (3 handlers)
# 这里触发一次接口调用
[GIN] 2023/02/24 - 22:05:29 | 200 |   85.618975ms |       127.0.0.1 | GET      "/echo"
```   

`bpftrace` 采集端的效果：
```   
# 启动采集
bpftrace ./caller.bt
Attaching 3 probes...
start to gather caller info.
get caller path: /echo
# 将 caller_path 和 传输层五元组结合起来（本机的IP实际上是输出的，但是为了信息安全，就使用 0.0.0.0 来代替了）
caller info: /echo
3326691  caller_tuple     0.0.0.0                            38610  110.242.68.66                           80
```

# 代码实现
这里分别上一下目标服务`caller_func`以及采集脚本`caller.bt`的代码，来说明下实现思路。


```     
// ./caller_tuple/main.go
package main

import (
	"net/http"

	"github.com/gin-gonic/gin"
)

type Resp struct {
	Errno int64  `json:"errno"`
	Msg   string `json:"msg"`
}

func Echo(c *gin.Context) {
	req, _ := http.NewRequest(http.MethodGet, "http://baidu.com", nil)
	client := http.Client{}
	resp, err := client.Do(req)
	if err != nil {
		c.JSON(http.StatusOK, &Resp{Errno: 1, Msg: "request error"})
		return
	}
	defer resp.Body.Close()
	c.JSON(http.StatusOK, &Resp{Errno: 0, Msg: "ok"})
	return
}

func main() {
	r := gin.Default()
	srv := &http.Server{
		Addr: "0.0.0.0:3344",
	}
	r.GET("/echo", Echo)
	srv.Handler = r
	srv.ListenAndServe()
}


// caller_tuple/caller.bt
#!/usr/bin/env bpftrace

#define AF_INET 2

struct sock_common {
        union {
                struct {
                        __be32 skc_daddr;
                        __be32 skc_rcv_saddr;
                };
        };
        union {
                unsigned int skc_hash;
                __u16 skc_u16hashes[2];
        };
        union {
                struct {
                        __be16 skc_dport;
                        __u16 skc_num;
                };
        };
        short unsigned int skc_family;
};

struct sock {
        struct sock_common __sk_common;
};

BEGIN{
    printf("start to gather caller info.
");
    @caller[pid] = "none";
}

// 这里通过 uprobe 来便捷的获取会话信息。同时将信息写入bpf_map
uprobe:./caller_tuple:"net/http.serverHandler.ServeHTTP"{
    $req_ptr = sarg3;
    $method_ptr = *(uint64*)($req_ptr);
    $method_len = *(uint64*)($req_ptr+8);

    /* read request.url.Path */
    $url_ptr = *(uint64*)($req_ptr + 16);
    $path_ptr = *(uint64*)($url_ptr+56);
    $path_len = *(uint64*)($url_ptr+64);
    printf("get caller path: %s
", str($path_ptr, $path_len));
    // 这里使用 pid 来作为 key 只是为了实现方便。实际可以采取其他更有区分性的内容。
    @caller_ptr[pid]=$path_ptr;
    @caller_len[pid]=$path_len;
}

// 通过 kprobe 来获取用户态无法获取的内容。同时通过 bpf_map 来控制生效及内容的交互。
kprobe:tcp_connect
{
    if (@caller_ptr[pid] == 0){
        return;
    }
    $ptr = @caller_ptr[pid];
    $len = @caller_len[pid];
    printf("caller info: %s
", str($ptr, $len));
    @caller_ptr[pid] = 0;
    @caller_len[pid] = 0;

  $sk = ((struct sock *) arg0);
  $inet_family = $sk->__sk_common.skc_family;

  if ($inet_family == AF_INET) {
    $daddr = ntop($sk->__sk_common.skc_daddr);
    $saddr = ntop($sk->__sk_common.skc_rcv_saddr);
    $lport = $sk->__sk_common.skc_num;
    $dport = $sk->__sk_common.skc_dport;
    $dport = (((($dport) >> 8) & 0xff) | ((($dport) & 0xff) << 8));
    printf("%-8d %-16s ", pid, comm);
    printf("%-39s %-6d %-39s %-6d
", $saddr, $lport, $daddr, $dport);
  }
}
```  

这样就达到了笔者的目标。这只是`ebpf`应用的一个简单的场景，更多的`metric`采集内容仍在进行。  
以上，周末愉快！
