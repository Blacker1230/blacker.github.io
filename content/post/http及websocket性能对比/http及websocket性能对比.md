---
title: http及websocket性能对比
author: 李岩
date: 2021-07-15 19:29:10
tags:
  - websocket
categories:
  - code
---
> 从过往的经历中来看，使用websocket作为http协议的替代似乎是一种潮流。websocket以其小包头、全双工的优势，弥补了http协议的性能上的缺陷。对于长链接需求，完全可以在初始化时创建websocket连接，在业务交互时直接进行通信，使得通信过程更加流畅。相信在基于Quic的http3协议走向成熟应用前，websocket在性能上都具有优势。本文以golang语言为基础，构造场景进行两种协议的性能对比。

<!-- more-->

# 场景
在服务端分别启动了```http```服务及```websocket```服务，返回所接受到的信息。构造```BenchmarkHttp```、```BenchmarkWS```进行请求，发送递增字符串。
# 代码
```
// server.go

/*
	golang中使用的是http1.1协议，默认为长链接。仅第一次发送请求时进行握手。
*/

package main

import (
	"flag"
	"fmt"
	"io"
	"log"
	"net/http"
	"sync"

	"github.com/gorilla/websocket"
)

var ws_addr = flag.String("ws_addr", "localhost:9080", "websocket http service address")
var http_addr = flag.String("http_addr", "localhost:9090", "http address address")

var upgrader = websocket.Upgrader{} // use default options

func ws_echo(w http.ResponseWriter, r *http.Request) {
	c, err := upgrader.Upgrade(w, r, nil)
	if err != nil {
		log.Print("upgrade:", err)
		return
	}
	defer c.Close()
	for {
		mt, message, err := c.ReadMessage()
		if err != nil {
			log.Println("read:", err)
			break
		}
		log.Printf("recv: %s", message)
		err = c.WriteMessage(mt, message)
		if err != nil {
			log.Println("write:", err)
			break
		}
	}
}

func http_echo(w http.ResponseWriter, req *http.Request) {
	req.ParseForm()
	echo_data := req.Form.Get("echo")
	fmt.Println(echo_data)
	io.WriteString(w, echo_data)
	return

}

func start_websocket() {
	http.HandleFunc("/ws_echo", ws_echo)
	log.Fatal(http.ListenAndServe(*ws_addr, nil))
}

func start_http() {
	http.HandleFunc("/http_echo", http_echo)
	log.Fatal(http.ListenAndServe(*http_addr, nil))
}

func main() {
	flag.Parse()
	log.SetFlags(0)
	wg := sync.WaitGroup{}
	wg.Add(2)
	go start_websocket()
	go start_http()
	wg.Wait()

}
```
```
// web_test.go
package main

import (
	"fmt"
	"io/ioutil"
	"net/http"
	"net/url"
	"strconv"
	"testing"

	"github.com/gorilla/websocket"
)

func BenchmarkHttp(b *testing.B) {
	client := &http.Client{}
	for i := 0; i < b.N; i++ {
		i_str := strconv.Itoa(i)
		req, err := http.NewRequest(http.MethodGet, "http://localhost:9090/http_echo?echo="+i_str, nil)
		if err != nil {
			fmt.Println("create new request failed", err.Error())
			return
		}
		//b.ResetTimer()
		resp, err := client.Do(req)
		if err != nil {
			fmt.Println("got http request error", err.Error())
			return
		}
		_, _ = ioutil.ReadAll(resp.Body)
		//fmt.Println(string(body))
	}
}

func BenchmarkWs(b *testing.B) {
	addr := "localhost:9080"
	u := url.URL{Scheme: "ws", Host: addr, Path: "/ws_echo"}
	c, _, err := websocket.DefaultDialer.Dial(u.String(), nil)
	if err != nil {
		fmt.Println("Error, create websocket connect failed")
		return
	}
	for i := 0; i < b.N; i++ {
		err = c.WriteMessage(websocket.TextMessage, []byte(strconv.Itoa(i)))
		if err != nil {
			fmt.Println("write ws message failed, ", err.Error())
			continue
		}
		_, message, err := c.ReadMessage()
		if err != nil {
			fmt.Println("Error, recv message failed")
			fmt.Println(string(message))
			continue
		}
		//fmt.Println(string(message))
	}
	err = c.WriteMessage(websocket.CloseMessage, websocket.FormatCloseMessage(websocket.CloseNormalClosure, ""))
	c.Close()
}
```
# 结果
```
go test -bench=. -benchtime=3s -run=none
BenchmarkHttp-8   	   57764	     62737 ns/op
BenchmarkWs-8     	  101538	     36740 ns/op
PASS
ok  	web_perf	8.850s
```
从结果中可以直观的看到，```websocket```协议有明显的性能优势。

# 问题结论
上次提出了两个问题，后来经过测试，有了结论。这里贴一下。
* 单个goroutine 崩溃时，该进程内其他的goroutine也会崩溃。通常的做法是使用一层wrapper，进行recover获取及现场、日志等保存；
* golang中线程的实现，runtime中，初始化时会申请内核态线程；见`runtime/proc.go`；

# 问题思考
* http1.0, http1.1, http2.0, http3.0, websocket, quic协议的介绍；
* rpc调用与websocket通信之间的网络延时对比；

# 文章推荐
[net/http长链接&连接池使用时的超时陷阱](https://mp.weixin.qq.com/s?__biz=MzAwMDAxNjU4Mg==&mid=2247484725&idx=1&sn=63941cdb8ba8961457ae7667eed84448&scene=21#wechat_redirect)
[换电脑后，hexo-next 窝火的报错](https://blog.csdn.net/qq_39898645/article/details/109181736)
[golang调度器初始化](https://blog.csdn.net/diaosssss/article/details/92830934)
